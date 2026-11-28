class_name NewsSelector
extends RefCounted
## Chooses a StalkleHeads year's news: a headline and an industry report per
## industry, earnings commentary and company news per company and each NPC
## trader's chatter (docs/stalkleheads-design.md §8.2); and, heard at each
## year's end about the next, the whispers (§8.4, `whispers_for`). Pure: no
## nodes, no autoloads, and no draw from the match's own generator. The one
## kind of news that moves prices, market news, is the economy's to choose
## (`MarketNewsRules`).
##
## **How a line is chosen (§8.2).** For each slot, gather every line whose
## conditions match this year and whose required lines have all been shown in
## an earlier year (D210); if any of those is a follow-up - a line that
## requires another - draw from the follow-ups; otherwise prefer the lines
## written for this exact industry, company or trader over the general ones;
## then draw one. **If nothing matches, the slot stays empty**: no generic line
## stands in.
##
## **The bag, kept in the history (decisions.md D200).** Lines are drawn
## without replacement the way `EventPool` draws events: among the matching
## lines, only those drawn the fewest times so far in this match are eligible,
## so no line comes round again until every other line that could fill that
## slot has had its turn. The counts are read from the earlier years' news,
## which every peer already holds - so, unlike the event bags (D177), nothing
## has to be kept in the market or sent in the snapshot.
##
## **Its own generator, seeded from the year (D200).** Each year's draws come
## from a `RandomNumberGenerator` seeded with a hash of the year's own draws
## (its number, the squeeze roll, the industry rolls and the companies' growth
## rolls) - the inputs every peer receives for the year anyway (D178). So the
## news is the same on the host, on every client, on a player who rejoins and
## on a host that takes over, and **choosing it never moves the match**: the
## match's generator is not touched, so prices are what they were before news
## existed. That is the property the NPC-thoughts note in design §14 asks of
## anything presentational.
##
## **Lazily, and once.** `news_for` works a year out the first time a screen
## asks, keeps it on the year's `EarningsYearResult.news`, and works out any
## earlier year still missing first, because a year's bag reads theirs.


## Whispers heard at the end of each year, each about a different company or
## industry (design §8.4).
const WHISPERS_PER_YEAR: int = 2

## Every squeeze and crash whisper is from this source (D214, D220): neither a
## squeeze nor its end is ever certain.
const SQUEEZE_WHISPER_SOURCE: WhisperRules.Source = WhisperRules.Source.QUESTIONABLE

## The first year at whose end whispers are heard. Not 0: trading opens in
## year 1, so a whisper about year 1 could not be acted on (D207).
const FIRST_WHISPER_YEAR: int = 1

## Move band edges, in percent (§8.1): CRASH at or below -15, DOWN below -3,
## FLAT from -3 to +3, UP below +15, SURGE at or above +15.
const CRASH_AT: float = -15.0
const FLAT_FROM: float = -3.0
const FLAT_TO: float = 3.0
const SURGE_AT: float = 15.0

## Surprise band edges: revenue growth this many points from what the regime
## leads one to expect (`expected_growth`) is BETTER or WORSE; this many is
## MUCH so (D202).
const SURPRISE_POINTS: float = 3.0
const MUCH_SURPRISE_POINTS: float = 8.0

## The tokens a line may contain, filled in when it is chosen.
const COMPANY_TOKEN: String = "{company}"
const INDUSTRY_TOKEN: String = "{industry}"
const TRADER_TOKEN: String = "{trader}"


## The latest year's news, or null before year 1 or outside StalkleHeads.
static func latest(state: GameState) -> YearNews:
	if state == null or state.market == null:
		return null
	var latest_result: YearResult = state.latest_result()
	if latest_result == null:
		return null
	return news_for(state, latest_result.year)


