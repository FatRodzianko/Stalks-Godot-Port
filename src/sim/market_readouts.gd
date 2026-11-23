class_name MarketReadouts
extends RefCounted
## Every figure the StalkleHeads screens show that is not stored anywhere:
## P/E, industry averages, market share, the desk by strategy, short interest,
## a company's year-by-year record. See docs/stalkleheads-design.md §7 and
## decisions.md D179.
##
## **Why these live in `sim` and not in the screens.** CLAUDE.md forbids a node
## computing a game rule inline, and design §9.1 says derived figures are
## recomputed by whoever shows them from the inputs that travelled. Both point
## here: one pure function per readout, called by the host's screen and a
## client's screen alike, and testable with no screen at all.
##
## **Nothing here changes anything.** Every function reads a `GameState` (and
## its `market` and `history`) and returns a number or a list. None draws from
## an RNG, none writes. A ratio is a float, as every ratio in this mode is
## (decisions.md D130); a money figure is an `int`.
##
## Pure: static functions only, no state, no nodes.


## How a figure that does not exist is reported: a P/E with no earnings, an
## average of nothing. The screens print it as "--".
const NONE: float = NAN


# ------------------------------------------------------------ one company

## Price over earnings per share. `NONE` when earnings are zero or negative,
## because a P/E of a loss-maker is not a smaller or larger number, it is not
## a number at all - and a negative one would sort as the cheapest company on
## the board.
static func price_earnings(price: int, earnings_per_share: float) -> float:
	if earnings_per_share <= 0.0 or price <= 0:
		return NONE
	return float(price) / earnings_per_share


## A company's P/E on its posted board price.
static func company_pe(state: GameState, company: CompanyState) -> float:
	var row: StalkState = state.stalk_by_id(company.id)
	if row == null or row.is_bankrupt:
		return NONE
	return price_earnings(row.price, company.earnings_per_share())


## The dividend per share a board row shows: what it paid in the latest year,
## or what it would pay on its year-0 figures before any year has run. 0 for a
## bankrupt row.
static func dividend_shown(state: GameState, stalk_id: StringName) -> int:
	var row: StalkState = state.stalk_by_id(stalk_id)
	if row == null or row.is_bankrupt:
		return 0
	var latest: EarningsYearResult = state.latest_result() as EarningsYearResult
	if latest != null and latest.dividend_per_share.has(stalk_id):
		return latest.dividend_per_share[stalk_id]
	var market: EarningsMarket = state.market
	var company: CompanyState = market.company_by_id(stalk_id)
	if company != null:
		return company.dividend_per_share()
	if row.is_price_static():
		return EarningsMarket.bond_coupon(row.definition)
	return _average_company_dividend(state)


## Its earnings yield on the posted price, in percent: EPS over price. `NONE`
## for a company with no price.
static func earnings_yield_percent(state: GameState, company: CompanyState) -> float:
	var row: StalkState = state.stalk_by_id(company.id)
	if row == null or row.price <= 0:
		return NONE
	return company.earnings_per_share() * 100.0 / float(row.price)


## A company's revenue as a percent of its industry's living members' total
## (design §7.4). A derived figure, not a simulated one. `NONE` for a failed
## company or an industry with no revenue.
static func market_share_percent(state: GameState, company: CompanyState) -> float:
	if _is_failed(state, company):
		return NONE
	var total: float = industry_revenue(state, company.profile.industry)
	if total <= 0.0:
		return NONE
	return company.revenue * 100.0 / total


## A company's share of its industry's revenue at the end of `year`, among
## the members alive then. `NONE` when it had failed or there was no revenue.
static func market_share_in_year(state: GameState, company_id: StringName, year: int) -> float:
	var company: CompanyState = company_in_year(state, company_id, year)
	if company == null or company.price <= 0:
		return NONE
	var total: float = 0.0
	for member: CompanyState in industry_members(state, company.profile.industry):
		var then: CompanyState = company_in_year(state, member.id, year)
		if then != null and then.price > 0:
			total += maxf(then.revenue, 0.0)
	if total <= 0.0:
		return NONE
	return maxf(company.revenue, 0.0) * 100.0 / total


