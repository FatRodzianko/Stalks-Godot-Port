extends GutTest
## StalkleHeads phase S7, the half with no screen: the figures the tabs show
## (`MarketReadouts`), the year digest (`YearDigest`), the per-year record the
## history keeps (`EarningsYearResult.companies_after`) and the text charts
## (`TextChart`). See docs/stalkleheads-design.md §6.3, §7 and decisions.md
## D179.
##
## Each readout is checked against an independent working-out from the raw
## state, over seeded matches, so a readout that drifts from what it claims to
## be fails here rather than on screen.


const SEED: int = 4242


func _match(years: int, seed_value: int = SEED) -> WireMatch:
	var played: WireMatch = WireMatch.start(seed_value, 3, 30)
	played.play(years)
	return played


# --------------------------------------------------------- the year record

## Every year records every company as it ended the year: the record's price
## is the board's closing price, splits and failures included.
func test_each_year_records_every_company_as_it_closed() -> void:
	var played: WireMatch = WireMatch.start(11, 3, 30)
	for _year: int in 25:
		var result: EarningsYearResult = WireMatch.play_year(played.authority)
		assert_eq(result.companies_after.size(), played.state.market.companies.size())
		for change: StalkYearChange in result.stalk_changes:
			var record: CompanyState = result.companies_after.get(change.stalk_id)
			if record == null:
				continue
			assert_eq(record.price, change.price_after, "%s year %d" % [change.stalk_id, result.year])
		assert_eq(result.index_level_after, played.state.market.index_level)


## The record is a copy: the next year moving the company does not move it.
func test_a_years_record_does_not_move_with_later_years() -> void:
	var played: WireMatch = WireMatch.start(SEED, 3, 30)
	var first: EarningsYearResult = WireMatch.play_year(played.authority)
	var company_id: StringName = played.state.market.companies[0].id
	var revenue: float = first.companies_after[company_id].revenue
	played.play(3)
	assert_eq(first.companies_after[company_id].revenue, revenue)


## Year 0 is the profile's opening figures; later years are their records.
func test_company_in_year_reads_year_zero_from_the_profile() -> void:
	var played: WireMatch = _match(4)
	var company: CompanyState = played.state.market.companies[0]
	var opening: CompanyState = MarketReadouts.company_in_year(played.state, company.id, 0)
	assert_eq(opening.price, CompanyState.new(company.profile).price)
	var latest: CompanyState = MarketReadouts.company_in_year(played.state, company.id, 4)
	assert_eq(latest.revenue, company.revenue)
	assert_null(MarketReadouts.company_in_year(played.state, company.id, 5), "a year not played")


func test_company_history_is_the_latest_years_oldest_first() -> void:
	var played: WireMatch = _match(7)
	var company_id: StringName = played.state.market.companies[2].id
	var series: Array[CompanyState] = MarketReadouts.company_history(played.state, company_id, 5)
	assert_eq(series.size(), 5)
	assert_eq(MarketReadouts.history_years(played.state, 5), [3, 4, 5, 6, 7] as Array[int])
	assert_eq(series[4].revenue, played.state.market.company_by_id(company_id).revenue)

	var early: WireMatch = _match(1)
	assert_eq(MarketReadouts.company_history(early.state, company_id, 5).size(), 2, "years 0 and 1")


# --------------------------------------------------------------- P/E

func test_a_pe_without_earnings_is_no_figure() -> void:
	assert_almost_eq(MarketReadouts.price_earnings(120, 8.0), 15.0, 0.0001)
	assert_true(is_nan(MarketReadouts.price_earnings(120, 0.0)))
	assert_true(is_nan(MarketReadouts.price_earnings(120, -2.5)), "a loss-maker has no P/E")
	assert_true(is_nan(MarketReadouts.price_earnings(0, 8.0)), "nor a failed company")


## The industry average is the mean of its living members' P/Es, worked out
## here from the board prices and the accounts directly.
func test_the_industry_average_pe_is_its_members_mean() -> void:
	var played: WireMatch = _match(6)
	var state: GameState = played.state
	for industry: IndustryState in state.market.industries:
		var total: float = 0.0
		var counted: int = 0
		for company: CompanyState in state.market.companies:
			if company.profile.industry != industry.id:
				continue
			var row: StalkState = state.stalk_by_id(company.id)
			var eps: float = company.profit / float(company.shares_outstanding)
			if row.is_bankrupt or eps <= 0.0:
				continue
			total += float(row.price) / eps
			counted += 1
		var expected: float = NAN if counted == 0 else total / float(counted)
		var actual: float = MarketReadouts.industry_average_pe(state, industry.id)
		if counted == 0:
			assert_true(is_nan(actual), String(industry.id))
		else:
			assert_almost_eq(actual, expected, 0.0001, String(industry.id))


