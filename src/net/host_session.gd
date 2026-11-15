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

## The lobby closed and the match is under way. Both sides' screen hosts listen
## for this to swap the lobby for the playing screen.
signal match_started


var _authority: MatchAuthority
var _library: ContentLibrary

## How this match is carried. Kept so the lobby can tell the host what to pass
## on, without knowing whether that is a port or an invite.
var _transport: Transport

## Which player each connected peer controls. The host itself is in here as
## HOST_PEER_ID, so every lookup goes through one map.
var _player_by_peer: Dictionary[int, StringName] = {}

## Reverse lookup, for sending a rejection back to one asker.
var _peer_by_player: Dictionary[StringName, int] = {}

## Every slot's player, in roster order, for the whole match — including players
## whose peer has dropped. `state.players` is this list minus the vacated ones,
## so rebuilding it keeps the roster order stable rather than shuffling the
## rankings whenever somebody leaves or comes back.
var _roster: Array[PlayerState] = []

## Players whose peer has gone mid-match. They are out of `state.players` — out
## of the economy, the standings and the ready gate — but their PlayerState stays
## alive in `_roster` with its cash and holdings.
##
## Nothing reads that retained position yet. It is kept because throwing it away
## is irreversible and keeping it costs one array, and because both planned
## successors need it: a bot taking over a vacant slot, and a real rejoin once
## Steam identity makes "is this the same person" answerable. See
## docs/decisions.md D47 and porting-plan Phase 8.
var _vacated_player_ids: Array[StringName] = []

## True until the host presses Start. While open, an arriving peer is given a new
## slot; once closed, the roster is fixed and a late joiner is turned away.
var _lobby_is_open: bool = true


## Starts listening on `port` with the host as the only player, and the lobby
## open.
##
## **Players are created as they arrive, not declared up front.** Sizing the match
## in advance meant a match set up for four with two people present could never
## advance a year — the ready gate counts every player, which is exactly the
## deadlock D47 fixed for disconnects. The roster is instead whoever is present
## when the host presses Start. See docs/decisions.md D48.
##
## `transport` carries the match — ENet today, Steam later. This function does
## not know which, which is what makes Steam a swap (D56).
##
## Returns `{session, peer, error}`; check `error` first.
static func host(
	transport: Transport,
	settings: GameSettings,
	library: ContentLibrary,
	host_name: String,
) -> Dictionary:
	var session: HostSession = HostSession.new()
	session.name = NODE_NAME
	session._library = library
	session._transport = transport
	session._authority = LocalSession.build_authority(
		settings, library, [sanitised_name(host_name, 0)] as Array[String]
	)

	# The host is the one slot that exists before anybody connects. It is claimed
	# when the peer is attached, once there is a MultiplayerAPI to read the host's
	# own peer id from.
	session._roster = session._authority.state.players.duplicate()

	var opened: Dictionary = transport.open_server(MAX_CLIENTS)
	if not String(opened["error"]).is_empty():
		return {"session": null, "error": String(opened["error"])}

	return {"session": session, "error": "", "peer": opened["peer"]}


## Attaches the transport. Separate from `host()` because the node must be in the
## tree first: `multiplayer` resolves by node path, so before the node is added
## there is no API to set a peer on. The spike in docs/architecture.md §5.2 found
## this the hard way.
func attach_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_seat(HOST_PEER_ID, _roster[0].id)


## Ten players maximum, host included. See docs/game-rules.md §2.
const MAX_PLAYERS: int = MAX_CLIENTS + 1


## Longest player name the boards have room for. Terminus is a fixed-width font
## and the rankings column is sized in characters, so this is a layout constant
## rather than an arbitrary limit.
const MAX_NAME_LENGTH: int = 16


## A display name that is safe to put on screen: trimmed, length-capped, and
## never empty.
##
## Names come from a client over the wire, so they are untrusted input. An empty
## or whitespace-only name would render as a blank row, and an overlong one would
## break the column, so both are corrected here rather than rejected — being
## turned away from a game because of your name would be worse.
static func sanitised_name(raw: String, slot_index: int) -> String:
	var trimmed: String = raw.strip_edges()
	if trimmed.is_empty():
		return "Player %d" % (slot_index + 1)
	# Control characters would corrupt a fixed-width row.
	var cleaned: String = ""
	for character: String in trimmed:
		cleaned += character if character.unicode_at(0) >= 32 else " "
	cleaned = cleaned.strip_edges()
	if cleaned.is_empty():
		return "Player %d" % (slot_index + 1)
	return cleaned.substr(0, MAX_NAME_LENGTH)


func state() -> GameState:
	return _authority.state if _authority != null else null


