extends GutTest
## The StalkleHeads year pipeline (phase S3): `EarningsYearResolver`, its board
## and market (`EarningsMarket`), and the back half it shares with the base game
## (`YearSettlement`). See docs/stalkleheads-design.md §3, §4, §10.2 and §12.1.
##
## Every test that draws from an RNG seeds it. Tests that need a particular
## event build their own `EventPool`; tests that must not be disturbed by an
## event use an empty one.


var _library: ContentLibrary


func before_all() -> void:
	_library = ContentLibrary.load_from()
	_library.load_fundamentals()


# --------------------------------------------------------------------- helpers

func _new_state(max_years: int = 10, player_count: int = 1) -> GameState:
	var state: GameState = EarningsMarket.new_game_state(_library, StalksFixture.make_settings(max_years))
	for index: int in player_count:
		state.players.append(PlayerState.new(StringName("p%d" % index), "P%d" % index, 10000))
	return state


func _shipped_resolver() -> EarningsYearResolver:
	return EarningsYearResolver.new(EarningsMarket.build_event_pool(_library))


func _quiet_resolver() -> EarningsYearResolver:
	return EarningsYearResolver.new(EventPool.new([]))


func _resolver_with(events: Array[SpecialEventDefinition]) -> EarningsYearResolver:
	return EarningsYearResolver.new(EventPool.new(events))


## A company that will price at or below zero this year: its earnings are wiped
## out, so fair value hits its -40 floor and nothing can lift it back above 0.
func _doom(state: GameState, company_id: StringName) -> void:
	var company: CompanyState = state.market.company_by_id(company_id)
	company.revenue = 1000000.0
	company.margin_percent = -90.0
	company.profit = -1000000.0
	company.regime = EarningsRegime.Value.DISTRESS


## Runs `years` years with the shipped events and returns every result.
func _run(seed_value: int, years: int, state: GameState = null) -> Array[EarningsYearResult]:
	if state == null:
		state = _new_state(years)
	var resolver: EarningsYearResolver = _shipped_resolver()
	var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
	var results: Array[EarningsYearResult] = []
	for year: int in years:
		results.append(resolver.advance_year(state, rng))
	return results


func _record(state: GameState, result: EarningsYearResult) -> String:
	var parts: PackedStringArray = ["y%d %s %.6f" % [result.year, MarketMood.label(result.mood), result.index_move_percent]]
	if result.event != null:
		parts.append(String(result.event.id))
	for row: StalkState in state.stalks:
		parts.append("%s=%d" % [row.id, row.price])
	for company: CompanyState in state.market.companies:
		parts.append("%s:%s:%.6f" % [company.id, EarningsRegime.name_of(company.regime), company.revenue])
	return " ".join(parts)


# ----------------------------------------------------------------- the board

func test_the_board_is_every_company_then_the_bond_then_the_index() -> void:
	var state: GameState = _new_state()
	assert_eq(state.stalks.size(), _library.companies.size() + 2, "20 rows on the shipped roster")
	for index: int in _library.companies.size():
		assert_eq(state.stalks[index].id, _library.companies[index].id, "companies first, in id order")
	assert_eq(state.stalks[-2].id, EarningsMarket.BOND_ID)
	assert_eq(state.stalks[-1].id, EarningsMarket.INDEX_ID)


func test_every_company_row_opens_at_its_own_price() -> void:
	var state: GameState = _new_state()
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		assert_eq(row.price, company.price, "%s" % company.id)
		assert_eq(company.price, int(company.profile.starting_earnings_per_share * ValuationRules.BASE_MULTIPLE),
			"%s opens at EPS x 12.5" % company.id)


func test_a_company_the_base_game_ships_keeps_its_shared_definition() -> void:
	var state: GameState = _new_state()
	assert_eq(state.stalk_by_id(&"springfield").definition, _library.stalk_by_id(&"springfield"))


