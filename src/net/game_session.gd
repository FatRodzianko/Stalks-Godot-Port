class_name GameSession
extends Node
## What the UI talks to. Owns "who is playing and who is allowed to do what",
## and hides whether the game is local, hosted, or joined.
##
## Abstract — see LocalSession for the offline implementation, and
## docs/architecture.md §5.
##
## **This is a Node, not a RefCounted.** The later HostSession and ClientSession
## need to issue `@rpc` calls, which requires being in the scene tree with a
## MultiplayerAPI. Making the base class a Node now means the UI's contract does
## not change when multiplayer arrives. See docs/decisions.md D32.
##
## The UI never reads rules and never mutates state. It calls a `request_*`
## method and waits for a signal. In a hosted game those requests become RPCs and
## the signals fire when the host answers; the UI cannot tell the difference.


## A year advance completed. Carries everything that happened, so the UI can
## present it without re-deriving anything.
signal year_resolved(result: YearResult)

## A player's cash, holdings or loan changed outside a year advance — normally
## because they bought, sold, borrowed or paid.
signal player_changed(player_id: StringName)

## A request was refused. `reason` is player-facing text, already written for
## display. The UI shows it; it does not interpret it.
signal action_rejected(player_id: StringName, reason: String)

## A player readied up or un-readied. The UI uses this to show who is waiting.
signal ready_state_changed(player_id: StringName, is_ready: bool)

## The match ended. `winners` may hold more than one id — ties are possible.
signal game_over(winners: Array[StringName])

## Somebody asked for a yeehaw. Every player hears about it, including the asker,
## so their own UI can show that the ask went out.
signal yeehaw_requested(player_id: StringName)

## Somebody gave one. Every player hears about it and plays the sound — see
## docs/game-rules.md §10.
signal yeehaw_given(giver_id: StringName, receiver_id: StringName)

## The host has reopened the lobby and is willing to play again. The result
## screen turns this into a way in; nothing else listens.
signal rematch_offered

## Somebody asked the host for another game. Host-side only — a client is never
## told who else asked, because nothing it could do with that is a rule. The
## host's result screen uses it to name them.
signal rematch_requested(player_id: StringName)

## This machine now has a seat in the rematch lobby, so the screen host should
## show the lobby. See `networked_session.gd` for why this is its own signal.
signal rematch_joined


## This machine's private messages (decisions.md D192). Lives on the session
## because the session is what receives them; never part of `state()`.
var _messages: MessageBook = MessageBook.new()

## This machine's own send limit. The host has a looser one of its own.
var _send_limit: MessageLimiter = MessageLimiter.new(
	MessageRules.SEND_LIMIT, MessageRules.WINDOW_MSEC
)


## The live match state. Read-only as far as the UI is concerned: look at it to
## render, never write to it.
func state() -> GameState:
	push_error("GameSession.state is abstract")
	return null


## The player this machine controls.
func local_player_id() -> StringName:
	push_error("GameSession.local_player_id is abstract")
	return &""


## Whether `player_id` is controlled from this machine. Always true in a local
## game; in a hosted one it gates which controls are interactive.
func controls(player_id: StringName) -> bool:
	return player_id == local_player_id()


# ------------------------------------------------------------------ the requests
#
# Each takes the acting player's id explicitly rather than assuming the local
# one, because the host executes requests on behalf of other players too.

func request_buy(_player_id: StringName, _stalk_id: StringName, _shares: int) -> void:
	push_error("GameSession.request_buy is abstract")


func request_sell(_player_id: StringName, _stalk_id: StringName, _shares: int) -> void:
	push_error("GameSession.request_sell is abstract")


func request_loan(_player_id: StringName, _amount: int) -> void:
	push_error("GameSession.request_loan is abstract")


func pay_loan(_player_id: StringName, _amount: int) -> void:
	push_error("GameSession.pay_loan is abstract")


func set_ready(_player_id: StringName, _is_ready: bool) -> void:
	push_error("GameSession.set_ready is abstract")


## "Can I get a yeehaw?" — notifies everybody else, and nothing more.
func request_yeehaw(_player_id: StringName) -> void:
	push_error("GameSession.request_yeehaw is abstract")


## Answers whoever is currently asking. There is no receiver argument on
## purpose: one request is pending at a time, so a giver cannot pick a target,
## and a client therefore cannot forge either end of the gesture.
func give_yeehaw(_giver_id: StringName) -> void:
	push_error("GameSession.give_yeehaw is abstract")


# ------------------------------------------------------------------ messages
#
# Private, text-only, and outside the game: the host passes each message to its
# one recipient and keeps nothing. See docs/decisions.md D192 and D193.

## This machine's conversations. Read it to render; the session writes it.
func messages() -> MessageBook:
	return _messages


