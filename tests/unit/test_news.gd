extends GutTest
## StalkleHeads phase S8: the news (docs/stalkleheads-design.md §8;
## decisions.md D199-D203, and D205 for whispers).
##
## Three things are under test:
##
## - **the content and its validator** - what ships loads clean, every slot
##   that can come up has a line to fill it, and each kind of mistake an author
##   can make is reported rather than producing a line that never fires;
## - **the selector** - the bands, the bag, the preference for specific lines,
##   the empty slot, the chatter; the whispers - next year's draws kept and
##   used, each whisper's truth, its source's odds, the line it is heard as;
## - **determinism** - the same match makes the same news; a client, a
##   rejoiner and a host that took over make the host's news; and choosing it
##   never moves the match.


const SEED: int = 4242
const YEARS: int = 30


func _library() -> ContentLibrary:
	return MatchSetup.load_library(GameMode.Value.STALKLEHEADS)


func _played(seed_value: int = SEED, years: int = YEARS) -> WireMatch:
	var played: WireMatch = WireMatch.start(seed_value, 3, years)
	played.play(years)
	return played


func _all_news(state: GameState) -> PackedStringArray:
	var lines: PackedStringArray = []
	for year: int in range(1, state.year + 1):
		for line: String in NewsSelector.news_for(state, year).all_lines():
			lines.append("%d %s" % [year, line])
	for round: WhisperRound in NewsSelector.whisper_history(state):
		lines.append_array(round.all_lines())
	return lines


## A fresh library whose news is only `lines`, everything else shipped.
func _with_news(library: ContentLibrary, book: NewsBook) -> NewsContent:
	library.news = NewsContent.build([book] as Array[NewsBook], [] as Array[NpcTraderDefinition])
	return library.news


## An industry headline for energy alone, whatever its mood and move: one is
## drawn for energy every year, so it is what the bag tests watch.
func _energy_headline(id: String) -> IndustryReport:
	var line: IndustryReport = IndustryReport.new()
	line.id = StringName(id)
	line.industry_id = &"energy"
	line.text = id
	return line


func _has_error(library: ContentLibrary, fragment: String) -> bool:
	for error: String in library.errors:
		if error.contains(fragment):
			return true
	return false


## The news of a played match, with its market's news replaced and every
## year's cached news cleared, so it is chosen again from `content`.
func _rechoose(state: GameState, content: NewsContent) -> void:
	state.market.news = content
	state.market.whisper_rounds.clear()
	for result: YearResult in state.history:
		(result as EarningsYearResult).news = null


# ---------------------------------------------------------------- content

func test_the_shipped_news_loads_and_validates_clean() -> void:
	var library: ContentLibrary = _library()
	assert_eq(library.errors, [] as Array[String])
	assert_eq(library.warnings, [] as Array[String])
	assert_eq(library.news.market_news.size(), 12, "the twelve headlines, moved over (D209)")
	for line: MarketNews in library.news.market_news:
		assert_false(line.headline.begins_with("MARKET HEADLINE"), "%s lost its old prefix" % line.id)
		assert_eq(line.amount, 0, "%s moves nothing yet" % line.id)
	assert_eq(library.news.company_news.size(), 5 + 8 * 10, "one per move, and every ported event (D211)")
	assert_eq(library.news.whispers.size(), 12, "five outcomes for a company and an industry, a squeeze and a crash")
	assert_eq(library.news.chatter.size(), 24 * 5, "every trader's five lines")


func test_every_base_event_of_a_stalkleheads_company_is_its_company_news() -> void:
	# D211: two per move band, by size, bear events low and bull events high.
	var library: ContentLibrary = _library()
	var by_id: Dictionary[StringName, CompanyNews] = {}
	for line: CompanyNews in library.news.company_news:
		by_id[line.id] = line
	var ported: int = 0
	for company: CompanyProfile in library.companies:
		var row: StalkDefinition = library.stalk_by_id(company.id)
		if row == null:
			continue
		var bands: Dictionary[NewsBands.Move, int] = {}
		for event: SpecialEventDefinition in row.all_events():
			var line: CompanyNews = by_id.get(StringName("cnews_%s" % event.id), null)
			assert_not_null(line, "%s is company news" % event.id)
			if line == null:
				continue
			ported += 1
			assert_eq(line.company_id, company.id)
			assert_eq(line.text, event.flavour_text)
			if event.price_change < 0:
				assert_true(line.move in [NewsBands.Move.CRASH, NewsBands.Move.DOWN, NewsBands.Move.FLAT], "%s" % event.id)
			else:
				assert_true(line.move in [NewsBands.Move.SURGE, NewsBands.Move.UP, NewsBands.Move.FLAT], "%s" % event.id)
			bands[line.move] = bands.get(line.move, 0) + 1
		if not bands.is_empty():
			for move: NewsBands.Move in [NewsBands.Move.CRASH, NewsBands.Move.DOWN, NewsBands.Move.FLAT, NewsBands.Move.UP, NewsBands.Move.SURGE]:
				assert_eq(bands.get(move, 0), 2, "%s has two lines for move %d" % [company.id, move])
	assert_eq(ported, 80)


