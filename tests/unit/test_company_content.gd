extends GutTest
## StalkleHeads content - the 18 company profiles and 6 industries in
## src/data/companies/ and src/data/industries/ - and the validator that guards
## them. See docs/stalkleheads-design.md §3.2.1, §3.2.3, §3.2.4 and decisions.md
## D128.


var _library: ContentLibrary


func before_each() -> void:
	_library = ContentLibrary.load_from()
	_library.load_fundamentals()


# --------------------------------------------------------- the authored content

func test_the_fundamentals_load_and_validate_clean() -> void:
	assert_eq(_library.errors, [] as Array[String])
	assert_eq(_library.warnings, [] as Array[String], "every industry has three members")
	assert_true(_library.is_valid())


func test_eighteen_companies_in_six_industries_of_three() -> void:
	assert_eq(_library.companies.size(), 18)
	assert_eq(_library.industries.size(), 6)
	var counts: Dictionary[StringName, int] = {}
	for company: CompanyProfile in _library.companies:
		counts[company.industry] = counts.get(company.industry, 0) + 1
	for industry: IndustryDefinition in _library.industries:
		assert_eq(counts.get(industry.id, 0), 3, String(industry.id))


func test_the_industry_names_are_the_owners() -> void:
	var names: Array[String] = []
	for industry: IndustryDefinition in _library.industries:
		names.append(industry.display_name)
	names.sort()
	assert_eq(names, [
		"Consumer Goods", "Energy", "Financial Services", "Food", "Technology", "Transportation",
	] as Array[String])


func test_the_roster_is_the_approved_one() -> void:
	# §3.2.3: company -> industry, as the owner named them (f41d317 replaced
	# the five placeholder companies).
	var expected: Dictionary[String, StringName] = {
		"Springfield Nuclear Power": &"energy",
		"PG&Enron": &"energy",
		"strYker!!!": &"energy",
		"North Haverbrook MONORAIL": &"transport",
		"Easy Breezy Airways": &"transport",
		"ElectroMotorTronics": &"transport",
		"Teamsters Pension Fund": &"financial",
		"Mafia HUD Scam": &"financial",
		"Landlords United": &"financial",
		"My Pillow, Your Pillow, We're All Pillows!": &"consumer",
		"GinkgoPals": &"consumer",
		"Unionized Submissives LLC": &"consumer",
		"Video Chrome": &"tech",
		"Meowly": &"tech",
		"BoobTube": &"tech",
		"Chicen Pizza": &"food",
		"Farms+": &"food",
		"Seed Genes": &"food",
	}
	var found: Dictionary[String, StringName] = {}
	for company: CompanyProfile in _library.companies:
		found[company.display_name] = company.industry
	assert_eq(found, expected)


func test_every_ticker_is_different() -> void:
	var seen: Dictionary[StringName, StringName] = {}
	for company: CompanyProfile in _library.companies:
		assert_false(seen.has(company.ticker), "%s and %s share %s" % [seen.get(company.ticker, &""), company.id, company.ticker])
		seen[company.ticker] = company.id


func test_shipped_companies_keep_their_stalk_id_and_ticker() -> void:
	for company: CompanyProfile in _library.companies:
		var stalk: StalkDefinition = _library.stalk_by_id(company.id)
		if stalk == null:
			continue
		assert_eq(company.ticker, stalk.ticker, String(company.id))
		assert_eq(company.display_name, stalk.display_name, String(company.id))


func test_opening_prices_are_the_proposed_table() -> void:
	# §3.2.4: opening price is EPS x 12.5, not separately authored.
	var expected: Dictionary[StringName, int] = {
		&"springfield": 120, &"pgenron": 80, &"stryker": 50,
		&"monorail": 40, &"easy-breezy-air": 75, &"electro_moto": 100,
		&"teamsters": 150, &"mafia": 70, &"landlords": 130,
		&"pillows": 90, &"ginkgo_pals": 100, &"submissives": 75,
		&"videochrome": 110, &"meowly": 30, &"boobtube": 100,
		&"chichen": 65, &"farmsplus": 140, &"seed_genes": 100,
	}
	for company: CompanyProfile in _library.companies:
		assert_eq(CompanyState.new(company).price, expected.get(company.id, -1), String(company.id))


func test_the_base_game_never_loads_the_fundamentals() -> void:
	var base: ContentLibrary = ContentLibrary.load_from()
	assert_eq(base.companies.size(), 0)
	assert_eq(base.industries.size(), 0)
	assert_true(base.is_valid())


