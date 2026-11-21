extends GutTest
## StalkleHeads company fundamentals: earnings, industries, valuation, the price
## identity, the split and dividends. See docs/stalkleheads-design.md §3.3-§3.6
## and §3.10a, and decisions.md D129-D135.


const G: EarningsRegime.Value = EarningsRegime.Value.GROWTH
const ST: EarningsRegime.Value = EarningsRegime.Value.STEADY
const SL: EarningsRegime.Value = EarningsRegime.Value.SLOWING
const DE: EarningsRegime.Value = EarningsRegime.Value.DECLINE
const DI: EarningsRegime.Value = EarningsRegime.Value.DISTRESS


func _profile(eps: float = 8.0, policy: int = 35, beta: int = 100, quality: int = 50) -> CompanyProfile:
	var profile: CompanyProfile = CompanyProfile.new()
	profile.id = &"test_company"
	profile.display_name = "Test Company"
	profile.ticker = &"TEST"
	profile.industry = &"test_industry"
	profile.starting_earnings_per_share = eps
	profile.payout_policy_percent = policy
	profile.industry_beta_percent = beta
	profile.quality = quality
	return profile


# ----------------------------------------------------------------- year 0

func test_a_company_opens_steady_at_eps_times_the_base_multiple() -> void:
	var company: CompanyState = CompanyState.new(_profile(9.6))
	assert_eq(company.regime, ST)
	assert_eq(company.years_in_regime, 0)
	assert_eq(company.multiple, 12.5)
	assert_eq(company.price, 120)
	assert_almost_eq(company.earnings_per_share(), 9.6, 0.000001)
	assert_eq(company.event_carry, 0.0)
	assert_eq(company.flow, 0.0)
	assert_eq(company.shares_outstanding, 1000)
	assert_almost_eq(company.revenue, 80000.0, 0.001, "profit 9,600 at a 12% margin")


# --------------------------------------------------------------- earnings

func test_margin_moves_one_third_of_the_way_to_its_target() -> void:
	var company: CompanyState = CompanyState.new(_profile())
	company.regime = DI
	company.move_accounts(-30, 0.0, 10)
	assert_almost_eq(company.margin_percent, 12.0 + (1.0 - 12.0) / 3.0, 0.000001)
	company.move_accounts(-30, 0.0, 10)
	assert_almost_eq(company.margin_percent, 8.3333333 + (1.0 - 8.3333333) / 3.0, 0.0001)


func test_revenue_moves_by_own_growth_plus_the_industry_through_beta() -> void:
	var company: CompanyState = CompanyState.new(_profile(8.0, 35, 150))
	var before: float = company.revenue
	company.regime = ST
	company.move_accounts(4, -10.0, 10)
	# own +4, industry -10 at beta 150 -> -15; total -11%.
	assert_almost_eq(company.revenue_growth_percent, -11.0, 0.000001)
	assert_almost_eq(company.revenue, before * 0.89, 0.001)
	assert_almost_eq(company.profit, company.revenue * company.margin_percent / 100.0, 0.000001)


func test_the_damping_ladder_scales_own_growth_in_long_matches() -> void:
	var short_match: CompanyState = CompanyState.new(_profile())
	var long_match: CompanyState = CompanyState.new(_profile())
	var longest: CompanyState = CompanyState.new(_profile())
	short_match.move_accounts(30, 0.0, 19)
	long_match.move_accounts(30, 0.0, 20)
	longest.move_accounts(30, 0.0, 50)
	assert_almost_eq(short_match.revenue_growth_percent, 30.0, 0.000001)
	assert_almost_eq(long_match.revenue_growth_percent, 24.0, 0.000001)
	assert_almost_eq(longest.revenue_growth_percent, 15.0, 0.000001)