func test_a_company_the_base_game_lacks_gets_a_definition_from_its_profile() -> void:
	var state: GameState = _new_state()
	var profile: CompanyProfile = _library.company_by_id(&"landlords")
	var row: StalkState = state.stalk_by_id(&"landlords")
	assert_not_null(row)
	assert_eq(row.definition.display_name, profile.display_name)
	assert_eq(row.definition.ticker, profile.ticker)
	assert_true(row.definition.all_events().is_empty(), "no events of its own")
	assert_false(row.is_price_static())


func test_the_index_opens_at_its_authored_price() -> void:
	var state: GameState = _new_state()
	var definition: StalkDefinition = _library.stalk_by_id(EarningsMarket.INDEX_ID)
	assert_eq(state.stalk_by_id(EarningsMarket.INDEX_ID).price, definition.starting_price)
	assert_eq(state.market.index_level, float(definition.starting_price))


func test_a_base_game_state_has_no_market() -> void:
	assert_null(StalksFixture.make_state(10, 1).market)


# ------------------------------------------------------- the shared back half

func test_the_settlement_computes_net_worth_standings_and_closes_the_year() -> void:
	var state: GameState = StalksFixture.make_state(10, 2)
	state.players[0].cash = 500
	state.players[1].cash = 900
	state.players[0].is_ready = true
	var result: YearResult = YearResult.new()

	YearSettlement.settle(state, result)

	assert_eq(result.net_worths[state.players[0].id], 500)
	assert_eq(result.rankings[0], state.players[1].id, "richest first")
	assert_false(state.players[0].is_ready, "ready flags cleared")
	assert_eq(state.history.back(), result, "the year is appended to the history")
	assert_false(state.is_over)


func test_the_settlement_ends_the_game_after_the_final_year() -> void:
	var state: GameState = StalksFixture.make_state(2, 1)
	state.year = 3
	var result: YearResult = YearResult.new()
	YearSettlement.settle(state, result)
	assert_true(state.is_over)
	assert_true(result.is_final_year)
	assert_eq(result.winners, [state.players[0].id] as Array[StringName])


func test_the_settlement_skips_loans_when_they_are_off() -> void:
	var state: GameState = StalksFixture.make_state(10, 1)
	StalksFixture.give_loan(state.players[0], 1000)
	var result: YearResult = YearResult.new()
	YearSettlement.settle(state, result)
	assert_true(result.loan_changes.is_empty())


func test_the_earnings_pipeline_runs_the_same_loans() -> void:
	var state: GameState = _new_state()
	state.settings.loans_enabled = true
	var loan: LoanState = StalksFixture.give_loan(state.players[0], 1000)
	var result: EarningsYearResult = _quiet_resolver().advance_year(state, StalksFixture.rng(1))
	var change: LoanYearChange = result.loan_change_for(state.players[0].id)
	assert_not_null(change, "the loan was assessed")
	assert_eq(loan.balance, int(1000 * (1.0 + LoanRules.ANNUAL_RATE)), "first year is interest only")


func test_the_earnings_pipeline_ends_the_game_like_the_base_game() -> void:
	var results: Array[EarningsYearResult] = _run(4, 3, _new_state(2))
	assert_false(results[1].is_final_year)
	assert_true(results[2].is_final_year, "a 2-year match settles into year 3 and ends")
	assert_false(results[2].winners.is_empty())


func test_net_worth_is_read_from_the_posted_prices() -> void:
	var state: GameState = _new_state()
	var player: PlayerState = state.players[0]
	player.set_shares(&"springfield", 10)
	var result: EarningsYearResult = _quiet_resolver().advance_year(state, StalksFixture.rng(2))
	assert_eq(result.net_worths[player.id], TradeRules.net_worth(player, state))
	assert_eq(state.stalk_by_id(&"springfield").price, state.market.company_by_id(&"springfield").price)


# ------------------------------------------------------------- determinism

