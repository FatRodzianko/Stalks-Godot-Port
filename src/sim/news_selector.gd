class_name NewsSelector
extends RefCounted
## Chooses a StalkleHeads year's news: the market headline, a report per
## industry, earnings commentary per company and each NPC trader's chatter
## (docs/stalkleheads-design.md §8.2); and, heard at each year's end about the
## next, the whispers (§8.4, `whispers_for`). Pure: no nodes, no
## autoloads, and no draw from the match's own generator.
##
## **How a line is chosen (§8.2).** For each slot, gather every line whose
## conditions match this year; prefer the lines written for this exact
## industry, company or trader over the general ones; then draw one. **If
## nothing matches, the slot stays empty**: no generic line stands in.
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
	for each: int in range(1, year + 1):
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, each)
		if result == null:
			continue
		if result.news == null:
			result.news = select(state, result, counts)
		for id: StringName in result.news.drawn:
			counts[id] = counts.get(id, 0) + 1
	return target.news


## One year's news, given how many times each line was drawn before it.
## Public for tests; screens use `news_for`.
static func select(
	state: GameState,
	result: EarningsYearResult,
	counts: Dictionary[StringName, int],
) -> YearNews:
	var news: YearNews = YearNews.new()
	news.year = result.year
	var content: NewsContent = state.market.news
	if content == null:
		return news
	var rng: RandomNumberGenerator = rng_for(result)
	_select_headline(content, result, counts, rng, news)
	_select_reports(state, content, result, counts, rng, news)
	_select_commentary(state, content, result, counts, rng, news)
	_select_chatter(state, content, result, counts, rng, news)
	return news


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

static func _select_headline(
	content: NewsContent,
	result: EarningsYearResult,
	counts: Dictionary[StringName, int],
	rng: RandomNumberGenerator,
	news: YearNews,
) -> void:
	var mood: NewsBands.Mood = mood_band(result.mood)
	var move: NewsBands.Move = move_band(result.index_move_percent)
	var pool: Array[Resource] = []
	for line: MarketHeadline in content.headlines:
		if _mood_fits(line.mood, mood) and _move_fits(line.move, move):
			pool.append(line)
	var chosen: MarketHeadline = _draw(pool, counts, rng) as MarketHeadline
	if chosen != null:
		news.headline = chosen.text
		news.drawn.append(chosen.id)


static func _select_reports(
	state: GameState,
	content: NewsContent,
	result: EarningsYearResult,
	counts: Dictionary[StringName, int],
	rng: RandomNumberGenerator,
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
		var chosen: IndustryReport = _draw(_preferred(own, general), counts, rng) as IndustryReport
		if chosen != null:
			news.industry_reports[industry.id] = _fill(chosen.text, {INDUSTRY_TOKEN: industry.definition.display_name})
			news.drawn.append(chosen.id)


static func _select_commentary(
	state: GameState,
	content: NewsContent,
	result: EarningsYearResult,
	counts: Dictionary[StringName, int],
	rng: RandomNumberGenerator,
	news: YearNews,
) -> void:
	for company: CompanyState in state.market.companies:
		var after: CompanyState = result.companies_after.get(company.id, null)
		if not result.regimes.has(company.id) or after == null:
			continue
		var regime: EarningsRegime.Value = result.regimes[company.id]
		var regime_band: NewsBands.Regime = NewsBands.regime_band(regime)
		var expected: float = expected_growth(regime, company.profile.payout_policy_percent, state.settings.max_years)
		var surprise: NewsBands.Surprise = surprise_band(after.revenue_growth_percent, expected)
		var own: Array[Resource] = []
		var general: Array[Resource] = []
		for line: EarningsCommentary in content.earnings_commentary:
			var regime_fits: bool = line.regime == NewsBands.Regime.ANY or line.regime == regime_band
			var surprise_fits: bool = line.surprise == NewsBands.Surprise.ANY or line.surprise == surprise
			if not (regime_fits and surprise_fits):
				continue
			if line.company_id == company.id:
				own.append(line)
			elif line.company_id.is_empty():
				general.append(line)
		var chosen: EarningsCommentary = _draw(_preferred(own, general), counts, rng) as EarningsCommentary
		if chosen != null:
			news.commentary[company.id] = _fill(chosen.text, _company_tokens(state, company.id))
			news.drawn.append(chosen.id)


static func _select_chatter(
	state: GameState,
	content: NewsContent,
	result: EarningsYearResult,
	counts: Dictionary[StringName, int],
	rng: RandomNumberGenerator,
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
		var chosen: NpcChatter = _draw(_preferred(own, general), counts, rng) as NpcChatter
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
			round = select_whispers(state, each, draws, counts)
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


## One round, given how many times each line was drawn before it. Public for
## tests; screens use `whispers_for`.
##
## Up to `WHISPERS_PER_YEAR` subjects are picked evenly from every industry and
## every company still trading, without repeats. For each: its true outcome
## (`WhisperRules`), a source, the outcome that source tells, and a line written
## for that outcome - one written for this very subject if there is any. With
## no line for it, that whisper is not heard, and the rest go on.
static func select_whispers(
	state: GameState,
	year: int,
	draws: KeptDraws,
	counts: Dictionary[StringName, int],
) -> WhisperRound:
	var round: WhisperRound = WhisperRound.new()
	round.year = year
	var content: NewsContent = state.market.news
	if content == null:
		return round
	var rng: RandomNumberGenerator = whisper_rng(year, draws)
	var subjects: Array[StringName] = []
	var kinds: Array[NewsBands.Subject] = []
	for industry: IndustryState in state.market.industries:
		if draws.industry_rolls.has(industry.id):
			subjects.append(industry.id)
			kinds.append(NewsBands.Subject.INDUSTRY)
	for company: CompanyState in state.market.companies:
		if draws.regimes.has(company.id):
			subjects.append(company.id)
			kinds.append(NewsBands.Subject.COMPANY)

	for _slot: int in WHISPERS_PER_YEAR:
		if subjects.is_empty():
			break
		var pick: int = rng.randi_range(0, subjects.size() - 1)
		var subject: StringName = subjects[pick]
		var kind: NewsBands.Subject = kinds[pick]
		subjects.remove_at(pick)
		kinds.remove_at(pick)
		var truth: NewsBands.Surprise = whisper_truth(state, year, draws, subject, kind)
		var source: WhisperRules.Source = WhisperRules.roll_source(rng)
		var said: NewsBands.Surprise = WhisperRules.distort(truth, source, rng)
		var own: Array[Resource] = []
		var general: Array[Resource] = []
		for line: Whisper in content.whispers:
			if line.about != kind or line.outcome != said:
				continue
			if line.subject == subject:
				own.append(line)
			elif line.subject.is_empty():
				general.append(line)
		var chosen: Whisper = _draw(_preferred(own, general), counts, rng) as Whisper
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