## `year`'s news, worked out now if no screen has asked for it before. Null for
## a year not played.
static func news_for(state: GameState, year: int) -> YearNews:
	if state.market == null:
		return null
	var target: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	if target == null:
		return null
	if target.news != null:
		return target.news
	var counts: Dictionary[StringName, int] = {}
	var shown: Dictionary[StringName, bool] = {}
	for each: int in range(1, year + 1):
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, each)
		if result == null:
			continue
		if result.news == null:
			result.news = select(state, result, counts, shown)
		for id: StringName in result.news.drawn:
			counts[id] = counts.get(id, 0) + 1
		_add_shown_in(state, each, shown)
	return target.news


## The ids of every news line shown in years 1 to `last_year`: each year's
## news, its market news and the whispers heard at its end. What a line's
## `requires` is checked against (D210): a line may follow one shown in an
## earlier year, never one shown in its own.
static func shown_through(state: GameState, last_year: int) -> Dictionary[StringName, bool]:
	var shown: Dictionary[StringName, bool] = {}
	for year: int in range(1, last_year + 1):
		var news: YearNews = news_for(state, year)
		if news != null:
			for id: StringName in news.drawn:
				shown[id] = true
		_add_shown_in(state, year, shown)
	return shown


## Adds year `year`'s market news and the whispers heard at its end to `shown`.
static func _add_shown_in(state: GameState, year: int, shown: Dictionary[StringName, bool]) -> void:
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	if result != null and result.market_news != null:
		shown[result.market_news.id] = true
	var round: WhisperRound = whispers_for(state, year)
	if round != null:
		for id: StringName in round.drawn:
			shown[id] = true


## One year's news, given how many times each line was drawn before it and
## which lines were shown in earlier years. Public for tests; screens use
## `news_for`.
static func select(
	state: GameState,
	result: EarningsYearResult,
	counts: Dictionary[StringName, int],
	shown: Dictionary[StringName, bool] = {},
) -> YearNews:
	var news: YearNews = YearNews.new()
	news.year = result.year
	var content: NewsContent = state.market.news
	if content == null:
		return news
	var pick: Pick = Pick.new(counts, shown, rng_for(result))
	_select_reports(state, content, result, pick, news)
	_write_industry_reports(state, result, news)
	_write_earnings(state, result, news)
	_select_company_news(state, content, result, pick, news)
	_select_chatter(state, content, result, pick, news)
	return news


## What every draw in a year needs: the bag's counts, what was shown before,
## and the year's own generator.
class Pick:
	extends RefCounted
	var counts: Dictionary[StringName, int] = {}
	var shown: Dictionary[StringName, bool] = {}
	var rng: RandomNumberGenerator

	func _init(
		bag_counts: Dictionary[StringName, int],
		shown_before: Dictionary[StringName, bool],
		generator: RandomNumberGenerator,
	) -> void:
		counts = bag_counts
		shown = shown_before
		rng = generator

	## One line from the candidates written for this subject (`own`) and for
	## any (`general`): follow-ups not yet shown first, then own, then general
	## (D210).
	func choose(own: Array[Resource], general: Array[Resource]) -> Resource:
		var follow_ups: Array[Resource] = []
		var own_ready: Array[Resource] = []
		var general_ready: Array[Resource] = []
		for line: Resource in own:
			if _ready(line):
				own_ready.append(line)
		for line: Resource in general:
			if _ready(line):
				general_ready.append(line)
		for line: Resource in own_ready + general_ready:
			if NewsSelector.is_waiting_follow_up(line, shown):
				follow_ups.append(line)
		if not follow_ups.is_empty():
			return NewsSelector._draw(follow_ups, counts, rng)
		return NewsSelector._draw(NewsSelector._preferred(own_ready, general_ready), counts, rng)

	func _ready(line: Resource) -> bool:
		var required: Array[StringName] = line.get("requires")
		return MarketNewsRules.requirements_met(required, shown)


## True for a follow-up that has not been shown yet: a line that requires
## another and has never been shown itself. Such a line comes first once it
## may be drawn; after it has been shown once it is an ordinary line, or it
## would be drawn every year from then on (D210).
static func is_waiting_follow_up(line: Resource, shown: Dictionary[StringName, bool]) -> bool:
	var required: Array[StringName] = line.get("requires")
	return not required.is_empty() and not shown.has(line.get("id"))