func test_the_same_seed_reproduces_a_whole_match() -> void:
	var records: Array[String] = []
	for attempt: int in 2:
		var state: GameState = _new_state(15)
		var resolver: EarningsYearResolver = _shipped_resolver()
		var rng: RandomNumberGenerator = StalksFixture.rng(31)
		var lines: PackedStringArray = []
		for year: int in 15:
			lines.append(_record(state, resolver.advance_year(state, rng)))
		records.append("\n".join(lines))
	assert_eq(records[0], records[1])


func test_a_different_seed_plays_a_different_match() -> void:
	var a: GameState = _new_state()
	var b: GameState = _new_state()
	_run(1, 5, a)
	_run(2, 5, b)
	assert_ne(_record(a, a.history.back()), _record(b, b.history.back()))


# ------------------------------------------------------------ the ledger, P1

func test_every_ledger_balances_and_is_the_yearly_change() -> void:
	var checked: int = 0
	for seed_value: int in 20:
		var state: GameState = _new_state(15)
		for result: EarningsYearResult in _run(seed_value, 15, state):
			for company_id: StringName in result.ledgers:
				var ledger: PriceLedger = result.ledgers[company_id]
				var change: StalkYearChange = result.change_for(company_id)
				assert_true(ledger.is_balanced(), "seed %d year %d %s: %s" % [seed_value, result.year, company_id, ledger])
				assert_eq(change.price_before, ledger.price_before)
				assert_eq(change.total_delta(), ledger.price_after - ledger.price_before,
					"base + event is the whole pre-split move")
				assert_eq(change.event_delta, ledger.this_years_event)
				checked += 1
	assert_gt(checked, 3000, "the check reached every company in every year")


func test_yearly_change_includes_the_event() -> void:
	# §14 q7: in this mode the board's Yearly Change is the whole move, and the
	# ledger is what breaks it down. The base game's excludes the event.
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"up", &"springfield", MarketMood.Value.BULL, 20),
	]
	var state: GameState = _new_state()
	var before: int = state.stalk_by_id(&"springfield").price
	var result: EarningsYearResult = _resolver_with(events).advance_year(state, StalksFixture.rng(5))
	var ledger: PriceLedger = result.ledger_for(&"springfield")
	var row: StalkState = state.stalk_by_id(&"springfield")

	assert_eq(result.event.id, &"up")
	assert_between(ledger.this_years_event, 19, 21, "the event's line, within one coin of truncation")
	assert_eq(row.last_yearly_change, ledger.price_after - before, "the event is inside Yearly Change")
	assert_eq(row.last_yearly_change, ledger.total())


func test_a_company_with_no_event_has_no_event_line() -> void:
	var result: EarningsYearResult = _quiet_resolver().advance_year(_new_state(), StalksFixture.rng(5))
	for company_id: StringName in result.ledgers:
		assert_eq(result.ledgers[company_id].this_years_event, 0)
		assert_eq(result.change_for(company_id).event_delta, 0)


# ------------------------------------------------- the derived mood (§3.1)

func test_the_mood_is_bull_exactly_when_the_index_rose() -> void:
	var bulls: int = 0
	var bears: int = 0
	for seed_value: int in 30:
		for result: EarningsYearResult in _run(seed_value, 10):
			assert_eq(result.mood, EarningsYearResolver.mood_for(result.index_move_percent))
			if result.index_move_percent > 0.0:
				assert_eq(result.mood, MarketMood.Value.BULL)
				bulls += 1
			else:
				assert_eq(result.mood, MarketMood.Value.BEAR)
				bears += 1
	assert_gt(bulls, 0, "both moods occur")
	assert_gt(bears, 0, "both moods occur")


func test_a_flat_year_is_a_bear_year() -> void:
	assert_eq(EarningsYearResolver.mood_for(0.0), MarketMood.Value.BEAR)
	assert_eq(EarningsYearResolver.mood_for(0.001), MarketMood.Value.BULL)


