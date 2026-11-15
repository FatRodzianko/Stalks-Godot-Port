class_name HostSession
extends NetworkedSession
## The authoritative side of a networked match.
##
## Owns the same MatchAuthority that offline play uses, so hosted and single-player
## games resolve identically. On top of that it does exactly three things: map
## peers to players, run each request through the authority, and push the result
## out as a redacted per-player snapshot.
##
## The host is also a player. Its own requests take the identical path as a
## client's — `request_buy` here calls the authority directly rather than going
## through the wire, but it is the same authority call with the same validation,
## so the host gets no privileged behaviour, only lower latency.


## Emitted when a peer joins and has been assigned a player. The lobby listens for
## this; nothing in the economy does.
signal player_joined(player_id: StringName)

## Emitted when a peer drops. Their player stays in the match — see
## `_on_peer_disconnected`.
signal player_left(player_id: StringName)


var _authority: MatchAuthority
var _library: ContentLibrary

## Which player each connected peer controls. The host itself is in here as
## HOST_PEER_ID, so every lookup goes through one map.
var _player_by_peer: Dictionary[int, StringName] = {}

## Reverse lookup, for sending a rejection back to one asker.
var _peer_by_player: Dictionary[StringName, int] = {}

## Player slots that exist in the match but have nobody connected to them. A
## dropped player's slot goes back here so it can be reclaimed.
var _free_player_ids: Array[StringName] = []

## Every slot's player, in roster order, for the whole match — including players
## whose peer has dropped. `state.players` is this list minus the vacated ones,
## so rebuilding it keeps the roster order stable rather than shuffling the
## rankings whenever somebody leaves or comes back.
var _roster: Array[PlayerState] = []

## Players whose peer has gone. Their PlayerState stays alive in `_roster` with
## its cash and holdings intact, so reclaiming the slot resumes the portfolio
## rather than starting a fresh player. See docs/decisions.md D47.
var _vacated_player_ids: Array[StringName] = []


## Starts listening on `port` and seats the host as the first player.
##
## `expected_players` sizes the match: the slots are created up front, because the
## economy needs every player to exist before year 1 resolves and the original
## likewise locked the roster at the lobby. Slots nobody claims are still played
## by the authority — a Phase 5 lobby limitation noted in docs/porting-plan.md.
##
## Returns an error string, or empty on success.
static func host(
	port: int,
	settings: GameSettings,
	library: ContentLibrary,
	player_names: Array[String],
) -> Dictionary:
	var session: HostSession = HostSession.new()
	session.name = NODE_NAME
	session._library = library
	session._authority = LocalSession.build_authority(settings, library, player_names)

	# Every slot starts unclaimed; the host claims the first one when its peer is
	# attached, once there is a MultiplayerAPI to read its own peer id from.
	session._roster = session._authority.state.players.duplicate()
	for player: PlayerState in session._roster:
		session._free_player_ids.append(player.id)

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		return {"session": null, "error": "Could not listen on port %d (%d)." % [port, error]}

	return {"session": session, "error": "", "peer": peer}


## Attaches the transport. Separate from `host()` because the node must be in the
## tree first: `multiplayer` resolves by node path, so before the node is added
## there is no API to set a peer on. The spike in docs/architecture.md §5.2 found
## this the hard way.
func attach_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_claim_slot(HOST_PEER_ID)


func state() -> GameState:
	return _authority.state if _authority != null else null


func local_player_id() -> StringName:
	return _player_by_peer.get(HOST_PEER_ID, &"")


func seed_value() -> int:
	return _authority.seed_value() if _authority != null else 0


## Which player a peer controls, or an empty id. Exposed for the lobby and for
## tests; nothing in the economy consults it.
func player_for_peer(peer_id: int) -> StringName:
	return _player_by_peer.get(peer_id, &"")


## Every slot's player in roster order, **including** those whose peer has
## dropped, with their cash and holdings intact.
##
## This is what a lobby or a disconnect notice should show ("Guest —
## disconnected"). The economy reads `state().players` instead, which is this
## list minus the vacated ones.
func roster() -> Array[PlayerState]:
	return _roster


## Whether this player's peer has gone. A vacated player is out of the economy
## but not destroyed.
func is_vacated(player_id: StringName) -> bool:
	return _vacated_player_ids.has(player_id)


# ------------------------------------------- the host's own requests (no wire)