## §8.3's budget: every slot that can come up has at least one line, so a
## match with the shipped content is never silent for want of writing. Stays
## true whatever the words become.
func test_every_slot_that_can_come_up_has_a_line() -> void:
	var library: ContentLibrary = _library()
	var news: NewsContent = library.news
	for mood: NewsBands.Mood in [NewsBands.Mood.BULL, NewsBands.Mood.BEAR]:
		var moves: Array[NewsBands.Move] = [NewsBands.Move.FLAT, NewsBands.Move.UP, NewsBands.Move.SURGE]
		if mood == NewsBands.Mood.BEAR:
			moves = [NewsBands.Move.FLAT, NewsBands.Move.DOWN, NewsBands.Move.CRASH]
		for move: NewsBands.Move in moves:
			var found: bool = false
			for line: MarketNews in news.market_news:
				found = found or ((line.mood in [mood, NewsBands.Mood.ANY]) and (line.move in [move, NewsBands.Move.ANY]))
			assert_true(found, "market news for %d %d" % [mood, move])
	var all_moves: Array[NewsBands.Move] = [NewsBands.Move.CRASH, NewsBands.Move.DOWN, NewsBands.Move.FLAT, NewsBands.Move.UP, NewsBands.Move.SURGE]
	for move: NewsBands.Move in all_moves:
		var company_found: bool = false
		for line: CompanyNews in news.company_news:
			company_found = company_found or (line.company_id.is_empty() and line.move in [move, NewsBands.Move.ANY])
		assert_true(company_found, "company news for any company on %d" % move)
	for industry: IndustryDefinition in library.industries:
		for move: NewsBands.Move in [NewsBands.Move.CRASH, NewsBands.Move.DOWN, NewsBands.Move.FLAT, NewsBands.Move.UP, NewsBands.Move.SURGE]:
			var found: bool = false
			for line: IndustryReport in news.industry_reports:
				var fits_industry: bool = line.industry_id in [industry.id, &""]
				found = found or (fits_industry and line.move in [move, NewsBands.Move.ANY])
			assert_true(found, "a report for %s %d" % [industry.id, move])
	for about: NewsBands.Subject in [NewsBands.Subject.SQUEEZE, NewsBands.Subject.CRASH]:
		var found: bool = false
		for line: Whisper in news.whispers:
			found = found or (line.about == about and line.subject.is_empty())
		assert_true(found, "a whisper for any %d" % about)
	for about: NewsBands.Subject in [NewsBands.Subject.COMPANY, NewsBands.Subject.INDUSTRY]:
		for outcome: NewsBands.Surprise in WhisperRules.OUTCOMES:
			var found: bool = false
			for line: Whisper in news.whispers:
				found = found or (line.about == about and line.outcome == outcome and line.subject.is_empty())
			assert_true(found, "a whisper about any %d for %d" % [about, outcome])


func test_the_validator_reports_every_kind_of_mistake() -> void:
	var library: ContentLibrary = _library()
	var book: NewsBook = NewsBook.new()
	var report: IndustryReport = IndustryReport.new()
	report.id = &"r1"
	report.industry_id = &"energee"
	report.text = "x"
	book.industry_reports.append(report)
	var gossip: CompanyNews = CompanyNews.new()
	gossip.id = &"e1"
	gossip.company_id = &"nobody"
	gossip.text = "IN THE NEWS: {compnay}"
	book.company_news.append(gossip)
	var lie: Whisper = Whisper.new()
	lie.id = &"w1"
	lie.about = NewsBands.Subject.INDUSTRY
	lie.subject = &"stryker"
	lie.outcome = NewsBands.Surprise.ANY
	lie.text = "{company}"
	book.whispers.append(lie)
	var chatter: NpcChatter = NpcChatter.new()
	chatter.id = &"c1"
	chatter.npc_id = &"nobody_1"
	chatter.text = ""
	book.chatter.append(chatter)
	var headline: MarketNews = StalksFixture.make_market_news(&"e1", &"", 0, NewsBands.Mood.BULL, NewsBands.Move.UP)
	headline.set("move", 99)
	book.market_news.append(headline)
	var both: MarketNews = StalksFixture.make_market_news(&"m2", &"stryker", 5, NewsBands.Mood.ANY, NewsBands.Move.ANY, &"energy")
	book.market_news.append(both)
	var ghost: MarketNews = StalksFixture.make_market_news(&"m3", &"nobody_inc", 5)
	book.market_news.append(ghost)
	var aimless: MarketNews = StalksFixture.make_market_news(&"m4", &"", 5)
	aimless.requires = [&"m4", &"no_such_line"] as Array[StringName]
	book.market_news.append(aimless)
	_with_news(library, book)
	library.validate()

	assert_false(library.is_valid())
	assert_true(_has_error(library, "names industry energee"), "an industry that does not exist")
	assert_true(_has_error(library, "names company nobody"), "a company that does not exist")
	assert_true(_has_error(library, "uses {compnay}"), "a misspelt token")
	assert_true(_has_error(library, "uses {company}"), "a token the kind of line does not fill")
	assert_true(_has_error(library, "w1 has no outcome"), "a whisper that foretells nothing")
	assert_true(_has_error(library, "stryker, which is not an industry"), "a subject of the wrong kind")
	assert_true(_has_error(library, "names trader nobody_1"), "a trader that does not exist")
	assert_true(_has_error(library, "c1 has no text"), "an empty line")
	assert_true(_has_error(library, "Duplicate news id: e1"), "two lines with one id")
	assert_true(_has_error(library, "unknown move (99)"), "a band that does not exist")
	assert_true(_has_error(library, "m2 names both a company and an industry"), "two targets")
	assert_true(_has_error(library, "names company nobody_inc"), "a target that does not exist")
	assert_true(_has_error(library, "m4 has an amount but nothing"), "an amount with no target")
	assert_true(_has_error(library, "m4 requires itself"), "a line that waits for itself")
	assert_true(_has_error(library, "requires no_such_line"), "a requirement that is not a line")


