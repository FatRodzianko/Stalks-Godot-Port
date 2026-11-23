extends GutTest
## StalkleHeads phase S8: the news (docs/stalkleheads-design.md §8;
## decisions.md D199-D203).
##
## Three things are under test:
##
## - **the content and its validator** - what ships loads clean, every slot
##   that can come up has a line to fill it, and each kind of mistake an author
##   can make is reported rather than producing a line that never fires;
## - **the selector** - the bands, the bag, the preference for specific lines,
##   the empty slot, the whispers' honesty, the chatter;
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
	return lines


## A fresh library whose news is only `lines`, everything else shipped.
func _with_news(library: ContentLibrary, book: NewsBook) -> NewsContent:
	library.news = NewsContent.build([book] as Array[NewsBook], [] as Array[NpcTraderDefinition])
	return library.news


func _headline(id: String, mood: NewsBands.Mood, move: NewsBands.Move) -> MarketHeadline:
	var line: MarketHeadline = MarketHeadline.new()
	line.id = StringName(id)
	line.mood = mood
	line.move = move
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
	for result: YearResult in state.history:
		(result as EarningsYearResult).news = null


# ---------------------------------------------------------------- content

func test_the_shipped_news_loads_and_validates_clean() -> void:
	var library: ContentLibrary = _library()
	assert_eq(library.errors, [] as Array[String])
	assert_eq(library.warnings, [] as Array[String])
	assert_eq(library.news.headlines.size(), 6, "one per mood and move that can happen")
	assert_eq(library.news.industry_reports.size(), 30, "five moves for each of six industries")
	assert_eq(library.news.earnings_commentary.size(), 25, "five regimes by five surprises")
	assert_eq(library.news.whispers.size(), NewsBands.ALL_TRIGGERS.size(), "one per trigger")
	assert_eq(library.news.chatter.size(), 24 * 5, "every trader's five lines")


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
			for line: MarketHeadline in news.headlines:
				found = found or ((line.mood in [mood, NewsBands.Mood.ANY]) and (line.move in [move, NewsBands.Move.ANY]))
			assert_true(found, "a headline for %d %d" % [mood, move])
	for industry: IndustryDefinition in library.industries:
		for move: NewsBands.Move in [NewsBands.Move.CRASH, NewsBands.Move.DOWN, NewsBands.Move.FLAT, NewsBands.Move.UP, NewsBands.Move.SURGE]:
			var found: bool = false
			for line: IndustryReport in news.industry_reports:
				var fits_industry: bool = line.industry_id in [industry.id, &""]
				found = found or (fits_industry and line.move in [move, NewsBands.Move.ANY])
			assert_true(found, "a report for %s %d" % [industry.id, move])
	for trigger: NewsBands.Trigger in NewsBands.ALL_TRIGGERS:
		var found: bool = false
		for line: Whisper in news.whispers:
			found = found or line.trigger == trigger
		assert_true(found, "a whisper for trigger %d" % trigger)