## The year's own generator: seeded from what the year drew, which every peer
## holds, so every peer makes the same draws (D200).
static func rng_for(result: EarningsYearResult) -> RandomNumberGenerator:
	var parts: PackedStringArray = [str(result.year), str(result.squeeze_roll)]
	for key: StringName in _sorted_keys(result.industry_rolls.keys()):
		parts.append("%s=%d" % [key, result.industry_rolls[key]])
	for key: StringName in _sorted_keys(result.growth_rolls.keys()):
		parts.append("%s=%d" % [key, result.growth_rolls[key]])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = ",".join(parts).hash()
	return rng


# ------------------------------------------------------------------ bands

static func move_band(percent: float) -> NewsBands.Move:
	if percent <= CRASH_AT:
		return NewsBands.Move.CRASH
	if percent < FLAT_FROM:
		return NewsBands.Move.DOWN
	if percent <= FLAT_TO:
		return NewsBands.Move.FLAT
	if percent < SURGE_AT:
		return NewsBands.Move.UP
	return NewsBands.Move.SURGE


## Revenue growth against what the regime leads one to expect (§8.1).
static func surprise_band(growth_percent: float, expected_percent: float) -> NewsBands.Surprise:
	var gap: float = growth_percent - expected_percent
	if gap <= -MUCH_SURPRISE_POINTS:
		return NewsBands.Surprise.MUCH_WORSE
	if gap <= -SURPRISE_POINTS:
		return NewsBands.Surprise.WORSE
	if gap < SURPRISE_POINTS:
		return NewsBands.Surprise.AS_EXPECTED
	if gap < MUCH_SURPRISE_POINTS:
		return NewsBands.Surprise.BETTER
	return NewsBands.Surprise.MUCH_BETTER


## The growth a company's regime leads one to expect: the middle of the
## regime's growth band, put through the same long-match damping and payout
## retention its real growth goes through (`CompanyState.move_accounts`), with
## no help or harm from its industry. So the surprise is the growth roll's luck
## plus the industry's year, and a 99-year match, whose growth is halved, is
## not "much worse than expected" every year (decisions.md D202).
static func expected_growth(
	regime: EarningsRegime.Value,
	payout_policy_percent: int,
	match_years: int,
) -> float:
	var band: Vector2i = RegimeRules.GROWTH_BAND[regime]
	var middle: float = float(band.x + band.y) / 2.0 * RegimeRules.growth_damping(match_years)
	return DividendRules.retained_growth(middle, payout_policy_percent)


static func mood_band(mood: MarketMood.Value) -> NewsBands.Mood:
	if mood == MarketMood.Value.BULL:
		return NewsBands.Mood.BULL
	return NewsBands.Mood.BEAR


# ------------------------------------------------------------------ slots

static func _select_reports(
	state: GameState,
	content: NewsContent,
	result: EarningsYearResult,
	pick: Pick,
	news: YearNews,
) -> void:
	var mood: NewsBands.Mood = mood_band(result.mood)
	for industry: IndustryState in state.market.industries:
		if not result.industry_performance.has(industry.id):
			continue
		var move: NewsBands.Move = move_band(result.industry_performance[industry.id])
		var own: Array[Resource] = []
		var general: Array[Resource] = []
		for line: IndustryReport in content.industry_reports:
			if not (_mood_fits(line.mood, mood) and _move_fits(line.move, move)):
				continue
			if line.industry_id == industry.id:
				own.append(line)
			elif line.industry_id.is_empty():
				general.append(line)
		var chosen: IndustryReport = pick.choose(own, general) as IndustryReport
		if chosen != null:
			news.industry_reports[industry.id] = _fill(chosen.text, {INDUSTRY_TOKEN: industry.definition.display_name})
			news.drawn.append(chosen.id)