## One line telling the host how others can join. The lobby shows it verbatim
## and does not care whether it names a port or a Steam invite.
func joining_hint() -> String:
	return _transport.joining_hint() if _transport != null else ""


## Whether the lobby is still accepting players.
func lobby_is_open() -> bool:
	return _lobby_is_open


## Why the match cannot start yet, or an empty string.
##
## Everybody except the host must be ready. The host does not ready up —
## pressing Start is their readiness — so they are excluded from the check, and a
## host on their own can always start.
##
## A player who will not ready up is removed with `kick_player`, which is what
## stops this becoming the deadlock that an all-ready gate would otherwise be.
## See docs/decisions.md D49.
func why_not_start() -> String:
	if not _lobby_is_open:
		return "The match has already started."

	var waiting: PackedStringArray = waiting_on()
	if waiting.is_empty():
		return ""
	return "Not everybody is ready yet."


## Display names of the players who have not readied up, in roster order. The
## host is never in this list.
func waiting_on() -> PackedStringArray:
	var waiting: PackedStringArray = []
	for player: PlayerState in _authority.state.players:
		if player.id != local_player_id() and not player.is_ready:
			waiting.append(player.display_name)
	return waiting


## Closes the lobby and begins the match with whoever is present.
##
## Refuses unless everybody is ready. The host is the authority, so this is not a
## security check — it is here rather than only on the button so that the rule has
## one home and a second caller cannot skip it.
##
## The roster is fixed from here on: late joiners are turned away, and a player
## who drops vacates their slot rather than disappearing (D47). Before Start a
## dropped player is simply forgotten — there is no portfolio to keep and nobody
## is waiting on them.
func start_match() -> void:
	if not why_not_start().is_empty():
		return
	_lobby_is_open = false
	_authority.state.clear_ready_flags()
	_rpc_match_started.rpc()
	_broadcast_state(local_player_id())
	match_started.emit()


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


func give_yeehaw(giver_id: StringName) -> void:
	_apply_yeehaw_give(giver_id)


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


## The giver is the *sender*, and the receiver is whoever is asking. Neither
## comes from the packet, so a client cannot claim to be somebody else giving one
## nor nominate who gets it — which is what makes "you cannot yeehaw yourself"
## enforceable rather than merely checked.
func _on_yeehaw_offered(peer: int) -> void:
	var giver_id: StringName = _require_player(peer)
	if not giver_id.is_empty():
		_apply_yeehaw_give(giver_id)


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
	# The pending request is state, and every other player's button depends on
	# it, so the snapshot has to go out too.
	_broadcast_state(player_id)


func _apply_yeehaw_give(giver_id: StringName) -> void:
	var receiver_id: StringName = _authority.receiver_of_yeehaw()
	var reason: String = _authority.give_yeehaw(giver_id)
	if not reason.is_empty():
		_reject(giver_id, reason)
		return
	yeehaw_given.emit(giver_id, receiver_id)
	_rpc_yeehaw_given.rpc(String(giver_id), String(receiver_id))
	_broadcast_state(giver_id)


## The single gate. Called when somebody readies up and when somebody leaves,
## because either can be the last thing the year was waiting for.
##
## `all_players_ready()` is false for an empty roster, so a match everybody has
## left does not resolve years on its own.
##
## Nothing advances while the lobby is open. Readiness means two different things
## either side of Start — "ready to begin" in the lobby, "advance the year" in the
## match — and without this guard a full lobby of ready players would resolve
## year 1 before anybody had seen the board.
func _advance_if_everybody_is_ready() -> void:
	if _lobby_is_open or _authority.state.is_over:
		return
	if _authority.state.all_players_ready():
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

## A socket connected. Nothing is decided here — the host waits for the peer to
## introduce itself, because the player's chosen name arrives with that and a slot
## created now would have no name to show.
func _on_peer_connected(_peer_id: int) -> void:
	pass


## A peer has told the host its name, so it can be seated.
##
## Everything that can refuse a joiner is decided here, and each refusal sends a
## reason before disconnecting: a player turned away in silence has no idea
## whether the game is full, already running, or simply broken.
func _on_introduced(peer_id: int, player_name: String) -> void:
	if _player_by_peer.has(peer_id):
		# A second introduction from the same peer. Ignored rather than treated as
		# a rename: the lobby is not a place to change your name, and honouring it
		# mid-match would let a client rewrite the rankings.
		return

	if not _lobby_is_open:
		_turn_away(peer_id, "That game has already started.")
		return

	var player_id: StringName = _seat_new_player(peer_id, player_name)
	if player_id.is_empty():
		_turn_away(peer_id, "That game is full.")
		return

	_rpc_welcome.rpc_id(
		peer_id, String(player_id), StateSync.encode_state(_authority.state, player_id)
	)
	player_joined.emit(player_id)
	# Everybody else needs the new arrival in their player list.
	_broadcast_state(player_id)


