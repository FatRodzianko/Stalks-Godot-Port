class_name HostSession
extends NetworkedSession
## The authoritative side of a networked match.
##
## Owns the same MatchAuthority that offline play uses, so hosted and single-player
## games resolve identically. On top of that it does exactly three things: map
## peers to players, run each request through the authority, and push the result
## out as a snapshot of the whole match.
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

## There is no roster list here, and there used to be two.
##
## `_roster` held every slot for the whole match and `state.players` held that
## list minus whoever had dropped, rebuilt on every arrival and departure. The
## difference between them was exactly "has this player's peer gone", which is
## now `PlayerState.is_away` — one flag on the player instead of a second list
## to keep in step. So **`state.players` is the roster**: a player who drops
## stays in it with their position and their place in the standings, and the
## year gate skips them rather than waiting (`GameState.all_players_ready`).
##
## That is what makes rejoining mean something. Under the old model a returning
## player got their cash and holdings back but had been out of the economy
## while they were gone — no dividends, no splits, no loan interest. See
## docs/decisions.md D47 and D110.

## True until the host presses Start. While open, an arriving peer is given a new
## slot; once closed, the roster is fixed and a late joiner is turned away.
var _lobby_is_open: bool = true

## Which roster slot this host plays. Slot zero in a match this host started,
## and whichever slot they already held in one they took over (`take_over`).
var _host_player_id: StringName = &""

## Who has asked for another game, by their slot in the **finished** match.
##
## Advisory and host-local: it puts names on the host's result screen and gates
## nothing. Cleared when a rematch is offered, because by then it has been
## acted on, and when a peer drops, because an ask from somebody who has gone
## is not an ask. See docs/decisions.md D124.
var _rematch_asked_for_by: Array[StringName] = []

## The finished match's seats, by peer, kept alive across the reset.
##
## **Two fields of each are read and nothing else:** the display name and the
## Steam ID. A player opting into the rematch sends no arguments (D45), so this
## is where their identity comes from — and taking it from here rather than
## from the packet is what stops a rematch being a chance to rename yourself,
## and what keeps every seat's Steam ID so the new match can be reconnected to
## exactly as any other can.
var _rematch_identities: Dictionary[int, PlayerState] = {}

## Messages passed on per sender, so a client that ignores its own send limit
## cannot flood anybody. Looser than that limit (MessageRules.RELAY_LIMIT).
var _relay_limit: MessageLimiter = MessageLimiter.new(
	MessageRules.RELAY_LIMIT, MessageRules.WINDOW_MSEC
)


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
	steam_id: int = 0,
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
	var seats: Array[PlayerState] = session._authority.state.players
	# The host's own Steam account, so their avatar appears beside everybody
	# else's. 0 for a direct connection, which has no Steam at all.
	if not seats.is_empty():
		seats[0].steam_id = steam_id
		session._host_player_id = seats[0].id
		# So every board knows who is hosting rather than guessing from the
		# order of the list. See GameState.hosted_by.
		session._authority.state.hosted_by = session._host_player_id

	var opened: Dictionary = transport.open_server(MAX_CLIENTS)
	if not String(opened["error"]).is_empty():
		# Freed for the same reason as the client's: nothing puts this Node in
		# the tree on the failure path. See `ClientSession.join`.
		session.free()
		return {"session": null, "error": String(opened["error"])}

	return {"session": session, "error": "", "peer": opened["peer"]}


