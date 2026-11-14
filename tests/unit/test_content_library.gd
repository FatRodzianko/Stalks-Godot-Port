extends GutTest
## The authored content in src/data/stalks/, and the validator that guards it.
## See docs/game-rules.md §3 and §5.


var _library: ContentLibrary


func before_each() -> void:
	_library = ContentLibrary.load_from()


# ------------------------------------------------------- the real shipped content

func test_the_real_content_loads_and_validates_clean() -> void:
	# The single most important assertion in this file: whatever is on disk is
	# internally consistent.
	assert_eq(_library.errors, [] as Array[String],
		"authored content should have no validation errors")
	assert_true(_library.is_valid())


func test_ten_stalks_are_authored() -> void:
	assert_eq(_library.stalks.size(), 10)


func test_the_expected_stalk_ids_are_present() -> void:
	var ids: Array[String] = []
	for stalk: StalkDefinition in _library.stalks:
		ids.append(String(stalk.id))
	ids.sort()

	var expected: Array[String] = [
		"berry_bonds", "mafia", "monorail", "mutuals", "pgenron",
		"pillows", "springfield", "stryker", "submissives", "teamsters",
	]
	assert_eq(ids, expected)


func test_every_stalk_starts_at_one_hundred() -> void:
	for stalk: StalkDefinition in _library.stalks:
		assert_eq(stalk.starting_price, 100, "%s should start at 100" % stalk.id)


func test_event_pools_are_forty_five_each() -> void:
	assert_eq(_library.events_for_mood(MarketMood.Value.BULL).size(), 45)
	assert_eq(_library.events_for_mood(MarketMood.Value.BEAR).size(), 45)
	assert_eq(_library.all_events().size(), 90)


func test_the_static_stalk_is_berry_bonds_and_carries_no_events() -> void:
	var static_ids: Array[StringName] = []
	for stalk: StalkDefinition in _library.stalks:
		if stalk.is_price_static:
			static_ids.append(stalk.id)
	assert_eq(static_ids, [&"berry_bonds"] as Array[StringName],
		"exactly one stalk should be static-price")

	var bonds: StalkDefinition = _library.stalk_by_id(&"berry_bonds")
	assert_eq(bonds.all_events().size(), 0)


func test_every_non_static_stalk_has_five_events_per_mood() -> void:
	for stalk: StalkDefinition in _library.stalks:
		if stalk.is_price_static:
			continue
		assert_eq(stalk.bull_events.size(), 5, "%s bull events" % stalk.id)
		assert_eq(stalk.bear_events.size(), 5, "%s bear events" % stalk.id)


func test_every_event_targets_the_stalk_it_lives_on() -> void:
	for stalk: StalkDefinition in _library.stalks:
		for event: SpecialEventDefinition in stalk.all_events():
			assert_eq(event.target_stalk_id, stalk.id,
				"event %s should target %s" % [event.id, stalk.id])


func test_every_event_has_flavour_text_and_a_real_price_change() -> void:
	for event: SpecialEventDefinition in _library.all_events():
		assert_false(event.flavour_text.is_empty(), "event %s has no text" % event.id)
		assert_ne(event.price_change, 0, "event %s changes nothing" % event.id)


func test_event_ids_are_unique() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for event: SpecialEventDefinition in _library.all_events():
		assert_false(seen.has(event.id), "duplicate event id %s" % event.id)
		seen[event.id] = true
	assert_eq(seen.size(), 90)


func test_the_shipped_stat_blocks_match_the_documented_values() -> void:
	# Cross-check: the .tres files on disk against the table in
	# docs/game-rules.md §3, which StalksFixture also encodes by hand. The
	# duplication is deliberate — it means a bad edit to a .tres, or a mistake in
	# the importer that produced them, fails here instead of silently changing
	# how the game plays.
	for row: Array in StalksFixture.STALK_ROWS:
		var stalk_id: StringName = row[0]
		var stalk: StalkDefinition = _library.stalk_by_id(stalk_id)
		assert_not_null(stalk, "missing stalk %s" % stalk_id)
		if stalk == null:
			continue

		assert_eq(stalk.display_name, row[1] as String, "%s display name" % stalk_id)
		assert_eq(stalk.bear_change, row[2] as Vector2i, "%s bear range" % stalk_id)
		assert_eq(stalk.bull_change, row[3] as Vector2i, "%s bull range" % stalk_id)
		assert_eq(stalk.bear_dividend, row[4] as int, "%s bear dividend" % stalk_id)
		assert_eq(stalk.bull_dividend, row[5] as int, "%s bull dividend" % stalk_id)
		assert_eq(stalk.is_price_static, row[6] as bool, "%s static flag" % stalk_id)


func test_loading_is_deterministic_in_order() -> void:
	# Directory listing order is not guaranteed across platforms, and the stalk
	# order affects iteration in the simulation.
	var second: ContentLibrary = ContentLibrary.load_from()
	for i: int in _library.stalks.size():
		assert_eq(_library.stalks[i].id, second.stalks[i].id)


# --------------------------------------------------------------------- factories

func test_building_stalk_states_gives_a_fresh_market() -> void:
	var states: Array[StalkState] = _library.build_stalk_states()
	assert_eq(states.size(), 10)
	for state: StalkState in states:
		assert_eq(state.price, 100)
		assert_false(state.is_bankrupt)
		assert_eq(state.last_yearly_change, 0)


func test_building_an_event_pool_gives_both_full_pools() -> void:
	var pool: EventPool = _library.build_event_pool()
	assert_eq(pool.pool_size(MarketMood.Value.BULL), 45)
	assert_eq(pool.pool_size(MarketMood.Value.BEAR), 45)


