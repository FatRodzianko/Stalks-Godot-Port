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


## How long to wait for the host's welcome before giving up.
##
## **Why a timeout and not a disconnect signal.** Over ENet, a host that goes
## away produces `connection_failed` or `server_disconnected` and this would
## not be needed. Over Steam it does not: the peer-to-peer session simply goes
## quiet, so a client whose host left mid-join sat on the lobby for ever,
## looking connected, with a Ready button that answered "Not connected." to
## every press. A clock is the only thing that catches every way of not
## arriving. See docs/decisions.md D67.
##
## Twelve seconds because Steam's relay can take several to negotiate a route
## and a false failure is worse than a slow one.
const JOIN_TIMEOUT_SECONDS: float = 12.0


var _state: GameState
var _library: ContentLibrary
var _local_player_id: StringName = &""
var _has_joined: bool = false

## The name the player typed, sent once the socket is up. The host sanitises it
## and may hand back something different, which is what the replica then shows.
var _chosen_name: String = ""

## The Steam account this client is playing as, or 0 when it is not playing
## through Steam. Sent once, with the introduction, purely so the lobby can
## show an avatar. See `networked_session.gd`.
var _steam_id: int = 0

## Set when the host turned this client away, so a subsequent disconnect is
## reported with the host's reason rather than a generic one.
## How far the match's random stream had run at the last snapshot.
##
## Kept against the day the host walks out and this client is the one Steam
## makes the new owner: it promotes its own copy of the match and picks the
## stream up here, rather than reseeding and dealing year one again. Unused
## until then. See docs/decisions.md D105.
var _rng_state: int = 0

var _refusal: String = ""

## Whether the host has said the match is under way.
##
## **The snapshot cannot say it.** Year 0 is a real year, so a lobby and a match
## that has just begun look identical in the state — which is why the host says
## so outright (D116). That used to be re-emitted and forgotten, because the only
## listener was the lobby screen, which acts the moment it hears.
##
## It is remembered now because a migration decides, long afterwards, which
## screen to put this player back on, and "lobby or match" is exactly the
## question the state cannot answer. See `Main._show_the_screen_for` and
## docs/decisions.md D122.
var _match_is_on: bool = false

## Whether the host has said it is willing to play again. See D124.
var _rematch_is_offered: bool = false

## Seconds spent waiting for the welcome, or -1 when not waiting. See
## `JOIN_TIMEOUT_SECONDS`.
var _waiting_for: float = -1.0


## Builds a client and its transport. Returns `{session, peer, error}` in the same
## shape as HostSession.host, so the caller handles both the same way.
##
## A successful return means only that the socket was created — the connection
## itself is asynchronous, and arrives as `joined` or `connection_lost`.
static func join(
	transport: Transport,
	library: ContentLibrary,
	player_name: String = "",
	steam_id: int = 0,
) -> Dictionary:
	var session: ClientSession = ClientSession.new()
	session.name = NODE_NAME
	session._library = library
	session._chosen_name = player_name
	session._steam_id = steam_id
	# An empty state until the host's first snapshot. Settings arrive with it, so
	# there is nothing to guess at locally.
	session._state = GameState.new(null)

	var opened: Dictionary = transport.open_client()
	if not String(opened["error"]).is_empty():
		# A session is a Node, and this one was built before the socket was
		# tried. Nothing adds it to the tree on this path, so without the free
		# it is an orphan for the rest of the process. Harmless in a real game,
		# which gives up after one, and noisy in a suite that exercises the
		# failure deliberately.
		session.free()
		return {"session": null, "error": String(opened["error"])}

	# The clock starts here rather than at `attach_peer`, which happens a line
	# later in every caller: this way it also covers the gap in between, and a
	# test can exercise the timeout without touching a multiplayer peer.
	session._waiting_for = 0.0
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
## Counts the wait for the welcome, and gives up if it never comes.
func _process(delta: float) -> void:
	if _waiting_for < 0.0:
		return
	_waiting_for += delta
	if _waiting_for < JOIN_TIMEOUT_SECONDS:
		return
	_waiting_for = -1.0
	connection_lost.emit("Could not reach the host. They may have left.")
	close()


func _on_connected() -> void:
	_rpc_introduce.rpc_id(HOST_PEER_ID, _chosen_name, _steam_id)


func state() -> GameState:
	return _state