## How many points of its industry's revenue a company gained or lost this
## year. `NONE` before year 1 or when either year has no share.
static func market_share_change(state: GameState, company: CompanyState) -> float:
	if state.year <= 0:
		return NONE
	var now: float = market_share_percent(state, company)
	var before: float = market_share_in_year(state, company.id, state.year - 1)
	if is_nan(now) or is_nan(before):
		return NONE
	return now - before


## Revenue less profit: what the Company tab's "expenses" line shows.
static func expenses(company: CompanyState) -> float:
	return company.revenue - company.profit


## The company as it stood at the end of `year`: year 0 is its profile's
## opening figures, every later year is that year's record
## (`EarningsYearResult.companies_after`). Null for a year that has not
## happened.
static func company_in_year(state: GameState, company_id: StringName, year: int) -> CompanyState:
	var company: CompanyState = state.market.company_by_id(company_id)
	if company == null:
		return null
	if year == 0:
		return CompanyState.new(company.profile)
	var result: EarningsYearResult = result_for_year(state, year)
	if result == null:
		return null
	return result.companies_after.get(company_id, null)


## The latest `count` years of a company's record, oldest first, as many as
## exist. Includes year 0, so a match in year 2 has three.
static func company_history(state: GameState, company_id: StringName, count: int) -> Array[CompanyState]:
	var series: Array[CompanyState] = []
	var first: int = maxi(0, state.year - count + 1)
	for year: int in range(first, state.year + 1):
		var record: CompanyState = company_in_year(state, company_id, year)
		if record != null:
			series.append(record)
	return series


## A per-share figure from a year when the company had `shares_then` shares,
## restated on today's `shares_now`: what it would read had every split since
## already happened. A split doubles the shares and halves the price, so an
## unadjusted chart would show a split as a crash. Charts adjust, as real price
## charts do; the earnings table does not, and marks the split instead
## (decisions.md D188).
static func per_share_adjusted(value: float, shares_then: int, shares_now: int) -> float:
	if shares_now <= 0 or is_nan(value):
		return value
	return value * float(shares_then) / float(shares_now)


## The dividend per share a company paid in `year`. Year 0 paid none.
static func dividend_in(state: GameState, company_id: StringName, year: int) -> int:
	var result: EarningsYearResult = result_for_year(state, year)
	if result == null:
		return 0
	return result.dividend_per_share.get(company_id, 0)


## The mean P/E of an industry's companies at the end of `year`, on that
## year's prices and earnings; companies with no earnings or no price are left
## out. `NONE` if none count. `industry_average_pe` is this for the latest year,
## on the board's posted prices.
static func industry_average_pe_in(state: GameState, industry_id: StringName, year: int) -> float:
	var total: float = 0.0
	var counted: int = 0
	for company: CompanyState in state.market.companies:
		if company.profile.industry != industry_id:
			continue
		var record: CompanyState = company_in_year(state, company.id, year)
		if record == null:
			continue
		var pe: float = price_earnings(record.price, record.earnings_per_share())
		if is_nan(pe):
			continue
		total += pe
		counted += 1
	if counted == 0:
		return NONE
	return total / float(counted)


## The year numbers `company_history` covers, in the same order.
static func history_years(state: GameState, count: int) -> Array[int]:
	var years: Array[int] = []
	for year: int in range(maxi(0, state.year - count + 1), state.year + 1):
		years.append(year)
	return years


## "SLOWING, 2nd year": the regime and how long it has held, counting the year
## it was entered as the first (`years_in_regime` is 0 then, D131). Design §7.5
## and §14 q8: the regime is named on screen. Empty for a failed company.
static func regime_caption(state: GameState, company: CompanyState) -> String:
	if _is_failed(state, company):
		return ""
	return "%s, %s year" % [
		EarningsRegime.name_of(company.regime), ordinal(company.years_in_regime + 1),
	]


