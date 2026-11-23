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
	state.market.whisper_rounds.clear()
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
	assert_eq(library.news.whispers.size(), 10, "five outcomes, for a company and for an industry")
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
	var commentary: EarningsCommentary = EarningsCommentary.new()
	commentary.id = &"e1"
	commentary.company_id = &"nobody"
	commentary.text = "EARNINGS: {compnay}"
	book.earnings_commentary.append(commentary)
	var lie: Whisper = Whisper.new()
	lie.id = &"w1"
	lie.about = NewsBands.Subject.INDUSTRY
	lie.subject = &"stryker"
	lie.outcome = NewsBands.Surprise.ANY
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
	assert_true(_has_error(library, "w1 has no outcome"), "a whisper that foretells nothing")
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
		assert_true(NewsSelector.whispers_for(played.state, year - 1).lines.is_empty(), "heard after year %d" % (year - 1))
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
	assert_null(played.state.market.next_draws, "nothing is drawn after the last year")


## Whispers are heard from the match's start, about year 1, and not at the end
## of the last year, which has no next year.
func test_whispers_are_heard_from_the_start_and_not_after_the_last_year() -> void:
	var fresh: WireMatch = WireMatch.start(SEED, 3, 5)
	var opening: WhisperRound = NewsSelector.latest_whispers(fresh.state)
	assert_not_null(opening)
	assert_eq(opening.year, 0)
	assert_eq(opening.about_year(), 1)
	assert_eq(opening.lines.size(), NewsSelector.WHISPERS_PER_YEAR)
	assert_false(opening.is_settled(fresh.state))
	fresh.play(5)
	assert_null(NewsSelector.whispers_for(fresh.state, 5))
	assert_eq(_rounds(fresh.state).size(), 5, "rounds 0 to 4")
	assert_true(opening.is_settled(fresh.state))


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
		assert_true(round.lines.size() <= NewsSelector.WHISPERS_PER_YEAR)
		var subjects: Dictionary[StringName, bool] = {}
		for line: WhisperRound.Line in round.lines:
			assert_false(subjects.has(line.subject), "two whispers about one subject")
			subjects[line.subject] = true
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
