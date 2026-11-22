class_name YearDigest
extends RefCounted
## The whole of a StalkleHeads year's fundamentals in one record, for the panel
## that opens at the year turn (docs/stalkleheads-design.md §6.3).
##
## **The design's real answer to "how much does a player have to hold in their
## head"**: a player who reads only this is playing at tier 2 or better, because
## it hands them the market's move, every industry's, and the year's outliers
## directly. The tabs are the drill-down.
##
## Built from the state as the year left it, on whichever machine shows it,
## from what the history already holds. Pure: no nodes, no RNG, changes nothing.
## Each outlier is empty (`&""`) when nothing qualified - a year with no dividend
## cut has no dividend-cut line, rather than a filler one (design §8.2 rule 3).


var year: int = 0

## The index move, in percent, and the mood it was reported as. The mood line
## reads in the order it was decided: the move first, then the label (§6.3).
var index_move_percent: float = 0.0
var mood: MarketMood.Value = MarketMood.Value.BULL
var market_pe: float = MarketReadouts.NONE

## The sentiment next year's prices will be valued on: this year's index move,
## clamped (glossary "Sentiment"). `EarningsMarket.sentiment` after the year.
var next_sentiment: float = 0.0

## Each industry's performance this year: `[industry_id, display_name,
## percent]`, in board order.
var industries: Array[Array] = []

## The living company whose profit grew most this year, and by how much.
var surprise_id: StringName = &""
var surprise_profit_percent: float = 0.0

## The living company whose margin fell furthest this year, from and to.
var disappointment_id: StringName = &""
var disappointment_margin_before: float = 0.0
var disappointment_margin_after: float = 0.0

## The company whose dividend per share fell most this year, from and to, and
## whether it is now in DISTRESS.
var dividend_cut_id: StringName = &""
var dividend_before: int = 0
var dividend_after: int = 0
var dividend_cut_in_distress: bool = false

## The row the desk bought most of, net, after the year settled, and the
## strategies of the traders who bought it.
var desk_pick_id: StringName = &""
var desk_pick_shares: int = 0
var desk_pick_strategies: Array[NpcStrategy.Value] = []


## The digest of the latest year in `state`, or null before year 1 or in a
## match with no market.
static func for_latest_year(state: GameState) -> YearDigest:
	if state.market == null:
		return null
	var result: EarningsYearResult = state.latest_result() as EarningsYearResult
	if result == null:
		return null

	var digest: YearDigest = YearDigest.new()
	digest.year = result.year
	digest.index_move_percent = result.index_move_percent
	digest.mood = result.mood
	digest.market_pe = MarketReadouts.market_pe(state)
	digest.next_sentiment = state.market.sentiment
	for industry: IndustryState in state.market.industries:
		digest.industries.append([
			industry.id, industry.definition.display_name,
			result.industry_performance.get(industry.id, 0.0),
		])
	digest._find_earnings_outliers(state, result)
	digest._find_dividend_cut(state, result)
	digest._find_desk_pick(state, result)
	return digest


func _find_earnings_outliers(state: GameState, result: EarningsYearResult) -> void:
	var best_growth: float = 0.0
	var worst_fall: float = 0.0
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row == null or row.is_bankrupt or not result.ledgers.has(company.id):
			continue
		var growth: float = company.profit_growth_percent()
		if not is_nan(growth) and growth > best_growth:
			best_growth = growth
			surprise_id = company.id
			surprise_profit_percent = growth

		var before: CompanyState = MarketReadouts.company_in_year(state, company.id, result.year - 1)
		if before == null:
			continue
		var fall: float = before.margin_percent - company.margin_percent
		if fall > worst_fall:
			worst_fall = fall
			disappointment_id = company.id
			disappointment_margin_before = before.margin_percent
			disappointment_margin_after = company.margin_percent


func _find_dividend_cut(state: GameState, result: EarningsYearResult) -> void:
	var worst_cut: int = 0
	var previous: EarningsYearResult = MarketReadouts.result_for_year(state, result.year - 1)
	for company: CompanyState in state.market.companies:
		if not result.ledgers.has(company.id):
			continue
		var before: int = 0
		if previous != null:
			before = previous.dividend_per_share.get(company.id, 0)
		else:
			before = CompanyState.new(company.profile).dividend_per_share()
		var after: int = result.dividend_per_share.get(company.id, 0)
		if before - after > worst_cut:
			worst_cut = before - after
			dividend_cut_id = company.id
			dividend_before = before
			dividend_after = after
			dividend_cut_in_distress = company.regime == EarningsRegime.Value.DISTRESS


func _find_desk_pick(state: GameState, result: EarningsYearResult) -> void:
	if result.desk == null:
		return
	var most: int = 0
	for stalk_id: StringName in result.desk.net_shares:
		var shares: int = result.desk.net_shares[stalk_id]
		var better: bool = shares > most
		if shares == most and shares > 0 and String(stalk_id) < String(desk_pick_id):
			better = true
		if better:
			most = shares
			desk_pick_id = stalk_id
	if desk_pick_id.is_empty():
		return
	desk_pick_shares = most
	for trader_id: StringName in result.desk.trader_ids:
		if result.desk.targets.get(trader_id, &"") != desk_pick_id:
			continue
		if result.desk.actions.get(trader_id, -1) != NpcTraderDefinition.Situation.BOUGHT:
			continue
		var trader: NpcTraderState = state.market.desk.trader_by_id(trader_id)
		if trader != null and not desk_pick_strategies.has(trader.strategy):
			desk_pick_strategies.append(trader.strategy)