## Picks a match in progress up on a new host, after the old one walked out.
##
## **The state is this client's own copy, not anybody's word for it.** Every
## client holds a complete snapshot of the match (see the note at the top of
## `state_sync.gd`), so the player Steam hands the lobby to promotes what it
## already had and asks nobody for anything. That is what keeps the handover
## honest: no player can put a figure into this match that the departed host
## did not put there. Collecting positions from the remaining players instead
## would have meant believing them, and avoiding that is why the snapshot
## stopped being redacted. See docs/decisions.md D105.
##
## `state` is that copy, `rng_state` is how far its random stream had run, and
## `host_player_id` is which roster slot the new host plays.
##
## **The lobby is closed and everybody else starts away.** The match is already
## under way, so the roster is the one it was played with, and nobody is
## connected to the new host yet. Each player reclaims their own slot as they
## arrive (`_slot_to_reclaim`); starting them away is also what stops the year
## gate waiting on players who have not reconnected.
##
## They stay in the match while they are away, so the first year after a
## handover pays their dividends and charges their loans exactly as the years
## before it did (D110). Nobody loses a position by being on the wrong side of
## a migration.
##
## Returns `{session, peer, error}`; check `error` first.
static func take_over(
	transport: Transport,
	state: GameState,
	library: ContentLibrary,
	host_player_id: StringName,
	rng_state: int,
) -> Dictionary:
	var refused: String = MatchSetup.why_not_take_over(state)
	if not refused.is_empty():
		return {"session": null, "peer": null, "error": refused}

	var session: HostSession = HostSession.new()
	session.name = NODE_NAME
	session._library = library
	session._transport = transport
	session._lobby_is_open = false
	session._host_player_id = host_player_id

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = state.settings.rng_seed
	session._authority = MatchAuthority.new(
		state, MatchSetup.new_pipeline(state.settings, library), rng
	)
	# The match changed hands, so the board's host marker has to move with it.
	state.hosted_by = host_player_id
	# Where the departed host had got to, so the match does not deal its own
	# past out a second time.
	session._authority.adopt_rng_state(rng_state)

	for player: PlayerState in state.players:
		if player.id == host_player_id:
			# Whoever is running the match is by definition here, whatever the
			# snapshot they promoted happened to say.
			player.is_away = false
			continue
		player.is_away = true
		# Cleared because a reconnecting player has not readied for anything
		# yet on this host.
		player.is_ready = false

	var opened: Dictionary = transport.open_server(MAX_CLIENTS)
	if not String(opened["error"]).is_empty():
		session.free()
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
	_seat(HOST_PEER_ID, _host_player_id)


## Ten players maximum, host included. See docs/game-rules.md §2.
const MAX_PLAYERS: int = MAX_CLIENTS + 1


## How many players this match will hold.
##
## The host picks it on the title screen, 1 to 10, as the original did (audit
## 17.4). It is clamped here rather than trusted: the settings arrive from a
## screen, and a limit of zero or of eleven would be a lobby nobody can join
## or a roster the rankings cannot draw.
##
## **A Steam lobby has its own limit** set at creation from the same number, so
## Steam usually turns a latecomer away before this does. This is the check
## that holds for a direct connection, where nothing else is counting.
func seat_count() -> int:
	return clampi(_authority.state.settings.player_count, 1, MAX_PLAYERS)


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
##
## **Nor is anybody who is away.** Start would otherwise refuse forever on
## account of a player who is not there to press anything — the same deadlock
## for the lobby that D47 fixed for the year.
func waiting_on() -> PackedStringArray:
	var waiting: PackedStringArray = []
	for player: PlayerState in _authority.state.players_present():
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


## How far this match's random stream has run. Travels in every snapshot so
## that whoever takes the match over next continues it rather than re-rolling
## its past. See docs/decisions.md D105.
func rng_state() -> int:
	return _authority.rng_state() if _authority != null else 0


## Which player a peer controls, or an empty id. Exposed for the lobby and for
## tests; nothing in the economy consults it.
func player_for_peer(peer_id: int) -> StringName:
	return _player_by_peer.get(peer_id, &"")


## Every slot's player in roster order, including those whose peer has dropped.
##
## **The same list the economy reads.** It used to be a longer one — the roster
## kept players that `state.players` had dropped — and the two are now the same
## thing. Kept as a name because "the roster" is what the lobby and the
## disconnect notices mean, and because every caller of it already said so.
func roster() -> Array[PlayerState]:
	return _authority.state.players


## Whether this player's peer has gone. An away player is still in the match,
## still paid and still ranked; the year simply does not wait for them.
##
## This was `is_vacated`, which meant the opposite thing about the economy: out
## of it. See docs/decisions.md D110.
func is_away(player_id: StringName) -> bool:
	var player: PlayerState = _authority.state.player_by_id(player_id)
	return player != null and player.is_away


# ------------------------------------------------------------------ the rematch
#
# The host reopens the lobby on a finished match, with the same settings and a
# new seed, and the players who want another game join it. See D124.

func can_offer_rematch() -> bool:
	return _authority.state.is_over and not _lobby_is_open


func rematch_asked_for_by() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for player: PlayerState in _authority.state.players:
		if _rematch_asked_for_by.has(player.id):
			names.append(player.display_name)
	return names