## How far the match's random stream had run at the last snapshot. What a new
## host needs in order to continue the match rather than re-roll its past.
func rng_state() -> int:
	return _rng_state


func local_player_id() -> StringName:
	return _local_player_id


## False until the host's welcome arrives. The UI should not render a match before
## this is true — the replica is empty.
func has_joined() -> bool:
	return _has_joined


## Whether the host has said the match is under way, as opposed to this client
## sitting in a lobby. See `_match_is_on` for why the state cannot answer this.
func match_is_on() -> bool:
	return _match_is_on


# ------------------------------------------------------------------ the rematch

## Whether the host has offered another game. Cleared by the welcome that takes
## this client into it, so the offer is not still standing once it is taken up.
func rematch_is_offered() -> bool:
	return _rematch_is_offered


## Only the host can offer one — it is the only peer that can reopen the lobby.
func can_offer_rematch() -> bool:
	return false


func ask_for_rematch() -> void:
	if not _has_joined:
		return
	_rpc_ask_for_rematch.rpc_id(HOST_PEER_ID)


func join_rematch() -> void:
	if not _rematch_is_offered:
		return
	_rpc_want_rematch.rpc_id(HOST_PEER_ID)


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

func _on_welcomed(
	player_id: StringName, state_data: Dictionary, history_data: Array = []
) -> void:
	_local_player_id = player_id
	# **Cleared on every welcome.** A welcome is an arrival, and an arrival is in
	# a lobby until the host says otherwise. When there is a match to arrive in,
	# the host sends `_rpc_match_started` straight after this one (D116), and
	# both are reliable on the same channel, so that answer always lands after
	# this line.
	_match_is_on = false
	# The offer has been taken up — this welcome is the seat it was offering —
	# or this is an arrival somewhere else entirely. Either way it is not an
	# offer still waiting to be accepted.
	_rematch_is_offered = false
	var problem: String = StateSync.apply_state(_state, state_data, _library)
	if not problem.is_empty():
		connection_lost.emit(problem)
		close()
		return
	_rng_state = StateSync.rng_state_of(state_data)
	# The years this client was not here for. Without it the year-by-year
	# record starts wherever the player happened to arrive. See D118. A
	# StalkleHeads record is replayed from its inputs and can be refused, for
	# the same reason a snapshot can (D178).
	problem = StateSync.apply_history(_state, history_data, _library)
	if not problem.is_empty():
		connection_lost.emit(problem)
		close()
		return
	_has_joined = true
	_waiting_for = -1.0
	joined.emit(player_id)


func _on_state_pushed(state_data: Dictionary, changed_player_id: StringName) -> void:
	if not _absorb(state_data):
		return
	player_changed.emit(changed_player_id)


func _on_rejection_pushed(reason: String) -> void:
	action_rejected.emit(_local_player_id, reason)


## The year's events and the new market arrive together, and the snapshot is
## applied before anybody hears of the year: the UI reads current state while
## presenting the result, so showing a result against last year's prices would
## be wrong.
##
## **The result is decoded first, though.** A StalkleHeads year arrives as its
## inputs and is replayed from the market as this replica held it before the
## year, which the snapshot is about to overwrite (`StateSync.decode_live_year`,
## D178). A base-game year decodes the same either way round.
func _on_year_pushed(result_data: Dictionary, state_data: Dictionary) -> void:
	var result: YearResult = StateSync.decode_live_year(_state, result_data, _library)
	if result == null:
		connection_lost.emit(MarketSync.MALFORMED)
		close()
		return
	if not _absorb(state_data):
		return
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
	_match_is_on = true
	# **An offer this client did not take up is over.** The host has pressed
	# Play, so there is no longer a lobby to join — and a client still on the
	# result screen must stop showing a way into one, or its button fails when
	# pressed. This arrives there as well as to the players who joined, because
	# `start_match` broadcasts to every peer rather than to the seated ones.
	_rematch_is_offered = false
	match_started.emit()


func _on_rematch_offer_pushed() -> void:
	_rematch_is_offered = true
	rematch_offered.emit()


func _on_rematch_join_pushed() -> void:
	rematch_joined.emit()


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
		_rng_state = StateSync.rng_state_of(state_data)
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
	_waiting_for = -1.0
	connection_lost.emit("Could not connect to the host.")


func _on_server_disconnected() -> void:
	_has_joined = false
	_waiting_for = -1.0
	connection_lost.emit(_refusal if not _refusal.is_empty() else "The host closed the game.")
