class_name NpcDesk
extends RefCounted
## The NPC desk of StalkleHeads mode: about twenty-four simulated traders, three
## per strategy, who trade on the published state after every year settles and
## whose net trading becomes next year's `flow` (docs/stalkleheads-design.md §5,
## §4 step 13, decisions.md D162-D164).
##
## They are **not players**: not ranked, cannot win, never in the ready gate.
## They exist to be watched - a room full of the readings a player might make,
## each personified - and because their trading moves prices, reading them is a
## route to winning (§5.2).
##
## **Determinism (§5.4) is three rules, all held here:**
##
## 1. Traders act in sorted id order, never load or dictionary order.
## 2. Each trader draws **exactly DRAWS_PER_TRADER times a year**, before it
##    decides anything, whether or not it then uses the draws. A trader that only
##    rolled when it had cash would make every later draw in the match depend on
##    history.
## 3. A decision is a pure function of (`GameState`, the trader, its two draws).
##
## Pure simulation: RefCounted, no nodes, no autoloads, the RNG passed in.
##
## **How a trader trades.** Every strategy but SHORT holds one target at a time:
## it sells everything else at the posted price, then spends
## `cash * conviction * appetite / 10000` on the target, rounding shares down.
## The SHORT trader buys back any short not on its target, then sizes its short
## on the target at `worth * conviction * appetite / 10000`, selling more or
## buying back to reach it. The draws are the appetite (70-130) and a pick
## (0-9999), which only PANIC uses, to choose what to buy back in a bull year.


## Draws per trader per year: the appetite, then the pick. Never fewer, never more.
const DRAWS_PER_TRADER: int = 2

## The appetite draw, in percent of the trader's conviction (§5.1).
const APPETITE_MIN: int = 70
const APPETITE_MAX: int = 130

## The pick draw's range: 0 to PICK_RANGE - 1.
const PICK_RANGE: int = 10000


## Every trader, sorted by id.
var traders: Array[NpcTraderState] = []


## A desk of fresh traders, each at its starting cash, sorted by id.
static func from_definitions(definitions: Array[NpcTraderDefinition]) -> NpcDesk:
	var desk: NpcDesk = NpcDesk.new()
	for definition: NpcTraderDefinition in definitions:
		if definition != null:
			desk.traders.append(NpcTraderState.new(definition))
	desk.traders.sort_custom(_trader_order)
	return desk


func trader_by_id(trader_id: StringName) -> NpcTraderState:
	for trader: NpcTraderState in traders:
		if trader.id == trader_id:
			return trader
	return null


## §4 step 13: every trader acts once, in id order, on the settled state.
## Returns what they did; the caller records `net_shares` into the flow input.
func act(state: GameState, rng: RandomNumberGenerator) -> NpcDeskYear:
	var year: NpcDeskYear = NpcDeskYear.new()
	for trader: NpcTraderState in traders:
		# Draw first, always (§5.4).
		var appetite: int = rng.randi_range(APPETITE_MIN, APPETITE_MAX)
		var pick: int = rng.randi_range(0, PICK_RANGE - 1)

		var target: StringName = choose_target(trader.strategy, state, pick)
		year.trader_ids.append(trader.id)
		year.appetites[trader.id] = appetite
		year.targets[trader.id] = target
		if NpcStrategy.is_short(trader.strategy):
			year.actions[trader.id] = _trade_short(trader, target, appetite, state, year)
		else:
			year.actions[trader.id] = _trade_long(trader, target, appetite, state, year)
	return year


## The shares a trader is short in a company, summed across the desk. **This is
## the short interest** the Company tab publishes and the event weighting reads
## (§5.3).
func short_interest(company_id: StringName) -> int:
	var total: int = 0
	for trader: NpcTraderState in traders:
		total += trader.short_of(company_id)
	return total


## Living companies whose short interest is flagged
## (`ShortInterestRules.is_flagged`), most shorted first by percent of shares
## outstanding, ties by id.
func flagged_companies(state: GameState) -> Array[StringName]:
	var scored: Array[Array] = []
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row == null or row.is_bankrupt:
			continue
		var interest: int = short_interest(company.id)
		if ShortInterestRules.is_flagged(interest, company.shares_outstanding):
			scored.append([-ShortInterestRules.percent_of(interest, company.shares_outstanding), company.id])
	scored.sort_custom(_score_then_id)
	var flagged: Array[StringName] = []
	for entry: Array in scored:
		flagged.append(entry[1])
	return flagged


