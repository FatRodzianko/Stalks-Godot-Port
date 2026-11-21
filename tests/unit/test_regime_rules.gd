extends GutTest
## StalkleHeads earnings regimes: the transition matrix and its three modifiers.
## See docs/stalkleheads-design.md §3.3 and decisions.md D131.
##
## Most of these need no RNG at all: `RegimeRules.odds` enumerates all hundred
## rolls, so the odds are exact.


const G: EarningsRegime.Value = EarningsRegime.Value.GROWTH
const ST: EarningsRegime.Value = EarningsRegime.Value.STEADY
const SL: EarningsRegime.Value = EarningsRegime.Value.SLOWING
const DE: EarningsRegime.Value = EarningsRegime.Value.DECLINE
const DI: EarningsRegime.Value = EarningsRegime.Value.DISTRESS


func test_every_matrix_row_sums_to_one_hundred() -> void:
	for regime: EarningsRegime.Value in EarningsRegime.ALL:
		var row: Array = RegimeRules.TRANSITION[regime]
		var total: int = 0
		for weight: int in row:
			total += weight
		assert_eq(row.size(), 5, "%s row has five columns" % EarningsRegime.name_of(regime))
		assert_eq(total, 100, "%s row sums to 100" % EarningsRegime.name_of(regime))


func test_the_matrix_is_the_published_one() -> void:
	assert_eq(RegimeRules.TRANSITION[G], [58, 14, 20, 6, 2])
	assert_eq(RegimeRules.TRANSITION[ST], [16, 50, 18, 13, 3])
	assert_eq(RegimeRules.TRANSITION[SL], [10, 28, 38, 21, 3])
	assert_eq(RegimeRules.TRANSITION[DE], [6, 18, 16, 46, 14])
	assert_eq(RegimeRules.TRANSITION[DI], [5, 10, 10, 25, 50])


func test_a_neutral_unaged_company_rolls_exactly_its_matrix_row() -> void:
	for regime: EarningsRegime.Value in EarningsRegime.ALL:
		var expected: Array[int] = []
		expected.assign(RegimeRules.TRANSITION[regime])
		assert_eq(RegimeRules.odds(regime, 50, 0), expected)


func test_the_stationary_distribution_sits_in_its_band() -> void:
	# §3.3: GROWTH 19.8%, STEADY 27.3%, SLOWING 21.5%, DECLINE 21.7%,
	# DISTRESS 9.8%. Editing a row must not quietly make the mode miserable.
	var share: Array[float] = [20.0, 20.0, 20.0, 20.0, 20.0]
	for step: int in 500:
		var next: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
		for from: int in 5:
			var row: Array = RegimeRules.TRANSITION[EarningsRegime.ALL[from]]
			for to: int in 5:
				next[to] += share[from] * float(row[to]) / 100.0
		share = next

	var published: Array[float] = [19.8, 27.3, 21.5, 21.7, 9.8]
	for index: int in 5:
		assert_almost_eq(share[index], published[index], 0.5,
			"%s stationary share" % EarningsRegime.name_of(EarningsRegime.ALL[index]))


func test_ageing_makes_a_long_growth_run_likelier_to_end() -> void:
	var stay: Array[int] = []
	for years: int in 5:
		stay.append(RegimeRules.odds(G, 50, years)[0])
	# 10 points a year off the 58-point GROWTH column.
	assert_eq(stay, [58, 48, 38, 28, 18] as Array[int])


func test_after_four_straight_growth_years_the_odds_have_turned_over() -> void:
	# Fourth year in GROWTH = three years beyond the year it was entered.
	assert_lt(RegimeRules.odds(G, 50, 3)[0], 50)


func test_ageing_also_applies_to_slowing() -> void:
	var fresh: Array[int] = RegimeRules.odds(SL, 50, 0)
	var aged: Array[int] = RegimeRules.odds(SL, 50, 2)
	assert_eq(fresh[0], 10)
	assert_eq(aged[0], 0, "20 points pushes the whole GROWTH column out")
	assert_gt(aged[3] + aged[4], fresh[3] + fresh[4], "pushed toward DECLINE and DISTRESS")


func test_steady_and_decline_do_not_age() -> void:
	assert_eq(RegimeRules.odds(ST, 50, 6), RegimeRules.odds(ST, 50, 0))
	assert_eq(RegimeRules.odds(DE, 50, 6), RegimeRules.odds(DE, 50, 0))


