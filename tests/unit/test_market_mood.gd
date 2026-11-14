extends GutTest
## The yearly bull/bear decision. See docs/game-rules.md §4.2.


func test_labels_match_the_original() -> void:
	assert_eq(MarketMood.label(MarketMood.Value.BULL), "BULL!!!")
	assert_eq(MarketMood.label(MarketMood.Value.BEAR), "bear...")


func test_shipped_weighting_is_seven_to_five() -> void:
	# The original encodes a 12-element array of 7 bull and 5 bear, i.e. 58.33%.
	# Seeded, so this assertion is stable rather than flaky.
	var rng: RandomNumberGenerator = StalksFixture.rng(12345)
	var trials: int = 60000
	var bull: int = 0
	for i: int in trials:
		if MarketMood.pick(7, 5, rng) == MarketMood.Value.BULL:
			bull += 1

	var percent: float = 100.0 * bull / trials
	assert_almost_eq(percent, 58.33, 1.0,
		"expected ~58.33%% bull, got %.2f%%" % percent)


func test_all_bull_weighting_never_returns_bear() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(1)
	for i: int in 500:
		assert_eq(MarketMood.pick(1, 0, rng), MarketMood.Value.BULL)


func test_all_bear_weighting_never_returns_bull() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(1)
	for i: int in 500:
		assert_eq(MarketMood.pick(0, 1, rng), MarketMood.Value.BEAR)


func test_zero_weights_fall_back_to_bull_instead_of_dividing_by_zero() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(1)
	assert_eq(MarketMood.pick(0, 0, rng), MarketMood.Value.BULL)
	assert_eq(MarketMood.pick(-5, -5, rng), MarketMood.Value.BULL)