func test_the_validator_reports_every_kind_of_mistake() -> void:
	var library: ContentLibrary = _library()
	var book: NewsBook = NewsBook.new()
	var report: IndustryReport = IndustryReport.new()
	report.id = &"r1"
	report.industry_id = &"energee"
	report.text = "x"
	book.industry_reports.append(report)
	var commentary: EarningsCommentary = EarningsCommentary.new()
	commentary.id = &"e1"
	commentary.company_id = &"nobody"
	commentary.text = "EARNINGS: {compnay}"
	book.earnings_commentary.append(commentary)
	var lie: Whisper = Whisper.new()
	lie.id = &"w1"
	lie.trigger = NewsBands.Trigger.SECTOR_RUN
	lie.subject = &"stryker"
	lie.truth_chance_percent = 150
	lie.text = "WHISPER: {company}"
	book.whispers.append(lie)
	var chatter: NpcChatter = NpcChatter.new()
	chatter.id = &"c1"
	chatter.npc_id = &"nobody_1"
	chatter.text = ""
	book.chatter.append(chatter)
	var headline: MarketHeadline = _headline("e1", NewsBands.Mood.BULL, NewsBands.Move.UP)
	headline.set("move", 99)
	book.headlines.append(headline)
	_with_news(library, book)
	library.validate()

	assert_false(library.is_valid())
	assert_true(_has_error(library, "names industry energee"), "an industry that does not exist")
	assert_true(_has_error(library, "names company nobody"), "a company that does not exist")
	assert_true(_has_error(library, "uses {compnay}"), "a misspelt token")
	assert_true(_has_error(library, "uses {company}"), "a token the kind of line does not fill")
	assert_true(_has_error(library, "truth chance of 150"), "a truth chance out of range")
	assert_true(_has_error(library, "stryker, which is not an industry"), "a subject of the wrong kind")
	assert_true(_has_error(library, "names trader nobody_1"), "a trader that does not exist")
	assert_true(_has_error(library, "c1 has no text"), "an empty line")
	assert_true(_has_error(library, "Duplicate news id: e1"), "two lines with one id")
	assert_true(_has_error(library, "unknown move (99)"), "a band that does not exist")


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
		book.headlines.append(_headline(id, NewsBands.Mood.ANY, NewsBands.Move.ANY))
	_rechoose(played.state, _with_news(played.library, book))
	var result: EarningsYearResult = played.state.history[0]
	var counts: Dictionary[StringName, int] = {&"a": 1, &"b": 0, &"c": 1}
	assert_eq(NewsSelector.select(played.state, result, counts).headline, "b")


func test_no_line_repeats_until_every_line_has_had_its_turn() -> void:
	var played: WireMatch = _played(SEED, 12)
	var book: NewsBook = NewsBook.new()
	for id: String in ["a", "b", "c", "d"]:
		book.headlines.append(_headline(id, NewsBands.Mood.ANY, NewsBands.Move.ANY))
	_rechoose(played.state, _with_news(played.library, book))
	var seen: PackedStringArray = []
	for year: int in range(1, 13):
		seen.append(NewsSelector.news_for(played.state, year).headline)
	for cycle: int in 3:
		var slice: PackedStringArray = seen.slice(cycle * 4, cycle * 4 + 4)
		slice.sort()
		assert_eq(slice, PackedStringArray(["a", "b", "c", "d"]), "cycle %d" % cycle)


func test_a_slot_nothing_matches_stays_empty() -> void:
	var played: WireMatch = _played(SEED, 5)
	var book: NewsBook = NewsBook.new()
	book.headlines.append(_headline("never", NewsBands.Mood.BULL, NewsBands.Move.CRASH))
	_rechoose(played.state, _with_news(played.library, book))
	for year: int in range(1, 6):
		var news: YearNews = NewsSelector.news_for(played.state, year)
		assert_eq(news.headline, "", "year %d" % year)
		assert_true(news.industry_reports.is_empty())
		assert_true(news.commentary.is_empty())
		assert_true(news.whispers.is_empty())
		assert_true(news.chatter.is_empty())


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


func test_commentary_names_its_company_and_matches_its_regime() -> void:
	var played: WireMatch = _played()
	var state: GameState = played.state
	for year: int in range(1, YEARS + 1):
		var news: YearNews = NewsSelector.news_for(state, year)
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
		for company_id: StringName in news.commentary:
			var text: String = news.commentary[company_id]
			assert_true(text.contains(state.stalk_by_id(company_id).definition.display_name))
			var regime: String = EarningsRegime.name_of(result.regimes[company_id]).to_lower()
			assert_true(text.contains(", %s," % regime), "%s in year %d: %s" % [company_id, year, text])


# ------------------------------------------------------------- whispers

func test_an_honest_whisper_is_true_and_a_lie_is_not() -> void:
	var played: WireMatch = _played()
	var state: GameState = played.state
	var honest: int = 0
	var lies: int = 0
	for year: int in range(1, YEARS + 1):
		var news: YearNews = NewsSelector.news_for(state, year)
		assert_true(news.whispers.size() <= NewsSelector.WHISPERS_PER_YEAR)
		for whisper: YearNews.WhisperLine in news.whispers:
			var trigger: NewsBands.Trigger = _whisper_by_id(state, whisper.id).trigger
			assert_eq(NewsSelector.trigger_holds(state, year, trigger, whisper.subject), whisper.is_true,
				"%s about %s in year %d" % [whisper.id, whisper.subject, year])
			if whisper.is_true:
				honest += 1
			else:
				lies += 1
	assert_gt(honest, 0)
	assert_gt(lies, 0, "at 75%, thirty years should hold a lie")