## The EARNINGS report (D215): for each company that had an earnings season,
## its revenue growth against what its regime led one to expect.
static func _write_earnings(state: GameState, result: EarningsYearResult, news: YearNews) -> void:
	for company: CompanyState in state.market.companies:
		var after: CompanyState = result.companies_after.get(company.id, null)
		if not result.regimes.has(company.id) or after == null:
			continue
		var regime: EarningsRegime.Value = result.regimes[company.id]
		var expected: float = expected_growth(regime, company.profile.payout_policy_percent, state.settings.max_years)
		var surprise: NewsBands.Surprise = surprise_band(after.revenue_growth_percent, expected)
		news.earnings_surprise[company.id] = surprise
		news.earnings[company.id] = ReportWriter.earnings_sentence(
			_company_tokens(state, company.id)[COMPANY_TOKEN], after.revenue_growth_percent, surprise, regime)


## The INDUSTRY REPORT (D212, D215): for each industry, how its year went
## against what was expected, and what is expected of it next year, written by
## `ReportWriter` from the numbers.
static func _write_industry_reports(state: GameState, result: EarningsYearResult, news: YearNews) -> void:
	for industry: IndustryState in state.market.industries:
		if not result.industry_performance.has(industry.id):
			continue
		var move: NewsBands.Move = move_band(result.industry_performance[industry.id])
		var surprise: NewsBands.Surprise = surprise_band(float(result.industry_rolls.get(industry.id, 0)), 0.0)
		var last_move: NewsBands.Move = NewsBands.Move.ANY
		if result.year > 1:
			last_move = move_band(industry_move_in(state, industry.id, result.year - 1))
		var outlook: NewsBands.Move = move_band(expected_industry_move(state, industry.id, result.year))
		news.industry_years[industry.id] = ReportWriter.year_sentence(
			industry.definition.display_name, move, surprise, last_move)
		news.industry_outlooks[industry.id] = ReportWriter.outlook_sentence(outlook)


## IN THE NEWS (D211): for each company that traded through the year, a line
## chosen by how far its own price moved.
static func _select_company_news(
	state: GameState,
	content: NewsContent,
	result: EarningsYearResult,
	pick: Pick,
	news: YearNews,
) -> void:
	for company: CompanyState in state.market.companies:
		if not result.regimes.has(company.id):
			continue
		var move: NewsBands.Move = move_band(company_move_percent(result, company.id))
		var own: Array[Resource] = []
		var general: Array[Resource] = []
		for line: CompanyNews in content.company_news:
			if not _move_fits(line.move, move):
				continue
			_sort_into(line, line.company_id, company.id, own, general)
		var chosen: CompanyNews = pick.choose(own, general) as CompanyNews
		if chosen != null:
			news.company_news[company.id] = _fill(chosen.text, _company_tokens(state, company.id))
			news.drawn.append(chosen.id)


## A company's price move in `result`'s year, in percent: from its posted price
## before the year to its price before any split, so a split is not a crash.
## -100 for a company that failed.
static func company_move_percent(result: EarningsYearResult, company_id: StringName) -> float:
	var ledger: PriceLedger = result.ledger_for(company_id)
	if ledger == null or ledger.price_before <= 0:
		return 0.0
	if ledger.price_after <= TradeRules.BANKRUPT_AT_OR_BELOW:
		return -100.0
	return float(ledger.price_after - ledger.price_before) * 100.0 / float(ledger.price_before)


## An industry's move in `year`, in percent; 0 before year 1.
static func industry_move_in(state: GameState, industry_id: StringName, year: int) -> float:
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	if result == null:
		return 0.0
	return result.industry_performance.get(industry_id, 0.0)


## What is expected of an industry the year after `year`, in percent: the part
## of its move that carries over from `year` plus the market's lean, before the
## next swing is drawn (`IndustryState.performance_after` with no swing). Only
## public figures: never the kept draw (D212).
static func expected_industry_move(state: GameState, industry_id: StringName, year: int) -> float:
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	if result == null:
		return 0.0
	var sentiment: float = ValuationRules.clamp_sentiment(result.index_move_percent)
	return IndustryState.performance_after(0, result.industry_performance.get(industry_id, 0.0), sentiment)


