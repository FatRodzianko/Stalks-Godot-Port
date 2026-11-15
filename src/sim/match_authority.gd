class_name MatchAuthority
extends RefCounted
## The one place a match is allowed to change. Validates an action, applies it,
## and says yes or no.
##
## Pure: no nodes, no signals, no peers, no `await`. A session wraps this and
## turns its return values into signals; the host wraps the same object and also
## broadcasts. One implementation of "what actually happens", used by offline play
## and by the host alike, so the two can never drift apart.
##
## **Every method returns a rejection reason, or an empty string for accepted.**
## Nothing here throws, pushes an error, or decides how to tell the player — that
## is presentation, and it lives in the session and the UI.
##
## This exists because the rules must not live in a Node. See docs/decisions.md
## D43 and the architecture rule in CLAUDE.md: if a change makes the economy
## depend on the scene tree, the change is wrong.


var state: GameState
var _resolver: YearResolver
var _rng: RandomNumberGenerator


func _init(
	game_state: GameState,
	resolver: YearResolver,
	rng: RandomNumberGenerator,
) -> void:
	state = game_state
	_resolver = resolver
	_rng = rng


# -------------------------------------------------------------------- the actions

func buy(player_id: StringName, stalk_id: StringName, shares: int) -> String:
	var player: PlayerState = state.player_by_id(player_id)
	var stalk: StalkState = state.stalk_by_id(stalk_id)
	if player == null or stalk == null:
		return "Unknown player or stalk."

	var reason: String = TradeRules.validate_buy(player, stalk, shares, state)
	if not reason.is_empty():
		return reason

	TradeRules.apply_buy(player, stalk, shares)
	player.net_worth = TradeRules.net_worth(player, state)
	return ""


func sell(player_id: StringName, stalk_id: StringName, shares: int) -> String:
	var player: PlayerState = state.player_by_id(player_id)
	var stalk: StalkState = state.stalk_by_id(stalk_id)
	if player == null or stalk == null:
		return "Unknown player or stalk."

	var reason: String = TradeRules.validate_sell(player, stalk, shares, state)
	if not reason.is_empty():
		return reason

	TradeRules.apply_sell(player, stalk, shares)
	player.net_worth = TradeRules.net_worth(player, state)
	return ""


func take_loan(player_id: StringName, amount: int) -> String:
	var player: PlayerState = state.player_by_id(player_id)
	if player == null:
		return "Unknown player."

	var reason: String = LoanRules.validate_take_loan(player, amount, state)
	if not reason.is_empty():
		return reason

	LoanRules.take_loan(player, amount)
	player.net_worth = TradeRules.net_worth(player, state)
	return ""


func pay_loan(player_id: StringName, amount: int) -> String:
	var player: PlayerState = state.player_by_id(player_id)
	if player == null:
		return "Unknown player."

	var reason: String = LoanRules.validate_payment(player, amount)
	if not reason.is_empty():
		return reason

	LoanRules.apply_payment(player, amount)
	player.net_worth = TradeRules.net_worth(player, state)
	return ""


## Marks a player ready or un-ready. Does **not** advance the year — the caller
## checks `state.all_players_ready()` and calls `advance_year()`, so that the
## session can emit the readiness change before the year resolves.
##
## The loan payment prompt is deliberately advisory: a player with an unpaid loan
## may ready up and take the penalty. The game must never withhold that choice —
## see docs/game-rules.md §9.5.
func set_ready(player_id: StringName, is_ready: bool) -> String:
	if state.is_over:
		return "The game is over."

	var player: PlayerState = state.player_by_id(player_id)
	if player == null:
		return "Unknown player."

	player.is_ready = is_ready
	return ""


func request_yeehaw(player_id: StringName) -> String:
	return YeehawRules.validate_request(player_id, state)


func give_yeehaw(giver_id: StringName, receiver_id: StringName) -> String:
	return YeehawRules.validate_give(giver_id, receiver_id, state)


## Resolves one year. Call only when every player is ready.
func advance_year() -> YearResult:
	return _resolver.advance_year(state, _rng)


## The seed this match is running on. What makes it reproducible, and worth
## quoting in a bug report.
func seed_value() -> int:
	return state.settings.rng_seed if state != null and state.settings != null else 0