func test_a_full_game_can_be_played_from_the_authored_content() -> void:
	# End-to-end: real content, real price model, a complete match.
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	var state: GameState = GameState.new(settings)
	state.stalks = _library.build_stalk_states()
	state.players.append(PlayerState.new(&"p0", "Player 0", settings.starting_cash))

	var resolver: YearResolver = YearResolver.new(
		RandomRangePriceModel.new(), _library.build_event_pool()
	)
	var rng: RandomNumberGenerator = StalksFixture.rng(2026)

	var advances: int = 0
	while not state.is_over and advances < 30:
		resolver.advance_year(state, rng)
		advances += 1

	assert_true(state.is_over)
	assert_eq(state.year, 11)
	assert_eq(state.history.size(), 11)
	assert_false(state.latest_result().winners.is_empty())

	# Events drawn from real content should have resolved against real stalks.
	var events_fired: int = 0
	for result: YearResult in state.history:
		if result.event != null:
			events_fired += 1
			assert_not_null(_library.stalk_by_id(result.event.target_stalk_id),
				"event %s targeted a stalk that does not exist" % result.event.id)
	assert_gt(events_fired, 0, "at least one event should have fired over 11 years")


# -------------------------------------------------------------- validator checks

## A minimal valid stalk, to be broken one way at a time.
func _good_stalk(stalk_id: StringName = &"a") -> StalkDefinition:
	var stalk: StalkDefinition = StalkDefinition.new()
	stalk.id = stalk_id
	stalk.display_name = "A Stalk"
	stalk.starting_price = 100
	stalk.bear_change = Vector2i(5, 10)
	stalk.bull_change = Vector2i(5, 10)
	return stalk


func _library_of(stalks: Array[StalkDefinition]) -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.new()
	library.stalks = stalks
	library.validate()
	return library


func test_validator_rejects_an_empty_library() -> void:
	assert_false(_library_of([] as Array[StalkDefinition]).is_valid())


func test_validator_accepts_a_good_stalk() -> void:
	assert_true(_library_of([_good_stalk()] as Array[StalkDefinition]).is_valid())


func test_validator_catches_duplicate_stalk_ids() -> void:
	var library: ContentLibrary = _library_of(
		[_good_stalk(&"dupe"), _good_stalk(&"dupe")] as Array[StalkDefinition]
	)
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("Duplicate stalk id"))


func test_validator_catches_a_missing_id() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.id = &""
	assert_false(_library_of([stalk] as Array[StalkDefinition]).is_valid())


func test_validator_catches_a_nonsense_starting_price() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.starting_price = 0
	assert_false(_library_of([stalk] as Array[StalkDefinition]).is_valid())


func test_validator_catches_an_inverted_range() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.bull_change = Vector2i(20, 5)
	var library: ContentLibrary = _library_of([stalk] as Array[StalkDefinition])
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("min above max"))


func test_validator_catches_a_negative_range_magnitude() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.bear_change = Vector2i(-5, 10)
	assert_false(_library_of([stalk] as Array[StalkDefinition]).is_valid())


func test_validator_catches_an_event_targeting_the_wrong_stalk() -> void:
	# The bug class this validator exists for: a typo in a target id produces an
	# event that can never fire, with no error anywhere.
	var stalk: StalkDefinition = _good_stalk(&"real")
	stalk.bull_events = [
		StalksFixture.make_event(&"ev", &"typo", MarketMood.Value.BULL, 10)
	] as Array[SpecialEventDefinition]

	var library: ContentLibrary = _library_of([stalk] as Array[StalkDefinition])
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("targets"))


func test_validator_catches_an_event_in_the_wrong_mood_list() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.bull_events = [
		StalksFixture.make_event(&"ev", &"a", MarketMood.Value.BEAR, -10)
	] as Array[SpecialEventDefinition]

	var library: ContentLibrary = _library_of([stalk] as Array[StalkDefinition])
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("marked"))


func test_validator_catches_duplicate_event_ids() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.bull_events = [
		StalksFixture.make_event(&"same", &"a", MarketMood.Value.BULL, 10),
		StalksFixture.make_event(&"same", &"a", MarketMood.Value.BULL, 15),
	] as Array[SpecialEventDefinition]

	var library: ContentLibrary = _library_of([stalk] as Array[StalkDefinition])
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("Duplicate event id"))


func test_validator_catches_a_zero_change_event() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.bull_events = [
		StalksFixture.make_event(&"ev", &"a", MarketMood.Value.BULL, 0)
	] as Array[SpecialEventDefinition]
	assert_false(_library_of([stalk] as Array[StalkDefinition]).is_valid())


func test_validator_catches_events_on_a_static_stalk() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.is_price_static = true
	stalk.bull_events = [
		StalksFixture.make_event(&"ev", &"a", MarketMood.Value.BULL, 10)
	] as Array[SpecialEventDefinition]

	var library: ContentLibrary = _library_of([stalk] as Array[StalkDefinition])
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("static-price"))


func test_validator_reports_every_problem_not_just_the_first() -> void:
	var stalk: StalkDefinition = _good_stalk()
	stalk.display_name = ""
	stalk.starting_price = -1
	stalk.bull_change = Vector2i(20, 5)

	var library: ContentLibrary = _library_of([stalk] as Array[StalkDefinition])
	assert_gt(library.errors.size(), 2,
		"an author should see all their mistakes in one run")


func test_loading_a_missing_directory_reports_an_error_rather_than_crashing() -> void:
	var library: ContentLibrary = ContentLibrary.load_from("res://does/not/exist")
	assert_false(library.is_valid())
	assert_eq(library.stalks.size(), 0)