static func _sort_into(
	line: Resource,
	line_subject: StringName,
	subject: StringName,
	own: Array[Resource],
	general: Array[Resource],
) -> void:
	if line_subject == subject:
		own.append(line)
	elif line_subject.is_empty():
		general.append(line)


static func _select_chatter(
	state: GameState,
	content: NewsContent,
	result: EarningsYearResult,
	pick: Pick,
	news: YearNews,
) -> void:
	if result.desk == null:
		return
	for trader_id: StringName in result.desk.trader_ids:
		var trader: NpcTraderState = state.market.desk.trader_by_id(trader_id)
		if trader == null:
			continue
		var situation: NpcTraderDefinition.Situation = result.desk.actions.get(trader_id, NpcTraderDefinition.Situation.HELD)
		var own: Array[Resource] = []
		var general: Array[Resource] = []
		for line: NpcChatter in content.chatter:
			if line.situation != situation:
				continue
			if line.npc_id == trader_id:
				own.append(line)
			elif line.npc_id.is_empty() and line.strategy == trader.definition.strategy:
				general.append(line)
		var chosen: NpcChatter = pick.choose(own, general) as NpcChatter
		if chosen == null:
			continue
		var target: StringName = result.desk.targets.get(trader_id, &"")
		var company_name: String = ""
		var row: StalkState = state.stalk_by_id(target)
		if row != null:
			company_name = row.definition.display_name
		news.chatter[trader_id] = _fill(chosen.text, {
			TRADER_TOKEN: trader.definition.display_name,
			COMPANY_TOKEN: company_name,
		})
		news.drawn.append(chosen.id)


# --------------------------------------------------------------- whispers

## The whispers heard at the end of `year`, about the next year, worked out
## now if no screen has asked before. Null outside StalkleHeads, for a year not
## yet reached, for the last year, which has no next year to whisper about, and
## for year 0: nobody can trade in year 0, so a whisper about year 1 could
## never be acted on (decisions.md D207). The first round is heard at the end
## of year 1.
##
## Rounds are worked out in order and cached on `EarningsMarket.whisper_rounds`,
## because a round's bag counts the lines drawn in the rounds before it. A
## round is the same whether the year it is about has been played or not: its
## draws are the same numbers, read from the kept draws before and from that
## year's record after (`draws_about`).
static func whispers_for(state: GameState, year: int) -> WhisperRound:
	if state == null or state.market == null or year < FIRST_WHISPER_YEAR or year > state.year:
		return null
	var market: EarningsMarket = state.market
	if market.whisper_rounds.has(year):
		return market.whisper_rounds[year]
	if draws_about(state, year + 1) == null:
		return null
	var counts: Dictionary[StringName, int] = {}
	for each: int in range(FIRST_WHISPER_YEAR, year + 1):
		var round: WhisperRound = market.whisper_rounds.get(each, null)
		if round == null:
			var draws: KeptDraws = draws_about(state, each + 1)
			if draws == null:
				continue
			round = select_whispers(state, each, draws, counts, shown_through(state, each - 1))
			market.whisper_rounds[each] = round
		for id: StringName in round.drawn:
			counts[id] = counts.get(id, 0) + 1
	return market.whisper_rounds.get(year, null)


## The whispers heard most recently: at the end of the year just played. Null
## in year 0.
static func latest_whispers(state: GameState) -> WhisperRound:
	if state == null:
		return null
	return whispers_for(state, state.year)


## Every round heard so far, oldest first, the latest included.
static func whisper_history(state: GameState) -> Array[WhisperRound]:
	var rounds: Array[WhisperRound] = []
	if state == null or state.market == null:
		return rounds
	for year: int in range(FIRST_WHISPER_YEAR, state.year + 1):
		var round: WhisperRound = whispers_for(state, year)
		if round != null:
			rounds.append(round)
	return rounds