## Reopens the lobby for another match: same settings, new seed, nobody seated
## but the host.
##
## **The roster is not carried over, it is rebuilt from arrivals.** That is what
## makes a player who never answers harmless — they are not in the new roster,
## so `why_not_start` has nothing to wait on, and no timeout or kick is needed
## to get past them. It is D48's rule doing the work: there is no such thing as
## an unclaimed slot.
##
## **A new seed every time.** `build_authority` writes the chosen seed back into
## the settings, so a finished match's settings carry a concrete number and
## reusing them would deal the same market out again. Cleared here for the same
## reason D38 clears it for *Play again*, and a typed seed is not distinguishable
## from a generated one anyway.
##
## **The peer maps are rebuilt, not amended.** `local_player_id()` *is*
## `_player_by_peer[HOST_PEER_ID]`, and every request is resolved through
## `_require_player`, so a stale entry here does not misbehave loudly — it makes
## buttons answer nothing.
func offer_rematch() -> void:
	if not can_offer_rematch():
		return

	# Captured before the reset drops the roster, and only for the two fields
	# `_seat_new_player` needs. See `_rematch_identities`.
	_rematch_identities.clear()
	for peer: int in _player_by_peer:
		var seat: PlayerState = _authority.state.player_by_id(_player_by_peer[peer])
		if seat != null:
			_rematch_identities[peer] = seat

	var host_seat: PlayerState = _rematch_identities.get(HOST_PEER_ID, null)
	var host_name: String = host_seat.display_name if host_seat != null else ""
	var host_steam_id: int = host_seat.steam_id if host_seat != null else 0

	var settings: GameSettings = _authority.state.settings.duplicate() as GameSettings
	settings.rng_seed = 0

	_authority = LocalSession.build_authority(
		settings, _library, [host_name] as Array[String]
	)
	_lobby_is_open = true
	_rematch_asked_for_by.clear()
	# The new match's seats are filled by whoever joins, in that order, so
	# "p1" need not be the same person. A conversation kept under that id
	# would be with the wrong player.
	_messages.clear()

	_player_by_peer.clear()
	_peer_by_player.clear()
	_host_player_id = &"p0"
	_seat(HOST_PEER_ID, _host_player_id)

	var seats: Array[PlayerState] = _authority.state.players
	if not seats.is_empty():
		seats[0].steam_id = host_steam_id
	_authority.state.hosted_by = _host_player_id

	_rpc_rematch_offered.rpc()


## The host's own ask, which there is no such thing as: offering is what the
## host does instead. Here so the interface has one implementation per side.
func ask_for_rematch() -> void:
	pass


## Nor does the host join its own rematch — `offer_rematch` seats it.
func join_rematch() -> void:
	pass


func _on_rematch_asked(peer: int) -> void:
	var player_id: StringName = _require_player(peer)
	if player_id.is_empty() or _rematch_asked_for_by.has(player_id):
		return
	_rematch_asked_for_by.append(player_id)
	rematch_requested.emit(player_id)


## Seats a player who has taken up the offer.
##
## Refused in silence rather than with a reason, because every one of these is
## a packet that should not have been sent: no offer is open, this peer already
## has a seat, or it was not in the finished match at all. None of them is
## something a player did, so there is nothing to tell them.
func _on_rematch_wanted(peer: int) -> void:
	if not _lobby_is_open or _player_by_peer.has(peer):
		return
	var was: PlayerState = _rematch_identities.get(peer, null)
	if was == null:
		return

	var player_id: StringName = _seat_new_player(peer, was.display_name, was.steam_id)
	if player_id.is_empty():
		_turn_away(peer, "That game is full.")
		return

	_rpc_welcome.rpc_id(
		peer, String(player_id), _snapshot(), StateSync.encode_history(state())
	)
	# **And that this is a lobby they have arrived in**, which the welcome
	# cannot say — the same gap D116 filled for a match. Without it their result
	# screen simply stays up.
	_rpc_rematch_joined.rpc_id(peer)
	# **Both, and the signal is not incidental.** `_broadcast_state` skips the
	# host's own peer, so without `player_joined` the host's lobby would not
	# show the player who just arrived. That is the fault D120 was.
	player_joined.emit(player_id)
	_broadcast_state(player_id)


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


