extends GutTest
## Special event selection: no repeats, refill on exhaustion, and skipping
## events whose target is already bankrupt. See docs/game-rules.md §5.


var _state: GameState
var _pool: EventPool


func before_each() -> void:
	var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
	_state = StalksFixture.make_state(10, 1, defs)
	_pool = EventPool.new(StalksFixture.build_events(defs))


func test_pool_sizes_match_the_shipped_content() -> void:
	# 5 events per mood for each of the 9 non-static stalks.
	assert_eq(_pool.pool_size(MarketMood.Value.BULL), 45)
	assert_eq(_pool.pool_size(MarketMood.Value.BEAR), 45)


func test_static_stalk_has_no_events() -> void:
	for event: SpecialEventDefinition in StalksFixture.build_events(
		StalksFixture.build_stalks()
	):
		assert_ne(event.target_stalk_id, &"berry_bonds",
			"BERRY BONDS must carry no special events")


func test_a_full_cycle_of_draws_yields_no_repeats() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(11)
	var seen: Dictionary[StringName, bool] = {}

	for i: int in 45:
		var drawn: SpecialEventDefinition = _pool.draw(MarketMood.Value.BULL, _state, rng)
		assert_not_null(drawn, "ran dry after %d draws" % i)
		if drawn != null:
			assert_false(seen.has(drawn.id), "event %s repeated within one cycle" % drawn.id)
			seen[drawn.id] = true

	assert_eq(seen.size(), 45, "did not see every event in the pool")


func test_the_bag_refills_once_exhausted() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(11)
	for i: int in 45:
		_pool.draw(MarketMood.Value.BULL, _state, rng)
	assert_eq(_pool.remaining(MarketMood.Value.BULL), 0, "bag should be empty")

	assert_not_null(_pool.draw(MarketMood.Value.BULL, _state, rng),
		"a 46th draw must refill rather than return null")


func test_a_long_game_keeps_drawing_past_pool_exhaustion() -> void:
	# A 99-year game has roughly 58 bull years against only 45 bull events, so
	# exhaustion is reachable in normal play.
	var rng: RandomNumberGenerator = StalksFixture.rng(3)
	for i: int in 200:
		assert_not_null(_pool.draw(MarketMood.Value.BULL, _state, rng),
			"draw %d returned null" % i)


func test_bull_draws_never_return_bear_events() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(8)
	for i: int in 60:
		var drawn: SpecialEventDefinition = _pool.draw(MarketMood.Value.BULL, _state, rng)
		if drawn != null:
			assert_eq(drawn.mood, MarketMood.Value.BULL)
			assert_gt(drawn.price_change, 0, "a bull event should raise the price")


func test_no_event_when_every_candidate_targets_a_bankrupt_stalk() -> void:
	var only_stryker: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"a", &"stryker", MarketMood.Value.BULL, 10),
		StalksFixture.make_event(&"b", &"stryker", MarketMood.Value.BULL, 15),
	]
	var pool: EventPool = EventPool.new(only_stryker)
	_state.stalk_by_id(&"stryker").is_bankrupt = true

	assert_null(pool.draw(MarketMood.Value.BULL, _state, StalksFixture.rng(5)),
		"should decline to pick an event targeting a dead stalk")


func test_a_skipped_event_is_not_consumed() -> void:
	var only_stryker: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"a", &"stryker", MarketMood.Value.BULL, 10),
		StalksFixture.make_event(&"b", &"stryker", MarketMood.Value.BULL, 15),
	]
	var pool: EventPool = EventPool.new(only_stryker)
	var stryker: StalkState = _state.stalk_by_id(&"stryker")

	stryker.is_bankrupt = true
	assert_null(pool.draw(MarketMood.Value.BULL, _state, StalksFixture.rng(5)))

	# Once the target is viable again, those same events must still be available.
	stryker.is_bankrupt = false
	assert_not_null(pool.draw(MarketMood.Value.BULL, _state, StalksFixture.rng(5)),
		"skipped events should have stayed in the bag")


func test_an_empty_pool_simply_yields_no_event() -> void:
	var pool: EventPool = EventPool.new([])
	assert_null(pool.draw(MarketMood.Value.BULL, _state, StalksFixture.rng(1)))
	assert_eq(pool.pool_size(MarketMood.Value.BULL), 0)