func _whisper_by_id(state: GameState, id: StringName) -> Whisper:
	for line: Whisper in state.market.news.whispers:
		if line.id == id:
			return line
	return null


func _single_whisper(state: GameState, library: ContentLibrary, truth: int, subject: StringName) -> void:
	var book: NewsBook = NewsBook.new()
	var line: Whisper = Whisper.new()
	line.id = &"w"
	line.trigger = NewsBands.Trigger.PE_ABOVE_INDUSTRY
	line.truth_chance_percent = truth
	line.subject = subject
	line.text = "W {company}"
	book.whispers.append(line)
	_rechoose(state, _with_news(library, book))


func test_a_whisper_at_one_hundred_never_lies_and_at_zero_always_does() -> void:
	var played: WireMatch = _played()
	_single_whisper(played.state, played.library, 100, &"")
	var shown: int = 0
	for year: int in range(1, YEARS + 1):
		for whisper: YearNews.WhisperLine in NewsSelector.news_for(played.state, year).whispers:
			assert_true(whisper.is_true)
			shown += 1
	assert_gt(shown, 0)
	_single_whisper(played.state, played.library, 0, &"")
	for year: int in range(1, YEARS + 1):
		for whisper: YearNews.WhisperLine in NewsSelector.news_for(played.state, year).whispers:
			assert_false(whisper.is_true)


## A whisper tied to one company has nothing else to name, so it cannot lie:
## when its roll says lie it is not shown (D201).
func test_a_whisper_about_one_company_is_never_a_lie() -> void:
	var played: WireMatch = _played()
	var state: GameState = played.state
	var subject: StringName = &""
	for year: int in range(1, YEARS + 1):
		for company: CompanyState in state.market.companies:
			if subject.is_empty() and NewsSelector.trigger_holds(state, year, NewsBands.Trigger.PE_ABOVE_INDUSTRY, company.id):
				subject = company.id
	assert_false(subject.is_empty())
	_single_whisper(state, played.library, 0, subject)
	for year: int in range(1, YEARS + 1):
		assert_true(NewsSelector.news_for(state, year).whispers.is_empty(), "year %d" % year)
	_single_whisper(state, played.library, 100, subject)
	var shown: int = 0
	for year: int in range(1, YEARS + 1):
		for whisper: YearNews.WhisperLine in NewsSelector.news_for(state, year).whispers:
			assert_eq(whisper.subject, subject)
			shown += 1
	assert_gt(shown, 0)


func test_the_triggers_read_real_state() -> void:
	var played: WireMatch = _played()
	var state: GameState = played.state
	for year: int in range(1, YEARS + 1):
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
		for company_id: StringName in NewsSelector.subjects_for(state, year, NewsBands.Trigger.NEAR_SPLIT):
			var after: CompanyState = result.companies_after[company_id]
			assert_eq(NewsSelector.trigger_holds(state, year, NewsBands.Trigger.NEAR_SPLIT, company_id), after.price > 260)
			assert_eq(
				NewsSelector.trigger_holds(state, year, NewsBands.Trigger.HIGH_SHORT_INTEREST, company_id),
				result.short_interest_flagged.has(company_id),
			)
			var near_failure: bool = after.regime == EarningsRegime.Value.DISTRESS and after.price < 20
			assert_eq(NewsSelector.trigger_holds(state, year, NewsBands.Trigger.NEAR_FAILURE, company_id), near_failure)
		for industry: IndustryState in state.market.industries:
			if year < 3:
				assert_false(NewsSelector.trigger_holds(state, year, NewsBands.Trigger.SECTOR_RUN, industry.id))
	# A failed company is nobody's subject.
	for year: int in range(1, YEARS + 1):
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
		for company_id: StringName in NewsSelector.subjects_for(state, year, NewsBands.Trigger.MARGIN_SLIPPING):
			assert_gt(result.companies_after[company_id].price, 0)


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