func test_recovery_lets_a_distressed_company_out() -> void:
	var stay: Array[int] = []
	for years: int in 5:
		stay.append(RegimeRules.odds(DI, 50, years)[4])
	assert_eq(stay[0], 50)
	for index: int in range(1, stay.size()):
		assert_lt(stay[index], stay[index - 1], "each DISTRESS year makes leaving likelier")
	# 12 points a year: 50 -> 38 -> 26.
	assert_eq(stay[1], 38)
	assert_eq(stay[2], 26)


func test_quality_biases_toward_better_regimes() -> void:
	var good: Array[int] = RegimeRules.odds(ST, 100, 0)
	var neutral: Array[int] = RegimeRules.odds(ST, 50, 0)
	var bad: Array[int] = RegimeRules.odds(ST, 0, 0)
	assert_eq(good[0], 26, "quality 100 takes 10 points off the roll")
	assert_eq(neutral[0], 16)
	assert_eq(bad[0], 6, "quality 0 adds 10")
	assert_gt(bad[4], neutral[4])
	assert_lt(good[4], neutral[4])


func test_quality_bias_range_is_ten_either_way() -> void:
	assert_eq(RegimeRules.quality_bias(0), -10.0)
	assert_eq(RegimeRules.quality_bias(50), 0.0)
	assert_eq(RegimeRules.quality_bias(100), 10.0)
	assert_eq(RegimeRules.quality_bias(25), -5.0)


func test_the_adjusted_roll_is_clamped_at_both_ends() -> void:
	assert_eq(RegimeRules.regime_for_roll(DI, 1, 100, 20), G, "far below 1 still lands left")
	assert_eq(RegimeRules.regime_for_roll(G, 100, 0, 20), DI, "far above 100 still lands right")


func test_the_roll_draws_once_whatever_the_outcome() -> void:
	# The twin makes the one `randi_range(1, 100)` call the roll is documented to
	# make. If the roll drew more or less, the two streams would part.
	for seed_value: int in 40:
		var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
		var twin: RandomNumberGenerator = StalksFixture.rng(seed_value)
		RegimeRules.roll_next(EarningsRegime.ALL[seed_value % 5], seed_value * 2, seed_value % 4, rng)
		twin.randi_range(1, 100)
		assert_eq(rng.state, twin.state, "seed %d" % seed_value)


func test_the_roll_follows_the_odds_over_many_draws() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(2026)
	var counts: Array[int] = [0, 0, 0, 0, 0]
	var trials: int = 20000
	for i: int in trials:
		counts[RegimeRules.roll_next(ST, 50, 0, rng)] += 1
	assert_almost_eq(100.0 * counts[1] / trials, 50.0, 1.5, "STEADY stays STEADY half the time")


func test_long_matches_damp_the_growth_bands() -> void:
	assert_eq(RegimeRules.growth_damping(10), 1.0)
	assert_eq(RegimeRules.growth_damping(19), 1.0)
	assert_eq(RegimeRules.growth_damping(20), 0.8)
	assert_eq(RegimeRules.growth_damping(49), 0.8)
	assert_eq(RegimeRules.growth_damping(50), 0.5)
	assert_eq(RegimeRules.growth_damping(99), 0.5)


func test_the_regime_tables_are_the_published_ones() -> void:
	assert_eq(RegimeRules.GROWTH_BAND[G], Vector2i(15, 35))
	assert_eq(RegimeRules.GROWTH_BAND[ST], Vector2i(-3, 6))
	assert_eq(RegimeRules.GROWTH_BAND[SL], Vector2i(2, 12))
	assert_eq(RegimeRules.GROWTH_BAND[DE], Vector2i(-20, -5))
	assert_eq(RegimeRules.GROWTH_BAND[DI], Vector2i(-45, -15))
	assert_eq(RegimeRules.MARGIN_TARGET[G], 14.0)
	assert_eq(RegimeRules.MARGIN_TARGET[ST], 12.0)
	assert_eq(RegimeRules.MARGIN_TARGET[SL], 11.0)
	assert_eq(RegimeRules.MARGIN_TARGET[DE], 7.0)
	assert_eq(RegimeRules.MARGIN_TARGET[DI], 1.0)
	assert_eq(RegimeRules.PREMIUM[G], 0.6)
	assert_eq(RegimeRules.PREMIUM[ST], 0.0)
	assert_eq(RegimeRules.PREMIUM[SL], 0.24)
	assert_eq(RegimeRules.PREMIUM[DE], -0.6)
	assert_eq(RegimeRules.PREMIUM[DI], -1.4)
