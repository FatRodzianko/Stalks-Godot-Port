extends SceneTree
## The StalkleHeads balance tool (phase S2, pointed at the real year in S3):
## plays many seeded matches over the real `src/sim/` pipeline and prints the strategy table of
## docs/stalkleheads-design.md §2.6.
##
##     <godot> --headless --script res://tools/balance_report.gd
##     <godot> --headless --script res://tools/balance_report.gd -- --years=25
##
## Arguments go after a lone `--`, which tells Godot the rest are the script's:
##
##   --years=N          match length (default 10)
##   --seeds=N          how many matches (default 400)
##   --first-seed=N     the first seed; seeds run N, N+1, ... (default 0)
##   --strategies=A,B   which strategies play (default all nine)
##   --player-flow      the players' own net buying feeds the flow term
##
## Balance levers, for a sweep. Each overrides a published number for this run
## only; the defaults in src/sim/ never change (tools/balance/levers.gd):
##
##   --premium=G,S,L,D,X   regime premiums, GROWTH to DISTRESS, turns of multiple
##   --premium-scale=F     the published premium spread times F (2.5 = first draft)
##   --growth-stay=N       GROWTH's stay chance in percent (published 42)
##   --ageing=N            ageing points a year in GROWTH and SLOWING (published 10)
##
## The year is the game's own, `EarningsYearResolver`, since S3 (through
## tools/balance/lever_year.gd, which only adds the levers). There is no NPC desk
## until S4, so there is no FOLLOW strategy and, by default, no flow. See docs/development.md and
## docs/testing.md for what the numbers mean and what they cannot tell you.


const BalanceMatch := preload("res://tools/balance/balance_match.gd")
const Levers := preload("res://tools/balance/levers.gd")

## A strategy "is a contender" when it wins at least this share of matches.
const CONTENDER_PERCENT: float = 4.0

## P4: the leading strategy's win share at the default length must be under
## this (§1). Recorded, not asserted, at any other length.
const P4_CEILING_PERCENT: float = 30.0
const P4_LENGTH: int = 10

const USAGE: String = """Usage: <godot> --headless --script res://tools/balance_report.gd -- [options]
  --years=N          match length (default 10)
  --seeds=N          how many matches (default 400)
  --first-seed=N     first seed (default 0)
  --strategies=A,B   subset of HOLD,LOWPE,HIGHPE,TREND,MOMENTUM,CONTRARIAN,INCOME,RANDOM,BOND
  --player-flow      players' net buying feeds the flow term (default off)
  --premium=G,S,L,D,X   regime premiums, GROWTH..DISTRESS (published 1.2,0,0.24,-0.6,-1.4)
  --premium-scale=F     published premium spread times F
  --growth-stay=N       GROWTH's stay chance, 0-100 (published 42)
  --ageing=N            ageing points a year in GROWTH and SLOWING (published 10)"""


func _init() -> void:
	var years: int = P4_LENGTH
	var seeds: int = 400
	var first_seed: int = 0
	var player_flow: bool = false
	var strategies: Array[StringName] = BalanceMatch.ALL_STRATEGIES.duplicate()
	var levers: Levers = Levers.new()

	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.split("=", true, 1)
		var value: String = ""
		if parts.size() > 1:
			value = parts[1]
		match parts[0]:
			"--years":
				years = value.to_int()
			"--seeds":
				seeds = value.to_int()
			"--first-seed":
				first_seed = value.to_int()
			"--player-flow":
				player_flow = true
			"--premium":
				var values: PackedStringArray = value.split(",", false)
				if values.size() != EarningsRegime.ALL.size():
					_fail("--premium needs five numbers, GROWTH to DISTRESS.")
					return
				levers.premium = []
				for number: String in values:
					levers.premium.append(number.to_float())
			"--premium-scale":
				levers.premium = Levers.scaled_premium(value.to_float())
			"--growth-stay":
				levers.growth_stay = value.to_int()
				if levers.growth_stay < 0 or levers.growth_stay > 100:
					_fail("--growth-stay must be 0 to 100.")
					return
			"--ageing":
				levers.ageing = value.to_float()
				if levers.ageing < 0.0:
					_fail("--ageing must be 0 or more.")
					return
			"--strategies":
				strategies = []
				for name: String in value.to_upper().split(",", false):
					strategies.append(StringName(name))
			_:
				_fail("Unknown argument: %s" % argument)
				return
	if years < 1 or seeds < 1:
		_fail("--years and --seeds must be at least 1.")
		return
	for strategy: StringName in strategies:
		if strategy not in BalanceMatch.ALL_STRATEGIES:
			_fail("Unknown strategy: %s" % strategy)
			return
	if strategies.is_empty():
		_fail("--strategies named none.")
		return

	var library: ContentLibrary = ContentLibrary.load_from()
	library.load_fundamentals()
	if not library.is_valid():
		print("Content did not load:")
		for problem: String in library.errors:
			print("  ", problem)
		quit(1)
		return

	var started: int = Time.get_ticks_msec()
	var runs: Array[BalanceMatch.Result] = []
	for match_seed: int in range(first_seed, first_seed + seeds):
		runs.append(BalanceMatch.play(library, match_seed, years, strategies, player_flow, levers))
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0

	_print_report(runs, strategies, years, seeds, first_seed, player_flow, levers)
	print("ran in %.1f s" % seconds)
	quit()