func test_the_retention_factor_applies_to_positive_growth_only() -> void:
	assert_almost_eq(DividendRules.retained_growth(25.0, 0), 33.75, 0.000001)
	assert_almost_eq(DividendRules.retained_growth(25.0, 35), 25.0, 0.000001)
	assert_almost_eq(DividendRules.retained_growth(25.0, 80), 13.75, 0.000001)
	assert_eq(DividendRules.retained_growth(-10.0, 80), -10.0, "a high payer shrinks no slower")
	assert_eq(DividendRules.retained_growth(-10.0, 0), -10.0)
	assert_eq(DividendRules.retained_growth(0.0, 0), 0.0)


func test_retention_reaches_revenue_but_not_the_industry_share() -> void:
	var payer: CompanyState = CompanyState.new(_profile(8.0, 80))
	payer.move_accounts(20, 10.0, 10)
	# own 20 * 0.55 = 11, industry +10 untouched.
	assert_almost_eq(payer.revenue_growth_percent, 21.0, 0.000001)


func test_earnings_season_draws_exactly_twice() -> void:
	for seed_value: int in 40:
		var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)
		var twin: RandomNumberGenerator = StalksFixture.rng(seed_value)
		var company: CompanyState = CompanyState.new(_profile(8.0, 35, 100, seed_value * 2))
		company.regime = EarningsRegime.ALL[seed_value % 5]
		company.years_in_regime = seed_value % 3
		var from: EarningsRegime.Value = company.regime
		var aged: int = company.years_in_regime
		company.advance_earnings(5.0, 10, rng)

		var landed: EarningsRegime.Value = RegimeRules.regime_for_roll(
			from, twin.randi_range(1, 100), seed_value * 2, aged
		)
		var band: Vector2i = RegimeRules.GROWTH_BAND[landed]
		twin.randi_range(band.x, band.y)
		assert_eq(company.regime, landed)
		assert_eq(rng.state, twin.state, "seed %d" % seed_value)


func test_years_in_regime_counts_up_and_resets_on_change() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(7)
	var company: CompanyState = CompanyState.new(_profile())
	for year: int in 60:
		var was: EarningsRegime.Value = company.regime
		var aged: int = company.years_in_regime
		company.advance_earnings(0.0, 99, rng)
		if company.regime == was:
			assert_eq(company.years_in_regime, aged + 1)
		else:
			assert_eq(company.years_in_regime, 0)


# ---------------------------------------------------------------- industries

func test_an_industry_roll_is_persistent_and_leans_with_sentiment() -> void:
	# Same seed, so the same raw roll; only the carried and tilt terms differ.
	var plain: float = IndustryState.next_performance(0.0, 0.0, StalksFixture.rng(3))
	var carried: float = IndustryState.next_performance(-20.0, 0.0, StalksFixture.rng(3))
	var tilted: float = IndustryState.next_performance(0.0, 20.0, StalksFixture.rng(3))
	if absf(plain) < 20.0:
		assert_almost_eq(carried - plain, -8.0, 0.000001, "40% of last year's -20 carried")
		assert_almost_eq(tilted - plain, 2.0, 0.000001, "10% of a +20 market")
	else:
		fail_test("seed 3 should give a roll inside the clamp; pick another seed")


func test_industry_performance_is_clamped_to_thirty() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(11)
	var outside: int = 0
	for i: int in 2000:
		var value: float = IndustryState.next_performance(30.0, 20.0, rng)
		if value > 30.0 or value < -30.0:
			outside += 1
	assert_eq(outside, 0)
	assert_eq(IndustryState.next_performance(100.0, 20.0, StalksFixture.rng(1)), 30.0)
	assert_eq(IndustryState.next_performance(-100.0, -20.0, StalksFixture.rng(1)), -30.0)


func test_industries_advance_in_id_order_whatever_order_they_are_held_in() -> void:
	var names: Array[StringName] = [&"tech", &"energy", &"food"]
	var held: Array[IndustryState] = []
	for industry_id: StringName in names:
		var definition: IndustryDefinition = IndustryDefinition.new()
		definition.id = industry_id
		held.append(IndustryState.new(definition))
	var reversed: Array[IndustryState] = []
	for industry: IndustryState in held:
		var twin: IndustryState = IndustryState.new(industry.definition)
		reversed.push_front(twin)

	IndustryState.advance_all(held, 5.0, StalksFixture.rng(99))
	IndustryState.advance_all(reversed, 5.0, StalksFixture.rng(99))
	for industry: IndustryState in held:
		for twin: IndustryState in reversed:
			if twin.id == industry.id:
				assert_eq(twin.performance, industry.performance, String(industry.id))