## A loop longer than one line is as stuck as a line that requires itself:
## none of the lines in it could ever be shown (docs/news-flow-chart.md §1.1).
func test_the_validator_refuses_a_loop_of_requires() -> void:
	var library: ContentLibrary = _library()
	var book: NewsBook = NewsBook.new()
	for id: String in ["a", "b", "c", "d"]:
		book.industry_reports.append(_energy_headline(id))
	book.industry_reports[0].requires = [&"c"] as Array[StringName]
	book.industry_reports[1].requires = [&"a"] as Array[StringName]
	book.industry_reports[2].requires = [&"b"] as Array[StringName]
	book.industry_reports[3].requires = [&"a"] as Array[StringName]
	_with_news(library, book)
	library.validate()

	assert_true(_has_error(library, "loop (a requires c, c requires b, b requires a)"), "the three-line loop, named once")
	var loops: int = 0
	for error: String in library.errors:
		if error.contains("loop"):
			loops += 1
	assert_eq(loops, 1, "d only follows the loop; it is not in it")


func test_requires_loops_finds_each_loop_once_and_skips_a_line_that_requires_itself() -> void:
	var book: NewsBook = NewsBook.new()
	for id: String in ["x", "y", "p", "q", "solo", "free"]:
		book.industry_reports.append(_energy_headline(id))
	book.industry_reports[0].requires = [&"y"] as Array[StringName]
	book.industry_reports[1].requires = [&"x"] as Array[StringName]
	book.industry_reports[2].requires = [&"q", &"no_such_line"] as Array[StringName]
	book.industry_reports[3].requires = [&"p"] as Array[StringName]
	book.industry_reports[4].requires = [&"solo"] as Array[StringName]
	var content: NewsContent = NewsContent.build([book] as Array[NewsBook], [] as Array[NpcTraderDefinition])
	var loops: Array[Array] = content.requires_loops()
	assert_eq(str(loops), str([[&"p", &"q"], [&"x", &"y"]]), "two loops, each from its smallest id, in id order")


func test_the_validator_refuses_a_retired_id() -> void:
	var library: ContentLibrary = _library()
	var book: NewsBook = NewsBook.new()
	book.industry_reports.append(_energy_headline("reborn"))
	_with_news(library, book)
	library.retired_news_ids = [&"reborn", &"long_gone"] as Array[StringName]
	library.validate()

	assert_true(_has_error(library, "reborn has a retired id"), "a live line with a deleted line's id")
	assert_false(_has_error(library, "long_gone"), "a retired id nobody uses is fine")


func test_the_retired_ids_file_ships_and_skips_comments() -> void:
	assert_true(FileAccess.file_exists(ContentLibrary.RETIRED_NEWS_IDS_PATH), "the list is in the repository")
	assert_true(_library().is_valid(), "the shipped news uses no retired id")
	var path: String = "user://test_retired_ids.txt"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# a comment

  mkt_bear_crash_9  
ind_any_up_3
")
	file.close()
	assert_eq(str(ContentLibrary.read_retired_news_ids(path)), str([&"mkt_bear_crash_9", &"ind_any_up_3"]))
	DirAccess.remove_absolute(path)
	assert_true(ContentLibrary.read_retired_news_ids("user://no_such_file.txt").is_empty(), "no file, no retired ids")


func test_the_validator_checks_the_transition_matrix_and_the_strategies() -> void:
	var library: ContentLibrary = _library()
	var kept: Array[NpcTraderDefinition] = []
	for trader: NpcTraderDefinition in library.traders:
		if trader.strategy != NpcStrategy.Value.PANIC:
			kept.append(trader)
	library.traders = kept
	library.news = NewsContent.build([] as Array[NewsBook], kept)
	library.validate()
	assert_true(library.is_valid(), "a strategy nobody follows is allowed")
	assert_true(library.warnings.has("No trader follows the PANIC strategy."))
	for regime: EarningsRegime.Value in EarningsRegime.ALL:
		var total: int = 0
		for odds: int in RegimeRules.TRANSITION[regime]:
			total += odds
		assert_eq(total, 100)


func test_a_traders_own_chatter_becomes_a_news_line() -> void:
	var library: ContentLibrary = _library()
	var found: NpcChatter = null
	for line: NpcChatter in library.news.chatter:
		if line.id == &"value_1_bought":
			found = line
	assert_not_null(found)
	assert_eq(found.npc_id, &"value_1")
	assert_eq(found.situation, NpcTraderDefinition.Situation.BOUGHT)
	var trader: NpcTraderDefinition = null
	for each: NpcTraderDefinition in library.traders:
		if each.id == &"value_1":
			trader = each
	assert_eq(found.text, trader.chatter_bought)
	assert_eq(found.strategy, trader.strategy)


# ------------------------------------------------------------------ bands