func _print_report(
	runs: Array[BalanceMatch.Result],
	strategies: Array[StringName],
	years: int,
	seeds: int,
	first_seed: int,
	player_flow: bool,
	levers: Levers,
) -> void:
	var flow_note: String = "no flow (no desk until S4)"
	if player_flow:
		flow_note = "flow from player trades only"
	print("=== StalkleHeads balance: %d years, %d seeds from %d, %s ===" % [
		years, seeds, first_seed, flow_note,
	])
	print("market: EarningsYearResolver (src/sim), events from the shipped EventPool")
	print("levers: %s" % levers.describe())

	var splits: float = 0.0
	var bankruptcies: float = 0.0
	var mean_move: float = 0.0
	var bull_rate: float = 0.0
	var finals: Array[int] = []
	for run: BalanceMatch.Result in runs:
		splits += run.splits
		bankruptcies += run.bankruptcies
		bull_rate += float(run.bull_years) / float(run.years)
		mean_move += _mean_of(run.moves)
		finals.append_array(run.final_prices)
	var count: float = float(runs.size())
	print("splits per match       mean %5.2f   bankruptcies mean %5.2f" % [
		splits / count, bankruptcies / count,
	])
	print("mean |yearly change|   %5.2f   bull year rate %5.3f" % [
		mean_move / count, bull_rate / count,
	])
	finals.sort()
	var zeros: int = finals.count(0)
	print("final price           p10 %5d  median %5d  p90 %5d  max %5d  zero %d%%" % [
		finals[finals.size() / 10], finals[finals.size() / 2],
		finals[finals.size() * 9 / 10], finals[-1], 100 * zeros / finals.size(),
	])

	var wins: Dictionary[StringName, int] = {}
	for strategy: StringName in strategies:
		wins[strategy] = 0
	for run: BalanceMatch.Result in runs:
		var best: int = run.net_worth.values().max()
		for strategy: StringName in strategies:
			if run.net_worth[strategy] == best:
				wins[strategy] += 1

	print("  strategy        median net   mean net    win share")
	var leader: StringName = strategies[0]
	var medians: Dictionary[StringName, int] = {}
	var contenders: int = 0
	for strategy: StringName in strategies:
		var values: Array[int] = []
		var total: float = 0.0
		for run: BalanceMatch.Result in runs:
			values.append(run.net_worth[strategy])
			total += run.net_worth[strategy]
		values.sort()
		medians[strategy] = values[values.size() / 2]
		if 100.0 * float(wins[strategy]) / count >= CONTENDER_PERCENT:
			contenders += 1
		print("  %-14s %10d %10d   %5.1f%%" % [
			strategy, values[values.size() / 2], int(total / count),
			100.0 * float(wins[strategy]) / count,
		])
		if wins[strategy] > wins[leader]:
			leader = strategy

	var top: float = 100.0 * float(wins[leader]) / count
	var verdict: String = "recorded, not asserted: P4 is scoped to %d years (§1)" % P4_LENGTH
	if years == P4_LENGTH:
		verdict = "P4 HOLDS"
		if top >= P4_CEILING_PERCENT:
			verdict = "P4 FAILS"
	print("  leading strategy win share: %.1f%% (%s)   ceiling %.0f%%: %s" % [
		top, leader, P4_CEILING_PERCENT, verdict,
	])
	print("  strategies winning at least %.0f%%: %d of %d" % [
		CONTENDER_PERCENT, contenders, strategies.size(),
	])
	var random_vs_leader: String = "n/a"
	if medians.has(&"RANDOM") and medians[leader] != 0:
		random_vs_leader = "%.2f" % (float(medians[&"RANDOM"]) / float(medians[leader]))
		print("  RANDOM median / leader median (P3): %s" % random_vs_leader)

	# One line with every figure a sweep compares, for grep.
	var share: Dictionary[StringName, String] = {}
	for strategy: StringName in [&"TREND", &"LOWPE"]:
		share[strategy] = "-"
		if wins.has(strategy):
			share[strategy] = "%.1f" % (100.0 * float(wins[strategy]) / count)
	print("summary: years=%d leader=%s %.1f trend=%s lowpe=%s contenders=%d bull=%.3f splits=%.2f bankruptcies=%.2f random/leader=%s" % [
		years, leader, top, share[&"TREND"], share[&"LOWPE"], contenders,
		bull_rate / count, splits / count, bankruptcies / count, random_vs_leader,
	])


func _mean_of(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: int in values:
		total += value
	return total / float(values.size())


func _fail(message: String) -> void:
	print(message)
	print(USAGE)
	quit(1)
