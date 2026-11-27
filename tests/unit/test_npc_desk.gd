extends GutTest
## The StalkleHeads NPC desk (phase S4): the trader content, `NpcDesk` and its
## eight strategies, the determinism rules of §5.4, the desk's trading as next
## year's flow, and short interest with the squeeze it makes possible (§5.3).
## See docs/stalkleheads-design.md §5 and decisions.md D162-D167.
##
## Every test that draws from an RNG seeds it.


var _library: ContentLibrary


func before_all() -> void:
	_library = ContentLibrary.load_from()
	_library.load_fundamentals()


# --------------------------------------------------------------------- helpers

func _new_state(max_years: int = 10) -> GameState:
	var state: GameState = EarningsMarket.new_game_state(_library, StalksFixture.make_settings(max_years))
	state.players.append(PlayerState.new(&"p0", "P0", 10000))
	return state


## Sets a company's posted price and its profit, keeping row and company agreed.
func _set_company(state: GameState, company_id: StringName, price: int, profit: float) -> CompanyState:
	var company: CompanyState = state.market.company_by_id(company_id)
	company.price = price
	company.profit = profit
	state.stalk_by_id(company_id).price = price
	return company


func _shipped_resolver() -> EarningsYearResolver:
	return EarningsYearResolver.new(_library.short_squeeze)


func _trader(strategy: NpcStrategy.Value, trader_id: StringName = &"t", cash: int = 8000) -> NpcTraderDefinition:
	var definition: NpcTraderDefinition = NpcTraderDefinition.new()
	definition.id = trader_id
	definition.display_name = "NPC NAME: test"
	definition.strategy = strategy
	definition.starting_cash = cash
	definition.conviction = 45
	return definition


func _desk_of(definitions: Array[NpcTraderDefinition]) -> NpcDesk:
	return NpcDesk.from_definitions(definitions)


## A desk whose SHORT trader is short `shares` of `company_id`.
func _shorted(state: GameState, company_id: StringName, shares: int) -> void:
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.SHORT, &"short_x")])
	desk.traders[0].set_short(company_id, shares)
	state.market.desk = desk


# ----------------------------------------------------------------- the content

func test_the_desk_is_twenty_four_traders_three_per_strategy() -> void:
	assert_true(_library.is_valid(), "%s" % [_library.errors])
	assert_eq(_library.traders.size(), 24, "§14 q11")
	for strategy: NpcStrategy.Value in NpcStrategy.ALL:
		var count: int = 0
		for trader: NpcTraderDefinition in _library.traders:
			if trader.strategy == strategy:
				count += 1
		assert_eq(count, 3, "three %s traders" % NpcStrategy.name_of(strategy))


func test_trader_content_is_sorted_by_id() -> void:
	for index: int in range(1, _library.traders.size()):
		assert_lt(String(_library.traders[index - 1].id), String(_library.traders[index].id))


func test_names_and_chatter_are_placeholders_that_say_which_slot_they_fill() -> void:
	# The owner writes these (§14). Until then each says what it is, in the
	# style of the news placeholders (§8.3), and invents nothing.
	for trader: NpcTraderDefinition in _library.traders:
		assert_true(trader.display_name.begins_with("NPC NAME: "), trader.display_name)
		for situation: NpcTraderDefinition.Situation in NpcTraderDefinition.Situation.values():
			assert_true(trader.chatter_for(situation).begins_with("NPC CHATTER: "), "%s" % trader.id)


func test_a_duplicate_trader_id_is_refused() -> void:
	var library: ContentLibrary = ContentLibrary.load_from()
	library.load_fundamentals()
	library.traders.append(_library.traders[0])
	library.validate()
	assert_false(library.is_valid())
	assert_string_contains(" ".join(library.errors), "Duplicate trader id")


func test_conviction_and_cash_are_range_checked() -> void:
	var library: ContentLibrary = ContentLibrary.load_from()
	library.load_fundamentals()
	var broken: NpcTraderDefinition = _trader(NpcStrategy.Value.VALUE, &"zz_broken", 0)
	broken.conviction = 101
	library.traders.append(broken)
	library.validate()
	var joined: String = " ".join(library.errors)
	assert_string_contains(joined, "conviction 101")
	assert_string_contains(joined, "starts with 0 cash")


