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
## Runs the same code as the tool, including its stand-in year
## (tools/balance/stand_in_year.gd), which S3 replaces.


const BalanceMatch := preload("res://tools/balance/balance_match.gd")

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
	# leaves the market, and so HOLD's result, exactly as it was.
	var fewer: Array[StringName] = [&"HOLD", &"BOND"]
	var subset: BalanceMatch.Result = BalanceMatch.play(_library, 3, YEARS, fewer)
	assert_eq(subset.final_prices, _runs[3].final_prices)
	assert_eq(subset.net_worth[&"HOLD"], _runs[3].net_worth[&"HOLD"])


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