# --------------------------------------------------------------------- messages
#
# The host is a relay and nothing more (decisions.md D192). It works out who
# sent a message from the peer id, checks the recipient is in the match, cleans
# the text, applies the rate limit, and hands it to that one recipient. It
# keeps no copy unless it is the recipient, and nothing here touches the match.

## A client's message. Dropped without a reply when refused: an honest client
## has already made the same checks itself (`send_message`), so a refusal here
## means a client that is not playing by them.
func _on_message_sent(peer: int, recipient_id: StringName, raw: String) -> void:
	var sender_id: StringName = _require_player(peer)
	if sender_id.is_empty():
		return
	if not MessageRules.why_not_relay(sender_id, recipient_id, state()).is_empty():
		return
	var text: String = MessageRules.clean(raw)
	if text.is_empty():
		return
	if not _relay_limit.allow(sender_id, _now_msec()):
		return
	_route_message(sender_id, recipient_id, text)


## The host player's own message, already checked by `send_message`.
func _deliver_message(recipient_id: StringName, text: String) -> void:
	_route_message(local_player_id(), recipient_id, text)


## To exactly one place: this machine's book if the host is the recipient,
## otherwise the recipient's peer and no other. A recipient who is away has
## no peer, and the message goes nowhere.
##
## **The ALL PLAYERS room** goes to everybody present except the sender: one
## `rpc_id` per peer, never `rpc()`, so the sender is skipped by name rather
## than by luck (D195). The host's own book gets it unless the host sent it.
func _route_message(sender_id: StringName, recipient_id: StringName, text: String) -> void:
	if recipient_id == MessageRules.ALL_PLAYERS:
		_route_to_room(sender_id, text)
		return
	if _is_host_player(recipient_id):
		_messages.record_received(sender_id, text)
		return
	var peer: int = _peer_by_player.get(recipient_id, 0)
	if peer != 0:
		_rpc_message.rpc_id(peer, String(sender_id), text, false)


func _route_to_room(sender_id: StringName, text: String) -> void:
	for peer: int in _player_by_peer:
		var player_id: StringName = _player_by_peer[peer]
		if player_id == sender_id:
			continue
		if peer == HOST_PEER_ID:
			_messages.record_received(sender_id, text, true)
		else:
			_rpc_message.rpc_id(peer, String(sender_id), text, true)


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
	# With the match, so a StalkleHeads year can go as its inputs (D178).
	var result_data: Dictionary = StateSync.encode_year_result(result, _authority.state)

	# The year's events plus a snapshot, in the same packet, so a client can
	# never render a result against a stale market.
	var snapshot: Dictionary = _snapshot()
	for peer: int in _player_by_peer:
		if peer == HOST_PEER_ID:
			continue
		_rpc_year.rpc_id(peer, result_data, snapshot)

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


## The same snapshot to everybody. Ten players is at most nine small packets,
## which is nothing for a game that changes state when somebody clicks a
## button. See docs/decisions.md D42.
##
## **One snapshot, not one per recipient.** Nothing is redacted any more, so
## there is nothing to vary between peers - and every client holding the same
## complete copy is what makes any of them able to take over as host
## (decisions.md D105).
func _broadcast_state(changed_player_id: StringName) -> void:
	var snapshot: Dictionary = _snapshot()
	for peer: int in _player_by_peer:
		if peer == HOST_PEER_ID:
			continue
		_rpc_state.rpc_id(peer, snapshot, String(changed_player_id))