func test_sentiment_is_last_years_index_move_clamped() -> void:
	var state: GameState = _new_state(20)
	var results: Array[EarningsYearResult] = _run(11, 20, state)
	assert_eq(results[0].sentiment_used, 0.0, "nothing to lean on in year 1")
	for index: int in range(1, results.size()):
		var expected: float = clampf(results[index - 1].index_move_percent, -20.0, 20.0)
		assert_almost_eq(results[index].sentiment_used, expected, 0.000001, "year %d" % results[index].year)
	assert_almost_eq(state.market.sentiment, clampf(results[-1].index_move_percent, -20.0, 20.0), 0.000001)


func test_prices_are_valued_on_last_years_sentiment_not_this_years() -> void:
	# The no-circularity check (§12.1): every multiple this year was built from
	# the sentiment carried in, never from this year's own index move.
	var state: GameState = _new_state(12)
	var resolver: EarningsYearResolver = _shipped_resolver()
	var rng: RandomNumberGenerator = StalksFixture.rng(12)
	for year: int in 12:
		var carried_in: float = state.market.sentiment
		var result: EarningsYearResult = resolver.advance_year(state, rng)
		for company_id: StringName in result.ledgers:
			var company: CompanyState = state.market.company_by_id(company_id)
			assert_eq(company.sentiment, carried_in, "year %d %s" % [result.year, company_id])


func test_the_mood_label_moves_no_price_except_through_the_event_bag() -> void:
	# Flip last year's label and keep its number. With no events to draw, the
	# label has nothing left to influence, so every price must be identical.
	var a: GameState = _new_state()
	var b: GameState = _new_state()
	var resolver_a: EarningsYearResolver = _quiet_resolver()
	var resolver_b: EarningsYearResolver = _quiet_resolver()
	var rng_a: RandomNumberGenerator = StalksFixture.rng(21)
	var rng_b: RandomNumberGenerator = StalksFixture.rng(21)
	for year: int in 6:
		resolver_a.advance_year(a, rng_a)
		resolver_b.advance_year(b, rng_b)
		if b.market.last_mood == MarketMood.Value.BULL:
			b.market.last_mood = MarketMood.Value.BEAR
		else:
			b.market.last_mood = MarketMood.Value.BULL
	for index: int in a.stalks.size():
		assert_eq(a.stalks[index].price, b.stalks[index].price, "%s" % a.stalks[index].id)


func test_the_derived_bull_rate_stays_in_its_band() -> void:
	# The guard on §3.1's feedback loop: a future edit to either sentiment gain
	# can quietly inflate the whole market. The design measured 55.4% with the
	# probe's events; S3 measures it on the shipped ones (decisions.md D161).
	var bulls: int = 0
	var years: int = 0
	for seed_value: int in 200:
		for result: EarningsYearResult in _run(seed_value, 10):
			years += 1
			if result.mood == MarketMood.Value.BULL:
				bulls += 1
	var rate: float = float(bulls) / float(years)
	assert_between(rate, 0.45, 0.65, "bull rate %.3f" % rate)


# ------------------------------------------------------------- the event bag

func test_year_one_draws_from_the_bull_bag() -> void:
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"good", &"springfield", MarketMood.Value.BULL, 10),
		StalksFixture.make_event(&"bad", &"stryker", MarketMood.Value.BEAR, -10),
	]
	var result: EarningsYearResult = _resolver_with(events).advance_year(_new_state(), StalksFixture.rng(3))
	assert_eq(result.event_bag, MarketMood.Value.BULL)
	assert_eq(result.event.id, &"good")


func test_the_event_comes_from_last_years_mood() -> void:
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"good", &"springfield", MarketMood.Value.BULL, 10),
		StalksFixture.make_event(&"bad", &"stryker", MarketMood.Value.BEAR, -10),
	]
	var state: GameState = _new_state()
	state.market.last_mood = MarketMood.Value.BEAR
	var result: EarningsYearResult = _resolver_with(events).advance_year(state, StalksFixture.rng(3))
	assert_eq(result.event_bag, MarketMood.Value.BEAR)
	assert_eq(result.event.id, &"bad")