## The industry and earnings draws of `about_year`: from its record once it has
## been played, from the market's kept draws when it is next, or null.
static func draws_about(state: GameState, about_year: int) -> KeptDraws:
	if about_year <= state.year:
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, about_year)
		if result == null:
			return null
		return KeptDraws.of_year(result)
	if about_year == state.year + 1:
		return state.market.next_draws
	return null


## One round, given how many times each line was drawn before it and which
## lines were shown in earlier years. Public for tests; screens use
## `whispers_for`.
##
## **A squeeze whisper first, if there is one to hear (D214).** While a
## company is squeezed, a whisper that its squeeze is ending (CRASH) is heard
## as often as the squeeze would end next year on what is known now: its fuel
## left and this year's mood (`ShortInterestRules.end_chance_percent`, D220).
## So it is heard more as the end nears, and can still be wrong. If none is
## heard, while a company is flagged, one says a squeeze is coming (SQUEEZE).
## Both are from a Questionable source.
##
## Then `WHISPERS_PER_YEAR` more, on top of it (D218), so a squeeze never takes
## the place of an ordinary whisper: subjects are picked evenly
## from every industry and every company still trading, without repeats. For
## each: its true outcome (`WhisperRules`), a source, the outcome that source
## tells, and a line written for that outcome - one written for this very
## subject if there is any. With no line for it, that whisper is not heard, and
## the rest go on.
##
## The last three arguments are the game's own constants unless the balance
## tool is sweeping them (decisions.md D236): how many ordinary whispers a
## round, each source's odds, and whether a squeeze or crash whisper is heard.
static func select_whispers(
	state: GameState,
	year: int,
	draws: KeptDraws,
	counts: Dictionary[StringName, int],
	shown: Dictionary[StringName, bool] = {},
	per_year: int = WHISPERS_PER_YEAR,
	odds: Dictionary[WhisperRules.Source, Vector2i] = WhisperRules.ODDS,
	squeeze_whispers: bool = true,
) -> WhisperRound:
	var round: WhisperRound = WhisperRound.new()
	round.year = year
	var content: NewsContent = state.market.news
	if content == null:
		return round
	var rng: RandomNumberGenerator = whisper_rng(year, draws)
	var pick: Pick = Pick.new(counts, shown, rng)
	var special: StringName = &""
	if squeeze_whispers:
		special = _select_squeeze_whisper(state, year, content, pick, round)
	var subjects: Array[StringName] = []
	var kinds: Array[NewsBands.Subject] = []
	for industry: IndustryState in state.market.industries:
		if draws.industry_rolls.has(industry.id):
			subjects.append(industry.id)
			kinds.append(NewsBands.Subject.INDUSTRY)
	for company: CompanyState in state.market.companies:
		if draws.regimes.has(company.id) and company.id != special:
			subjects.append(company.id)
			kinds.append(NewsBands.Subject.COMPANY)

	for _slot: int in per_year:
		if subjects.is_empty():
			break
		var which: int = rng.randi_range(0, subjects.size() - 1)
		var subject: StringName = subjects[which]
		var kind: NewsBands.Subject = kinds[which]
		subjects.remove_at(which)
		kinds.remove_at(which)
		var truth: NewsBands.Surprise = whisper_truth(state, year, draws, subject, kind)
		var source: WhisperRules.Source = WhisperRules.roll_source(rng)
		var said: NewsBands.Surprise = WhisperRules.distort(truth, source, rng, odds)
		var own: Array[Resource] = []
		var general: Array[Resource] = []
		for line: Whisper in content.whispers:
			if line.about != kind or line.outcome != said:
				continue
			if line.subject == subject:
				own.append(line)
			elif line.subject.is_empty():
				general.append(line)
		var chosen: Whisper = pick.choose(own, general) as Whisper
		if chosen == null:
			continue
		var heard: WhisperRound.Line = WhisperRound.Line.new()
		heard.id = chosen.id
		heard.subject = subject
		heard.about = kind
		heard.source = source
		heard.said = said
		heard.truth = truth
		if kind == NewsBands.Subject.INDUSTRY:
			heard.text = _fill(chosen.text, {INDUSTRY_TOKEN: _industry_name(state, subject)})
		else:
			heard.text = _fill(chosen.text, _company_tokens(state, subject))
		round.lines.append(heard)
		round.drawn.append(chosen.id)
	return round