func test_the_squeeze_template_is_content_that_names_no_target() -> void:
	# Its size comes from the short interest, not the file (D213).
	assert_not_null(_library.short_squeeze)
	assert_eq(_library.short_squeeze.target_stalk_id, &"", "the squeeze names its own target")
	assert_true(_library.short_squeeze.flavour_text.begins_with("EVENT: "), "a placeholder")


func test_the_base_game_library_loads_no_traders() -> void:
	assert_eq(ContentLibrary.load_from().traders.size(), 0)


# ------------------------------------------------------------- determinism §5.4

func test_traders_act_in_sorted_id_order_whatever_the_load_order() -> void:
	var definitions: Array[NpcTraderDefinition] = _library.traders.duplicate()
	definitions.reverse()
	var desk: NpcDesk = _desk_of(definitions)
	var year: NpcDeskYear = desk.act(_new_state(), StalksFixture.rng(1))
	var sorted_ids: Array[StringName] = []
	for trader: NpcTraderDefinition in _library.traders:
		sorted_ids.append(trader.id)
	assert_eq(year.trader_ids, sorted_ids)


func test_every_trader_draws_twice_a_year_whatever_it_decides() -> void:
	# One market where everyone can trade, one where every company is bankrupt
	# and the index too, so most traders find nothing to do. The stream must be
	# left in the same place.
	var busy: GameState = _new_state()
	var dead: GameState = _new_state()
	for row: StalkState in dead.stalks:
		if row.id != EarningsMarket.BOND_ID:
			row.is_bankrupt = true
			row.price = 0
	var busy_rng: RandomNumberGenerator = StalksFixture.rng(77)
	var dead_rng: RandomNumberGenerator = StalksFixture.rng(77)
	busy.market.desk.act(busy, busy_rng)
	var idle: NpcDeskYear = dead.market.desk.act(dead, dead_rng)
	assert_eq(busy_rng.state, dead_rng.state, "same draws in both")

	var counted: RandomNumberGenerator = StalksFixture.rng(77)
	for index: int in _library.traders.size():
		counted.randi_range(NpcDesk.APPETITE_MIN, NpcDesk.APPETITE_MAX)
		counted.randi_range(0, NpcDesk.PICK_RANGE - 1)
	assert_eq(counted.state, busy_rng.state, "exactly DRAWS_PER_TRADER each")
	assert_eq(NpcDesk.DRAWS_PER_TRADER, 2)
	assert_eq(idle.actions[&"value_1"], NpcTraderDefinition.Situation.HELD, "drew, then did nothing")


func test_appetite_stays_in_its_band() -> void:
	var state: GameState = _new_state()
	var rng: RandomNumberGenerator = StalksFixture.rng(5)
	for year: int in 20:
		var desk_year: NpcDeskYear = state.market.desk.act(state, rng)
		for trader_id: StringName in desk_year.trader_ids:
			assert_between(desk_year.appetites[trader_id], NpcDesk.APPETITE_MIN, NpcDesk.APPETITE_MAX)


func test_the_same_seed_reproduces_the_desk_too() -> void:
	# The StalkleHeads sibling of test_the_same_seed_reproduces_a_whole_match
	# that §5.4 asks for: NPC positions are identical, not only prices.
	var first: GameState = _new_state(12)
	var second: GameState = _new_state(12)
	var first_rng: RandomNumberGenerator = StalksFixture.rng(2024)
	var second_rng: RandomNumberGenerator = StalksFixture.rng(2024)
	var resolver: EarningsYearResolver = _shipped_resolver()
	var other: EarningsYearResolver = _shipped_resolver()
	for year: int in 12:
		resolver.advance_year(first, first_rng)
		other.advance_year(second, second_rng)
	for index: int in first.market.desk.traders.size():
		var a: NpcTraderState = first.market.desk.traders[index]
		var b: NpcTraderState = second.market.desk.traders[index]
		assert_eq(a.cash, b.cash, "%s cash" % a.id)
		assert_eq(a.holdings, b.holdings, "%s holdings" % a.id)
		assert_eq(a.shorts, b.shorts, "%s shorts" % a.id)
	for row: StalkState in first.stalks:
		assert_eq(row.price, second.stalk_by_id(row.id).price)


func test_traders_are_not_players() -> void:
	var state: GameState = _new_state()
	var resolver: EarningsYearResolver = _shipped_resolver()
	var result: EarningsYearResult = resolver.advance_year(state, StalksFixture.rng(3))
	assert_eq(state.players.size(), 1, "the desk adds nobody to the table")
	assert_eq(result.rankings, [&"p0"] as Array[StringName], "or to the standings")


