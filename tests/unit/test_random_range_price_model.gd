extends GutTest
## The faithful price model: per-stalk ranges, the 10% contrarian move, and
## long-game softening. See docs/game-rules.md §4.3, §4.4 and §4.5.


var _model: RandomRangePriceModel
var _state: GameState
var _stryker: StalkState
var _bonds: StalkState


func before_each() -> void:
	_model = RandomRangePriceModel.new()
	_state = StalksFixture.make_state(10, 1)
	_stryker = _state.stalk_by_id(&"stryker")
	_bonds = _state.stalk_by_id(&"berry_bonds")


func test_static_stalk_never_moves() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(42)
	for i: int in 2000:
		assert_eq(_model.next_change(_bonds, MarketMood.Value.BULL, _state, rng), 0)
		assert_eq(_model.next_change(_bonds, MarketMood.Value.BEAR, _state, rng), 0)


func test_contrarian_move_fires_about_ten_percent_of_the_time() -> void:
	# strYker's normal bull move is +13..+42, so any delta <= 0 must be contrarian.
	var rng: RandomNumberGenerator = StalksFixture.rng(777)
	var trials: int = 60000
	var contrarian: int = 0
	for i: int in trials:
		if _model.next_change(_stryker, MarketMood.Value.BULL, _state, rng) <= 0:
			contrarian += 1

	var percent: float = 100.0 * contrarian / trials
	assert_almost_eq(percent, 10.0, 0.8,
		"expected ~10%% contrarian, got %.2f%%" % percent)


func test_bull_range_endpoints_are_both_reachable() -> void:
	# The original used C# Random.Next(min, max), which excludes max, so 42 was
	# unreachable despite the stat block. The port is inclusive on purpose.
	var rng: RandomNumberGenerator = StalksFixture.rng(4242)
	var saw_min: bool = false
	var saw_max: bool = false
	var outside: int = 0

	for i: int in 50000:
		var delta: int = _model.next_change(_stryker, MarketMood.Value.BULL, _state, rng)
		if delta <= 0:
			continue  # contrarian move, not the normal range
		if delta == 13:
			saw_min = true
		if delta == 42:
			saw_max = true
		if delta < 13 or delta > 42:
			outside += 1

	assert_true(saw_min, "never produced the range minimum of 13")
	assert_true(saw_max, "never produced the range maximum of 42")
	assert_eq(outside, 0, "produced a normal move outside 13..42")


func test_bear_range_endpoints_are_both_reachable() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(909)
	var saw_min: bool = false
	var saw_max: bool = false

	for i: int in 50000:
		var delta: int = _model.next_change(_stryker, MarketMood.Value.BEAR, _state, rng)
		if delta >= 0:
			continue  # contrarian move
		if delta == -15:
			saw_min = true
		if delta == -50:
			saw_max = true

	assert_true(saw_min, "never produced the smallest bear drop of -15")
	assert_true(saw_max, "never produced the largest bear drop of -50")


func test_bear_moves_are_negative_and_bull_moves_positive() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(31337)
	# mafia has no zero in either range, so sign is unambiguous outside the
	# contrarian case.
	var mafia: StalkState = _state.stalk_by_id(&"mafia")
	for i: int in 3000:
		var bear: int = _model.next_change(mafia, MarketMood.Value.BEAR, _state, rng)
		assert_between(bear, -25, 5, "bear move out of expected bounds")
		var bull: int = _model.next_change(mafia, MarketMood.Value.BULL, _state, rng)
		assert_between(bull, -10, 15, "bull move out of expected bounds")


func test_softening_thresholds() -> void:
	# Boundaries are strictly greater-than, so 19 and 49 are NOT softened.
	var cases: Array = [
		[10, 1.0, 1.0],
		[19, 1.0, 1.0],
		[20, 0.80, 0.70],
		[49, 0.80, 0.70],
		[50, 0.50, 0.45],
		[99, 0.50, 0.45],
	]
	for case: Array in cases:
		var settings: GameSettings = StalksFixture.make_settings(case[0])
		assert_almost_eq(
			settings.softening_multiplier(MarketMood.Value.BULL), case[1] as float, 0.001,
			"bull multiplier wrong at %d years" % case[0]
		)
		assert_almost_eq(
			settings.softening_multiplier(MarketMood.Value.BEAR), case[2] as float, 0.001,
			"bear multiplier wrong at %d years" % case[0]
		)


func test_softening_shrinks_moves_in_a_long_game() -> void:
	var long_state: GameState = StalksFixture.make_state(99, 1)
	var long_stryker: StalkState = long_state.stalk_by_id(&"stryker")
	var rng: RandomNumberGenerator = StalksFixture.rng(5150)

	# Softened bull range is int(13..42 * 0.5) = 6..21. Nothing may exceed 21.
	var highest: int = 0
	for i: int in 20000:
		var delta: int = _model.next_change(long_stryker, MarketMood.Value.BULL, long_state, rng)
		if delta > highest:
			highest = delta
	assert_between(highest, 18, 21,
		"softened bull move peaked at %d, expected at most 21" % highest)


func test_truncation_runs_toward_zero_like_the_original_cast() -> void:
	# C#'s (int) cast truncates toward zero for both signs; int() must match, or
	# softened bear moves would be a point too harsh.
	assert_eq(int(-13.5), -13)
	assert_eq(int(13.5), 13)
