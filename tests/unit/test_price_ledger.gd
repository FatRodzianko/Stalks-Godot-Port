extends GutTest
## The StalkleHeads ledger (property P1) and same-seed determinism, run over the
## real roster. See docs/stalkleheads-design.md §3.5, §12.1 and decisions.md D133.
##
## The year here is a stand-in for S3's `EarningsYearResolver`, which does not
## exist yet: industries roll, earnings move, an event lands on one company, a
## random net-shares figure stands in for the desk, prices are set, and splits
## run. Its order is §4's; its event and flow inputs are synthetic.


const SEEDS: int = 40
const YEARS: int = 30


## Runs one synthetic match and returns every year's ledgers and a text record.
## `on_year` receives (before, after, ledger) for every company in every year.
func _run_match(seed_value: int, match_years: int, on_year: Callable) -> String:
	var library: ContentLibrary = ContentLibrary.load_from()
	library.load_fundamentals()
	var rng: RandomNumberGenerator = StalksFixture.rng(seed_value)

	var industries: Array[IndustryState] = []
	var by_industry: Dictionary[StringName, IndustryState] = {}
	for definition: IndustryDefinition in library.industries:
		var industry: IndustryState = IndustryState.new(definition)
		industries.append(industry)
		by_industry[definition.id] = industry
	var companies: Array[CompanyState] = []
	for profile: CompanyProfile in library.companies:
		companies.append(CompanyState.new(profile))

	var record: PackedStringArray = []
	var sentiment: float = 0.0
	for year: int in range(1, match_years + 1):
		IndustryState.advance_all(industries, sentiment, rng)
		var befores: Array[CompanyState] = []
		for company: CompanyState in companies:
			befores.append(company.copy())
			company.advance_earnings(by_industry[company.profile.industry].performance, match_years, rng)

		var target: int = rng.randi_range(0, companies.size() - 1)
		var event_delta: int = rng.randi_range(-25, 20)

		var moves: Array[float] = []
		for index: int in companies.size():
			var company: CompanyState = companies[index]
			var net_shares: int = rng.randi_range(-400, 400)
			var delta: int = event_delta if index == target else 0
			company.reprice(sentiment, by_industry[company.profile.industry].performance, delta, net_shares)
			var ledger: PriceLedger = PriceLedger.between(befores[index], company)
			on_year.call(befores[index], company, ledger)
			if befores[index].price > 0:
				moves.append(float(company.price - befores[index].price) * 100.0 / float(befores[index].price))
			company.split_if_above()
			record.append("%d %s %s %d %d %.6f" % [
				year, company.id, EarningsRegime.name_of(company.regime), company.price,
				company.shares_outstanding, company.revenue,
			])

		var total: float = 0.0
		for move: float in moves:
			total += move
		if not moves.is_empty():
			sentiment = ValuationRules.clamp_sentiment(total / float(moves.size()))
	return "\n".join(record)


func test_the_ledger_balances_for_every_company_in_every_year_over_many_seeds() -> void:
	var state: Dictionary[String, int] = {"checked": 0, "unbalanced": 0, "off_identity": 0}
	var first_failure: Array[String] = []
	var check: Callable = func(before: CompanyState, after: CompanyState, ledger: PriceLedger) -> void:
		state["checked"] += 1
		if not ledger.is_balanced() or ledger.total() != after.price - before.price:
			state["unbalanced"] += 1
			if first_failure.is_empty():
				first_failure.append(str(ledger))
		if after.price != int(after.fair_value + after.event_carry + after.flow):
			state["off_identity"] += 1
	for seed_value: int in SEEDS:
		_run_match(seed_value, YEARS, check)

	assert_eq(state["checked"], SEEDS * YEARS * 18)
	assert_eq(state["unbalanced"], 0, "first: %s" % str(first_failure))
	assert_eq(state["off_identity"], 0)


func test_the_ledger_names_this_years_event_and_last_years_fade() -> void:
	var company: CompanyState = CompanyState.new(_profile())
	var before: CompanyState = company.copy()
	company.reprice(0.0, 0.0, -12, 0)
	var ledger: PriceLedger = PriceLedger.between(before, company)
	assert_eq(ledger.this_years_event, -12)
	assert_eq(ledger.last_years_event_faded, 0)
	assert_eq(ledger.earnings, 0)
	assert_eq(ledger.total(), -12)

	before = company.copy()
	company.reprice(0.0, 0.0, 0, 0)
	ledger = PriceLedger.between(before, company)
	assert_eq(ledger.this_years_event, 0)
	assert_eq(ledger.last_years_event_faded, 6, "half of last year's -12 has gone")
	assert_true(ledger.is_balanced())


func test_the_ledger_separates_earnings_sentiment_standing_and_regime() -> void:
	var company: CompanyState = CompanyState.new(_profile(8.0))
	var before: CompanyState = company.copy()
	# Earnings up 10%: profit and revenue scaled, margin unchanged.
	company.profit *= 1.1
	company.regime = EarningsRegime.Value.GROWTH
	company.reprice(10.0, 20.0, 0, 0)
	var ledger: PriceLedger = PriceLedger.between(before, company)
	# (8.8 - 8.0) * 12.5 = 10; 8.8 * 10 * 0.02 = 1.76; 8.8 * 1.2 = 10.56 for standing; 8.8 * 1.2 = 10.56 for GROWTH's premium (D151)
	assert_eq(ledger.price_before, 100)
	assert_eq(ledger.earnings, 10)
	assert_eq(ledger.sentiment, 1)
	assert_eq(ledger.industry_standing, 11)
	assert_eq(ledger.regime_premium, 10)
	assert_eq(ledger.valuation_limits, 0)
	assert_eq(ledger.total(), company.price - 100)


func test_the_ledger_reports_a_clamp_as_its_own_line() -> void:
	var company: CompanyState = CompanyState.new(_profile(100.0))
	var before: CompanyState = company.copy()
	company.reprice(20.0, 30.0, 0, 0)
	assert_true(company.valuation_clamped, "fair value 100 * 14.7 is above 1,200")
	var ledger: PriceLedger = PriceLedger.between(before, company)
	assert_lt(ledger.valuation_limits, 0)
	assert_true(ledger.is_balanced())


func test_the_ledger_balances_across_a_split() -> void:
	var company: CompanyState = CompanyState.new(_profile(26.68))
	company.split_if_above()
	var before: CompanyState = company.copy()
	company.reprice(0.0, 0.0, 0, 0)
	var ledger: PriceLedger = PriceLedger.between(before, company)
	assert_true(ledger.is_balanced(), str(ledger))


func test_the_same_seed_gives_the_same_market() -> void:
	var ignore: Callable = func(_before: CompanyState, _after: CompanyState, _ledger: PriceLedger) -> void:
		pass
	var first: String = _run_match(1234, 25, ignore)
	var second: String = _run_match(1234, 25, ignore)
	var other: String = _run_match(4321, 25, ignore)
	assert_eq(first, second)
	assert_ne(first, other, "a different seed should give a different market")


func _profile(eps: float = 8.0) -> CompanyProfile:
	var profile: CompanyProfile = CompanyProfile.new()
	profile.id = &"ledger_company"
	profile.industry = &"test_industry"
	profile.starting_earnings_per_share = eps
	return profile