## The trader worth most at the posted prices, ties to the lowest id. What a
## FOLLOW player copies (§5.2). Null for an empty desk.
func best_trader(state: GameState) -> NpcTraderState:
	var best: NpcTraderState = null
	var best_worth: int = 0
	for trader: NpcTraderState in traders:
		var worth: int = trader.worth(state)
		if best == null or worth > best_worth:
			best = trader
			best_worth = worth
	return best


# ------------------------------------------------- what the year does to them

## A row went bankrupt: every holder's shares are worthless, and every short in
## it is closed at zero, so the SHORT trader keeps what it sold them for.
func wipe_out(stalk_id: StringName) -> void:
	for trader: NpcTraderState in traders:
		trader.set_shares(stalk_id, 0)
		trader.set_short(stalk_id, 0)


## A row split: shares held and shares short both double, as a player's do.
func split(stalk_id: StringName) -> void:
	for trader: NpcTraderState in traders:
		trader.set_shares(stalk_id, trader.shares_of(stalk_id) * 2)
		trader.set_short(stalk_id, trader.short_of(stalk_id) * 2)


## Dividends, per share by stalk id, as the year paid them. A holder is paid; a
## short seller pays, as a short seller does.
func settle_dividends(dividend_per_share: Dictionary[StringName, int]) -> void:
	for trader: NpcTraderState in traders:
		for stalk_id: StringName in trader.held_ids():
			trader.cash += trader.shares_of(stalk_id) * dividend_per_share.get(stalk_id, 0)
		for company_id: StringName in trader.shorted_ids():
			trader.cash -= trader.short_of(company_id) * dividend_per_share.get(company_id, 0)


# ------------------------------------------------------------- the strategies

## The target `act` trades on: `target_for`, unchanged. **A seam for the
## balance tool only**, which overrides it to sweep the SHORT trader's target
## (tools/balance/lever_desk.gd, decisions.md D168); nothing in the game
## overrides it.
func choose_target(strategy: NpcStrategy.Value, state: GameState, pick: int) -> StringName:
	return target_for(strategy, state, pick)


## What a strategy wants this year, read from the published state, or `&""`
## when nothing qualifies. Ties break to the lowest id. `pick` is the trader's
## pick draw; only PANIC uses it. Pure.
##
## - VALUE: lowest P/E (price over earnings per share), positive earnings only.
## - MOMENTUM / CONTRARIAN: highest / lowest Yearly Change.
## - INCOME: highest dividend yield, from this year's dividend per share.
## - INDEXER: My Mutuals and Me Inc., while it is not bankrupt.
## - PANIC: the bond in a bear year; in a bull year a living company chosen by
##   `pick`, so the three PANIC traders do not move as one block.
## - GROWTH / SHORT: highest / lowest profit growth over the latest season,
##   where there was a positive profit to grow from.
static func target_for(strategy: NpcStrategy.Value, state: GameState, pick: int) -> StringName:
	var market: EarningsMarket = state.market
	var alive: Array[CompanyState] = []
	for company: CompanyState in market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row != null and not row.is_bankrupt and row.price > 0:
			alive.append(company)

	var scored: Array[Array] = []
	match strategy:
		NpcStrategy.Value.INDEXER:
			var index_row: StalkState = state.stalk_by_id(EarningsMarket.INDEX_ID)
			if index_row == null or index_row.is_bankrupt or index_row.price <= 0:
				return &""
			return EarningsMarket.INDEX_ID
		NpcStrategy.Value.PANIC:
			if market.last_mood == MarketMood.Value.BEAR:
				if state.stalk_by_id(EarningsMarket.BOND_ID) == null:
					return &""
				return EarningsMarket.BOND_ID
			if alive.is_empty():
				return &""
			return alive[pick % alive.size()].id
		NpcStrategy.Value.VALUE:
			for company: CompanyState in alive:
				var eps: float = company.earnings_per_share()
				if eps > 0.0:
					scored.append([float(company.price) / eps, company.id])
		NpcStrategy.Value.MOMENTUM, NpcStrategy.Value.CONTRARIAN:
			for company: CompanyState in alive:
				var change: float = float(state.stalk_by_id(company.id).last_yearly_change)
				if strategy == NpcStrategy.Value.MOMENTUM:
					change = -change
				scored.append([change, company.id])
		NpcStrategy.Value.INCOME:
			for company: CompanyState in alive:
				var paid: float = float(company.dividend_per_share())
				scored.append([-paid / float(company.price), company.id])
		NpcStrategy.Value.GROWTH, NpcStrategy.Value.SHORT:
			for company: CompanyState in alive:
				var growth: float = company.profit_growth_percent()
				if is_nan(growth):
					continue
				if strategy == NpcStrategy.Value.GROWTH:
					growth = -growth
				scored.append([growth, company.id])
	if scored.is_empty():
		return &""
	scored.sort_custom(_score_then_id)
	return scored[0][1]


