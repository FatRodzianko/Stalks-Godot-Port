extends GutTest
## The ordered end-of-year sequence. See docs/game-rules.md §4.1, §6, §7, §8, §12.
##
## The ordering assertions matter most: splits are checked once, AFTER the event,
## and dividends are paid AFTER splits.


var _state: GameState
var _player: PlayerState


func before_each() -> void:
	_state = StalksFixture.make_state(10, 1)
	_player = _state.players[0]


# -------------------------------------------------------------------- splitting

func test_split_halves_the_price_rounding_up_on_odd() -> void:
	# The live original rounds UP: 153 -> 77, not 76. A dead code path in the
	# original rounded down; this pins the behaviour that shipped.
	var cases: Array = [[151, 76], [152, 76], [153, 77], [155, 78], [300, 150]]
	for case: Array in cases:
		var state: GameState = StalksFixture.make_state(10, 1)
		var stalk: StalkState = state.stalk_by_id(&"stryker")
		stalk.price = case[0]
		state.players[0].set_shares(&"stryker", 10)

		StalksFixture.frozen_resolver().advance_year(state, StalksFixture.rng(1))

		assert_eq(stalk.price, case[1] as int,
			"price %d should split to %d" % [case[0], case[1]])
		assert_eq(state.players[0].shares_of(&"stryker"), 20,
			"shares should double when %d splits" % case[0])


func test_no_split_at_exactly_the_threshold() -> void:
	# The rule is strictly ABOVE 150.
	var stalk: StalkState = _state.stalk_by_id(&"stryker")
	stalk.price = 150
	_player.set_shares(&"stryker", 10)

	StalksFixture.frozen_resolver().advance_year(_state, StalksFixture.rng(1))

	assert_eq(stalk.price, 150)
	assert_eq(_player.shares_of(&"stryker"), 10)
	assert_false(stalk.did_split)


func test_split_is_reported_in_the_year_result() -> void:
	var stalk: StalkState = _state.stalk_by_id(&"stryker")
	stalk.price = 160

	var result: YearResult = StalksFixture.frozen_resolver().advance_year(
		_state, StalksFixture.rng(1)
	)

	assert_true(result.split_ids().has(&"stryker"))
	assert_true(result.change_for(&"stryker").did_split)
	assert_eq(result.change_for(&"stryker").price_after, 80)


func test_a_negative_event_can_prevent_a_split() -> void:
	# Splits are checked ONCE, after the event. A stalk pushed above 150 by its
	# base move and knocked back under by the event must not split.
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"crash", &"stryker", MarketMood.Value.BULL, -20),
	]
	var resolver: YearResolver = YearResolver.new(
		FixedPriceModelStub.new(55), EventPool.new(events)
	)
	_state.settings.bear_weight = 0  # force bull so the bull event is drawn

	var stalk: StalkState = _state.stalk_by_id(&"stryker")
	stalk.price = 100

	var result: YearResult = resolver.advance_year(_state, StalksFixture.rng(2))

	assert_eq(result.mood, MarketMood.Value.BULL)
	assert_eq(stalk.price, 135, "100 + 55 base - 20 event = 135")
	assert_false(stalk.did_split, "135 is under the threshold, so no split")


func test_holdings_of_a_static_stalk_are_never_doubled() -> void:
	var bonds: StalkState = _state.stalk_by_id(&"berry_bonds")
	_player.set_shares(&"berry_bonds", 10)

	StalksFixture.resolver_with_delta(100).advance_year(_state, StalksFixture.rng(1))

	assert_eq(bonds.price, 100, "BERRY BONDS must not move")
	assert_eq(_player.shares_of(&"berry_bonds"), 10)


# ------------------------------------------------------------------- bankruptcy

func test_price_at_or_below_zero_goes_bankrupt_and_wipes_holdings() -> void:
	var stalk: StalkState = _state.stalk_by_id(&"stryker")
	_player.set_shares(&"stryker", 50)

	var result: YearResult = StalksFixture.resolver_with_delta(-200).advance_year(
		_state, StalksFixture.rng(1)
	)

	assert_true(stalk.is_bankrupt)
	assert_eq(stalk.price, 0, "a bankrupt price is pinned to 0")
	assert_eq(_player.shares_of(&"stryker"), 0, "holdings are wiped with no compensation")
	assert_true(result.bankrupt_ids().has(&"stryker"))


func test_price_of_exactly_zero_is_bankrupt() -> void:
	var stalk: StalkState = _state.stalk_by_id(&"stryker")
	stalk.price = 50
	StalksFixture.resolver_with_delta(-50).advance_year(_state, StalksFixture.rng(1))
	assert_true(stalk.is_bankrupt, "the rule is at or below zero, not strictly below")