## 1st, 2nd, 3rd, 4th ... 11th, 12th, 13th, 21st.
static func ordinal(value: int) -> String:
	var suffix: String = "th"
	var tens: int = value % 100
	if tens < 11 or tens > 13:
		match value % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [value, suffix]


# ------------------------------------------------------------- industries

## Every company in an industry, failed ones too, in board (id) order - what
## the board lists under the industry's header.
static func industry_members(state: GameState, industry_id: StringName) -> Array[CompanyState]:
	var members: Array[CompanyState] = []
	for company: CompanyState in state.market.companies:
		if company.profile.industry == industry_id:
			members.append(company)
	return members


## The living companies in an industry, in board (id) order.
static func living_members(state: GameState, industry_id: StringName) -> Array[CompanyState]:
	var members: Array[CompanyState] = []
	for company: CompanyState in industry_members(state, industry_id):
		if not _is_failed(state, company):
			members.append(company)
	return members


## The mean P/E of an industry's living members that have earnings. The number
## a member's P/E is compared with, printed on the industry's header row (design
## §7.2: "the industry header row is how the P/E comparison becomes free").
## `NONE` when no member has a P/E.
static func industry_average_pe(state: GameState, industry_id: StringName) -> float:
	return _mean_pe(state, living_members(state, industry_id))


## The mean P/E of every living company with earnings: the market P/E.
## A move from `before` to `after` as a percentage of `before`: a price's
## year-on-year change. `NONE` from nothing.
static func percent_change(before: int, after: int) -> float:
	if before <= 0:
		return NONE
	return (after - before) * 100.0 / float(before)


static func market_pe(state: GameState) -> float:
	var alive: Array[CompanyState] = []
	for company: CompanyState in state.market.companies:
		if not _is_failed(state, company):
			alive.append(company)
	return _mean_pe(state, alive)


static func industry_revenue(state: GameState, industry_id: StringName) -> float:
	var total: float = 0.0
	for company: CompanyState in living_members(state, industry_id):
		total += maxf(company.revenue, 0.0)
	return total


## An industry's revenue as a percent of every living company's.
static func industry_revenue_share_percent(state: GameState, industry_id: StringName) -> float:
	var all: float = 0.0
	for industry: IndustryState in state.market.industries:
		all += industry_revenue(state, industry.id)
	if all <= 0.0:
		return NONE
	return industry_revenue(state, industry_id) * 100.0 / all


## An industry's performance in `year`, in percent. 0 for year 0 or a year not
## played.
static func industry_performance_in(state: GameState, industry_id: StringName, year: int) -> float:
	var result: EarningsYearResult = result_for_year(state, year)
	if result == null:
		return 0.0
	return result.industry_performance.get(industry_id, 0.0)


## The industry's performance compounded over the latest `years` years, in
## percent: `prod(1 + p/100) - 1`. Over fewer years when fewer have run.
static func industry_compound_percent(state: GameState, industry_id: StringName, years: int) -> float:
	var factor: float = 1.0
	for year: int in range(maxi(1, state.year - years + 1), state.year + 1):
		factor *= (100.0 + industry_performance_in(state, industry_id, year)) / 100.0
	return (factor - 1.0) * 100.0


# ---------------------------------------------------------------- the market

## The index level at the end of each year from 0 to now, unrounded. Year 0 is
## the index row's starting price.
static func index_levels(state: GameState) -> Array[float]:
	var levels: Array[float] = []
	var row: StalkState = state.stalk_by_id(EarningsMarket.INDEX_ID)
	if row == null:
		return levels
	levels.append(float(row.definition.starting_price))
	for year: int in range(1, state.year + 1):
		var result: EarningsYearResult = result_for_year(state, year)
		if result != null:
			levels.append(result.index_level_after)
	return levels