func test_over_a_match_every_event_is_from_the_previous_years_mood() -> void:
	var results: Array[EarningsYearResult] = _run(8, 20)
	var previous: MarketMood.Value = MarketMood.Value.BULL
	for result: EarningsYearResult in results:
		assert_eq(result.event_bag, previous, "year %d" % result.year)
		if result.event != null:
			assert_eq(result.event.mood, previous, "year %d: %s" % [result.year, result.event.id])
		previous = result.mood


func test_the_event_is_drawn_before_prices_and_is_in_them() -> void:
	# Same seed, same year, with and without the event: the only difference in
	# the target's price is the event's own line.
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"crash", &"pgenron", MarketMood.Value.BULL, -25),
	]
	var with_event: GameState = _new_state()
	var without: GameState = _new_state()
	# An empty pool draws nothing from the RNG; one event costs no draw to pick
	# either once its bag of one is shuffled, so both runs see the same market.
	var hit: EarningsYearResult = _resolver_with(events).advance_year(with_event, StalksFixture.rng(9))
	_quiet_resolver().advance_year(without, StalksFixture.rng(9))
	var moved: int = with_event.stalk_by_id(&"pgenron").price - without.stalk_by_id(&"pgenron").price
	assert_eq(moved, hit.ledger_for(&"pgenron").this_years_event)
	assert_between(moved, -26, -24)


func test_an_event_aimed_at_a_bankrupt_company_is_skipped() -> void:
	# §4: an event carrying only a company delta is skipped at a dead target
	# and left in the bag (decisions.md D24), as in the base game.
	var events: Array[SpecialEventDefinition] = [
		StalksFixture.make_event(&"late", &"stryker", MarketMood.Value.BULL, 10),
	]
	var state: GameState = _new_state()
	state.stalk_by_id(&"stryker").is_bankrupt = true
	var result: EarningsYearResult = _resolver_with(events).advance_year(state, StalksFixture.rng(3))
	assert_null(result.event)


func test_the_index_carries_no_events_in_this_mode() -> void:
	var pool: EventPool = EarningsMarket.build_event_pool(_library)
	var index_events: int = _library.stalk_by_id(EarningsMarket.INDEX_ID).all_events().size()
	assert_gt(index_events, 0, "the shipped index has events, so leaving them out is a real choice")
	assert_eq(
		pool.pool_size(MarketMood.Value.BULL) + pool.pool_size(MarketMood.Value.BEAR),
		_library.all_events().size() - index_events,
	)
	for result: EarningsYearResult in _run(14, 30):
		if result.event != null:
			assert_ne(result.event.target_stalk_id, EarningsMarket.INDEX_ID)


# ------------------------------------------------------------------ the index

func test_the_index_moves_by_the_mean_pre_split_move() -> void:
	var saw_a_split: bool = false
	for seed_value: int in 10:
		var state: GameState = _new_state(20)
		var resolver: EarningsYearResolver = _shipped_resolver()
		var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
		for year: int in 20:
			var level_before: float = state.market.index_level
			var result: EarningsYearResult = resolver.advance_year(state, rng)
			var total: float = 0.0
			for company_id: StringName in result.ledgers:
				var ledger: PriceLedger = result.ledgers[company_id]
				if result.change_for(company_id).went_bankrupt:
					total -= 100.0
				else:
					total += float(ledger.price_after - ledger.price_before) * 100.0 / float(ledger.price_before)
				if result.change_for(company_id).did_split:
					saw_a_split = true
			var expected: float = total / float(result.ledgers.size())
			assert_almost_eq(result.index_move_percent, expected, 0.000001)
			var index_change: StalkYearChange = result.change_for(EarningsMarket.INDEX_ID)
			var posted: int = int(level_before * (100.0 + expected) / 100.0)
			if not index_change.did_split:
				assert_eq(index_change.price_after, posted, "seed %d year %d" % [seed_value, result.year])
	assert_true(saw_a_split, "a constituent split somewhere, and the index was measured before it")