## The squeeze or crash whisper of a round, if one is heard; returns the
## company it is about, or empty.
static func _select_squeeze_whisper(
	state: GameState,
	year: int,
	content: NewsContent,
	pick: Pick,
	round: WhisperRound,
) -> StringName:
	var subject: StringName = crash_whisper_subject(state, year, pick.rng)
	var kind: NewsBands.Subject = NewsBands.Subject.CRASH
	if subject.is_empty():
		var flagged: Array[StringName] = flagged_at_end_of(state, year)
		if flagged.is_empty():
			return &""
		subject = flagged[0]
		kind = NewsBands.Subject.SQUEEZE
	var own: Array[Resource] = []
	var general: Array[Resource] = []
	for line: Whisper in content.whispers:
		if line.about == kind:
			_sort_into(line, line.subject, subject, own, general)
	var chosen: Whisper = pick.choose(own, general) as Whisper
	if chosen == null:
		return &""
	var heard: WhisperRound.Line = WhisperRound.Line.new()
	heard.id = chosen.id
	heard.subject = subject
	heard.about = kind
	heard.source = SQUEEZE_WHISPER_SOURCE
	heard.text = _fill(chosen.text, _company_tokens(state, subject))
	round.lines.append(heard)
	round.drawn.append(chosen.id)
	return subject


## The company whose squeeze was still in its price at the end of `year`,
## lowest id first if there are several, or empty.
static func squeezed_at_end_of(state: GameState, year: int) -> StringName:
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	if result == null:
		return &""
	var ids: Array[StringName] = _sorted_keys(result.companies_after.keys())
	for id: StringName in ids:
		var company: CompanyState = result.companies_after[id]
		var row: StalkState = state.stalk_by_id(id)
		if company.in_squeeze() and row != null and not _failed_by(state, id, year):
			return id
	return &""


## The squeezed company a crash whisper is heard about at the end of `year`,
## or empty (D220). The first company still squeezed then, if `rng`'s roll
## (1-100, drawn only while one is) is at most the chance its squeeze ends next
## year, read from its fuel left and this year's mood: the same chance the
## resolver will roll against.
static func crash_whisper_subject(state: GameState, year: int, rng: RandomNumberGenerator) -> StringName:
	var subject: StringName = squeezed_at_end_of(state, year)
	if subject.is_empty():
		return &""
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	var company: CompanyState = result.companies_after[subject]
	var chance: int = ShortInterestRules.end_chance_percent(company.squeeze_remaining_percent, result.mood)
	if rng.randi_range(1, 100) <= chance:
		return subject
	return &""


## The companies flagged for a squeeze at the end of `year`, most shorted
## first: as the next year's record has them once it has been played, or the
## desk as it stands now.
static func flagged_at_end_of(state: GameState, year: int) -> Array[StringName]:
	var next: EarningsYearResult = MarketReadouts.result_for_year(state, year + 1)
	if next != null:
		return next.short_interest_flagged
	if year == state.year:
		return state.market.desk.flagged_companies(state)
	var none: Array[StringName] = []
	return none


## Whether a squeeze or crash whisper came true: whether the year it was about
## squeezed that company, or took its squeeze off. Null-safe; false until that
## year has been played.
static func squeeze_whisper_came_true(state: GameState, round: WhisperRound, line: WhisperRound.Line) -> bool:
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, round.about_year())
	if result == null:
		return false
	if line.about == NewsBands.Subject.SQUEEZE:
		return result.squeeze_target() == line.subject
	return result.squeeze_moves.get(line.subject, 0) < 0


static func _failed_by(state: GameState, company_id: StringName, year: int) -> bool:
	var company: CompanyState = MarketReadouts.company_in_year(state, company_id, year)
	return company == null or company.price <= TradeRules.BANKRUPT_AT_OR_BELOW