# ------------------------------------------------------------------ validator

func _industry(industry_id: StringName) -> IndustryDefinition:
	var industry: IndustryDefinition = IndustryDefinition.new()
	industry.id = industry_id
	industry.display_name = "Industry %s" % industry_id
	return industry


func _company(company_id: StringName, industry_id: StringName) -> CompanyProfile:
	var company: CompanyProfile = CompanyProfile.new()
	company.id = company_id
	company.display_name = "Company %s" % company_id
	company.ticker = StringName(String(company_id).to_upper())
	company.industry = industry_id
	return company


func _small_library(companies: Array[CompanyProfile], industries: Array[IndustryDefinition]) -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.load_from()
	library.companies = companies
	library.industries = industries
	library.validate()
	return library


func test_the_validator_catches_an_industry_id_that_does_not_resolve() -> void:
	var library: ContentLibrary = _small_library(
		[_company(&"a", &"energy"), _company(&"b", &"energy"), _company(&"c", &"enrgy")] as Array[CompanyProfile],
		[_industry(&"energy")] as Array[IndustryDefinition],
	)
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("enrgy"), str(library.errors))


func test_an_industry_with_one_member_is_refused() -> void:
	var library: ContentLibrary = _small_library(
		[_company(&"a", &"energy"), _company(&"b", &"energy"), _company(&"c", &"food")] as Array[CompanyProfile],
		[_industry(&"energy"), _industry(&"food")] as Array[IndustryDefinition],
	)
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("Industry food has 1 member"), str(library.errors))


func test_an_industry_with_no_members_is_refused() -> void:
	var library: ContentLibrary = _small_library(
		[_company(&"a", &"energy"), _company(&"b", &"energy"), _company(&"c", &"energy")] as Array[CompanyProfile],
		[_industry(&"energy"), _industry(&"food")] as Array[IndustryDefinition],
	)
	assert_false(library.is_valid())
	assert_true(str(library.errors).contains("Industry food has 0"), str(library.errors))


func test_an_industry_with_two_members_is_reported_but_allowed() -> void:
	var library: ContentLibrary = _small_library(
		[_company(&"a", &"energy"), _company(&"b", &"energy")] as Array[CompanyProfile],
		[_industry(&"energy")] as Array[IndustryDefinition],
	)
	assert_true(library.is_valid(), str(library.errors))
	assert_eq(library.warnings.size(), 1)
	assert_true(str(library.warnings).contains("energy"))


func test_a_missing_or_duplicated_ticker_is_refused() -> void:
	var blank: CompanyProfile = _company(&"c", &"energy")
	blank.ticker = &""
	var twin: CompanyProfile = _company(&"d", &"energy")
	twin.ticker = &"A"
	var library: ContentLibrary = _small_library(
		[_company(&"a", &"energy"), _company(&"b", &"energy"), blank, twin] as Array[CompanyProfile],
		[_industry(&"energy")] as Array[IndustryDefinition],
	)
	assert_true(str(library.errors).contains("has no ticker"), str(library.errors))
	assert_true(str(library.errors).contains("Duplicate ticker A"), str(library.errors))


func test_out_of_range_fundamentals_are_refused() -> void:
	var bad: CompanyProfile = _company(&"c", &"energy")
	bad.quality = 101
	bad.payout_policy_percent = -1
	bad.shares_outstanding = 0
	bad.starting_earnings_per_share = 0.0
	bad.starting_margin_percent = 0.0
	var library: ContentLibrary = _small_library(
		[_company(&"a", &"energy"), _company(&"b", &"energy"), bad] as Array[CompanyProfile],
		[_industry(&"energy")] as Array[IndustryDefinition],
	)
	var text: String = str(library.errors)
	assert_true(text.contains("quality 101"), text)
	assert_true(text.contains("payout policy of -1"), text)
	assert_true(text.contains("0 shares outstanding"), text)
	assert_true(text.contains("starting earnings per share"), text)
	assert_true(text.contains("starting margin"), text)


func test_a_duplicate_industry_or_company_id_is_refused() -> void:
	var library: ContentLibrary = _small_library(
		[_company(&"a", &"energy"), _company(&"a", &"energy")] as Array[CompanyProfile],
		[_industry(&"energy"), _industry(&"energy")] as Array[IndustryDefinition],
	)
	assert_true(str(library.errors).contains("Duplicate industry id: energy"), str(library.errors))
	assert_true(str(library.errors).contains("Duplicate company id: a"), str(library.errors))