## The match as it stands, including how far its random stream has run, so a
## client that has to take over as host can carry on rather than restart it.
func _snapshot() -> Dictionary:
	return StateSync.encode_state(_authority.state, _authority.rng_state())


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
func _on_introduced(peer_id: int, player_name: String, steam_id: int = 0) -> void:
	if _player_by_peer.has(peer_id):
		# A second introduction from the same peer. Ignored rather than treated as
		# a rename: the lobby is not a place to change your name, and honouring it
		# mid-match would let a client rewrite the rankings.
		return

	if not _lobby_is_open:
		var refusal: String = why_not_rejoin(steam_id)
		if not refusal.is_empty():
			_turn_away(peer_id, refusal)
			return
		var returning: StringName = _slot_to_reclaim(steam_id)
		_reclaim_slot(peer_id, returning)
		_rpc_welcome.rpc_id(
			peer_id, String(returning), _snapshot(), StateSync.encode_history(state())
		)
		# **And tell them the match is under way**, which is the one thing the
		# welcome does not say. A client that is only welcomed has no way to
		# know whether it has arrived in a lobby or in a game: the snapshot
		# looks the same either way, and year 0 is a real year.
		#
		# Without it, somebody coming back through Steam's friends list or an
		# invite was seated correctly and then stranded on a lobby screen
		# while the match ran on without them - with a Ready button that
		# reached the year gate. REJOIN GAME did not hit this because `Main`
		# suppresses the lobby screen on that route and shows the board itself;
		# every other way in needs to be told. Ordered after the welcome by
		# being reliable on the same channel. See docs/decisions.md D116.
		_rpc_match_started.rpc_id(peer_id)
		player_joined.emit(returning)
		_broadcast_state(returning)
		# Their return may be the last thing the year was waiting on.
		_advance_if_everybody_is_ready()
		return

	var player_id: StringName = _seat_new_player(peer_id, player_name, steam_id)
	if player_id.is_empty():
		_turn_away(peer_id, "That game is full.")
		return

	_rpc_welcome.rpc_id(
		peer_id, String(player_id), _snapshot(), StateSync.encode_history(state())
	)
	player_joined.emit(player_id)
	# Everybody else needs the new arrival in their player list.
	_broadcast_state(player_id)


## Why an arriving Steam account may not come back into this match, or an empty
## string if it may.
##
## **Having a seat comes first, and a finished match is no longer a refusal for
## the player who has one.** D111 turned those people away: the title screen
## offers a match it cannot know has ended, and being welcomed onto a dead board
## read as a turn you could take. The answer was the refusal; it is now the
## result screen, which is where a finished match belongs and what a returning
## player actually wants to see. So this amends D111 rather than reversing it —
## the sentence is kept for anybody who has no seat here. See decisions.md D122.
##
## **It also had to change for host migration.** A handover during the results
## leaves every remaining player holding a finished match, and whoever Steam
## does not pick has to reconnect into one. Refusing them dropped a player to
## the title screen for no reason other than having read the standings on the
## wrong machine — unreachable with two players, because the only client left
## becomes the host.
##
## **A sentence per refusal, decided in one place.** A stranger trying a game
## that is under way and a stranger trying one that has ended are different
## things, and each deserves to know which.
##
## Pure and public so the rule is testable without peers; `_on_introduced` is
## the only caller, and turns the answer into a refusal on the wire.
func why_not_rejoin(steam_id: int) -> String:
	if not _slot_to_reclaim(steam_id).is_empty():
		return ""
	if _authority.state.is_over:
		return "That game has finished."
	return "That game has already started."


## The slot an arriving player may take back, or an empty id for one who may
## not.
##
## **Steam identity is what makes this safe**, and is why it could not be built
## until now - D47 deferred it for exactly this reason. Handing a slot over
## hands over its cash, holdings and loan, so "is this the same person" has to
## be answered by something the arriving client does not get to choose. A Steam
## ID is issued by Steam and comes with the connection; a display name is typed
## in by whoever is connecting. That difference is the whole safeguard.
##
## **A connection with no Steam reclaims nothing.** Direct ENet play has
## `steam_id` 0 and so nothing to recognise anybody by, and letting 0 match 0
## would let any arrival walk into the richest vacant slot. A match played that
## way simply ends when its host leaves.
##
## This serves an ordinary mid-match dropout as much as a migration: a player
## whose connection blinks now returns to their own portfolio instead of being
## turned away, which is the rejoin D47 and porting-plan Phase 8 left open.
func _slot_to_reclaim(steam_id: int) -> StringName:
	if steam_id == 0:
		return &""
	for player: PlayerState in _authority.state.players:
		if player.steam_id != steam_id:
			continue
		if _peer_by_player.has(player.id):
			# That slot is already being played. A second client signed in to
			# one Steam account is not somebody returning.
			return &""
		return player.id
	return &""


## Puts a returning player back at the position the match has made for them.
##
## **Nothing is restored, because nothing was taken away.** Their `PlayerState`
## never left `state.players`, so it has been collecting dividends, splitting
## with its stalks, going bankrupt with them and missing a loan payment every
## year they were gone (D110). What they get back is not the position they left
## but the one the match carried on building for them, which is the point.
##
## So this is only two facts: they are here again, and they have not readied for
## anything.
func _reclaim_slot(peer_id: int, player_id: StringName) -> void:
	var player: PlayerState = _authority.state.player_by_id(player_id)
	if player != null:
		player.is_away = false
		# They were not here for whatever the others have readied for.
		player.is_ready = false
	_seat(peer_id, player_id)