## What really comes of `subject` in the year after `year` (`WhisperRules`).
## A company is measured against its regime at the end of `year`.
static func whisper_truth(
	state: GameState,
	year: int,
	draws: KeptDraws,
	subject: StringName,
	kind: NewsBands.Subject,
) -> NewsBands.Surprise:
	if kind == NewsBands.Subject.INDUSTRY:
		return WhisperRules.industry_outcome(draws.industry_rolls.get(subject, 0))
	var now: CompanyState = MarketReadouts.company_in_year(state, subject, year)
	return WhisperRules.company_outcome(
		now.regime,
		draws.growth_rolls.get(subject, 0),
		now.profile.payout_policy_percent,
		state.settings.max_years,
	)


## A round's own generator, seeded from the draws it is about, which every peer
## holds, so every peer hears the same whispers; never the match's (D200).
static func whisper_rng(year: int, draws: KeptDraws) -> RandomNumberGenerator:
	var parts: PackedStringArray = ["whispers", str(year)]
	for key: StringName in _sorted_keys(draws.industry_rolls.keys()):
		parts.append("%s=%d" % [key, draws.industry_rolls[key]])
	for key: StringName in _sorted_keys(draws.regimes.keys()):
		parts.append("%s=%d,%d" % [key, draws.regimes[key], draws.growth_rolls.get(key, 0)])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = ",".join(parts).hash()
	return rng


# ---------------------------------------------------------------- helpers

## One line from `pool`, from among those drawn least so far: a bag that
## refills when every line in it has been drawn equally (D200). Null when the
## pool is empty. `pool` is in id order, so the draw is the same everywhere.
static func _draw(
	pool: Array[Resource],
	counts: Dictionary[StringName, int],
	rng: RandomNumberGenerator,
) -> Resource:
	if pool.is_empty():
		return null
	var fewest: int = -1
	for line: Resource in pool:
		var drawn: int = counts.get(line.get("id"), 0)
		if fewest < 0 or drawn < fewest:
			fewest = drawn
	var eligible: Array[Resource] = []
	for line: Resource in pool:
		if counts.get(line.get("id"), 0) == fewest:
			eligible.append(line)
	return eligible[rng.randi_range(0, eligible.size() - 1)]


## The lines written for this exact subject if there are any, else the
## general ones.
static func _preferred(own: Array[Resource], general: Array[Resource]) -> Array[Resource]:
	if own.is_empty():
		return general
	return own


static func _mood_fits(wanted: NewsBands.Mood, actual: NewsBands.Mood) -> bool:
	return wanted == NewsBands.Mood.ANY or wanted == actual


static func _move_fits(wanted: NewsBands.Move, actual: NewsBands.Move) -> bool:
	return wanted == NewsBands.Move.ANY or wanted == actual


static func _surprise_fits(wanted: NewsBands.Surprise, actual: NewsBands.Surprise) -> bool:
	return wanted == NewsBands.Surprise.ANY or wanted == actual


static func _company_tokens(state: GameState, company_id: StringName) -> Dictionary[String, String]:
	var tokens: Dictionary[String, String] = {COMPANY_TOKEN: "", INDUSTRY_TOKEN: ""}
	var row: StalkState = state.stalk_by_id(company_id)
	if row != null:
		tokens[COMPANY_TOKEN] = row.definition.display_name
	var company: CompanyState = state.market.company_by_id(company_id)
	if company != null:
		tokens[INDUSTRY_TOKEN] = _industry_name(state, company.profile.industry)
	return tokens


static func _industry_name(state: GameState, industry_id: StringName) -> String:
	var industry: IndustryState = state.market.industry_by_id(industry_id)
	if industry == null:
		return ""
	return industry.definition.display_name


static func _fill(text: String, tokens: Dictionary[String, String]) -> String:
	var filled: String = text
	for token: String in tokens:
		filled = filled.replace(token, tokens[token])
	return filled


static func _sorted_keys(keys: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in keys:
		out.append(key as StringName)
	out.sort_custom(_by_text)
	return out


static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