func test_market_share_sums_to_a_hundred_within_an_industry() -> void:
	var played: WireMatch = _match(9)
	for industry: IndustryState in played.state.market.industries:
		var total: float = 0.0
		for company: CompanyState in MarketReadouts.living_members(played.state, industry.id):
			total += MarketReadouts.market_share_percent(played.state, company)
		if not MarketReadouts.living_members(played.state, industry.id).is_empty():
			assert_almost_eq(total, 100.0, 0.001, String(industry.id))


## The industries' revenue shares of the whole market sum to a hundred too.
func test_industry_revenue_shares_sum_to_a_hundred() -> void:
	var played: WireMatch = _match(5)
	var total: float = 0.0
	for industry: IndustryState in played.state.market.industries:
		total += MarketReadouts.industry_revenue_share_percent(played.state, industry.id)
	assert_almost_eq(total, 100.0, 0.001)


func test_industry_compound_move_compounds_its_years() -> void:
	var played: WireMatch = _match(6)
	var industry_id: StringName = played.state.market.industries[0].id
	var factor: float = 1.0
	for year: int in [4, 5, 6]:
		factor *= 1.0 + MarketReadouts.result_for_year(played.state, year).industry_performance[industry_id] / 100.0
	assert_almost_eq(
		MarketReadouts.industry_compound_percent(played.state, industry_id, 3),
		(factor - 1.0) * 100.0, 0.0001,
	)


# ---------------------------------------------------------------- regime

## §14 q8: the regime is named on screen, counting its first year as the 1st.
func test_the_regime_caption_counts_from_the_first_year() -> void:
	var played: WireMatch = _match(3)
	var company: CompanyState = played.state.market.companies[0]
	company.regime = EarningsRegime.Value.SLOWING
	company.years_in_regime = 1
	assert_eq(MarketReadouts.regime_caption(played.state, company), "SLOWING, 2nd year")
	company.years_in_regime = 0
	assert_eq(MarketReadouts.regime_caption(played.state, company), "SLOWING, 1st year")


func test_ordinals() -> void:
	var expected: Dictionary[int, String] = {
		1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 11: "11th", 12: "12th",
		13: "13th", 21: "21st", 22: "22nd", 101: "101st", 111: "111th",
	}
	for value: int in expected:
		assert_eq(MarketReadouts.ordinal(value), expected[value])


# ----------------------------------------------------------------- market

func test_the_index_levels_start_at_the_rows_opening_price() -> void:
	var played: WireMatch = _match(5)
	var levels: Array[float] = MarketReadouts.index_levels(played.state)
	assert_eq(levels.size(), 6, "years 0 to 5")
	var index_row: StalkState = played.state.stalk_by_id(EarningsMarket.INDEX_ID)
	assert_eq(levels[0], float(index_row.definition.starting_price))
	assert_eq(int(levels[5]), index_row.price)


func test_breadth_counts_the_companies_that_rose() -> void:
	var played: WireMatch = _match(4)
	var latest: EarningsYearResult = played.state.latest_result()
	var rose: int = 0
	for change: StalkYearChange in latest.stalk_changes:
		if latest.ledgers.has(change.stalk_id) and change.price_after > change.price_before:
			rose += 1
	var breadth: Vector2i = MarketReadouts.breadth(played.state)
	assert_eq(breadth.x, rose)
	assert_eq(breadth.y, latest.ledgers.size())


func test_bull_years_counts_the_latest_moods() -> void:
	var played: WireMatch = _match(12)
	var bull: int = 0
	for result: YearResult in played.state.history.slice(2):
		bull += int(result.mood == MarketMood.Value.BULL)
	assert_eq(MarketReadouts.bull_years(played.state, 10), Vector2i(bull, 10))


## The board's DIV is what the row paid last year; at year 0, what it would.
func test_the_dividend_shown_is_last_years_payout() -> void:
	var opening: WireMatch = _match(0)
	var company: CompanyState = opening.state.market.companies[0]
	assert_eq(MarketReadouts.dividend_shown(opening.state, company.id), company.dividend_per_share())

	var played: WireMatch = _match(5)
	var latest: EarningsYearResult = played.state.latest_result()
	for row: StalkState in played.state.stalks:
		if row.is_bankrupt:
			assert_eq(MarketReadouts.dividend_shown(played.state, row.id), 0)
		else:
			assert_eq(MarketReadouts.dividend_shown(played.state, row.id), latest.dividend_per_share[row.id])