func test_move_bands_have_the_designs_edges() -> void:
	assert_eq(NewsSelector.move_band(-15.0), NewsBands.Move.CRASH)
	assert_eq(NewsSelector.move_band(-14.9), NewsBands.Move.DOWN)
	assert_eq(NewsSelector.move_band(-3.1), NewsBands.Move.DOWN)
	assert_eq(NewsSelector.move_band(-3.0), NewsBands.Move.FLAT)
	assert_eq(NewsSelector.move_band(3.0), NewsBands.Move.FLAT)
	assert_eq(NewsSelector.move_band(3.1), NewsBands.Move.UP)
	assert_eq(NewsSelector.move_band(14.9), NewsBands.Move.UP)
	assert_eq(NewsSelector.move_band(15.0), NewsBands.Move.SURGE)


func test_surprise_bands_measure_from_what_was_expected() -> void:
	assert_eq(NewsSelector.surprise_band(2.0, 10.0), NewsBands.Surprise.MUCH_WORSE)
	assert_eq(NewsSelector.surprise_band(5.0, 10.0), NewsBands.Surprise.WORSE)
	assert_eq(NewsSelector.surprise_band(10.0, 10.0), NewsBands.Surprise.AS_EXPECTED)
	assert_eq(NewsSelector.surprise_band(14.0, 10.0), NewsBands.Surprise.BETTER)
	assert_eq(NewsSelector.surprise_band(18.0, 10.0), NewsBands.Surprise.MUCH_BETTER)


func test_the_expectation_is_damped_and_retained_like_real_growth() -> void:
	# GROWTH's band is 15-35, middle 25. Payout 0 retains it all.
	assert_eq(NewsSelector.expected_growth(EarningsRegime.Value.GROWTH, 0, 10), 25.0 * DividendRules.retention_factor(0))
	assert_eq(NewsSelector.expected_growth(EarningsRegime.Value.GROWTH, 0, 99), 12.5 * DividendRules.retention_factor(0))
	# DISTRESS shrinks; retention leaves a shrink alone.
	assert_eq(NewsSelector.expected_growth(EarningsRegime.Value.DISTRESS, 80, 10), -30.0)


# --------------------------------------------------------------- the bag

func test_a_line_drawn_fewer_times_is_drawn_first() -> void:
	var played: WireMatch = _played(SEED, 3)
	var book: NewsBook = NewsBook.new()
	for id: String in ["a", "b", "c"]:
		book.industry_reports.append(_energy_headline(id))
	_rechoose(played.state, _with_news(played.library, book))
	var result: EarningsYearResult = played.state.history[0]
	var counts: Dictionary[StringName, int] = {&"a": 1, &"b": 0, &"c": 1}
	assert_eq(NewsSelector.select(played.state, result, counts).industry_reports[&"energy"], "b")


func test_no_line_repeats_until_every_line_has_had_its_turn() -> void:
	var played: WireMatch = _played(SEED, 12)
	var book: NewsBook = NewsBook.new()
	for id: String in ["a", "b", "c", "d"]:
		book.industry_reports.append(_energy_headline(id))
	_rechoose(played.state, _with_news(played.library, book))
	var seen: PackedStringArray = []
	for year: int in range(1, 13):
		seen.append(NewsSelector.news_for(played.state, year).industry_reports[&"energy"])
	for cycle: int in 3:
		var slice: PackedStringArray = seen.slice(cycle * 4, cycle * 4 + 4)
		slice.sort()
		assert_eq(slice, PackedStringArray(["a", "b", "c", "d"]), "cycle %d" % cycle)


func test_a_slot_nothing_matches_stays_empty() -> void:
	var played: WireMatch = _played(SEED, 5)
	var book: NewsBook = NewsBook.new()
	var never: CompanyNews = CompanyNews.new()
	never.id = &"never"
	never.company_id = &"stryker"
	never.move = NewsBands.Move.CRASH
	never.requires = [&"never_shown"] as Array[StringName]
	never.text = "never"
	book.company_news.append(never)
	_rechoose(played.state, _with_news(played.library, book))
	for year: int in range(1, 6):
		var news: YearNews = NewsSelector.news_for(played.state, year)
		assert_true(news.company_news.is_empty(), "year %d" % year)
		assert_true(news.industry_reports.is_empty())
		var round: WhisperRound = NewsSelector.whispers_for(played.state, year)
		assert_true(round == null or round.lines.is_empty(), "heard after year %d" % year)
		assert_true(news.chatter.is_empty())
		assert_false(news.earnings.is_empty(), "the reports need no lines (D215)")
		assert_false(news.industry_years.is_empty())
		assert_false(news.industry_outlooks.is_empty())


func test_a_line_for_this_industry_beats_a_general_one() -> void:
	var played: WireMatch = _played(SEED, 4)
	var book: NewsBook = NewsBook.new()
	var general: IndustryReport = IndustryReport.new()
	general.id = &"any_industry"
	general.text = "ANY {industry}"
	book.industry_reports.append(general)
	var energy: IndustryReport = IndustryReport.new()
	energy.id = &"energy_only"
	energy.industry_id = &"energy"
	energy.text = "ENERGY"
	book.industry_reports.append(energy)
	_rechoose(played.state, _with_news(played.library, book))
	for year: int in range(1, 5):
		var news: YearNews = NewsSelector.news_for(played.state, year)
		assert_eq(news.industry_reports[&"energy"], "ENERGY")
		assert_eq(news.industry_reports[&"food"], "ANY Food", "the token is filled in")