## How many living companies rose and how many there were, this year: the
## market's breadth. `Vector2i(rose, of)`. Both 0 before year 1.
static func breadth(state: GameState) -> Vector2i:
	var latest: EarningsYearResult = state.latest_result() as EarningsYearResult
	if latest == null:
		return Vector2i.ZERO
	var rose: int = 0
	var counted: int = 0
	for company_id: StringName in latest.ledgers:
		var ledger: PriceLedger = latest.ledgers[company_id]
		counted += 1
		if ledger.price_after > ledger.price_before:
			rose += 1
	return Vector2i(rose, counted)


## How many of the latest `count` years were bull years, and how many years
## that was. `Vector2i(bull, of)`.
static func bull_years(state: GameState, count: int) -> Vector2i:
	var bull: int = 0
	var counted: int = 0
	for year: int in range(maxi(1, state.year - count + 1), state.year + 1):
		var result: YearResult = result_for_year(state, year)
		if result == null:
			continue
		counted += 1
		if result.mood == MarketMood.Value.BULL:
			bull += 1
	return Vector2i(bull, counted)


## The bond's yield, the risk-free rate (design §3.8). `NONE` without a bond.
static func risk_free_percent(state: GameState) -> float:
	var bond: StalkState = state.stalk_by_id(EarningsMarket.BOND_ID)
	if bond == null:
		return NONE
	return EarningsMarket.risk_free_yield_percent(bond.definition)


# ------------------------------------------------------------------ the desk

## Each strategy's return on the match so far, in percent: what its traders are
## worth at the posted prices over what they started with, less one. The
## Exchange tab's "value +61%" (design §7.2). Keyed by strategy, every strategy
## that has a trader.
static func desk_returns(state: GameState) -> Dictionary[NpcStrategy.Value, float]:
	var worth: Dictionary[NpcStrategy.Value, int] = {}
	var started: Dictionary[NpcStrategy.Value, int] = {}
	for trader: NpcTraderState in state.market.desk.traders:
		worth[trader.strategy] = worth.get(trader.strategy, 0) + trader.worth(state)
		started[trader.strategy] = started.get(trader.strategy, 0) + trader.definition.starting_cash
	var returns: Dictionary[NpcStrategy.Value, float] = {}
	for strategy: NpcStrategy.Value in NpcStrategy.ALL:
		if not started.has(strategy):
			continue
		if started[strategy] <= 0:
			returns[strategy] = 0.0
		else:
			returns[strategy] = float(worth[strategy] - started[strategy]) * 100.0 / float(started[strategy])
	return returns


## The strategies, best return first, ties in the design's order.
static func strategies_by_return(state: GameState) -> Array[NpcStrategy.Value]:
	var returns: Dictionary[NpcStrategy.Value, float] = desk_returns(state)
	var ordered: Array[NpcStrategy.Value] = []
	for strategy: NpcStrategy.Value in NpcStrategy.ALL:
		if returns.has(strategy):
			ordered.append(strategy)
	ordered.sort_custom(_by_return.bind(returns))
	return ordered


## Every living company somebody is short, most shorted first, with the shares
## short: `[[company_id, shares], ...]`. Short interest is the one piece of the
## desk the squeeze needs a player to have seen (design §5.3, §7.2).
static func short_interest(state: GameState) -> Array[Array]:
	var rows: Array[Array] = []
	for company: CompanyState in state.market.companies:
		if _is_failed(state, company):
			continue
		var shares: int = state.market.desk.short_interest(company.id)
		if shares > 0:
			rows.append([company.id, shares])
	rows.sort_custom(_by_shares_then_id)
	return rows


