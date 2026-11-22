extends GutTest
## A small fixed-seed version of the StalkleHeads balance tool, so a change that
## breaks balance badly fails somewhere a person sees it without remembering to
## run anything. See docs/stalkleheads-design.md §12.1 and docs/testing.md.
##
## **The bands are deliberately loose.** Thirty matches is far too few to measure
## P2-P4; `tools/balance_report.gd` does that over hundreds. These only catch a
## market that has gone badly wrong: no splits, everyone bankrupt, a bull rate
## of 95%, one strategy winning nearly every match. P4 itself (under 30% at ten
## years) is the tool's to report, not this file's to assert.
##
## Runs the same code as the tool, which since S3 is the game's own
## `EarningsYearResolver` (through tools/balance/lever_year.gd).


const BalanceMatch := preload("res://tools/balance/balance_match.gd")
const Levers := preload("res://tools/balance/levers.gd")
const LeverDesk := preload("res://tools/balance/lever_desk.gd")

const SEEDS: int = 30
const YEARS: int = 10

var _library: ContentLibrary
var _runs: Array[BalanceMatch.Result] = []


func before_all() -> void:
	_library = ContentLibrary.load_from()
	_library.load_fundamentals()
	_runs = []
	for match_seed: int in SEEDS:
		_runs.append(BalanceMatch.play(_library, match_seed, YEARS, BalanceMatch.ALL_STRATEGIES))


func test_the_content_the_tool_plays_on_is_valid() -> void:
	assert_true(_library.is_valid(), "%s" % [_library.errors])


func test_the_same_seed_plays_the_same_match() -> void:
	var again: BalanceMatch.Result = BalanceMatch.play(_library, 7, YEARS, BalanceMatch.ALL_STRATEGIES)
	assert_eq(again.net_worth, _runs[7].net_worth)
	assert_eq(again.final_prices, _runs[7].final_prices)


func test_choosing_strategies_does_not_change_the_market() -> void:
	# RANDOM draws from its own stream (decisions.md D145), so running a subset
	# leaves the market, and so HOLD's result, exactly as it was - as long as
	# the players' own trades do not feed the flow term.
	var fewer: Array[StringName] = [&"HOLD", &"BOND"]
	var every: BalanceMatch.Result = BalanceMatch.play(
		_library, 3, YEARS, BalanceMatch.ALL_STRATEGIES, BalanceMatch.FLOW_DESK
	)
	var subset: BalanceMatch.Result = BalanceMatch.play(_library, 3, YEARS, fewer, BalanceMatch.FLOW_DESK)
	assert_eq(subset.final_prices, every.final_prices)
	assert_eq(subset.net_worth[&"HOLD"], every.net_worth[&"HOLD"])


func test_the_players_trades_feed_flow_by_default() -> void:
	var desk_only: BalanceMatch.Result = BalanceMatch.play(
		_library, 3, YEARS, BalanceMatch.ALL_STRATEGIES, BalanceMatch.FLOW_DESK
	)
	assert_ne(desk_only.final_prices, _runs[3].final_prices)


func test_without_flow_or_squeeze_the_desk_moves_no_price() -> void:
	# FLOW_NONE: the desk trades and FOLLOW reads it, but its trading reaches no
	# price. With the squeeze off too, nothing the desk does reaches the market,
	# so who is playing makes no difference to it.
	var levers: Levers = Levers.new()
	levers.squeeze = false
	var every: BalanceMatch.Result = BalanceMatch.play(
		_library, 5, YEARS, BalanceMatch.ALL_STRATEGIES, BalanceMatch.FLOW_NONE, levers
	)
	var alone: BalanceMatch.Result = BalanceMatch.play(
		_library, 5, YEARS, [&"HOLD"] as Array[StringName], BalanceMatch.FLOW_NONE, levers
	)
	assert_eq(every.final_prices, alone.final_prices)
	assert_eq(every.squeezes, 0)


func test_follow_plays_and_the_desk_has_a_best_trader() -> void:
	for run: BalanceMatch.Result in _runs:
		assert_true(run.net_worth.has(&"FOLLOW"))
		assert_ne(run.best_npc_strategy, "")


func test_the_bond_player_earns_the_coupon_and_nothing_else() -> void:
	# 10,000 at 100 a share and 3 a share a year, reinvested each year: the
	# market cannot touch it, so it is the same figure in every match.
	for run: BalanceMatch.Result in _runs:
		assert_eq(run.net_worth[&"BOND"], 13426)


func test_the_market_still_moves_like_a_market() -> void:
	var splits: float = 0.0
	var bankruptcies: float = 0.0
	var bull_years: float = 0.0
	for run: BalanceMatch.Result in _runs:
		splits += run.splits
		bankruptcies += run.bankruptcies
		bull_years += run.bull_years
	var count: float = float(SEEDS)
	assert_between(splits / count, 0.5, 5.0, "splits per match")
	assert_between(bankruptcies / count, 0.0, 2.0, "bankruptcies per match")
	assert_between(bull_years / (count * YEARS), 0.40, 0.72, "bull-year rate")