# ------------------------------------------------------------- the strategies

func test_value_buys_the_lowest_p_e() -> void:
	var state: GameState = _new_state()
	_set_company(state, &"meowly", 50, 10000.0)   # eps 10, P/E 5
	_set_company(state, &"mafia", 50, 8000.0)     # eps 8, P/E 6.25
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.VALUE, state, 0), &"meowly")


func test_value_ignores_a_company_losing_money() -> void:
	var state: GameState = _new_state()
	_set_company(state, &"meowly", 1, -5000.0)
	assert_ne(NpcDesk.target_for(NpcStrategy.Value.VALUE, state, 0), &"meowly")


func test_momentum_and_contrarian_read_yearly_change() -> void:
	var state: GameState = _new_state()
	state.stalk_by_id(&"pillows").last_yearly_change = 40
	state.stalk_by_id(&"stryker").last_yearly_change = -40
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.MOMENTUM, state, 0), &"pillows")
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.CONTRARIAN, state, 0), &"stryker")


func test_income_buys_the_highest_yield() -> void:
	var state: GameState = _new_state()
	var best: StringName = &""
	var best_yield: float = -1.0
	for company: CompanyState in state.market.companies:
		var paid: float = float(company.dividend_per_share()) / float(company.price)
		if paid > best_yield:
			best_yield = paid
			best = company.id
	assert_gt(best_yield, 0.0)
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.INCOME, state, 0), best)


func test_the_indexer_buys_the_index_and_nothing_else() -> void:
	var state: GameState = _new_state()
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.INDEXER, state, 0), EarningsMarket.INDEX_ID)
	state.stalk_by_id(EarningsMarket.INDEX_ID).is_bankrupt = true
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.INDEXER, state, 0), &"", "never a substitute")


func test_panic_flees_to_the_bond_in_a_bear_year_and_buys_back_in_a_bull_one() -> void:
	var state: GameState = _new_state()
	state.market.last_mood = MarketMood.Value.BEAR
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.PANIC, state, 0), EarningsMarket.BOND_ID)
	state.market.last_mood = MarketMood.Value.BULL
	var companies: Array[CompanyState] = state.market.companies
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.PANIC, state, 0), companies[0].id)
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.PANIC, state, 3), companies[3].id, "the pick draw chooses")
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.PANIC, state, companies.size() + 1), companies[1].id)


func test_growth_reads_profit_growth() -> void:
	var state: GameState = _new_state()
	for company: CompanyState in state.market.companies:
		company.profit_before_season = 1000.0
		company.profit = 1000.0
	state.market.company_by_id(&"videochrome").profit = 1500.0
	state.market.company_by_id(&"monorail").profit = 600.0
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.GROWTH, state, 0), &"videochrome")


func test_short_bets_against_the_highest_p_e() -> void:
	# decisions.md D169: the most expensive company, not the weakest.
	var state: GameState = _new_state()
	_set_company(state, &"meowly", 100, 2000.0)   # eps 2, P/E 50
	_set_company(state, &"mafia", 50, 2000.0)     # eps 2, P/E 25
	assert_eq(NpcDesk.target_for(NpcStrategy.Value.SHORT, state, 0), &"meowly")


func test_short_ignores_a_company_losing_money() -> void:
	# A loss has no P/E, however high the price.
	var state: GameState = _new_state()
	_set_company(state, &"meowly", 1000, -5000.0)
	assert_ne(NpcDesk.target_for(NpcStrategy.Value.SHORT, state, 0), &"meowly")


func test_growth_needs_a_positive_base() -> void:
	var company: CompanyState = _new_state().market.company_by_id(&"monorail")
	company.profit_before_season = -10.0
	assert_true(is_nan(company.profit_growth_percent()))


func test_a_bankrupt_company_is_never_a_target() -> void:
	var state: GameState = _new_state()
	state.stalk_by_id(&"pillows").last_yearly_change = 400
	state.stalk_by_id(&"pillows").is_bankrupt = true
	assert_ne(NpcDesk.target_for(NpcStrategy.Value.MOMENTUM, state, 0), &"pillows")


# ------------------------------------------------------------------ trading

