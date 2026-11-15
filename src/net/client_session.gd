class_name ClientSession
extends NetworkedSession
## The joining side of a networked match.
##
## Holds a **replica** of the match, not a simulation of it. Every `request_*`
## goes to the host and nothing changes locally until the host says so; the
## replica is only ever overwritten from a snapshot. There is deliberately no
## MatchAuthority here, so a client physically cannot resolve a year, move a
## price, or pay itself a dividend.
##
## The replica is partial by design: this client's own cash, holdings and loan are
## real, and other players carry only their public figures. See StateSync and
## docs/architecture.md §5.3.
##
## What the client *does* compute is the pre-check (`why_not_buy` and friends on
## GameSession), which runs the same rule functions the host enforces with. That
## is presentation — greying out a button — and is never a second source of truth.


## The host accepted the connection and sent the opening state. The UI waits for
## this before showing the match.
signal joined(player_id: StringName)

## The connection failed or dropped. `reason` is player-facing.
signal connection_lost(reason: String)

## The host closed the lobby and the match is under way.
signal match_started


var _state: GameState
var _library: ContentLibrary
var _local_player_id: StringName = &""
var _has_joined: bool = false

## The name the player typed, sent once the socket is up. The host sanitises it
## and may hand back something different, which is what the replica then shows.
var _chosen_name: String = ""

## Set when the host turned this client away, so a subsequent disconnect is
## reported with the host's reason rather than a generic one.
var _refusal: String = ""


## Builds a client and its transport. Returns `{session, peer, error}` in the same
## shape as HostSession.host, so the caller handles both the same way.
##
## A successful return means only that the socket was created — the connection
## itself is asynchronous, and arrives as `joined` or `connection_lost`.
static func join(
	transport: Transport,
	library: ContentLibrary,
	player_name: String = "",
) -> Dictionary:
	var session: ClientSession = ClientSession.new()
	session.name = NODE_NAME
	session._library = library
	session._chosen_name = player_name
	# An empty state until the host's first snapshot. Settings arrive with it, so
	# there is nothing to guess at locally.
	session._state = GameState.new(null)

	var opened: Dictionary = transport.open_client()
	if not String(opened["error"]).is_empty():
		return {"session": null, "error": String(opened["error"])}

	return {"session": session, "error": "", "peer": opened["peer"]}


## Attaches the transport. Separate from `join()` for the same reason as on the
## host: `multiplayer` only resolves once the node is in the tree.
func attach_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		multiplayer.connected_to_server.connect(_on_connected)


## The socket is up. The host does not seat this client until it says who it is,
## so the name goes out immediately.
func _on_connected() -> void:
	_rpc_introduce.rpc_id(HOST_PEER_ID, _chosen_name)


func state() -> GameState:
	return _state


func local_player_id() -> StringName:
	return _local_player_id


## False until the host's welcome arrives. The UI should not render a match before
## this is true — the replica is empty.
func has_joined() -> bool:
	return _has_joined


## A client controls exactly one player and never acts for another. The base
## implementation compares against the local id, which is already correct; it is
## restated here because it is a security property, not a convenience.
func controls(player_id: StringName) -> bool:
	return _has_joined and player_id == _local_player_id


# ------------------------------------------------------------------ the requests
#
# `player_id` is accepted to satisfy the GameSession interface and then checked,
# not sent: the host derives the actor from the peer id. A client asking to act as
# somebody else is refused here *and* could not express it on the wire anyway.

func request_buy(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	if not _may_act(player_id):
		return
	_rpc_buy.rpc_id(HOST_PEER_ID, String(stalk_id), shares)


func request_sell(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	if not _may_act(player_id):
		return
	_rpc_sell.rpc_id(HOST_PEER_ID, String(stalk_id), shares)


func request_loan(player_id: StringName, amount: int) -> void:
	if not _may_act(player_id):
		return
	_rpc_take_loan.rpc_id(HOST_PEER_ID, amount)


func pay_loan(player_id: StringName, amount: int) -> void:
	if not _may_act(player_id):
		return
	_rpc_pay_loan.rpc_id(HOST_PEER_ID, amount)


func set_ready(player_id: StringName, is_ready: bool) -> void:
	if not _may_act(player_id):
		return
	_rpc_set_ready.rpc_id(HOST_PEER_ID, is_ready)


func request_yeehaw(player_id: StringName) -> void:
	if not _may_act(player_id):
		return
	_rpc_ask_yeehaw.rpc_id(HOST_PEER_ID)


func give_yeehaw(giver_id: StringName) -> void:
	if not _may_act(giver_id):
		return
	_rpc_give_yeehaw.rpc_id(HOST_PEER_ID)


# ------------------------------------------------------------- what the host says

func _on_welcomed(player_id: StringName, state_data: Dictionary) -> void:
	_local_player_id = player_id
	var problem: String = StateSync.apply_state(_state, state_data, _library)
	if not problem.is_empty():
		connection_lost.emit(problem)
		close()
		return
	_has_joined = true
	joined.emit(player_id)


func _on_state_pushed(state_data: Dictionary, changed_player_id: StringName) -> void:
	if not _absorb(state_data):
		return
	player_changed.emit(changed_player_id)


func _on_rejection_pushed(reason: String) -> void:
	action_rejected.emit(_local_player_id, reason)


## The year's events and the new market arrive together, and the snapshot is
## applied *first*: the UI reads current state while presenting the result, so
## showing a result against last year's prices would be wrong.
func _on_year_pushed(result_data: Dictionary, state_data: Dictionary) -> void:
	if not _absorb(state_data):
		return
	var result: YearResult = StateSync.decode_year_result(result_data, _library)
	_state.history.append(result)
	year_resolved.emit(result)
	if result.is_final_year:
		game_over.emit(result.winners)


func _on_ready_pushed(player_id: StringName, is_ready: bool) -> void:
	var player: PlayerState = _state.player_by_id(player_id)
	if player != null:
		player.is_ready = is_ready
	ready_state_changed.emit(player_id, is_ready)


func _on_match_start_pushed() -> void:
	match_started.emit()


## The host refused this client. Recorded rather than emitted as a lost
## connection straight away, because the disconnect follows immediately and would
## otherwise report a second, vaguer message over the top of this one.
func _on_turned_away(reason: String) -> void:
	_refusal = reason


func _on_yeehaw_ask_pushed(player_id: StringName) -> void:
	yeehaw_requested.emit(player_id)


func _on_yeehaw_given_pushed(giver_id: StringName, receiver_id: StringName) -> void:
	yeehaw_given.emit(giver_id, receiver_id)


# -------------------------------------------------------------------- internals

## Applies a snapshot, reporting a content mismatch as a lost connection rather
## than rendering a board that disagrees with the host's.
func _absorb(state_data: Dictionary) -> bool:
	var problem: String = StateSync.apply_state(_state, state_data, _library)
	if problem.is_empty():
		return true
	connection_lost.emit(problem)
	close()
	return false


## Guards against the UI asking this client to act for somebody else. It cannot
## happen through the normal screens, which always pass `local_player_id()`, but
## the interface permits any id and silence would be the wrong answer.
func _may_act(player_id: StringName) -> bool:
	if not _has_joined:
		action_rejected.emit(player_id, "Not connected.")
		return false
	if player_id != _local_player_id:
		action_rejected.emit(player_id, "You can only act for yourself.")
		return false
	return true


func _on_connection_failed() -> void:
	connection_lost.emit("Could not connect to the host.")


func _on_server_disconnected() -> void:
	_has_joined = false
	connection_lost.emit(_refusal if not _refusal.is_empty() else "The host closed the game.")