## D215: every company with an earnings season gets its EARNINGS report every
## year, naming it, its revenue change and its regime.
func test_every_company_gets_an_earnings_report_naming_its_numbers() -> void:
	var played: WireMatch = _played()
	var state: GameState = played.state
	for year: int in range(1, YEARS + 1):
		var news: YearNews = NewsSelector.news_for(state, year)
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
		for company_id: StringName in result.regimes:
			if not result.companies_after.has(company_id):
				continue
			var after: CompanyState = result.companies_after[company_id]
			var name: String = state.stalk_by_id(company_id).definition.display_name
			var expected: String = ReportWriter.earnings_sentence(
				name, after.revenue_growth_percent, news.earnings_surprise[company_id], result.regimes[company_id])
			assert_eq(news.earnings.get(company_id, ""), expected, "%s in year %d" % [company_id, year])
			assert_true(expected.begins_with(ReportWriter.possessive(name) + " revenue "), expected)


## D215: the reports' wording, word for word.
func test_the_report_writer_says_what_happened_in_plain_words() -> void:
	assert_eq(ReportWriter.earnings_sentence("Mafia HUD Scam", -14.4, NewsBands.Surprise.MUCH_WORSE, EarningsRegime.Value.DISTRESS),
		"Mafia HUD Scam's revenue fell 14%, far worse than expected. The company is in distress.")
	assert_eq(ReportWriter.earnings_sentence("Easy Breezy Airways", 8.6, NewsBands.Surprise.BETTER, EarningsRegime.Value.GROWTH),
		"Easy Breezy Airways' revenue rose 9%, better than expected. The company is growing.")
	assert_eq(ReportWriter.earnings_sentence("BoobTube", 0.4, NewsBands.Surprise.AS_EXPECTED, EarningsRegime.Value.STEADY),
		"BoobTube's revenue held steady, as expected. The company is steady.")
	assert_eq(ReportWriter.year_sentence("Consumer Goods", NewsBands.Move.DOWN, NewsBands.Surprise.WORSE, NewsBands.Move.CRASH),
		"Consumer Goods fell again, worse than expected.", "a crash then a fall is the same way")
	assert_eq(ReportWriter.year_sentence("Energy", NewsBands.Move.UP, NewsBands.Surprise.BETTER, NewsBands.Move.ANY),
		"Energy rose, better than expected.", "no again without a last year")
	assert_eq(ReportWriter.year_sentence("Food", NewsBands.Move.FLAT, NewsBands.Surprise.AS_EXPECTED, NewsBands.Move.UP),
		"Food held steady, as expected.")
	assert_eq(ReportWriter.outlook_sentence(NewsBands.Move.SURGE), "Expected to surge next year.")
	for move: NewsBands.Move in [NewsBands.Move.CRASH, NewsBands.Move.DOWN, NewsBands.Move.FLAT, NewsBands.Move.UP, NewsBands.Move.SURGE]:
		for surprise: NewsBands.Surprise in WhisperRules.OUTCOMES:
			assert_false(ReportWriter.year_sentence("X", move, surprise, NewsBands.Move.ANY).is_empty())
		assert_false(ReportWriter.outlook_sentence(move).is_empty())
	for regime: EarningsRegime.Value in EarningsRegime.ALL:
		assert_true(ReportWriter.earnings_sentence("X", 1.0, NewsBands.Surprise.AS_EXPECTED, regime).ends_with("."))


# ------------------------------------------------------------- whispers

## Every round of a played match, from the start to the last year with one.
func _rounds(state: GameState) -> Array[WhisperRound]:
	return NewsSelector.whisper_history(state)


func _whisper(id: String, about: NewsBands.Subject, outcome: NewsBands.Surprise, subject: StringName, text: String) -> Whisper:
	var line: Whisper = Whisper.new()
	line.id = StringName(id)
	line.about = about
	line.outcome = outcome
	line.subject = subject
	line.text = text
	return line


## Each source tells the true outcome, one band off and further off as often as
## design §8.4's table says. 20,000 seeded draws per source, within 2 points.
func test_each_source_bends_the_truth_as_often_as_its_odds_say() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(77)
	for source: WhisperRules.Source in WhisperRules.ALL_SOURCES:
		var tally: Array[int] = [0, 0, 0]
		var draws: int = 20000
		for index: int in draws:
			var truth: NewsBands.Surprise = WhisperRules.OUTCOMES[index % WhisperRules.OUTCOMES.size()]
			var said: NewsBands.Surprise = WhisperRules.distort(truth, source, rng)
			tally[mini(WhisperRules.distance(said, truth), 2)] += 1
		var odds: Vector2i = WhisperRules.ODDS[source]
		var name: String = WhisperRules.SOURCE_NAMES[source]
		assert_almost_eq(tally[0] * 100.0 / draws, float(odds.x), 2.0, "%s true" % name)
		assert_almost_eq(tally[1] * 100.0 / draws, float(odds.y), 2.0, "%s one off" % name)
		assert_almost_eq(tally[2] * 100.0 / draws, float(100 - odds.x - odds.y), 2.0, "%s further" % name)
	# Rock Solid is never two bands out.
	for index: int in 5000:
		var said: NewsBands.Surprise = WhisperRules.distort(NewsBands.Surprise.AS_EXPECTED, WhisperRules.Source.ROCK_SOLID, rng)
		assert_true(WhisperRules.distance(said, NewsBands.Surprise.AS_EXPECTED) <= 1)