func test_a_long_trader_sells_the_rest_and_buys_its_target() -> void:
	var state: GameState = _new_state()
	state.stalk_by_id(&"pillows").last_yearly_change = 50
	_set_company(state, &"pillows", 100, state.market.company_by_id(&"pillows").profit)
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.MOMENTUM)])
	var trader: NpcTraderState = desk.traders[0]
	trader.set_shares(&"mafia", 10)
	var mafia_price: int = state.stalk_by_id(&"mafia").price
	var rng: RandomNumberGenerator = StalksFixture.rng(9)
	var year: NpcDeskYear = desk.act(state, rng)

	var appetite: int = year.appetites[&"t"]
	var cash_after_sale: int = 8000 + 10 * mafia_price
	@warning_ignore("integer_division")
	var bought: int = cash_after_sale * 45 * appetite / 10000 / 100
	assert_eq(trader.shares_of(&"mafia"), 0, "sold what was not the target")
	assert_eq(trader.shares_of(&"pillows"), bought)
	assert_eq(trader.cash, cash_after_sale - bought * 100)
	assert_eq(year.net_shares[&"mafia"], -10)
	assert_eq(year.net_shares[&"pillows"], bought)
	assert_eq(year.actions[&"t"], NpcTraderDefinition.Situation.BOUGHT)


func test_a_short_trader_sells_short_without_changing_its_worth() -> void:
	var state: GameState = _new_state()
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.SHORT)])
	var trader: NpcTraderState = desk.traders[0]
	var year: NpcDeskYear = desk.act(state, StalksFixture.rng(4))
	var target: StringName = year.targets[&"t"]
	assert_ne(target, &"")
	var short: int = trader.short_of(target)
	assert_gt(short, 0)
	assert_eq(trader.cash, 8000 + short * state.stalk_by_id(target).price, "the sale's proceeds")
	assert_eq(trader.worth(state), 8000, "worth is unchanged by opening a short")
	assert_eq(year.net_shares[target], -short, "a short sale is selling")
	assert_eq(desk.short_interest(target), short, "the position is the short interest")
	assert_eq(year.actions[&"t"], NpcTraderDefinition.Situation.SHORTED)


func test_a_short_trader_covers_when_its_target_moves() -> void:
	var state: GameState = _new_state()
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.SHORT)])
	var trader: NpcTraderState = desk.traders[0]
	var target: StringName = NpcDesk.target_for(NpcStrategy.Value.SHORT, state, 0)
	var elsewhere: StringName = &"chichen" if target != &"chichen" else &"mafia"
	trader.set_short(elsewhere, 30)
	var year: NpcDeskYear = desk.act(state, StalksFixture.rng(4))
	assert_eq(trader.short_of(elsewhere), 0, "bought back")
	assert_eq(year.net_shares[elsewhere], 30, "covering is buying")
	assert_gt(trader.short_of(target), 0)


func test_short_interest_sums_the_desk() -> void:
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.SHORT, &"a"), _trader(NpcStrategy.Value.SHORT, &"b")])
	desk.traders[0].set_short(&"stryker", 40)
	desk.traders[1].set_short(&"stryker", 25)
	assert_eq(desk.short_interest(&"stryker"), 65)
	assert_eq(desk.short_interest(&"mafia"), 0)


func test_a_bankruptcy_wipes_out_holders_and_closes_shorts_in_the_shorts_favour() -> void:
	var state: GameState = _new_state()
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.VALUE, &"long"), _trader(NpcStrategy.Value.SHORT, &"short")])
	desk.traders[0].set_shares(&"stryker", 20)
	desk.traders[1].set_short(&"stryker", 20)
	desk.traders[1].cash += 20 * state.stalk_by_id(&"stryker").price
	desk.wipe_out(&"stryker")
	assert_eq(desk.traders[0].shares_of(&"stryker"), 0)
	assert_eq(desk.traders[1].short_of(&"stryker"), 0)
	assert_gt(desk.traders[1].worth(state), 8000, "the short seller keeps the proceeds")


func test_a_split_doubles_shares_and_shorts() -> void:
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.VALUE, &"long"), _trader(NpcStrategy.Value.SHORT, &"short")])
	desk.traders[0].set_shares(&"mafia", 7)
	desk.traders[1].set_short(&"mafia", 5)
	desk.split(&"mafia")
	assert_eq(desk.traders[0].shares_of(&"mafia"), 14)
	assert_eq(desk.traders[1].short_of(&"mafia"), 10)


