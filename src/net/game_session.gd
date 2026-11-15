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


## Answers somebody's ask. `receiver_id` is who gets it; the giver cannot be the
## receiver.
func give_yeehaw(_giver_id: StringName, _receiver_id: StringName) -> void:
	push_error("GameSession.give_yeehaw is abstract")


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


func why_not_give_yeehaw(giver_id: StringName, receiver_id: StringName) -> String:
	var game: GameState = state()
	if game == null:
		return "No game in progress."
	return YeehawRules.validate_give(giver_id, receiver_id, game)


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