func test_one_industry_draws_once() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(5)
	var twin: RandomNumberGenerator = StalksFixture.rng(5)
	var industry: IndustryState = IndustryState.new(IndustryDefinition.new())
	industry.advance(3.0, rng)
	twin.randi_range(-15, 15)
	assert_eq(rng.state, twin.state)


func test_standing_is_six_hundredths_of_performance() -> void:
	assert_almost_eq(IndustryState.standing_for(20.0), 1.2, 0.000001)
	assert_almost_eq(IndustryState.standing_for(-30.0), -1.8, 0.000001)


# ---------------------------------------------------------------- valuation

func test_the_multiple_composes_from_its_four_terms() -> void:
	# 12.5 + 10 * 0.02 + 1.2 + 0.6
	assert_almost_eq(ValuationRules.multiple(10.0, 1.2, G), 14.5, 0.000001)
	assert_almost_eq(ValuationRules.multiple(0.0, 0.0, ST), 12.5, 0.000001)
	assert_almost_eq(ValuationRules.multiple(-5.0, -0.6, DI), 12.5 - 0.1 - 0.6 - 1.4, 0.000001)
	assert_almost_eq(ValuationRules.multiple(0.0, 0.0, SL), 12.74, 0.000001)
	assert_almost_eq(ValuationRules.multiple(0.0, 0.0, DE), 11.9, 0.000001)


func test_sentiment_is_clamped_to_twenty_before_it_reaches_the_multiple() -> void:
	assert_almost_eq(ValuationRules.multiple(100.0, 0.0, ST), 12.9, 0.000001)
	assert_almost_eq(ValuationRules.multiple(-100.0, 0.0, ST), 12.1, 0.000001)


func test_the_multiple_clamps_to_four_and_thirty() -> void:
	assert_eq(ValuationRules.multiple(0.0, 40.0, G), 30.0)
	assert_eq(ValuationRules.multiple(0.0, -40.0, DI), 4.0)


func test_fair_value_is_eps_times_the_multiple_and_clamps() -> void:
	assert_almost_eq(ValuationRules.fair_value(8.0, 14.5), 116.0, 0.000001)
	assert_eq(ValuationRules.fair_value(100.0, 30.0), 1200.0)
	assert_eq(ValuationRules.fair_value(-10.0, 12.5), -40.0)


# ---------------------------------------------------------- the price identity

func test_the_price_is_one_truncation_of_the_three_terms() -> void:
	assert_eq(PriceIdentity.price_of(99.9, 0.0, 0.0), 99)
	assert_eq(PriceIdentity.price_of(100.0, 5.5, -2.25), 103)
	assert_eq(PriceIdentity.price_of(-0.5, 0.0, 0.0), 0, "toward zero, like int / int")
	assert_eq(PriceIdentity.price_of(-3.5, 0.0, 0.0), -3)


func test_event_carry_halves_each_year_and_adds_this_years_event() -> void:
	assert_eq(PriceIdentity.carry_after(0.0, -12), -12.0)
	assert_eq(PriceIdentity.carry_after(-12.0, 0), -6.0)
	assert_eq(PriceIdentity.carry_after(-6.0, 10), 7.0)


func test_flow_persists_at_seventy_percent() -> void:
	assert_almost_eq(PriceIdentity.flow_after(4.0, 0, 1000, 100.0), 2.8, 0.000001)


func test_flow_gains_point_five_five_per_percent_of_shares_traded() -> void:
	# 10 of 1,000 shares is 1%.
	assert_almost_eq(PriceIdentity.flow_after(0.0, 10, 1000, 100.0), 0.55, 0.000001)
	assert_almost_eq(PriceIdentity.flow_after(0.0, -10, 1000, 100.0), -0.55, 0.000001)