func test_holders_are_paid_dividends_and_short_sellers_pay_them() -> void:
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.VALUE, &"long"), _trader(NpcStrategy.Value.SHORT, &"short")])
	desk.traders[0].set_shares(&"mafia", 10)
	desk.traders[1].set_short(&"mafia", 10)
	var paid: Dictionary[StringName, int] = {&"mafia": 3}
	desk.settle_dividends(paid)
	assert_eq(desk.traders[0].cash, 8030)
	assert_eq(desk.traders[1].cash, 7970)


func test_the_pipeline_settles_the_desk_through_splits_and_bankruptcy() -> void:
	var state: GameState = _new_state()
	var company: CompanyState = state.market.company_by_id(&"pillows")
	company.revenue = 1000000.0
	company.margin_percent = -90.0
	company.profit = -1000000.0
	company.regime = EarningsRegime.Value.DISTRESS
	state.market.desk.trader_by_id(&"value_1").set_shares(&"pillows", 50)
	EarningsYearResolver.new().advance_year(state, StalksFixture.rng(6))
	assert_true(state.stalk_by_id(&"pillows").is_bankrupt)
	assert_eq(state.market.desk.trader_by_id(&"value_1").shares_of(&"pillows"), 0)


# ---------------------------------------------------------------- flow

func test_the_desks_trading_is_next_years_flow_input() -> void:
	var state: GameState = _new_state()
	var result: EarningsYearResult = _shipped_resolver().advance_year(state, StalksFixture.rng(11))
	assert_false(result.desk.net_shares.is_empty(), "the desk traded")
	assert_eq(state.market.net_shares_traded, result.desk.net_shares, "and that is the flow input")


func test_the_desks_buying_moves_next_years_price_through_flow_clamped() -> void:
	var state: GameState = _new_state()
	var resolver: EarningsYearResolver = EarningsYearResolver.new()
	resolver.advance_year(state, StalksFixture.rng(21))
	var bought: StringName = &""
	for stalk_id: StringName in state.market.net_shares_traded:
		if state.market.company_by_id(stalk_id) != null and state.market.net_shares_traded[stalk_id] > 0:
			bought = stalk_id
			break
	assert_ne(bought, &"", "the desk bought some company")
	var before: CompanyState = state.market.company_by_id(bought).copy()
	var traded: int = state.market.net_shares_traded[bought]
	resolver.advance_year(state, StalksFixture.rng(22))
	var after: CompanyState = state.market.company_by_id(bought)
	var expected: float = PriceIdentity.flow_after(before.flow, traded, before.shares_outstanding, after.fair_value)
	assert_almost_eq(after.flow, expected, 0.000001, "flow is the identity's, from the desk's shares")
	assert_gt(after.flow, 0.0)
	assert_lte(absf(after.flow), PriceIdentity.flow_limit(after.fair_value) + 0.000001, "clamped at 5%")


func test_flow_stays_clamped_over_a_whole_match() -> void:
	var state: GameState = _new_state(25)
	var resolver: EarningsYearResolver = _shipped_resolver()
	var rng: RandomNumberGenerator = StalksFixture.rng(31)
	for year: int in 25:
		resolver.advance_year(state, rng)
		for company: CompanyState in state.market.companies:
			if state.stalk_by_id(company.id).is_bankrupt:
				continue
			# A split halves fair value and flow together, so the clamp holds after it too.
			assert_lte(absf(company.flow), PriceIdentity.flow_limit(company.fair_value) + 0.000001,
				"%s year %d" % [company.id, state.year])
	assert_eq(PriceIdentity.FLOW_LIMIT_FRACTION, 0.05)


func test_record_trade_adds_players_and_npcs_alike() -> void:
	var market: EarningsMarket = _new_state().market
	market.record_trade(&"mafia", 30)
	market.record_trade(&"mafia", -12)
	market.record_trade(&"stryker", 0)
	assert_eq(market.net_shares_traded, {&"mafia": 18} as Dictionary[StringName, int])


# ------------------------------------------------------- short interest §5.3

func test_the_flag_and_the_squeeze_chance_are_the_documented_amounts() -> void:
	assert_eq(ShortInterestRules.FLAG_AT_PERCENT, 10.0)
	assert_eq(ShortInterestRules.SQUEEZE_CHANCE_PERCENT, 25)
	assert_false(ShortInterestRules.is_flagged(99, 1000))
	assert_true(ShortInterestRules.is_flagged(100, 1000))
	assert_false(ShortInterestRules.is_flagged(0, 0))
	assert_eq(ShortInterestRules.squeeze_chance_percent(false), 0, "not eligible without the flag")
	assert_eq(ShortInterestRules.squeeze_chance_percent(true), 25)