func test_a_static_stalk_never_goes_bankrupt() -> void:
	var bonds: StalkState = _state.stalk_by_id(&"berry_bonds")
	StalksFixture.resolver_with_delta(-500).advance_year(_state, StalksFixture.rng(1))
	assert_false(bonds.is_bankrupt)
	assert_eq(bonds.price, 100)


func test_an_event_can_bankrupt_a_stalk_the_base_move_spared() -> void:
	# This is why there are two bankruptcy passes.
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"doom", &"stryker", MarketMood.Value.BEAR, -25),
	]
	var resolver: YearResolver = YearResolver.new(
		FixedPriceModelStub.new(-80), EventPool.new(events)
	)
	_state.settings.bull_weight = 0  # force bear

	var stalk: StalkState = _state.stalk_by_id(&"stryker")
	stalk.price = 100
	_player.set_shares(&"stryker", 10)

	resolver.advance_year(_state, StalksFixture.rng(3))

	assert_true(stalk.is_bankrupt, "100 - 80 = 20 survived, then -25 killed it")
	assert_eq(_player.shares_of(&"stryker"), 0)


func test_a_bankrupt_stalk_stays_bankrupt_and_stops_moving() -> void:
	var stalk: StalkState = _state.stalk_by_id(&"stryker")
	var resolver: YearResolver = StalksFixture.resolver_with_delta(-200)
	resolver.advance_year(_state, StalksFixture.rng(1))
	assert_true(stalk.is_bankrupt)

	var revive: YearResolver = StalksFixture.resolver_with_delta(500)
	revive.advance_year(_state, StalksFixture.rng(1))
	assert_eq(stalk.price, 0, "a bankrupt stalk must not come back to life")


# --------------------------------------------------------------------- dividends

func test_dividends_are_paid_on_post_split_share_counts() -> void:
	# Dividends come AFTER splits, so a split pays out on the doubled count.
	# teamsters pays 8 per share in a bull year.
	_state.settings.bear_weight = 0
	var teamsters: StalkState = _state.stalk_by_id(&"teamsters")
	teamsters.price = 152
	_player.set_shares(&"teamsters", 10)
	var cash_before: int = _player.cash

	var result: YearResult = StalksFixture.frozen_resolver().advance_year(
		_state, StalksFixture.rng(3)
	)

	assert_eq(result.mood, MarketMood.Value.BULL)
	assert_eq(teamsters.price, 76, "152 splits to 76")
	assert_eq(_player.shares_of(&"teamsters"), 20)
	assert_eq(_player.cash - cash_before, 160, "20 doubled shares x 8 = 160")
	assert_eq(result.dividends[&"p0"], 160)


func test_bear_and_bull_dividends_differ() -> void:
	# springfield pays 5 in a bull year and 0 in a bear year.
	for mood_case: Array in [[0, 5], [1, 0]]:
		var state: GameState = StalksFixture.make_state(10, 1)
		if mood_case[0] == 0:
			state.settings.bear_weight = 0
		else:
			state.settings.bull_weight = 0
		state.players[0].set_shares(&"springfield", 10)
		var cash_before: int = state.players[0].cash

		StalksFixture.frozen_resolver().advance_year(state, StalksFixture.rng(4))

		assert_eq(state.players[0].cash - cash_before, (mood_case[1] as int) * 10)


func test_no_dividend_from_a_stalk_that_went_bankrupt_this_year() -> void:
	_state.settings.bull_weight = 0  # bear; pillows pays 1 in a bear year
	var pillows: StalkState = _state.stalk_by_id(&"pillows")
	_player.set_shares(&"pillows", 100)
	var cash_before: int = _player.cash

	StalksFixture.resolver_with_delta(-200).advance_year(_state, StalksFixture.rng(1))

	assert_true(pillows.is_bankrupt)
	assert_eq(_player.cash - cash_before, 0, "wiped holdings pay nothing")


# ------------------------------------------------------------- yearly change text

func test_displayed_yearly_change_excludes_the_event_delta() -> void:
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"boom", &"stryker", MarketMood.Value.BULL, 15),
	]
	var resolver: YearResolver = YearResolver.new(
		FixedPriceModelStub.new(10), EventPool.new(events)
	)
	_state.settings.bear_weight = 0

	var result: YearResult = resolver.advance_year(_state, StalksFixture.rng(5))
	var change: StalkYearChange = result.change_for(&"stryker")

	assert_eq(change.base_delta, 10, "the displayed figure is the base move only")
	assert_eq(change.event_delta, 15, "the event is tracked separately")
	assert_eq(change.total_delta(), 25)
	assert_eq(_state.stalk_by_id(&"stryker").last_yearly_change, 10,
		"the board shows 10, not 25 — matching the original")


# ------------------------------------------------------------------- game length