## One band off from an end can only go one way; two off picks among those far
## enough away.
func test_a_bent_outcome_stays_on_the_scale() -> void:
	var rng: RandomNumberGenerator = StalksFixture.rng(3)
	var seen_far: Dictionary[NewsBands.Surprise, bool] = {}
	for index: int in 3000:
		var near: NewsBands.Surprise = WhisperRules.distort(NewsBands.Surprise.MUCH_BETTER, WhisperRules.Source.ROCK_SOLID, rng)
		assert_true(near in [NewsBands.Surprise.MUCH_BETTER, NewsBands.Surprise.BETTER])
		var said: NewsBands.Surprise = WhisperRules.distort(NewsBands.Surprise.AS_EXPECTED, WhisperRules.Source.GOSSIP, rng)
		if WhisperRules.distance(said, NewsBands.Surprise.AS_EXPECTED) >= 2:
			seen_far[said] = true
	assert_eq(seen_far.size(), 2, "both ends, and nothing else")
	assert_true(seen_far.has(NewsBands.Surprise.MUCH_WORSE) and seen_far.has(NewsBands.Surprise.MUCH_BETTER))


## The draws a year uses are the ones kept for it the year before, and the
## first year's are made when the match is opened (D205).
func test_next_years_draws_are_kept_and_then_used() -> void:
	var played: WireMatch = WireMatch.start(SEED, 3, 12)
	assert_not_null(played.state.market.next_draws, "drawn before year 1")
	for _year: int in 12:
		var kept: KeptDraws = played.state.market.next_draws.copy()
		var result: EarningsYearResult = WireMatch.play_year(played.authority)
		assert_eq(result.industry_rolls, kept.industry_rolls, "year %d industries" % result.year)
		assert_eq(result.regimes, kept.regimes, "year %d regimes" % result.year)
		assert_eq(result.growth_rolls, kept.growth_rolls, "year %d growth" % result.year)
	assert_not_null(played.state.market.next_draws, "the final year keeps the settling year's draws (D219)")
	WireMatch.play_year(played.authority)
	assert_true(played.state.is_over)
	assert_null(played.state.market.next_draws, "nothing is drawn after the match is settled")


## Whispers are heard from the end of year 1, and at the end of the final year
## too, about the year that settles the match (D219).
## Nobody can trade in year 0, so there are no whispers then (D207): the
## first round is heard at the end of year 1, and none after the last year.
func test_whispers_start_after_year_one_and_run_to_the_final_year() -> void:
	var fresh: WireMatch = WireMatch.start(SEED, 3, 5)
	assert_null(NewsSelector.latest_whispers(fresh.state), "none in year 0")
	assert_eq(_rounds(fresh.state).size(), 0)
	fresh.play(1)
	var first: WhisperRound = NewsSelector.latest_whispers(fresh.state)
	assert_not_null(first)
	assert_eq(first.year, 1)
	assert_eq(first.about_year(), 2)
	assert_eq(first.lines.size(), NewsSelector.WHISPERS_PER_YEAR)
	assert_false(first.is_settled(fresh.state))
	fresh.play(4)
	assert_not_null(NewsSelector.whispers_for(fresh.state, 5), "the final year has whispers: year 6 settles the match (D219)")
	assert_null(NewsSelector.whispers_for(fresh.state, 0))
	assert_eq(_rounds(fresh.state).size(), 5, "rounds 1 to 5")
	assert_true(first.is_settled(fresh.state))


## The truth a whisper carries is next year's real outcome, worked out again
## here from the year's record: a company's growth roll against its regime the
## year before, an industry's swing.
func test_a_whispers_truth_is_what_next_year_brought() -> void:
	var played: WireMatch = _played()
	var state: GameState = played.state
	var companies: int = 0
	var industries: int = 0
	for round: WhisperRound in _rounds(state):
		var next: EarningsYearResult = MarketReadouts.result_for_year(state, round.about_year())
		if next == null:
			continue  # the final year's round, about the settling year, not played here
		assert_true(round.lines.size() <= NewsSelector.WHISPERS_PER_YEAR + 1, "two, and a squeeze whisper on top")
		var subjects: Dictionary[StringName, bool] = {}
		for line: WhisperRound.Line in round.lines:
			assert_false(subjects.has(line.subject), "two whispers about one subject")
			subjects[line.subject] = true
			if line.is_about_squeeze():
				continue
			var expected: NewsBands.Surprise
			if line.about == NewsBands.Subject.INDUSTRY:
				industries += 1
				expected = WhisperRules.industry_outcome(next.industry_rolls[line.subject])
				assert_true(line.text.contains(state.market.industry_by_id(line.subject).definition.display_name))
			else:
				companies += 1
				var now: CompanyState = MarketReadouts.company_in_year(state, line.subject, round.year)
				expected = WhisperRules.company_outcome(
					now.regime, next.growth_rolls[line.subject], now.profile.payout_policy_percent, state.settings.max_years
				)
				assert_true(line.text.contains(state.stalk_by_id(line.subject).definition.display_name))
			assert_eq(line.truth, expected, "%s heard in year %d" % [line.subject, round.year])
	assert_gt(companies, 0)
	assert_gt(industries, 0)