func test_flagged_companies_are_most_shorted_first() -> void:
	var state: GameState = _new_state()
	var desk: NpcDesk = _desk_of([_trader(NpcStrategy.Value.SHORT, &"a"), _trader(NpcStrategy.Value.SHORT, &"b")])
	desk.traders[0].set_short(&"mafia", 150)
	desk.traders[1].set_short(&"stryker", 300)
	desk.traders[1].set_short(&"pillows", 50)
	state.market.desk = desk
	assert_eq(desk.flagged_companies(state), [&"stryker", &"mafia"] as Array[StringName])


func test_the_squeeze_happens_only_while_the_flag_is_set() -> void:
	# The test §5.3 promises: the squeeze's probability rises when the flag is
	# set and not otherwise. One year, 400 seeds, each way.
	var squeezes_flagged: int = 0
	var squeezes_unflagged: int = 0
	var resolver: EarningsYearResolver = _shipped_resolver()
	for seed_value: int in 400:
		var flagged: GameState = _new_state()
		_shorted(flagged, &"stryker", 400)
		if resolver.advance_year(flagged, StalksFixture.rng(seed_value)).squeezed:
			squeezes_flagged += 1
		var quiet: GameState = _new_state()
		_shorted(quiet, &"stryker", 50)
		if resolver.advance_year(quiet, StalksFixture.rng(seed_value)).squeezed:
			squeezes_unflagged += 1
	assert_eq(squeezes_unflagged, 0, "never without the flag")
	assert_between(squeezes_flagged, 70, 130, "about 25% of 400 with it")


func test_a_squeeze_is_exactly_the_roll_against_the_chance() -> void:
	var resolver: EarningsYearResolver = _shipped_resolver()
	for seed_value: int in 60:
		var state: GameState = _new_state()
		_shorted(state, &"stryker", 400)
		var result: EarningsYearResult = resolver.advance_year(state, StalksFixture.rng(seed_value))
		assert_between(result.squeeze_roll, 1, 100)
		assert_eq(result.squeezed, result.squeeze_roll <= ShortInterestRules.SQUEEZE_CHANCE_PERCENT)


## A state whose stryker is squeezed in year 1, with the seed that did it, or
## null when none of the first 100 seeds squeezes.
func _squeezed_state(shares_short: int = 400) -> Array:
	var resolver: EarningsYearResolver = _shipped_resolver()
	for seed_value: int in 100:
		var state: GameState = _new_state(20)
		_shorted(state, &"stryker", shares_short)
		var before: int = state.stalk_by_id(&"stryker").price
		var percent: float = MarketReadouts.short_interest_percent(state, &"stryker")
		var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
		var result: EarningsYearResult = resolver.advance_year(state, rng)
		if result.squeezed:
			return [state, result, before, percent, rng]
	return []


func test_the_spike_scales_with_short_interest_and_is_capped() -> void:
	assert_eq(ShortInterestRules.SPIKE_PERCENT_PER_POINT, 5.0)
	assert_eq(ShortInterestRules.SPIKE_MAX_PERCENT, 150.0)
	assert_eq(ShortInterestRules.spike_for(100, 10.0), 50, "10 points is 50% of the price")
	assert_eq(ShortInterestRules.spike_for(100, 20.0), 100)
	assert_eq(ShortInterestRules.spike_for(100, 30.0), 150, "the cap")
	assert_eq(ShortInterestRules.spike_for(100, 80.0), 150, "never past the cap")
	assert_eq(ShortInterestRules.spike_for(0, 40.0), 0)


## D220: the shorts buy back the year's cover roll of what they owe, rounded
## up, and all of it once the fuel is gone.
func test_shorts_in_a_squeeze_cover_the_years_roll() -> void:
	assert_eq(ShortInterestRules.cover_now(300, 20, 80), 60)
	assert_eq(ShortInterestRules.cover_now(10, 35, 50), 4, "rounding up")
	assert_eq(ShortInterestRules.cover_now(300, 20, 0), 300, "the fuel is gone: all of it")
	assert_eq(ShortInterestRules.cover_now(0, 50, 80), 0)
	assert_eq(ShortInterestRules.remaining_after(100, 30), 70)
	assert_eq(ShortInterestRules.remaining_after(40, 50), 20)
	assert_eq(ShortInterestRules.remaining_after(20, 50), 0, "at or under 10% the rest goes")