func test_a_bankrupt_constituent_counts_minus_100_once_and_then_drops_out() -> void:
	var state: GameState = _new_state()
	_doom(state, &"meowly")
	var resolver: EarningsYearResolver = _quiet_resolver()
	var rng: RandomNumberGenerator = StalksFixture.rng(6)

	var first: EarningsYearResult = resolver.advance_year(state, rng)
	assert_true(first.change_for(&"meowly").went_bankrupt)
	var others: float = 0.0
	for company_id: StringName in first.ledgers:
		if company_id == &"meowly":
			continue
		var ledger: PriceLedger = first.ledgers[company_id]
		others += float(ledger.price_after - ledger.price_before) * 100.0 / float(ledger.price_before)
	assert_almost_eq(first.index_move_percent, (others - 100.0) / float(first.ledgers.size()), 0.000001)

	var second: EarningsYearResult = resolver.advance_year(state, rng)
	assert_false(second.ledgers.has(&"meowly"), "a dead company is not a constituent any more")
	assert_eq(second.ledgers.size(), first.ledgers.size() - 1)


func test_the_index_survives_while_one_constituent_lives() -> void:
	var state: GameState = _new_state()
	for company: CompanyState in state.market.companies:
		if company.id != &"springfield":
			_doom(state, company.id)
	_quiet_resolver().advance_year(state, StalksFixture.rng(4))
	assert_false(state.stalk_by_id(&"springfield").is_bankrupt)
	assert_false(state.stalk_by_id(EarningsMarket.INDEX_ID).is_bankrupt)
	assert_gt(state.stalk_by_id(EarningsMarket.INDEX_ID).price, 0)


func test_the_index_fails_only_when_every_constituent_does() -> void:
	var state: GameState = _new_state()
	state.players[0].set_shares(EarningsMarket.INDEX_ID, 50)
	for company: CompanyState in state.market.companies:
		_doom(state, company.id)
	var result: EarningsYearResult = _quiet_resolver().advance_year(state, StalksFixture.rng(4))
	assert_almost_eq(result.index_move_percent, -100.0, 0.000001)
	assert_true(state.stalk_by_id(EarningsMarket.INDEX_ID).is_bankrupt)
	assert_true(result.change_for(EarningsMarket.INDEX_ID).went_bankrupt)
	assert_eq(state.players[0].shares_of(EarningsMarket.INDEX_ID), 0, "holders lose everything")


func test_the_index_pays_the_average_of_its_constituents_dividends() -> void:
	for result: EarningsYearResult in _run(16, 10):
		var total: int = 0
		var count: int = 0
		for company: CompanyProfile in _library.companies:
			if result.change_for(company.id).price_after > 0:
				total += result.dividend_per_share[company.id]
				count += 1
		@warning_ignore("integer_division")
		var expected: int = total / count
		assert_eq(result.dividend_per_share[EarningsMarket.INDEX_ID], expected, "year %d" % result.year)


func test_index_move_counts_only_companies_alive_at_the_start_of_the_year() -> void:
	var a: CompanyState = CompanyState.new(_library.company_by_id(&"springfield"))
	var b: CompanyState = CompanyState.new(_library.company_by_id(&"stryker"))
	var before: Dictionary[StringName, CompanyState] = {a.id: a.copy(), b.id: b.copy()}
	a.price = int(before[a.id].price * 1.1)
	b.price = -3
	var expected: float = (float(a.price - before[a.id].price) * 100.0 / float(before[a.id].price) - 100.0) / 2.0
	assert_almost_eq(EarningsYearResolver.index_move_percent(before, [a, b] as Array[CompanyState]), expected, 0.000001)
	assert_eq(EarningsYearResolver.index_move_percent({}, [] as Array[CompanyState]), 0.0, "no constituents, no move")