func test_no_strategy_wins_nearly_every_match() -> void:
	var wins: Dictionary[StringName, int] = {}
	for run: BalanceMatch.Result in _runs:
		var best: int = run.net_worth.values().max()
		for strategy: StringName in run.net_worth:
			if run.net_worth[strategy] == best:
				wins[strategy] = wins.get(strategy, 0) + 1
	for strategy: StringName in wins:
		assert_lt(float(wins[strategy]) / float(SEEDS), 0.75, "%s win share" % strategy)


func test_the_player_who_reads_nothing_is_not_ruined() -> void:
	# P3, loosely: RANDOM's median keeps at least half the starting cash.
	assert_gt(_median(&"RANDOM"), GameSettings.new().starting_cash / 2)


func test_reading_beats_not_reading() -> void:
	# P2, loosely: the best reader's median is above the no-reader's.
	var readers: Array[StringName] = [&"LOWPE", &"HIGHPE", &"TREND", &"MOMENTUM", &"CONTRARIAN", &"INCOME"]
	var best: int = 0
	for strategy: StringName in readers:
		best = maxi(best, _median(strategy))
	assert_gt(best, _median(&"RANDOM"))


func _median(strategy: StringName) -> int:
	var values: Array[int] = []
	for run: BalanceMatch.Result in _runs:
		values.append(run.net_worth[strategy])
	values.sort()
	return values[values.size() / 2]


func test_a_lever_set_to_its_published_value_changes_nothing() -> void:
	# The sweep's override path (levers.gd) re-implements the regime roll and
	# reaches the premium through reprice's performance argument. Set to the
	# published values it must reproduce the real path exactly (D150).
	var levers: Levers = Levers.new()
	levers.growth_stay = int(RegimeRules.TRANSITION[EarningsRegime.Value.GROWTH][0])
	levers.ageing = RegimeRules.AGEING_POINTS
	levers.premium = Levers.scaled_premium(1.0)
	for match_seed: int in [0, 7, 19]:
		var forced: BalanceMatch.Result = BalanceMatch.play(
			_library, match_seed, YEARS, BalanceMatch.ALL_STRATEGIES, BalanceMatch.FLOW_ALL, levers
		)
		assert_eq(forced.net_worth, _runs[match_seed].net_worth, "seed %d" % match_seed)
		assert_eq(forced.final_prices, _runs[match_seed].final_prices, "seed %d" % match_seed)


func test_a_lever_that_moves_does_move_the_market() -> void:
	var levers: Levers = Levers.new()
	levers.growth_stay = 26
	var moved: BalanceMatch.Result = BalanceMatch.play(
		_library, 0, YEARS, BalanceMatch.ALL_STRATEGIES, BalanceMatch.FLOW_ALL, levers
	)
	assert_ne(moved.final_prices, _runs[0].final_prices)


func test_a_rebuilt_growth_row_still_sums_to_100() -> void:
	for stay: int in [0, 26, 34, 42, 50, 58, 70, 100]:
		var row: Array[int] = Levers.growth_row(stay)
		var total: int = 0
		for weight: int in row:
			total += weight
		assert_eq(total, 100, "stay %d: %s" % [stay, row])
		assert_eq(row[0], stay)
	var published: Array = RegimeRules.TRANSITION[EarningsRegime.Value.GROWTH]
	assert_eq(Levers.growth_row(int(published[0])), published, "the published row comes back unchanged")


func test_the_short_target_lever_at_its_published_rule_changes_nothing() -> void:
	# The lever desk replaces the real one only off the published rule, and
	# its seam calls straight through for every other strategy (D168).
	var levers: Levers = Levers.new()
	levers.short_target = &"slowest"
	var same: BalanceMatch.Result = BalanceMatch.play(
		_library, 4, YEARS, BalanceMatch.ALL_STRATEGIES, BalanceMatch.FLOW_ALL, levers
	)
	assert_eq(same.net_worth, _runs[4].net_worth)
	assert_eq(same.final_prices, _runs[4].final_prices)


func test_the_highpe_short_target_bets_against_the_dearest_company() -> void:
	var library_state: GameState = EarningsMarket.new_game_state(_library, GameSettings.new())
	var company: CompanyState = library_state.market.company_by_id(&"meowly")
	company.price = 400
	library_state.stalk_by_id(&"meowly").price = 400
	var desk: LeverDesk = LeverDesk.new()
	desk.short_target = LeverDesk.SHORT_HIGHPE
	assert_eq(desk.choose_target(NpcStrategy.Value.SHORT, library_state, 0), &"meowly")
	assert_eq(
		desk.choose_target(NpcStrategy.Value.VALUE, library_state, 0),
		NpcDesk.target_for(NpcStrategy.Value.VALUE, library_state, 0),
		"every other strategy is the real one",
	)
	var levers: Levers = Levers.new()
	levers.short_target = LeverDesk.SHORT_HIGHPE
	var moved: BalanceMatch.Result = BalanceMatch.play(
		_library, 0, YEARS, BalanceMatch.ALL_STRATEGIES, BalanceMatch.FLOW_ALL, levers
	)
	assert_ne(moved.final_prices, _runs[0].final_prices)
