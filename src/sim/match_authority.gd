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


## Records the request, so that everybody else's button can offer to answer it.
func request_yeehaw(player_id: StringName) -> String:
	var reason: String = YeehawRules.validate_request(player_id, state)
	if not reason.is_empty():
		return reason
	state.yeehaw_requested_by = player_id
	return ""


## Answers the pending request and clears it. `receiver_of_yeehaw()` says who it
## went to; call it before this, or keep the id yourself.
func give_yeehaw(giver_id: StringName) -> String:
	var reason: String = YeehawRules.validate_give(giver_id, state)
	if not reason.is_empty():
		return reason
	state.yeehaw_requested_by = &""
	return ""


## Who a yeehaw given right now would go to, or an empty id.
func receiver_of_yeehaw() -> StringName:
	return state.yeehaw_requested_by


## Resolves one year. Call only when every player is ready.
##
## An unanswered request does not survive the year. The original left it pending
## forever, which meant one ignored ask locked the button into "Give Yeehaw" for
## the rest of the match and nobody could ask again. A new year is the natural
## place to let it go. See docs/decisions.md D52.
func advance_year() -> YearResult:
	state.yeehaw_requested_by = &""
	return _resolver.advance_year(state, _rng)


## How far this match's random stream has run.
##
## **Part of match state, not a detail of the generator.** A match is
## reproducible from its seed plus the number of draws taken off it, so a new
## host taking over mid-match needs this as much as it needs the prices: seeded
## afresh from `rng_seed` it would deal year one's rolls out all over again.
## Travels in every snapshot (`state_sync.gd`). See docs/decisions.md D105.
func rng_state() -> int:
	return int(_rng.state)


## Picks the random stream up where another host left it.
func adopt_rng_state(value: int) -> void:
	_rng.state = value


## The seed this match is running on. What makes it reproducible, and worth
## quoting in a bug report.
func seed_value() -> int:
	return state.settings.rng_seed if state != null and state.settings != null else 0