## What the desk did about one company last year, trader by trader, in the
## order they acted: `[[trader_id, situation, shares held, shares short], ...]`.
## Only traders whose pick was this company. The Company tab names them (§14
## q11). Empty before the desk has acted.
static func desk_activity(state: GameState, company_id: StringName) -> Array[Array]:
	var rows: Array[Array] = []
	var latest: EarningsYearResult = state.latest_result() as EarningsYearResult
	if latest == null or latest.desk == null:
		return rows
	for trader_id: StringName in latest.desk.trader_ids:
		if latest.desk.targets.get(trader_id, &"") != company_id:
			continue
		var trader: NpcTraderState = state.market.desk.trader_by_id(trader_id)
		if trader == null:
			continue
		rows.append([
			trader_id,
			latest.desk.actions.get(trader_id, NpcTraderDefinition.Situation.HELD),
			trader.shares_of(company_id),
			trader.short_of(company_id),
		])
	return rows


## What an NPC trader holds of a company, for the Company tab's NOW column:
## "short 239" when it is short, the share count when it holds shares, "-" for
## neither.
static func position_caption(shares: int, short_shares: int) -> String:
	if short_shares > 0:
		return "short %d" % short_shares
	if shares > 0:
		return str(shares)
	return "-"


## How many of the desk's traders hold `company_id` or are short it now: the
## company list's NPC column.
static func npc_holder_count(state: GameState, company_id: StringName) -> int:
	if state.market == null or state.market.desk == null:
		return 0
	var count: int = 0
	for trader: NpcTraderState in state.market.desk.traders:
		if trader.shares_of(company_id) > 0 or trader.short_of(company_id) > 0:
			count += 1
	return count


## A situation as one lower-case word, for a line about what a trader did.
static func situation_word(situation: NpcTraderDefinition.Situation) -> String:
	match situation:
		NpcTraderDefinition.Situation.BOUGHT:
			return "bought"
		NpcTraderDefinition.Situation.SOLD:
			return "sold"
		NpcTraderDefinition.Situation.SHORTED:
			return "shorted"
		NpcTraderDefinition.Situation.COVERED:
			return "covered"
	return "held"


# ------------------------------------------------------------------ helpers

## The result of `year`, or null for year 0 and years not yet played. The
## history is in year order from year 1, so this is a direct index, checked.
static func result_for_year(state: GameState, year: int) -> EarningsYearResult:
	var index: int = year - 1
	if index < 0 or index >= state.history.size():
		return null
	var result: EarningsYearResult = state.history[index] as EarningsYearResult
	if result != null and result.year == year:
		return result
	for candidate: YearResult in state.history:
		if candidate.year == year:
			return candidate as EarningsYearResult
	return null


static func _is_failed(state: GameState, company: CompanyState) -> bool:
	var row: StalkState = state.stalk_by_id(company.id)
	return row == null or row.is_bankrupt


static func _mean_pe(state: GameState, companies: Array[CompanyState]) -> float:
	var total: float = 0.0
	var counted: int = 0
	for company: CompanyState in companies:
		var pe: float = company_pe(state, company)
		if is_nan(pe):
			continue
		total += pe
		counted += 1
	if counted == 0:
		return NONE
	return total / float(counted)


static func _average_company_dividend(state: GameState) -> int:
	var total: int = 0
	var counted: int = 0
	for company: CompanyState in state.market.companies:
		if _is_failed(state, company):
			continue
		total += company.dividend_per_share()
		counted += 1
	if counted == 0:
		return 0
	@warning_ignore("integer_division")
	return total / counted


static func _by_return(
	a: NpcStrategy.Value,
	b: NpcStrategy.Value,
	returns: Dictionary[NpcStrategy.Value, float],
) -> bool:
	if returns[a] != returns[b]:
		return returns[a] > returns[b]
	return NpcStrategy.ALL.find(a) < NpcStrategy.ALL.find(b)


static func _by_shares_then_id(a: Array, b: Array) -> bool:
	if a[1] != b[1]:
		return a[1] > b[1]
	return String(a[0]) < String(b[0])
