class_name NewsSelector
extends RefCounted
## Chooses a StalkleHeads year's news: the market headline, a report per
## industry, earnings commentary per company, the whispers and each NPC
## trader's chatter (docs/stalkleheads-design.md §8.2). Pure: no nodes, no
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


## The most whispers shown in one year.
const WHISPERS_PER_YEAR: int = 2

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

## PE_ABOVE_INDUSTRY / PE_BELOW_INDUSTRY: more than this far from the
## industry's average P/E, in percent (§8.1).
const PE_GAP_PERCENT: float = 20.0

## SECTOR_RUN: the same direction this many years running (§8.1).
const SECTOR_RUN_YEARS: int = 3

## THIRD_GROWTH_YEAR: this many years in GROWTH, counting the year it entered.
const GROWTH_RUN_YEARS: int = 3

## NEAR_SPLIT: a price above this. The design's 130 was written against the
## base game's split at 150; this mode splits above 300, so it is scaled to the
## same distance from the line (D202).
const NEAR_SPLIT_ABOVE: int = 260

## NEAR_FAILURE: DISTRESS and a price below this (§8.1).
const NEAR_FAILURE_BELOW: int = 20

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
	_select_whispers(state, content, result, counts, rng, news)
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


# --------------------------------------------------------------- triggers

## What a whisper with `trigger` may be about in `year`: the companies still
## trading at the end of it, or for SECTOR_RUN every industry. In id order.
static func subjects_for(state: GameState, year: int, trigger: NewsBands.Trigger) -> Array[StringName]:
	var subjects: Array[StringName] = []
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	if result == null:
		return subjects
	if NewsBands.is_industry_trigger(trigger):
		for industry: IndustryState in state.market.industries:
			if result.industry_performance.has(industry.id):
				subjects.append(industry.id)
		return subjects
	for company: CompanyState in state.market.companies:
		var after: CompanyState = result.companies_after.get(company.id, null)
		if result.regimes.has(company.id) and after != null and after.price > 0:
			subjects.append(company.id)
	return subjects


## True when `trigger` holds for `subject` at the end of `year`. Every one is
## a real condition on real state (§8.1), read from the year's record.
static func trigger_holds(
	state: GameState,
	year: int,
	trigger: NewsBands.Trigger,
	subject: StringName,
) -> bool:
	var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
	if result == null:
		return false
	if trigger == NewsBands.Trigger.SECTOR_RUN:
		return _sector_run(state, year, subject)
	var after: CompanyState = result.companies_after.get(subject, null)
	if after == null or after.price <= 0:
		return false
	match trigger:
		NewsBands.Trigger.HIGH_SHORT_INTEREST:
			# Flagged when this year's event was chosen: the desk as last year
			# left it, which is what the year's record carries (§5.3).
			return result.short_interest_flagged.has(subject)
		NewsBands.Trigger.THIRD_GROWTH_YEAR:
			return after.regime == EarningsRegime.Value.GROWTH and after.years_in_regime >= GROWTH_RUN_YEARS - 1
		NewsBands.Trigger.MARGIN_SLIPPING:
			var before: CompanyState = MarketReadouts.company_in_year(state, subject, year - 1)
			return before != null and after.margin_percent < before.margin_percent and after.revenue > before.revenue
		NewsBands.Trigger.PE_ABOVE_INDUSTRY:
			return _pe_gap(state, year, after) > PE_GAP_PERCENT
		NewsBands.Trigger.PE_BELOW_INDUSTRY:
			return _pe_gap(state, year, after) < -PE_GAP_PERCENT
		NewsBands.Trigger.NEAR_SPLIT:
			return after.price > NEAR_SPLIT_ABOVE
		NewsBands.Trigger.NEAR_FAILURE:
			return after.regime == EarningsRegime.Value.DISTRESS and after.price < NEAR_FAILURE_BELOW
	return false


## How far a company's P/E sits from its industry's average, in percent of
## the average. NaN when either is not a number.
static func _pe_gap(state: GameState, year: int, after: CompanyState) -> float:
	var pe: float = MarketReadouts.price_earnings(after.price, after.earnings_per_share())
	var average: float = MarketReadouts.industry_average_pe_in(state, after.profile.industry, year)
	if is_nan(pe) or is_nan(average) or average <= 0.0:
		return NAN
	return (pe - average) / average * 100.0


static func _sector_run(state: GameState, year: int, industry_id: StringName) -> bool:
	if year < SECTOR_RUN_YEARS:
		return false
	var ups: int = 0
	var downs: int = 0
	for each: int in range(year - SECTOR_RUN_YEARS + 1, year + 1):
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, each)
		if result == null or not result.industry_performance.has(industry_id):
			return false
		var performance: float = result.industry_performance[industry_id]
		if performance > 0.0:
			ups += 1
		elif performance < 0.0:
			downs += 1
	return ups == SECTOR_RUN_YEARS or downs == SECTOR_RUN_YEARS


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


## Up to `WHISPERS_PER_YEAR`, drawn from the whispers in play: those whose
## trigger holds for at least one subject they may name. Each then rolls for
## honesty (`Whisper`, D201). A whisper is drawn at most once a year.
static func _select_whispers(
	state: GameState,
	content: NewsContent,
	result: EarningsYearResult,
	counts: Dictionary[StringName, int],
	rng: RandomNumberGenerator,
	news: YearNews,
) -> void:
	var year: int = result.year
	var in_play: Array[Resource] = []
	var holds_for: Dictionary[StringName, Array] = {}
	var fails_for: Dictionary[StringName, Array] = {}
	for line: Whisper in content.whispers:
		var true_subjects: Array[StringName] = []
		var false_subjects: Array[StringName] = []
		for subject: StringName in subjects_for(state, year, line.trigger):
			if not line.subject.is_empty() and subject != line.subject:
				continue
			if trigger_holds(state, year, line.trigger, subject):
				true_subjects.append(subject)
			else:
				false_subjects.append(subject)
		if true_subjects.is_empty():
			continue
		in_play.append(line)
		holds_for[line.id] = true_subjects
		fails_for[line.id] = false_subjects

	for _slot: int in WHISPERS_PER_YEAR:
		var chosen: Whisper = _draw(in_play, counts, rng) as Whisper
		if chosen == null:
			return
		in_play.erase(chosen)
		news.drawn.append(chosen.id)
		var honest: bool = rng.randi_range(1, 100) <= chosen.truth_chance_percent
		var subjects: Array = holds_for[chosen.id]
		if not honest:
			subjects = fails_for[chosen.id]
		if subjects.is_empty():
			continue
		var whisper: YearNews.WhisperLine = YearNews.WhisperLine.new()
		whisper.id = chosen.id
		whisper.subject = subjects[rng.randi_range(0, subjects.size() - 1)]
		whisper.is_true = honest
		if NewsBands.is_industry_trigger(chosen.trigger):
			whisper.text = _fill(chosen.text, {INDUSTRY_TOKEN: _industry_name(state, whisper.subject)})
		else:
			whisper.text = _fill(chosen.text, _company_tokens(state, whisper.subject))
		news.whispers.append(whisper)


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