func test_the_flow_clamp_is_five_percent_of_fair_value() -> void:
	# Asserted as a constant: §2.4 measured 18% restores the dominant strategy.
	assert_eq(PriceIdentity.FLOW_LIMIT_FRACTION, 0.05)
	assert_eq(PriceIdentity.flow_after(0.0, 1_000_000, 1000, 120.0), 6.0)
	assert_eq(PriceIdentity.flow_after(0.0, -1_000_000, 1000, 120.0), -6.0)
	assert_eq(PriceIdentity.flow_after(50.0, 0, 1000, 120.0), 6.0, "old flow is clamped too")


func test_a_desk_buying_every_share_cannot_push_past_the_clamp() -> void:
	var company: CompanyState = CompanyState.new(_profile(8.0))
	for year: int in 10:
		company.reprice(0.0, 0.0, 0, company.shares_outstanding * 10)
		assert_true(company.flow <= company.fair_value * 0.05 + 0.000001)
	assert_eq(company.flow, PriceIdentity.flow_limit(company.fair_value), "held at the clamp")


func test_a_player_share_and_an_npc_share_count_the_same() -> void:
	# The identity takes one net figure; there is no way to tell it who traded.
	# 30 NPC shares bought + 20 player shares bought == 50 shares bought.
	var mixed: float = PriceIdentity.flow_after(0.0, 30 + 20, 1000, 100.0)
	var single: float = PriceIdentity.flow_after(0.0, 50, 1000, 100.0)
	assert_eq(mixed, single)


func test_the_flow_bound_never_inverts_for_a_negative_fair_value() -> void:
	assert_almost_eq(PriceIdentity.flow_after(0.0, 1000, 1000, -40.0), 2.0, 0.000001)


func test_reprice_sets_the_price_from_the_identity() -> void:
	var company: CompanyState = CompanyState.new(_profile(8.0))
	company.reprice(10.0, 20.0, -12, 30)
	assert_almost_eq(company.multiple, 12.5 + 0.2 + 1.2 + 0.0, 0.000001)
	assert_almost_eq(company.fair_value, 8.0 * company.multiple, 0.000001)
	assert_eq(company.event_carry, -12.0)
	assert_almost_eq(company.flow, 3.0 * 0.55, 0.000001)
	assert_eq(company.price, int(company.fair_value + company.event_carry + company.flow))


# --------------------------------------------------------------------- split

func test_the_split_is_value_neutral_and_the_identity_still_holds() -> void:
	var company: CompanyState = CompanyState.new(_profile(25.6))
	company.event_carry = 8.0
	company.flow = 4.0
	company.price = PriceIdentity.price_of(company.fair_value, company.event_carry, company.flow)
	assert_eq(company.price, 332)
	var eps_before: float = company.earnings_per_share()
	var market_cap: int = company.price * company.shares_outstanding

	assert_true(company.split_if_above())
	assert_eq(company.price, 166)
	assert_eq(company.shares_outstanding, 2000)
	assert_almost_eq(company.earnings_per_share(), eps_before / 2.0, 0.000001)
	assert_almost_eq(company.fair_value, 160.0, 0.000001)
	assert_eq(company.event_carry, 4.0)
	assert_eq(company.flow, 2.0)
	assert_eq(company.price * company.shares_outstanding, market_cap)
	assert_eq(company.price, PriceIdentity.price_of(company.fair_value, company.event_carry, company.flow))
	assert_true(company.did_split)


func test_the_design_documents_worked_split() -> void:
	# §3.6: price 320, eps 25.60, multiple 12.5 -> eps 12.80, fair 160, price 160.
	var company: CompanyState = CompanyState.new(_profile(25.6))
	assert_eq(company.price, 320)
	company.split_if_above()
	assert_eq(company.price, 160)
	assert_almost_eq(company.earnings_per_share(), 12.8, 0.000001)
	company.reprice(0.0, 0.0, 0, 0)
	assert_eq(company.price, 160, "repricing after the split changes nothing")