## Sends `raw` from this machine's player to `recipient_id`, or writes it as a
## note when the recipient is this player. Returns why it was not sent, or an
## empty string - and what was sent is in `messages()` straight away.
##
## These are the same checks the host makes, run first so a refusal can be
## shown beside the send box. The host makes them again (D45): this is a
## courtesy, not the security.
func send_message(recipient_id: StringName, raw: String) -> String:
	var writer_id: StringName = local_player_id()
	if writer_id.is_empty():
		return "Not connected."
	var text: String = MessageRules.clean(raw)
	if text.is_empty():
		return "Nothing to send."
	if recipient_id == writer_id:
		_messages.record_sent(writer_id, writer_id, text)
		return ""
	var reason: String = MessageRules.why_not_relay(writer_id, recipient_id, state())
	if not reason.is_empty():
		return reason
	if recipient_id != MessageRules.ALL_PLAYERS:
		var recipient: PlayerState = state().player_by_id(recipient_id)
		if recipient.is_away:
			return "%s is not here, so it would not arrive." % recipient.display_name
	if not _send_limit.allow(writer_id, _now_msec()):
		return "Too many messages. Wait a few seconds."
	_messages.record_sent(writer_id, recipient_id, text)
	_deliver_message(recipient_id, text)
	return ""


## Puts an already-checked message on its way. Nowhere to go offline: a local
## game has no other machine (hot-seat play is not supported).
func _deliver_message(_recipient_id: StringName, _text: String) -> void:
	pass


## The clock both rate limits read.
func _now_msec() -> int:
	return Time.get_ticks_msec()


# ------------------------------------------------------------------ the rematch
#
# A rematch is the host reopening the lobby after a match has ended, with the
# same settings and a new seed. Players who want one join that lobby; players
# who do not stay on the result screen and are simply not in the next match.
#
# Nothing here is a rule, so nothing is validated: the host decides when to
# offer and when to press Play, and the only authority check is that a client
# cannot do either. Doing nothing is the right answer for a solo game, which is
# why these are empty rather than abstract. See docs/decisions.md D124.

## Whether this session can offer a rematch — true only on a networked host.
func can_offer_rematch() -> bool:
	return false


## Whether the host has offered one that this machine could join.
func rematch_is_offered() -> bool:
	return false


## Reopens the lobby for another match. Host only.
func offer_rematch() -> void:
	pass


## Asks the host for another game. Advisory: it names the asker on the host's
## result screen and gates nothing.
func ask_for_rematch() -> void:
	pass


## Takes a seat in the rematch the host has offered.
func join_rematch() -> void:
	pass


## Display names of the players who have asked for another game, in roster
## order. Empty on a client, which is never told who else asked.
func rematch_asked_for_by() -> PackedStringArray:
	return PackedStringArray()


# ------------------------------------------------------------- local pre-checks
#
# The UI calls these to grey out or red-flag a control before anything is sent.
# They run the SAME functions the authority runs, so a pre-check can never
# disagree with enforcement — see docs/architecture.md §5.1. They are
# presentation only: a client is never a second source of truth.

## Empty string means the action would be allowed.
func why_not_buy(player_id: StringName, stalk_id: StringName, shares: int) -> String:
	var game: GameState = state()
	if game == null:
		return "No game in progress."
	var player: PlayerState = game.player_by_id(player_id)
	var stalk: StalkState = game.stalk_by_id(stalk_id)
	if player == null or stalk == null:
		return "Unknown player or stalk."
	return TradeRules.validate_buy(player, stalk, shares, game)


func why_not_sell(player_id: StringName, stalk_id: StringName, shares: int) -> String:
	var game: GameState = state()
	if game == null:
		return "No game in progress."
	var player: PlayerState = game.player_by_id(player_id)
	var stalk: StalkState = game.stalk_by_id(stalk_id)
	if player == null or stalk == null:
		return "Unknown player or stalk."
	return TradeRules.validate_sell(player, stalk, shares, game)


func why_not_loan(player_id: StringName, amount: int) -> String:
	var game: GameState = state()
	if game == null:
		return "No game in progress."
	var player: PlayerState = game.player_by_id(player_id)
	if player == null:
		return "Unknown player."
	return LoanRules.validate_take_loan(player, amount, game)


func why_not_request_yeehaw(player_id: StringName) -> String:
	var game: GameState = state()
	if game == null:
		return "No game in progress."
	return YeehawRules.validate_request(player_id, game)


func why_not_give_yeehaw(giver_id: StringName) -> String:
	var game: GameState = state()
	if game == null:
		return "No game in progress."
	return YeehawRules.validate_give(giver_id, game)


## Who is currently asking for a yeehaw, or an empty id. The UI reads this to
## decide whether its button asks for one or offers one.
func yeehaw_requested_by() -> StringName:
	var game: GameState = state()
	return game.yeehaw_requested_by if game != null else &""


## The most shares of `stalk_id` that `player_id` could afford right now.
func max_affordable(player_id: StringName, stalk_id: StringName) -> int:
	var game: GameState = state()
	if game == null:
		return 0
	var player: PlayerState = game.player_by_id(player_id)
	var stalk: StalkState = game.stalk_by_id(stalk_id)
	if player == null or stalk == null:
		return 0
	return TradeRules.max_affordable(player, stalk)
