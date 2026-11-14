class_name TradeRules
extends RefCounted
## Buying, selling, net worth and standings. All static, all pure.
##
## The validation functions here are the SINGLE implementation of what counts as a
## legal action. The host calls them to enforce; a client calls the same functions
## to reject obviously-invalid input instantly without a round trip. One
## implementation called from two places, so a client's pre-check can never drift
## from the host's enforcement. See docs/architecture.md §5.1.
##
## Validation returns an empty string for "allowed", or a player-facing reason why
## not. The original failed silently on an unaffordable purchase; the port must
## always be able to say what went wrong. See docs/game-rules.md §11.


## A stalk splits once its price is strictly ABOVE this.
const SPLIT_ABOVE: int = 150

## A stalk goes bankrupt at or below this.
const BANKRUPT_AT_OR_BELOW: int = 0


# ---------------------------------------------------------------- buying/selling

static func purchase_cost(stalk: StalkState, shares: int) -> int:
	return stalk.price * shares


## The most shares of `stalk` that `player` could currently afford. Returns 0 for
## a worthless stalk rather than dividing by zero.
static func max_affordable(player: PlayerState, stalk: StalkState) -> int:
	if not stalk.has_value():
		return 0
	@warning_ignore("integer_division")
	var affordable: int = player.cash / stalk.price
	return affordable


static func validate_buy(
	player: PlayerState,
	stalk: StalkState,
	shares: int,
	state: GameState,
) -> String:
	if not state.is_trading_open():
		return "Trading is closed."
	if player.is_bankrupt:
		return "You are bankrupt."
	if shares <= 0:
		return "Enter a number of shares to buy."
	if stalk.is_bankrupt:
		return "%s is bankrupt." % stalk.definition.display_name
	var cost: int = purchase_cost(stalk, shares)
	if cost > player.cash:
		return "That costs %d, and you have %d." % [cost, player.cash]
	return ""


static func validate_sell(
	player: PlayerState,
	stalk: StalkState,
	shares: int,
	state: GameState,
) -> String:
	if not state.is_trading_open():
		return "Trading is closed."
	if shares <= 0:
		return "Enter a number of shares to sell."
	var held: int = player.shares_of(stalk.id)
	if held <= 0:
		return "You own no shares of %s." % stalk.definition.display_name
	if shares > held:
		return "You only own %d shares." % held
	if stalk.is_bankrupt:
		return "%s is bankrupt — its shares are worthless." % stalk.definition.display_name
	return ""


## Applies a purchase. Caller must have validated first; this does not re-check.
static func apply_buy(player: PlayerState, stalk: StalkState, shares: int) -> void:
	player.cash -= purchase_cost(stalk, shares)
	player.add_shares(stalk.id, shares)


## Applies a sale. Caller must have validated first.
static func apply_sell(player: PlayerState, stalk: StalkState, shares: int) -> void:
	player.cash += stalk.price * shares
	player.add_shares(stalk.id, -shares)


# -------------------------------------------------------------------- net worth

## cash + value of holdings - outstanding loan.
##
## Worthless stalks contribute nothing: the original guarded on `price > 0`, and
## bankruptcy zeroes holdings anyway, so both guards are kept.
## See docs/game-rules.md §1.
static func net_worth(player: PlayerState, state: GameState) -> int:
	var total: int = player.cash
	for stalk: StalkState in state.stalks:
		if not stalk.has_value():
			continue
		total += stalk.price * player.shares_of(stalk.id)
	total -= player.owes()
	return total


## Total market value of a player's holdings, excluding cash and loans.
static func holdings_value(player: PlayerState, state: GameState) -> int:
	var total: int = 0
	for stalk: StalkState in state.stalks:
		if stalk.has_value():
			total += stalk.price * player.shares_of(stalk.id)
	return total


# --------------------------------------------------------------------- standings

## Player ids ordered best first: net worth, then cash on hand as the tie-break.
static func rank(players: Array[PlayerState]) -> Array[StringName]:
	var ordered: Array[PlayerState] = players.duplicate()
	ordered.sort_custom(_compare_standing)
	var ids: Array[StringName] = []
	for player: PlayerState in ordered:
		ids.append(player.id)
	return ids


## Everyone tied at the top. If two players match on BOTH net worth and cash, they
## both win — see docs/game-rules.md §1.
static func winners(players: Array[PlayerState]) -> Array[StringName]:
	var result: Array[StringName] = []
	if players.is_empty():
		return result

	var ordered: Array[PlayerState] = players.duplicate()
	ordered.sort_custom(_compare_standing)
	var best: PlayerState = ordered[0]
	for player: PlayerState in ordered:
		if player.net_worth == best.net_worth and player.cash == best.cash:
			result.append(player.id)
		else:
			break
	return result


static func _compare_standing(a: PlayerState, b: PlayerState) -> bool:
	if a.net_worth != b.net_worth:
		return a.net_worth > b.net_worth
	return a.cash > b.cash