## A match whose one SHORT trader is 400 shares short of stryker, one year in.
func _shorted_year_one(library: ContentLibrary, seed_value: int) -> GameState:
	var state: GameState = EarningsMarket.new_game_state(library, StalksFixture.make_settings(10))
	state.players.append(PlayerState.new(&"p0", "P0", 10000))
	var trader: NpcTraderDefinition = NpcTraderDefinition.new()
	trader.id = &"short_x"
	trader.display_name = "NPC NAME: test"
	trader.strategy = NpcStrategy.Value.SHORT
	trader.starting_cash = 8000
	trader.conviction = 45
	state.market.desk = NpcDesk.from_definitions([trader] as Array[NpcTraderDefinition])
	state.market.desk.traders[0].set_short(&"stryker", 400)
	EarningsYearResolver.new(library.short_squeeze).advance_year(state, StalksFixture.rng(seed_value))
	return state


## D214: a flagged company makes a squeeze whisper and a squeezed one a crash
## whisper, always Questionable; next year says whether it happened. D218: it
## comes on top of the two ordinary whispers, not in place of one.
func test_squeeze_and_crash_whispers_come_on_top_of_the_two_from_a_questionable_source() -> void:
	var library: ContentLibrary = _library()
	var seen: Dictionary[NewsBands.Subject, int] = {}
	var held: int = 0
	for seed_value: int in 80:
		var state: GameState = _shorted_year_one(library, seed_value)
		var kind: NewsBands.Subject = NewsBands.Subject.CRASH
		var subject: StringName = NewsSelector.squeezed_at_end_of(state, 1)
		if not subject.is_empty():
			var crash_heard: bool = false
			for line: WhisperRound.Line in NewsSelector.whispers_for(state, 1).lines:
				crash_heard = crash_heard or line.about == NewsBands.Subject.CRASH
			if not crash_heard:
				# D220: the crash whisper is heard only as often as the end is likely.
				held += 1
				continue
		if subject.is_empty():
			# Not squeezed: short stryker again at the year's end, as a desk might.
			state.market.desk.traders[0].set_short(&"stryker", 400)
			state.market.whisper_rounds.clear()
			var flagged: Array[StringName] = NewsSelector.flagged_at_end_of(state, 1)
			if flagged.is_empty():
				continue
			kind = NewsBands.Subject.SQUEEZE
			subject = flagged[0]
		var round: WhisperRound = NewsSelector.whispers_for(state, 1)
		assert_eq(round.lines.size(), NewsSelector.WHISPERS_PER_YEAR + 1, "seed %d" % seed_value)
		var special: Array[WhisperRound.Line] = []
		for line: WhisperRound.Line in round.lines:
			if line.is_about_squeeze():
				special.append(line)
			else:
				assert_ne(line.subject, subject, "the other whisper is about something else")
		assert_eq(special.size(), 1, "seed %d: one squeeze or crash whisper" % seed_value)
		if special.size() != 1:
			continue
		var heard: WhisperRound.Line = special[0]
		assert_eq(heard.about, kind, "seed %d" % seed_value)
		assert_eq(heard.subject, subject)
		assert_eq(heard.source, WhisperRules.Source.QUESTIONABLE)
		assert_true(heard.text.contains(state.stalk_by_id(subject).definition.display_name), heard.text)
		seen[kind] = seen.get(kind, 0) + 1

		EarningsYearResolver.new(library.short_squeeze).advance_year(state, StalksFixture.rng(seed_value + 1000))
		var next: EarningsYearResult = MarketReadouts.result_for_year(state, 2)
		var happened: bool = next.squeeze_target() == subject
		if kind == NewsBands.Subject.CRASH:
			happened = next.squeeze_moves.get(subject, 0) < 0
		assert_eq(NewsSelector.squeeze_whisper_came_true(state, round, heard), happened, "seed %d" % seed_value)
	assert_gt(seen.get(NewsBands.Subject.SQUEEZE, 0), 0, "some seed left stryker flagged")
	assert_gt(seen.get(NewsBands.Subject.CRASH, 0), 0, "some seed made a crash whisper")
	assert_gt(held, 0, "and some squeezed seed did not")


## The line heard is one written for the outcome its source told, never for
## the truth when they differ.
func test_the_line_heard_is_written_for_what_the_source_told() -> void:
	var played: WireMatch = _played()
	var by_id: Dictionary[StringName, Whisper] = {}
	for line: Whisper in played.state.market.news.whispers:
		by_id[line.id] = line
	var bent: int = 0
	for round: WhisperRound in _rounds(played.state):
		for line: WhisperRound.Line in round.lines:
			assert_eq(by_id[line.id].outcome, line.said)
			assert_eq(by_id[line.id].about, line.about)
			if line.said != line.truth:
				bent += 1
	assert_gt(bent, 0, "some whispers are wrong")