func request_buy(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	_apply_buy(player_id, stalk_id, shares)


func request_sell(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	_apply_sell(player_id, stalk_id, shares)


func request_loan(player_id: StringName, amount: int) -> void:
	_apply_loan(player_id, amount)


func pay_loan(player_id: StringName, amount: int) -> void:
	_apply_payment(player_id, amount)


func set_ready(player_id: StringName, is_ready: bool) -> void:
	_apply_ready(player_id, is_ready)


func request_yeehaw(player_id: StringName) -> void:
	_apply_yeehaw_ask(player_id)


func give_yeehaw(giver_id: StringName, receiver_id: StringName) -> void:
	_apply_yeehaw_give(giver_id, receiver_id)


# ------------------------------------------------- client requests (over the wire)
#
# Each resolves the sender to a player and then calls the identical method the
# host's own UI calls. A peer with no player assigned is ignored entirely.

func _on_buy_requested(peer: int, stalk_id: StringName, shares: int) -> void:
	var player_id: StringName = _require_player(peer)
	if not player_id.is_empty():
		_apply_buy(player_id, stalk_id, shares)


func _on_sell_requested(peer: int, stalk_id: StringName, shares: int) -> void:
	var player_id: StringName = _require_player(peer)
	if not player_id.is_empty():
		_apply_sell(player_id, stalk_id, shares)


func _on_loan_requested(peer: int, amount: int) -> void:
	var player_id: StringName = _require_player(peer)
	if not player_id.is_empty():
		_apply_loan(player_id, amount)


func _on_payment_requested(peer: int, amount: int) -> void:
	var player_id: StringName = _require_player(peer)
	if not player_id.is_empty():
		_apply_payment(player_id, amount)


func _on_ready_requested(peer: int, is_ready: bool) -> void:
	var player_id: StringName = _require_player(peer)
	if not player_id.is_empty():
		_apply_ready(player_id, is_ready)


func _on_yeehaw_asked(peer: int) -> void:
	var player_id: StringName = _require_player(peer)
	if not player_id.is_empty():
		_apply_yeehaw_ask(player_id)


## Note the giver is the *sender*, never a value from the packet. A client can
## nominate who receives a yeehaw but can never claim to be somebody else giving
## it, which is what makes "you cannot yeehaw yourself" enforceable.
func _on_yeehaw_offered(peer: int, receiver_id: StringName) -> void:
	var giver_id: StringName = _require_player(peer)
	if not giver_id.is_empty():
		_apply_yeehaw_give(giver_id, receiver_id)


# ------------------------------------------------------------ one path per action

func _apply_buy(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	_settle(player_id, _authority.buy(player_id, stalk_id, shares))


func _apply_sell(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	_settle(player_id, _authority.sell(player_id, stalk_id, shares))


func _apply_loan(player_id: StringName, amount: int) -> void:
	_settle(player_id, _authority.take_loan(player_id, amount))


func _apply_payment(player_id: StringName, amount: int) -> void:
	_settle(player_id, _authority.pay_loan(player_id, amount))


func _apply_ready(player_id: StringName, is_ready: bool) -> void:
	var reason: String = _authority.set_ready(player_id, is_ready)
	if not reason.is_empty():
		_reject(player_id, reason)
		return

	ready_state_changed.emit(player_id, is_ready)
	_rpc_ready_changed.rpc(String(player_id), is_ready)
	_advance_if_everybody_is_ready()


func _apply_yeehaw_ask(player_id: StringName) -> void:
	var reason: String = _authority.request_yeehaw(player_id)
	if not reason.is_empty():
		_reject(player_id, reason)
		return
	yeehaw_requested.emit(player_id)
	_rpc_yeehaw_asked.rpc(String(player_id))


func _apply_yeehaw_give(giver_id: StringName, receiver_id: StringName) -> void:
	var reason: String = _authority.give_yeehaw(giver_id, receiver_id)
	if not reason.is_empty():
		_reject(giver_id, reason)
		return
	yeehaw_given.emit(giver_id, receiver_id)
	_rpc_yeehaw_given.rpc(String(giver_id), String(receiver_id))


## The single gate. Called when somebody readies up and when somebody leaves,
## because either can be the last thing the year was waiting for.
##
## `all_players_ready()` is false for an empty roster, so a match everybody has
## left does not resolve years on its own.
func _advance_if_everybody_is_ready() -> void:
	if _authority.state.all_players_ready() and not _authority.state.is_over:
		_advance()


func _advance() -> void:
	var result: YearResult = _authority.advance_year()
	var result_data: Dictionary = StateSync.encode_year_result(result)

	# Each peer gets the year's events, which are public, plus a snapshot built
	# for them alone. The snapshot goes in the same packet so a client can never
	# render a result against a stale market.
	for peer: int in _player_by_peer:
		if peer == HOST_PEER_ID:
			continue
		_rpc_year.rpc_id(
			peer, result_data, StateSync.encode_state(_authority.state, _player_by_peer[peer])
		)

	year_resolved.emit(result)
	if result.is_final_year:
		game_over.emit(result.winners)


# -------------------------------------------------------------------- pushing out

## Accepted or refused, in one shape. A refusal is sent only to the asker; a
## change is broadcast, because everybody's rankings move when anybody's net
## worth does.
func _settle(player_id: StringName, reason: String) -> void:
	if not reason.is_empty():
		_reject(player_id, reason)
		return
	player_changed.emit(player_id)
	_broadcast_state(player_id)


func _reject(player_id: StringName, reason: String) -> void:
	if _is_host_player(player_id):
		action_rejected.emit(player_id, reason)
		return
	var peer: int = _peer_by_player.get(player_id, 0)
	if peer != 0:
		_rpc_rejected.rpc_id(peer, reason)


## One snapshot per peer, each redacted for its own recipient. Ten players is at
## most nine small packets, which is nothing for a game that changes state when
## somebody clicks a button. See docs/decisions.md D42.
func _broadcast_state(changed_player_id: StringName) -> void:
	for peer: int in _player_by_peer:
		if peer == HOST_PEER_ID:
			continue
		_rpc_state.rpc_id(
			peer,
			StateSync.encode_state(_authority.state, _player_by_peer[peer]),
			String(changed_player_id),
		)


# ------------------------------------------------------------------- connections

func _on_peer_connected(peer_id: int) -> void:
	var player_id: StringName = _claim_slot(peer_id)
	if player_id.is_empty():
		# The match is full. Disconnecting is blunt but honest; the lobby will
		# turn this into a message before Phase 5 is done.
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	_rpc_welcome.rpc_id(
		peer_id, String(player_id), StateSync.encode_state(_authority.state, player_id)
	)
	player_joined.emit(player_id)
	# Everybody else needs the new arrival in their player list.
	_broadcast_state(player_id)


## A dropped peer's player leaves the **active roster**, and their portfolio is
## kept so that reclaiming the slot resumes it.
##
## Leaving the player in the match was tried first and is wrong: the all-ready gate
## counts every player, so a disconnect deadlocked the year for everybody still
## playing. A game that cannot continue is worse than a game whose standings
## changed, so the player is removed from `state.players`.
##
## It is removal from the roster only. The `PlayerState` itself stays alive in
## `_roster` with its cash and holdings, so this is not destruction — it is
## setting them aside. See docs/decisions.md D47, and the two future directions
## (a bot taking over, and a proper rejoin) in docs/porting-plan.md.
func _on_peer_disconnected(peer_id: int) -> void:
	var player_id: StringName = _player_by_peer.get(peer_id, &"")
	if player_id.is_empty():
		return

	_player_by_peer.erase(peer_id)
	_peer_by_player.erase(player_id)
	_free_player_ids.append(player_id)

	if not _vacated_player_ids.has(player_id):
		_vacated_player_ids.append(player_id)
	var player: PlayerState = _player_in_roster(player_id)
	if player != null:
		# Cleared so a resumed player is not already ready for a year they were
		# not present for.
		player.is_ready = false
	_rebuild_active_players()

	player_left.emit(player_id)
	_broadcast_state(player_id)

	# Their departure may be the last thing the year was waiting on.
	_advance_if_everybody_is_ready()


## Seats a peer in the first free slot, in roster order so that the host is always
## player 0 and joiners are seated predictably.
##
## A slot vacated by a disconnect comes back with its portfolio. Without an
## identity system the host cannot tell a reconnecting player from a stranger, and
## among the handful of friends this game is played by, a peer claiming a vacated
## slot is overwhelmingly the person who just dropped — so resuming is the better
## guess. Steam identity in Phase 6 makes it checkable.
func _claim_slot(peer_id: int) -> StringName:
	if _free_player_ids.is_empty():
		return &""
	var player_id: StringName = _free_player_ids.pop_front()
	_player_by_peer[peer_id] = player_id
	_peer_by_player[player_id] = peer_id

	if _vacated_player_ids.has(player_id):
		_vacated_player_ids.erase(player_id)
		_rebuild_active_players()

	return player_id


## `state.players` is the roster minus whoever has dropped, rebuilt in roster
## order. The authority reads this list for the ready gate, dividends, net worth
## and rankings, so removing somebody here is what takes them out of the economy.
func _rebuild_active_players() -> void:
	var active: Array[PlayerState] = []
	for player: PlayerState in _roster:
		if not _vacated_player_ids.has(player.id):
			active.append(player)
	_authority.state.players = active


func _player_in_roster(player_id: StringName) -> PlayerState:
	for player: PlayerState in _roster:
		if player.id == player_id:
			return player
	return null


## The player a peer controls, or an empty id for a peer with no slot. Returning
## empty rather than erroring means a packet from a peer mid-disconnect is simply
## dropped.
func _require_player(peer_id: int) -> StringName:
	return _player_by_peer.get(peer_id, &"")


func _is_host_player(player_id: StringName) -> bool:
	return _player_by_peer.get(HOST_PEER_ID, &"") == player_id