## Creates a fresh player for an arriving peer, or an empty id if the match is
## full.
##
## **An away player's slot is never handed out.** Resuming somebody else's
## position is the rejoin feature, and it is answered by Steam ID in
## `_slot_to_reclaim` — not by being the next person to turn up. In practice no
## arrival gets this far once a match has started anyway, because
## `_on_introduced` turns latecomers away. See D47 and D110.
func _seat_new_player(
	peer_id: int, player_name: String, steam_id: int = 0
) -> StringName:
	var seats: Array[PlayerState] = _authority.state.players
	if seats.size() >= seat_count():
		return &""

	var index: int = seats.size()
	var player: PlayerState = PlayerState.new(
		StringName("p%d" % index),
		sanitised_name(player_name, index),
		_authority.state.settings.starting_cash,
	)
	player.steam_id = steam_id
	seats.append(player)
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


## A dropped peer's player is marked **away**, and the match carries on with
## them still in it.
##
## Two wrong answers came before this one, and the flag is what makes the third
## possible. Leaving the player in the match untouched deadlocked the year,
## because the all-ready gate counted every player and a dropped one could
## never ready up (D46). Taking them out of `state.players` fixed that and cost
## them the match: no dividends, no splits, no loan interest, no place in the
## standings (D47). Being away is neither — they are in the economy and out of
## the gate. See docs/decisions.md D110.
func _on_peer_disconnected(peer_id: int) -> void:
	var player_id: StringName = _player_by_peer.get(peer_id, &"")
	if player_id.is_empty():
		return

	_player_by_peer.erase(peer_id)
	_peer_by_player.erase(player_id)
	# An ask from somebody who has gone is not an ask, and an identity kept for
	# a peer that has dropped would seat a ghost if that peer id came round
	# again. See docs/decisions.md D124.
	_rematch_asked_for_by.erase(player_id)
	_rematch_identities.erase(peer_id)

	if _lobby_is_open:
		# Nothing to preserve and nobody waiting on them: somebody who leaves the
		# lobby was never in the match. Their slot is removed outright so the
		# remaining players keep consecutive ids and a tidy list.
		_forget_player(player_id)
	else:
		var player: PlayerState = _authority.state.player_by_id(player_id)
		if player != null:
			player.is_away = true
			# Cleared so a resumed player is not already ready for a year they
			# were not present for.
			player.is_ready = false

	player_left.emit(player_id)
	_broadcast_state(player_id)

	# Their departure may be the last thing the year was waiting on.
	_advance_if_everybody_is_ready()


## Drops a player from the lobby entirely. Only safe before the match starts:
## afterwards their holdings and their place in the standings matter, which is
## what D47 and D110 are about.
func _forget_player(player_id: StringName) -> void:
	var seats: Array[PlayerState] = _authority.state.players
	for index: int in seats.size():
		if seats[index].id == player_id:
			seats.remove_at(index)
			break


## Records which player a peer controls, both ways round.
func _seat(peer_id: int, player_id: StringName) -> void:
	_player_by_peer[peer_id] = player_id
	_peer_by_player[player_id] = peer_id


## What to call a player, including one who has just dropped.
##
## It used to need its own lookup, because a disconnect took the player out of
## `state.players` at exactly the moment a screen wanted to say "so-and-so
## left". An away player is still in that list (D110), so the ordinary lookup
## now answers. Returns an empty string for an id this host has never seated —
## which is what a player forgotten in the lobby becomes.
func display_name_of(player_id: StringName) -> String:
	var player: PlayerState = _authority.state.player_by_id(player_id)
	return player.display_name if player != null else ""


## The player a peer controls, or an empty id for a peer with no slot. Returning
## empty rather than erroring means a packet from a peer mid-disconnect is simply
## dropped.
func _require_player(peer_id: int) -> StringName:
	return _player_by_peer.get(peer_id, &"")


func _is_host_player(player_id: StringName) -> bool:
	return _player_by_peer.get(HOST_PEER_ID, &"") == player_id