## Which subjects are picked does not depend on the words, so the company
## whispered about first with the shipped lines is whispered about again here.
func test_a_whisper_written_for_one_subject_beats_a_general_one() -> void:
	var played: WireMatch = _played(SEED, 20)
	var chosen: StringName = &""
	for round: WhisperRound in _rounds(played.state):
		for line: WhisperRound.Line in round.lines:
			if chosen.is_empty() and line.about == NewsBands.Subject.COMPANY:
				chosen = line.subject
	var book: NewsBook = NewsBook.new()
	for outcome: NewsBands.Surprise in WhisperRules.OUTCOMES:
		book.whispers.append(_whisper("general_%d" % outcome, NewsBands.Subject.COMPANY, outcome, &"", "ANY {company}"))
		book.whispers.append(_whisper("ss_%d" % outcome, NewsBands.Subject.COMPANY, outcome, chosen, "ONE COMPANY ONLY"))
		book.whispers.append(_whisper("ind_%d" % outcome, NewsBands.Subject.INDUSTRY, outcome, &"", "IND {industry}"))
	_rechoose(played.state, _with_news(played.library, book))
	var own: int = 0
	for round: WhisperRound in _rounds(played.state):
		for line: WhisperRound.Line in round.lines:
			if line.subject == chosen:
				own += 1
				assert_eq(line.text, "ONE COMPANY ONLY")
			elif line.about == NewsBands.Subject.COMPANY:
				assert_eq(line.text, "ANY %s" % played.state.stalk_by_id(line.subject).definition.display_name)
			else:
				assert_true(line.text.begins_with("IND "))
	assert_gt(own, 0)


# --------------------------------------------------------------- chatter

func test_each_trader_says_its_own_line_for_what_it_did() -> void:
	var played: WireMatch = _played(SEED, 5)
	var state: GameState = played.state
	for year: int in range(1, 6):
		var news: YearNews = NewsSelector.news_for(state, year)
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
		assert_eq(news.chatter.size(), result.desk.trader_ids.size(), "every trader has a line for every situation")
		for trader_id: StringName in result.desk.trader_ids:
			var trader: NpcTraderDefinition = state.market.desk.trader_by_id(trader_id).definition
			assert_eq(news.chatter[trader_id], trader.chatter_for(result.desk.actions[trader_id]))


func test_a_strategy_line_speaks_for_a_trader_with_none_and_fills_its_tokens() -> void:
	var played: WireMatch = _played(SEED, 5)
	var book: NewsBook = NewsBook.new()
	for situation: NpcTraderDefinition.Situation in NpcTraderDefinition.Situation.values():
		var line: NpcChatter = NpcChatter.new()
		line.id = StringName("value_%d" % situation)
		line.strategy = NpcStrategy.Value.VALUE
		line.situation = situation
		line.text = "{trader} on {company}"
		book.chatter.append(line)
	_rechoose(played.state, _with_news(played.library, book))
	var state: GameState = played.state
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, 5)
	var news: YearNews = NewsSelector.news_for(state, 5)
	for trader_id: StringName in result.desk.trader_ids:
		var trader: NpcTraderDefinition = state.market.desk.trader_by_id(trader_id).definition
		if trader.strategy != NpcStrategy.Value.VALUE:
			assert_false(news.chatter.has(trader_id))
			continue
		var target: StalkState = state.stalk_by_id(result.desk.targets[trader_id])
		var company_name: String = target.definition.display_name if target != null else ""
		assert_eq(news.chatter[trader_id], "%s on %s" % [trader.display_name, company_name])


# ------------------------------------------------------------ determinism

func test_the_same_match_makes_the_same_news() -> void:
	assert_eq(_all_news(_played().state), _all_news(_played().state))


func test_choosing_the_news_never_moves_the_match() -> void:
	var quiet: WireMatch = WireMatch.start(SEED, 3, YEARS)
	var reading: WireMatch = WireMatch.start(SEED, 3, YEARS)
	for _year: int in YEARS:
		WireMatch.play_year(quiet.authority)
		WireMatch.play_year(reading.authority)
		NewsSelector.latest(reading.state)
		NewsSelector.latest_whispers(reading.state)
	assert_eq(WireMatch.first_difference(WireMatch.state_lines(quiet.state), WireMatch.state_lines(reading.state)), "")


## A welcomed client, and so a rejoiner, works out the host's news year for
## year from the history it was sent; nothing about the news travels.
func test_a_welcomed_client_makes_the_hosts_news() -> void:
	var played: WireMatch = _played()
	var host_news: PackedStringArray = _all_news(played.state)
	var replica: GameState = GameState.new(GameSettings.new())
	var library: ContentLibrary = ContentLibrary.load_from()
	assert_eq(StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), library), "")
	assert_eq(StateSync.apply_history(replica, StateSync.encode_history(played.state), library), "")
	assert_eq(WireMatch.first_difference(host_news, _all_news(replica)), "")
	assert_gt(host_news.size(), YEARS * 20)


## A client that took the match over goes on making the news the departed host
## would have made.
func test_a_promoted_host_goes_on_making_the_same_news() -> void:
	var played: WireMatch = _played(SEED, 10)
	var replica: GameState = GameState.new(GameSettings.new())
	var library: ContentLibrary = ContentLibrary.load_from()
	StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), library)
	StateSync.apply_history(replica, StateSync.encode_history(played.state), library)
	var opened: Dictionary = HostSession.take_over(
		StubTransport.new(), replica, MatchSetup.load_library(GameMode.Value.STALKLEHEADS),
		&"p1", played.authority.rng_state(),
	)
	assert_eq(String(opened["error"]), "", "take-over should succeed")
	var session: HostSession = opened["session"]
	autofree(session)
	var promoted: MatchAuthority = session._authority
	for _year: int in 10:
		WireMatch.play_year(played.authority)
		WireMatch.play_year(promoted)
	assert_eq(WireMatch.first_difference(_all_news(played.state), _all_news(replica)), "")