## D220: the end chance rises as the shorts cover, and with a bear year; the
## drift leans up with most shorts open and down with few.
func test_a_squeeze_ends_more_likely_as_its_fuel_runs_out() -> void:
	var bull: MarketMood.Value = MarketMood.Value.BULL
	var bear: MarketMood.Value = MarketMood.Value.BEAR
	assert_eq(ShortInterestRules.end_chance_percent(100, bull), 5, "just fired, a bull year: the floor")
	assert_eq(ShortInterestRules.end_chance_percent(70, bull), 26)
	assert_eq(ShortInterestRules.end_chance_percent(70, bear), 46, "a bear year helps it end")
	assert_eq(ShortInterestRules.end_chance_percent(0, bear), 95, "never certain")
	assert_lt(ShortInterestRules.end_chance_percent(70, bull), ShortInterestRules.end_chance_percent(30, bull))
	assert_eq(ShortInterestRules.drift_percent(0, 100, bull), 25)
	assert_eq(ShortInterestRules.drift_percent(0, 0, bear), -10)
	assert_eq(ShortInterestRules.drift_percent(-15, 0, bear), -25)


func test_a_squeeze_lifts_the_most_shorted_company_through_the_ledger() -> void:
	var found: Array = _squeezed_state()
	assert_false(found.is_empty(), "some seed squeezed")
	var state: GameState = found[0]
	var result: EarningsYearResult = found[1]
	var before: int = found[2]
	assert_eq(result.squeeze_target(), &"stryker")
	assert_null(result.event, "the squeeze is not a special event any more")
	assert_eq(result.squeeze_spike, ShortInterestRules.spike_for(before, found[3]))
	var ledger: PriceLedger = result.ledger_for(&"stryker")
	var company: CompanyState = state.market.company_by_id(&"stryker")
	assert_eq(ledger.squeeze, company.squeeze_premium, "the ledger's squeeze line is the lift")
	assert_eq(result.squeeze_moves[&"stryker"], company.squeeze_premium)
	assert_gte(company.squeeze_premium, result.squeeze_spike, "at least the spike")
	assert_gte(state.stalk_by_id(&"stryker").price, before + result.squeeze_spike, "and no loss in the squeeze year")
	assert_eq(company.squeeze_remaining_percent, ShortInterestRules.remaining_after(100, result.squeeze_cover_roll))


func test_the_lift_comes_off_once_the_shorts_have_covered() -> void:
	var found: Array = _squeezed_state()
	assert_false(found.is_empty(), "some seed squeezed")
	var state: GameState = found[0]
	var rng: RandomNumberGenerator = found[4]
	var resolver: EarningsYearResolver = _shipped_resolver()
	var company: CompanyState = state.market.company_by_id(&"stryker")
	var came_off: bool = false
	for year: int in 40:
		var premium: int = company.squeeze_premium
		var remaining: int = company.squeeze_remaining_percent
		var mood: MarketMood.Value = state.market.last_mood
		var result: EarningsYearResult = resolver.advance_year(state, rng)
		var ends: bool = result.squeeze_end_roll <= ShortInterestRules.end_chance_percent(remaining, mood)
		if result.squeeze_moves.has(&"stryker"):
			assert_true(ends, "it ends exactly when the roll says")
			assert_eq(result.squeeze_moves[&"stryker"], -premium, "the whole lift comes off")
			assert_eq(result.ledger_for(&"stryker").squeeze, -premium, "on the ledger's squeeze line")
			came_off = true
			break
		assert_false(ends)
		assert_true(company.in_squeeze(), "still squeezed in year %d" % state.year)
		var drift: int = result.squeeze_drift_moves[&"stryker"]
		@warning_ignore("integer_division")
		assert_eq(drift, premium * ShortInterestRules.drift_percent(result.squeeze_drift_roll, remaining, mood) / 100)
		assert_eq(result.ledger_for(&"stryker").squeeze, drift, "the drift is on the squeeze line")
	assert_true(came_off, "it ends in time")
	assert_false(company.in_squeeze())