# ----------------------------------------------------- the bond as yardstick

func test_the_bond_never_moves_and_always_pays_its_coupon() -> void:
	var state: GameState = _new_state(30)
	state.players[0].set_shares(EarningsMarket.BOND_ID, 10)
	for result: EarningsYearResult in _run(17, 30, state):
		var change: StalkYearChange = result.change_for(EarningsMarket.BOND_ID)
		assert_eq(change.price_after, 100)
		assert_false(change.did_split)
		assert_false(change.went_bankrupt)
		assert_eq(result.dividend_per_share[EarningsMarket.BOND_ID], 3, "in a %s year" % MarketMood.label(result.mood))
	assert_eq(state.players[0].shares_of(EarningsMarket.BOND_ID), 10)


func test_the_bond_is_the_risk_free_rate_the_base_multiple_is_measured_against() -> void:
	var bond: StalkDefinition = _library.stalk_by_id(EarningsMarket.BOND_ID)
	assert_eq(EarningsMarket.bond_coupon(bond), bond.bear_dividend, "the coupon is the same in both moods")
	assert_almost_eq(EarningsMarket.risk_free_yield_percent(bond), 3.0, 0.000001)
	assert_almost_eq(EarningsMarket.earnings_yield_percent(ValuationRules.BASE_MULTIPLE), 8.0, 0.000001)
	assert_almost_eq(EarningsMarket.equity_premium_percent(bond), 5.0, 0.000001,
		"12.5x pays five points over the bond (§3.4)")


# ---------------------------------------------------- bankruptcy, splits, pay

func test_bankruptcy_is_one_pass_and_wipes_out_holders() -> void:
	var state: GameState = _new_state()
	state.players[0].set_shares(&"monorail", 40)
	_doom(state, &"monorail")
	var result: EarningsYearResult = _quiet_resolver().advance_year(state, StalksFixture.rng(7))
	var row: StalkState = state.stalk_by_id(&"monorail")
	assert_true(row.is_bankrupt)
	assert_eq(row.price, 0)
	assert_eq(result.change_for(&"monorail").price_after, 0)
	assert_true(result.bankrupt_ids().has(&"monorail"))
	assert_eq(state.players[0].shares_of(&"monorail"), 0)
	assert_eq(result.dividend_per_share[&"monorail"], 0)


func test_a_bankrupt_company_is_never_advanced_again() -> void:
	var state: GameState = _new_state()
	_doom(state, &"monorail")
	var resolver: EarningsYearResolver = _quiet_resolver()
	var rng: RandomNumberGenerator = StalksFixture.rng(7)
	resolver.advance_year(state, rng)
	var frozen: float = state.market.company_by_id(&"monorail").revenue
	resolver.advance_year(state, rng)
	assert_eq(state.market.company_by_id(&"monorail").revenue, frozen)
	assert_eq(state.stalk_by_id(&"monorail").price, 0)


func test_a_split_doubles_holders_and_is_value_neutral() -> void:
	var state: GameState = _new_state()
	var company: CompanyState = state.market.company_by_id(&"farmsplus")
	company.profit = float(company.shares_outstanding) * 32.0
	company.revenue = company.profit * 100.0 / company.margin_percent
	var shares_before: int = company.shares_outstanding
	state.players[0].set_shares(&"farmsplus", 10)

	var result: EarningsYearResult = _quiet_resolver().advance_year(state, StalksFixture.rng(8))
	var ledger: PriceLedger = result.ledger_for(&"farmsplus")
	assert_gt(ledger.price_after, PriceIdentity.SPLIT_ABOVE, "it priced above 300 before splitting")
	assert_true(result.change_for(&"farmsplus").did_split)
	assert_eq(state.players[0].shares_of(&"farmsplus"), 20)
	assert_eq(company.shares_outstanding, shares_before * 2)
	assert_eq(state.stalk_by_id(&"farmsplus").price, PriceIdentity.split_price(ledger.price_after))
	assert_eq(state.stalk_by_id(&"farmsplus").price, company.price)
	var worth_if_unsplit: int = 10 * ledger.price_after
	assert_between(20 * company.price - worth_if_unsplit, 0, 20, "a split rounds up, so worth moves at most a coin a share")