## Creates a fresh player for an arriving peer, or an empty id if the match is
## full.
##
## **A vacated slot is never handed out.** Resuming somebody else's position is
## the rejoin feature, and rejoining needs identity to be safe — without it, any
## arrival could claim a dropped player's portfolio. Deferred until Steam IDs
## exist; see porting-plan Phase 8 and D47. In practice no arrival gets this far
## once a match has started anyway, because `_on_introduced` turns latecomers
## away.
func _seat_new_player(peer_id: int, player_name: String) -> StringName:
	if _roster.size() >= MAX_PLAYERS:
		return &""

	var index: int = _roster.size()
	var player: PlayerState = PlayerState.new(
		StringName("p%d" % index),
		sanitised_name(player_name, index),
		_authority.state.settings.starting_cash,
	)
	_roster.append(player)
	_rebuild_active_players()
	_seat(peer_id, player.id)
	return player.id


## Removes a player from the lobby, telling them why.
##
## **The host's escape from a waiting game.** Start requires everybody to be
## ready, so somebody who has wandered off would otherwise hold the lobby shut
## forever. Kicking is a decision a person makes, which is the right kind of
## answer — better than a rule that guesses when to give up on somebody.
##
## Lobby only. Removing somebody from a running match is a different act with
## different consequences for the economy — see D47 — and nothing asks for it
## yet.
##
## Returns a reason it could not be done, or an empty string.
func kick_player(player_id: StringName) -> String:
	if not _lobby_is_open:
		return "You can only remove players before the match starts."
	if player_id == local_player_id():
		return "You cannot remove yourself."

	var peer_id: int = _peer_by_player.get(player_id, 0)
	if peer_id == 0:
		return "That player is not connected."

	# Everything else follows from the disconnect: the peer's departure forgets
	# the player, rebuilds the roster and tells the others.
	_turn_away(peer_id, "The host removed you from the lobby.")
	return ""


func _turn_away(peer_id: int, reason: String) -> void:
	_rpc_turned_away.rpc_id(peer_id, reason)
	# Deferred so the reason is actually flushed to the socket before it closes.
	_disconnect_soon(peer_id)


func _disconnect_soon(peer_id: int) -> void:
	await get_tree().process_frame
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


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

	if _lobby_is_open:
		# Nothing to preserve and nobody waiting on them: somebody who leaves the
		# lobby was never in the match. Their slot is removed outright so the
		# remaining players keep consecutive ids and a tidy list.
		_forget_player(player_id)
	else:
		if not _vacated_player_ids.has(player_id):
			_vacated_player_ids.append(player_id)
		var player: PlayerState = _player_in_roster(player_id)
		if player != null:
			# Cleared so a resumed player is not already ready for a year they
			# were not present for.
			player.is_ready = false
		_rebuild_active_players()

	player_left.emit(player_id)
	_broadcast_state(player_id)

	# Their departure may be the last thing the year was waiting on.
	_advance_if_everybody_is_ready()


## Drops a player from the lobby entirely. Only safe before the match starts:
## afterwards their holdings and their place in the standings matter, which is
## what D47 is about.
func _forget_player(player_id: StringName) -> void:
	for index: int in _roster.size():
		if _roster[index].id == player_id:
			_roster.remove_at(index)
			break
	_vacated_player_ids.erase(player_id)
	_rebuild_active_players()


## Records which player a peer controls, both ways round.
func _seat(peer_id: int, player_id: StringName) -> void:
	_player_by_peer[peer_id] = player_id
	_peer_by_player[player_id] = peer_id


## `state.players` is the roster minus whoever has dropped, rebuilt in roster
## order. The authority reads this list for the ready gate, dividends, net worth
## and rankings, so removing somebody here is what takes them out of the economy.
func _rebuild_active_players() -> void:
	var active: Array[PlayerState] = []
	for player: PlayerState in _roster:
		if not _vacated_player_ids.has(player.id):
			active.append(player)
	_authority.state.players = active


## What to call a player who is no longer in `state().players`.
##
## A player who disconnects mid-match is taken off the active roster but kept in
## `_roster` with their holdings intact (D47), so the usual
## `state().player_by_id()` stops finding them at exactly the moment the screen
## wants to say "so-and-so left". This looks in the place they still exist.
## Returns an empty string for an id this host has never seated.
func display_name_of(player_id: StringName) -> String:
	var player: PlayerState = _player_in_roster(player_id)
	return player.display_name if player != null else ""


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