## D220: over many squeezes, most run two to five years, some end in their
## second, and none is fixed in length.
func test_squeezes_run_for_years_of_no_fixed_length() -> void:
	var lengths: Dictionary[int, int] = {}
	var resolver: EarningsYearResolver = _shipped_resolver()
	var found: int = 0
	for seed_value: int in 400:
		var state: GameState = _new_state(40)
		_shorted(state, &"stryker", 400)
		var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
		if not resolver.advance_year(state, rng).squeezed:
			continue
		found += 1
		var company: CompanyState = state.market.company_by_id(&"stryker")
		var years: int = 1
		while company.in_squeeze() and years < 30:
			resolver.advance_year(state, rng)
			years += 1
		lengths[years] = lengths.get(years, 0) + 1
	assert_gt(found, 40)
	assert_eq(lengths.get(1, 0), 0, "never over in its own year")
	assert_gt(lengths.get(2, 0), 0, "sometimes over in its second")
	var long_ones: int = 0
	for years: int in lengths:
		if years >= 4:
			long_ones += lengths[years]
	assert_gt(long_ones, 0, "some run four years or more")
	assert_gt(lengths.size(), 3, "lengths vary: %s" % lengths)


func test_a_squeezed_company_is_not_shorted_again_or_flagged() -> void:
	var found: Array = _squeezed_state()
	assert_false(found.is_empty(), "some seed squeezed")
	var state: GameState = found[0]
	var rng: RandomNumberGenerator = found[4]
	var resolver: EarningsYearResolver = _shipped_resolver()
	var company: CompanyState = state.market.company_by_id(&"stryker")
	var last: int = state.market.desk.short_interest(&"stryker")
	while company.in_squeeze():
		assert_false(state.market.desk.flagged_companies(state).has(&"stryker"), "not flagged while squeezed")
		assert_eq(MarketReadouts.short_status(state, &"stryker"), MarketReadouts.ShortStatus.SQUEEZED)
		resolver.advance_year(state, rng)
		var now: int = state.market.desk.short_interest(&"stryker")
		assert_lte(now, last, "the shorts only cover, year %d" % state.year)
		last = now


func test_short_status_reads_flagged_then_none() -> void:
	var state: GameState = _new_state()
	_shorted(state, &"stryker", 400)
	assert_eq(MarketReadouts.short_status(state, &"stryker"), MarketReadouts.ShortStatus.FLAGGED)
	assert_almost_eq(MarketReadouts.short_interest_percent(state, &"stryker"),
		ShortInterestRules.percent_of(400, state.market.company_by_id(&"stryker").shares_outstanding), 0.0001)
	assert_eq(MarketReadouts.short_status(state, &"mafia"), MarketReadouts.ShortStatus.NONE)


func test_without_a_template_nothing_squeezes_and_the_stream_is_unchanged() -> void:
	# The roll is drawn every year, so a match with no squeeze content and a
	# match where nothing is flagged leave the RNG in the same place.
	var with_template: GameState = _new_state()
	_shorted(with_template, &"stryker", 50)
	var without: GameState = _new_state()
	_shorted(without, &"stryker", 400)
	var rng_a: RandomNumberGenerator = StalksFixture.rng(8)
	var rng_b: RandomNumberGenerator = StalksFixture.rng(8)
	_shipped_resolver().advance_year(with_template, rng_a)
	var plain: EarningsYearResolver = EarningsYearResolver.new()
	var result: EarningsYearResult = plain.advance_year(without, rng_b)
	assert_false(result.squeezed)
	assert_eq(result.short_interest_flagged, [&"stryker"] as Array[StringName], "flagged, but no template")
	assert_eq(rng_a.state, rng_b.state, "the same draws either way")


func test_short_interest_builds_up_in_a_real_match() -> void:
	# The desk's own SHORT traders, not a staged position, flag something.
	var flagged_years: int = 0
	var resolver: EarningsYearResolver = _shipped_resolver()
	for seed_value: int in 10:
		var state: GameState = _new_state()
		var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
		for year: int in 10:
			if not resolver.advance_year(state, rng).short_interest_flagged.is_empty():
				flagged_years += 1
	assert_gt(flagged_years, 0)


# --------------------------------------------------------- players cannot short

func test_a_player_cannot_sell_what_they_do_not_hold() -> void:
	# §14 q10: no short selling for players. Selling is the base game's rule,
	# unchanged: you can only sell shares you own.
	var state: GameState = _new_state()
	state.year = 1
	var player: PlayerState = state.players[0]
	var reason: String = TradeRules.validate_sell(player, state.stalk_by_id(&"stryker"), 5, state)
	assert_ne(reason, "", "refused")