# ------------------------------------------------------------------ trading

## Sell everything but the target, then buy the target with
## `cash * conviction * appetite / 10000`.
func _trade_long(
	trader: NpcTraderState,
	target: StringName,
	appetite: int,
	state: GameState,
	year: NpcDeskYear,
) -> NpcTraderDefinition.Situation:
	if target == &"":
		return NpcTraderDefinition.Situation.HELD

	var sold: bool = false
	for stalk_id: StringName in trader.held_ids():
		if stalk_id == target:
			continue
		var held: int = trader.shares_of(stalk_id)
		var row: StalkState = state.stalk_by_id(stalk_id)
		if row != null and row.price > 0:
			trader.cash += held * row.price
			year.add_net(stalk_id, -held)
			sold = true
		trader.set_shares(stalk_id, 0)

	var price: int = state.stalk_by_id(target).price
	var bought: int = 0
	if price > 0 and trader.cash > 0:
		# Rounds down twice, toward zero: to whole coins, then to whole shares.
		@warning_ignore("integer_division")
		var spend: int = trader.cash * trader.definition.conviction * appetite / 10000
		@warning_ignore("integer_division")
		bought = spend / price
	if bought > 0:
		trader.cash -= bought * price
		trader.set_shares(target, trader.shares_of(target) + bought)
		year.add_net(target, bought)
		return NpcTraderDefinition.Situation.BOUGHT
	if sold:
		return NpcTraderDefinition.Situation.SOLD
	return NpcTraderDefinition.Situation.HELD


## Buy back every short not on the target, then bring the target's short to
## `worth * conviction * appetite / 10000` of shares at the posted price.
## With no target, every short is left as it is.
func _trade_short(
	trader: NpcTraderState,
	target: StringName,
	appetite: int,
	state: GameState,
	year: NpcDeskYear,
) -> NpcTraderDefinition.Situation:
	if target == &"":
		return NpcTraderDefinition.Situation.HELD

	var covered: bool = false
	for company_id: StringName in trader.shorted_ids():
		if company_id == target:
			continue
		var owed: int = trader.short_of(company_id)
		var row: StalkState = state.stalk_by_id(company_id)
		if row != null and row.price > 0:
			trader.cash -= owed * row.price
			year.add_net(company_id, owed)
			covered = true
		trader.set_short(company_id, 0)

	var price: int = state.stalk_by_id(target).price
	var wanted: int = 0
	var worth: int = trader.worth(state)
	if worth > 0:
		@warning_ignore("integer_division")
		wanted = worth * trader.definition.conviction * appetite / 10000 / price
	var change: int = wanted - trader.short_of(target)
	if change > 0:
		trader.cash += change * price
		trader.set_short(target, wanted)
		year.add_net(target, -change)
		return NpcTraderDefinition.Situation.SHORTED
	if change < 0:
		trader.cash += change * price
		trader.set_short(target, wanted)
		year.add_net(target, -change)
		covered = true
	if covered:
		return NpcTraderDefinition.Situation.COVERED
	return NpcTraderDefinition.Situation.HELD


static func _trader_order(a: NpcTraderState, b: NpcTraderState) -> bool:
	return String(a.id) < String(b.id)


## Entries are [score, id]: lowest score first, then lowest id.
static func _score_then_id(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return String(a[1]) < String(b[1])