# ------------------------------------------------------------------- desk

## Before the desk has traded, every strategy is where it started: 0%.
func test_the_desk_returns_nothing_before_it_trades() -> void:
	var opening: WireMatch = _match(0)
	var returns: Dictionary[NpcStrategy.Value, float] = MarketReadouts.desk_returns(opening.state)
	assert_eq(returns.size(), NpcStrategy.ALL.size())
	for strategy: NpcStrategy.Value in returns:
		assert_eq(returns[strategy], 0.0)


func test_a_strategys_return_is_its_traders_worth_against_their_start() -> void:
	var played: WireMatch = _match(8)
	var returns: Dictionary[NpcStrategy.Value, float] = MarketReadouts.desk_returns(played.state)
	for strategy: NpcStrategy.Value in NpcStrategy.ALL:
		var worth: int = 0
		var started: int = 0
		for trader: NpcTraderState in played.state.market.desk.traders:
			if trader.strategy == strategy:
				worth += trader.worth(played.state)
				started += trader.definition.starting_cash
		assert_almost_eq(returns[strategy], float(worth - started) * 100.0 / float(started), 0.0001)
	var order: Array[NpcStrategy.Value] = MarketReadouts.strategies_by_return(played.state)
	for index: int in order.size() - 1:
		assert_true(returns[order[index]] >= returns[order[index + 1]], "best first")


func test_short_interest_lists_what_the_desk_is_short_most_first() -> void:
	var found: bool = false
	for seed_value: int in [11, 4242, 90210]:
		var played: WireMatch = _match(10, seed_value)
		var rows: Array[Array] = MarketReadouts.short_interest(played.state)
		for index: int in rows.size():
			assert_eq(rows[index][1], played.state.market.desk.short_interest(rows[index][0]))
			if index > 0:
				assert_true(rows[index - 1][1] >= rows[index][1])
		found = found or not rows.is_empty()
	assert_true(found, "some match should have short interest to show")


## The Company tab names the traders who picked a company last year.
func test_desk_activity_is_the_traders_whose_pick_it_was() -> void:
	var played: WireMatch = _match(6)
	var latest: EarningsYearResult = played.state.latest_result()
	var named: int = 0
	for company: CompanyState in played.state.market.companies:
		for entry: Array in MarketReadouts.desk_activity(played.state, company.id):
			assert_eq(latest.desk.targets[entry[0]], company.id)
			named += 1
	assert_gt(named, 0, "the desk should have picked something")


# ----------------------------------------------------------------- digest

func test_there_is_no_digest_before_year_one() -> void:
	assert_null(YearDigest.for_latest_year(_match(0).state))


func test_the_digest_reports_the_years_market_and_industries() -> void:
	var played: WireMatch = _match(5)
	var latest: EarningsYearResult = played.state.latest_result()
	var digest: YearDigest = YearDigest.for_latest_year(played.state)
	assert_eq(digest.year, 5)
	assert_eq(digest.index_move_percent, latest.index_move_percent)
	assert_eq(digest.mood, latest.mood)
	assert_eq(digest.industries.size(), played.state.market.industries.size())
	for entry: Array in digest.industries:
		assert_eq(entry[2], latest.industry_performance[entry[0]])


## The surprise is the living company whose profit grew most, worked out here.
func test_the_digests_surprise_is_the_biggest_profit_growth() -> void:
	for seed_value: int in [11, 4242, 90210]:
		var played: WireMatch = _match(6, seed_value)
		var best_id: StringName = &""
		var best: float = 0.0
		for company: CompanyState in played.state.market.companies:
			if played.state.stalk_by_id(company.id).is_bankrupt:
				continue
			if company.profit_before_season <= 0.0:
				continue
			var growth: float = (company.profit - company.profit_before_season) * 100.0 / company.profit_before_season
			if growth > best:
				best = growth
				best_id = company.id
		var digest: YearDigest = YearDigest.for_latest_year(played.state)
		assert_eq(digest.surprise_id, best_id, "seed %d" % seed_value)


## The dividend cut is the biggest fall in a company's dividend per share.
func test_the_digests_dividend_cut_is_the_biggest_fall() -> void:
	for seed_value: int in [11, 4242, 90210]:
		var played: WireMatch = _match(7, seed_value)
		var now: EarningsYearResult = played.state.latest_result()
		var before: EarningsYearResult = MarketReadouts.result_for_year(played.state, 6)
		var worst: int = 0
		for company_id: StringName in now.ledgers:
			worst = maxi(worst, before.dividend_per_share.get(company_id, 0) - now.dividend_per_share[company_id])
		var digest: YearDigest = YearDigest.for_latest_year(played.state)
		if worst == 0:
			assert_eq(digest.dividend_cut_id, &"", "no cut, no line")
		else:
			assert_eq(digest.dividend_before - digest.dividend_after, worst, "seed %d" % seed_value)