func test_dividends_are_paid_on_post_split_shares_from_earnings() -> void:
	var state: GameState = _new_state()
	var company: CompanyState = state.market.company_by_id(&"teamsters")
	company.profit = float(company.shares_outstanding) * 30.0
	company.revenue = company.profit * 100.0 / company.margin_percent
	state.players[0].set_shares(&"teamsters", 10)
	var cash_before: int = state.players[0].cash

	var result: EarningsYearResult = _quiet_resolver().advance_year(state, StalksFixture.rng(10))
	assert_true(result.change_for(&"teamsters").did_split)
	assert_eq(result.dividend_per_share[&"teamsters"], company.dividend_per_share())
	assert_gt(company.dividend_per_share(), 0, "a big payer pays")
	assert_eq(result.dividends[state.players[0].id], 20 * company.dividend_per_share(), "twenty shares, not ten")
	assert_eq(state.players[0].cash, cash_before + result.dividends[state.players[0].id])


func test_a_company_with_no_payout_policy_never_pays() -> void:
	for result: EarningsYearResult in _run(18, 15):
		assert_eq(result.dividend_per_share[&"stryker"], 0)
		assert_eq(result.dividend_per_share[&"meowly"], 0)


# ---------------------------------------------------------------- flow input

func test_net_shares_traded_feed_flow_and_are_then_cleared() -> void:
	var state: GameState = _new_state()
	state.market.net_shares_traded = {&"pillows": 400}
	_quiet_resolver().advance_year(state, StalksFixture.rng(13))
	var company: CompanyState = state.market.company_by_id(&"pillows")
	assert_gt(company.flow, 0.0, "net buying pushes the price up")
	assert_lte(company.flow, PriceIdentity.flow_limit(company.fair_value) + 0.000001, "and is clamped")
	assert_eq(state.market.company_by_id(&"chichen").flow, 0.0, "nobody traded it")
	assert_true(state.market.net_shares_traded.is_empty(), "last year's trading is consumed once")


# --------------------------------------------------- the rules of the seam

func test_no_shared_pipeline_file_asks_which_mode_it_is() -> void:
	# §13.3: the moment a shared file says `if mode ==`, the modes are entangled
	# and the seam needs redesigning, not another branch.
	for path: String in [
		"res://src/sim/year_resolver.gd",
		"res://src/sim/year_settlement.gd",
		"res://src/sim/trade_rules.gd",
		"res://src/sim/loan_rules.gd",
		"res://src/sim/event_pool.gd",
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s was read" % path)
		assert_false(text.contains("settings.mode"), "%s asks which mode it is" % path)
		assert_false(text.contains("market != null"), "%s branches on the StalkleHeads market" % path)


func test_the_price_path_uses_no_transcendental_function() -> void:
	# §3.7: only + - * / and explicit rounding in the price path, because the
	# standard library's pow/exp/log are not guaranteed identical across
	# platforms and the price must be.
	for path: String in [
		"res://src/sim/earnings_year_resolver.gd",
		"res://src/sim/earnings_market.gd",
		"res://src/sim/company_state.gd",
		"res://src/sim/industry_state.gd",
		"res://src/sim/valuation_rules.gd",
		"res://src/sim/price_identity.gd",
		"res://src/sim/dividend_rules.gd",
		"res://src/sim/regime_rules.gd",
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s was read" % path)
		for name: String in ["pow(", "exp(", "log(", "sqrt(", "sin(", "cos("]:
			assert_false(text.contains(name), "%s calls %s" % [path, name])