func test_a_ten_year_match_settles_once_more_and_ends_at_year_eleven() -> void:
	var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
	var state: GameState = StalksFixture.make_state(10, 2, defs)
	var resolver: YearResolver = StalksFixture.real_resolver(defs)
	var rng: RandomNumberGenerator = StalksFixture.rng(2024)

	var advances: int = 0
	while not state.is_over and advances < 50:
		resolver.advance_year(state, rng)
		advances += 1

	assert_true(state.is_over)
	assert_eq(state.year, 11, "years 1..10 are played, then one final settling year")
	assert_eq(advances, 11)
	assert_eq(state.history.size(), 11, "every year is recorded in history")
	assert_true(state.latest_result().is_final_year)
	assert_false(state.latest_result().winners.is_empty(), "a winner must be declared")


func test_a_ninety_nine_year_match_runs_to_completion() -> void:
	# The longest legal match, at the heaviest softening tier. Also the strongest
	# check that BERRY BONDS is genuinely immovable and that nothing drifts over
	# a long run.
	var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
	var state: GameState = StalksFixture.make_state(99, 10, defs)
	var resolver: YearResolver = StalksFixture.real_resolver(defs)
	var rng: RandomNumberGenerator = StalksFixture.rng(7)

	# Give every player a position so splits, bankruptcies and dividends all bite.
	state.year = 1
	for player: PlayerState in state.players:
		player.set_shares(&"stryker", 20)
		player.set_shares(&"berry_bonds", 10)
		player.set_shares(&"teamsters", 15)
	state.year = 0

	var advances: int = 0
	while not state.is_over and advances < 200:
		resolver.advance_year(state, rng)
		advances += 1

	assert_true(state.is_over, "a 99-year match must terminate")
	assert_eq(state.year, 100, "years 1..99 plus one final settling year")
	assert_eq(state.history.size(), 100)

	var bonds: StalkState = state.stalk_by_id(&"berry_bonds")
	assert_eq(bonds.price, 100, "BERRY BONDS must sit at 100 after 99 years")
	assert_false(bonds.is_bankrupt)
	for player: PlayerState in state.players:
		assert_eq(player.shares_of(&"berry_bonds"), 10,
			"a static stalk never splits, so holdings never double")

	assert_false(state.latest_result().winners.is_empty())


func test_no_stalk_price_ever_goes_negative_over_a_long_match() -> void:
	var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
	var state: GameState = StalksFixture.make_state(99, 1, defs)
	var resolver: YearResolver = StalksFixture.real_resolver(defs)
	var rng: RandomNumberGenerator = StalksFixture.rng(555)

	while not state.is_over:
		resolver.advance_year(state, rng)
		for stalk: StalkState in state.stalks:
			assert_true(stalk.price >= 0,
				"%s fell to %d; bankruptcy should pin it at 0" % [stalk.id, stalk.price])


func test_trading_closes_once_the_game_is_over() -> void:
	var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
	var state: GameState = StalksFixture.make_state(2, 1, defs)
	var resolver: YearResolver = StalksFixture.real_resolver(defs)
	var rng: RandomNumberGenerator = StalksFixture.rng(9)
	while not state.is_over:
		resolver.advance_year(state, rng)
	assert_false(state.is_trading_open())


func test_ready_flags_clear_after_each_year() -> void:
	_player.is_ready = true
	StalksFixture.frozen_resolver().advance_year(_state, StalksFixture.rng(1))
	assert_false(_player.is_ready, "readiness resets so the next year can be gated")


# ------------------------------------------------------------------ determinism

func test_the_same_seed_reproduces_a_whole_match() -> void:
	var fingerprints: Array[String] = []
	for attempt: int in 2:
		var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
		var state: GameState = StalksFixture.make_state(20, 3, defs)
		var resolver: YearResolver = StalksFixture.real_resolver(defs)
		var rng: RandomNumberGenerator = StalksFixture.rng(99)
		while not state.is_over:
			resolver.advance_year(state, rng)
		fingerprints.append(_fingerprint(state))

	assert_eq(fingerprints[0], fingerprints[1],
		"identical seeds must produce an identical 20-year match")
	assert_gt(fingerprints[0].length(), 50, "the fingerprint should be substantial")


func test_different_seeds_produce_different_matches() -> void:
	var fingerprints: Array[String] = []
	for seed_value: int in [1, 2]:
		var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
		var state: GameState = StalksFixture.make_state(20, 3, defs)
		var resolver: YearResolver = StalksFixture.real_resolver(defs)
		var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
		while not state.is_over:
			resolver.advance_year(state, rng)
		fingerprints.append(_fingerprint(state))

	assert_ne(fingerprints[0], fingerprints[1])


func _fingerprint(state: GameState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for result: YearResult in state.history:
		var event_id: String = str(result.event.id) if result.event != null else "-"
		parts.append("%d:%d:%s:%d" % [
			result.year, result.mood, event_id, result.net_worths[&"p0"],
		])
	return "|".join(parts)