func test_an_odd_price_rounds_up_and_sits_at_most_one_above_the_identity() -> void:
	var company: CompanyState = CompanyState.new(_profile(26.68))
	assert_eq(company.price, 333)
	company.split_if_above()
	assert_eq(company.price, 167, "rounding up, as D22")
	var identity: int = PriceIdentity.price_of(company.fair_value, company.event_carry, company.flow)
	assert_true(company.price - identity >= 0 and company.price - identity <= 1)


func test_three_hundred_does_not_split_and_three_hundred_and_one_does() -> void:
	var at: CompanyState = CompanyState.new(_profile(24.0))
	assert_eq(at.price, 300)
	assert_false(at.split_if_above())
	assert_eq(at.price, 300)
	var above: CompanyState = CompanyState.new(_profile(24.1))
	assert_eq(above.price, 301)
	assert_true(above.split_if_above())


# ------------------------------------------------------------------ dividends

func test_a_policy_of_zero_never_pays() -> void:
	for regime: EarningsRegime.Value in EarningsRegime.ALL:
		for eps: float in [0.5, 3.0, 9.6, 40.0, 250.0]:
			assert_eq(DividendRules.dividend_per_share(eps, 0, regime), 0)


func test_distress_never_pays_whatever_the_policy() -> void:
	for policy: int in [0, 35, 80, 100]:
		assert_eq(DividendRules.dividend_per_share(50.0, policy, DI), 0)


func test_a_policy_of_35_reproduces_the_single_regime_table() -> void:
	# The policy is 35% scaled by the published regime table. STEADY pays the
	# policy exactly. The earlier single table (0.10 / 0.35 / 0.30 / 0.20 / 0)
	# is reproduced to within a hundredth, not exactly - see D135.
	var single: Dictionary[EarningsRegime.Value, float] = {
		G: 0.10, ST: 0.35, SL: 0.30, DE: 0.20, DI: 0.0,
	}
	for regime: EarningsRegime.Value in EarningsRegime.ALL:
		var ratio: float = DividendRules.payout_ratio(35, regime)
		assert_almost_eq(ratio, 0.35 * RegimeRules.PAYOUT_SCALE[regime], 0.0000001)
		assert_almost_eq(ratio, single[regime], 0.01, EarningsRegime.name_of(regime))
	assert_eq(DividendRules.payout_ratio(35, ST), 0.35)


func test_the_regime_scales_are_the_published_ones() -> void:
	assert_eq(RegimeRules.PAYOUT_SCALE[G], 0.30)
	assert_eq(RegimeRules.PAYOUT_SCALE[ST], 1.00)
	assert_eq(RegimeRules.PAYOUT_SCALE[SL], 0.85)
	assert_eq(RegimeRules.PAYOUT_SCALE[DE], 0.55)
	assert_eq(RegimeRules.PAYOUT_SCALE[DI], 0.0)


func test_the_dividend_is_one_truncation_toward_zero() -> void:
	# 9.6 * 0.60 = 5.76 -> 5
	assert_eq(DividendRules.dividend_per_share(9.6, 60, ST), 5)
	# A company earning under about 3 a share at policy 35 pays nothing (§3.7).
	assert_eq(DividendRules.dividend_per_share(2.8, 35, ST), 0)
	assert_eq(DividendRules.dividend_per_share(-20.0, 80, ST), 0, "losses never charge a holder")


func test_the_retention_factor_values() -> void:
	assert_almost_eq(DividendRules.retention_factor(0), 1.35, 0.000001)
	assert_almost_eq(DividendRules.retention_factor(35), 1.00, 0.000001)
	assert_almost_eq(DividendRules.retention_factor(80), 0.55, 0.000001)


func test_a_company_pays_from_its_own_earnings_and_regime() -> void:
	var company: CompanyState = CompanyState.new(_profile(12.0, 80))
	assert_eq(company.dividend_per_share(), 9, "12 * 0.80 = 9.6")
	company.regime = G
	assert_eq(company.dividend_per_share(), 2, "12 * 0.80 * 0.30 = 2.88")