func test_the_digests_desk_pick_is_what_the_desk_bought_most_of() -> void:
	var played: WireMatch = _match(4)
	var latest: EarningsYearResult = played.state.latest_result()
	var most: int = 0
	for stalk_id: StringName in latest.desk.net_shares:
		most = maxi(most, latest.desk.net_shares[stalk_id])
	var digest: YearDigest = YearDigest.for_latest_year(played.state)
	assert_eq(digest.desk_pick_shares, most)
	if most > 0:
		assert_eq(latest.desk.net_shares[digest.desk_pick_id], most)


# ------------------------------------------------------------------ charts

## §12.1: "a chart is a string, so assert the string".
func test_a_bar_chart_is_this_string() -> void:
	var chart: String = TextChart.bars([100.0, 120.0, 140.0] as Array[float], ["0", "1", "2"], 9, 2)
	var expected: PackedStringArray = [
		"  140|   ▁▁ ██",
		"  100|▁▁ ██ ██",
		"     +--------",
		"      0  1  2",
	]
	assert_eq(chart, "\n".join(expected))


func test_a_bar_chart_shows_the_latest_values_that_fit() -> void:
	var values: Array[float] = []
	var captions: PackedStringArray = []
	for year: int in 20:
		values.append(float(100 + year))
		captions.append(str(year))
	var chart: String = TextChart.bars(values, captions, 38, 7)
	assert_eq(TextChart.bars_that_fit(38), 13)
	assert_true(chart.ends_with("7  8  9  10 11 12 13 14 15 16 17 18 19"), chart)
	assert_eq(chart.split("\n").size(), 9, "seven rows, the axis, the captions")


func test_a_flat_series_still_draws() -> void:
	var chart: String = TextChart.bars([100.0, 100.0] as Array[float], ["1", "2"], 6, 1)
	assert_eq(chart.split("\n")[0], "  101|▁▁ ▁▁")


func test_a_signed_chart_hangs_losses_below_the_axis() -> void:
	var chart: String = TextChart.signed_bars([10.0, -10.0, -5.0] as Array[float], ["1", "2", "3"], 9, 1)
	var expected: PackedStringArray = [
		"   10|██",
		"    0+--------",
		"  -10|   ██ ▀▀",
		"      1  2  3",
	]
	assert_eq(chart, "\n".join(expected))


func test_a_share_bar_is_at_least_one_cell_and_at_most_its_length() -> void:
	assert_eq(TextChart.share_bar(0.0, 10), "")
	assert_eq(TextChart.share_bar(2.0, 10), "▄", "a small share is not drawn as none")
	assert_eq(TextChart.share_bar(38.0, 10), "▄▄▄▄")
	assert_eq(TextChart.share_bar(100.0, 10), "▄▄▄▄▄▄▄▄▄▄")


func test_a_percent_change_is_of_the_starting_figure() -> void:
	assert_almost_eq(MarketReadouts.percent_change(80, 100), 25.0, 0.0001)
	assert_almost_eq(MarketReadouts.percent_change(100, 80), -20.0, 0.0001)
	assert_eq(MarketReadouts.percent_change(50, 50), 0.0)
	assert_true(is_nan(MarketReadouts.percent_change(0, 10)), "nothing to start from")


# ------------------------------------------------------------- formatting

func test_the_shared_formatter_prints_ratios_and_missing_figures() -> void:
	assert_eq(Palette.format_decimal(12.64, 1), "12.6")
	assert_eq(Palette.format_decimal(9.4, 2), "9.40")
	assert_eq(Palette.format_decimal(NAN, 1), "--")
	assert_eq(Palette.format_percent_change(6.4), "+6%")
	assert_eq(Palette.format_percent_change(-4.0), "-4%")
	assert_eq(Palette.format_percent_change(0.2), "0%")
	assert_eq(Palette.format_percent(38.4), "38%")
	assert_eq(Palette.format_percent_decimal(3.0), "3.0%")
	assert_eq(Palette.format_signed_decimal(0.84, 2), "+0.84")
	assert_eq(Palette.format_signed_decimal(-0.24, 2), "-0.24")
	assert_eq(Palette.format_signed_decimal(0.001, 2), "0.00", "no plus on a figure that prints as zero")
