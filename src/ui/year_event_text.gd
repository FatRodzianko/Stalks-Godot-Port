class_name YearEventText
extends RefCounted
## A StalkleHeads year's events in words: the market news (headline, event
## text and what it did) and the short squeeze (its words and what it did), as
## the top strip, the news panel, the Market tab's THIS YEAR'S NEWS and the
## final board's year-by-year column show them (decisions.md D209, D213).
##
## Presentation only. What each event did is read from the year's record -
## the market news line and its targets, and `EarningsYearResult.squeeze_moves`
## - and nothing is worked out here that the simulation has not already
## decided.


## The market news headline, or empty.
var headline: String = ""

## The market news event text, its tokens filled in, or empty.
var body: String = ""

## What the market news did, such as "Meowly rose by 10", or empty for news
## with no effect.
var effect: String = ""

## The amount the market news moved each target by, for coloring `effect`.
var effect_change: int = 0

## The squeeze's words, from the template, or empty for no squeeze.
var squeeze_text: String = ""

## What the squeeze did this year: the lift, then any squeeze that came off.
var squeeze_effects: PackedStringArray = []

## The coins the first squeeze line moved by, for coloring.
var squeeze_change: int = 0


## The words for `result`'s year. The squeeze's own words come from the
## market's template; without one, the squeeze is unnamed but still says what
## it did.
static func of(state: GameState, result: EarningsYearResult) -> YearEventText:
	var squeeze: SpecialEventDefinition = null
	if state.market != null:
		squeeze = state.market.squeeze_words
	var words: YearEventText = YearEventText.new()
	if result == null:
		return words
	var news: MarketNews = result.market_news
	if news != null:
		words.headline = news.headline
		words.body = news.text
		if not news.target_company.is_empty():
			words.body = news.text.replace(NewsSelector.COMPANY_TOKEN, _name_of(state, news.target_company))
			words.body = words.body.replace(NewsSelector.INDUSTRY_TOKEN, _industry_of_company(state, news.target_company))
		elif not news.target_industry.is_empty():
			words.body = news.text.replace(NewsSelector.INDUSTRY_TOKEN, _industry_name(state, news.target_industry))
		if news.has_target() and news.amount != 0:
			words.effect_change = news.amount
			if not news.target_company.is_empty():
				words.effect = moved(_name_of(state, news.target_company), news.amount)
			else:
				words.effect = moved("Every %s company" % _industry_name(state, news.target_industry), news.amount)

	var squeezed: StringName = result.squeeze_target()
	if not squeezed.is_empty():
		if squeeze != null:
			words.squeeze_text = squeeze.flavour_text.replace(NewsSelector.COMPANY_TOKEN, _name_of(state, squeezed))
		var lift: int = result.squeeze_moves.get(squeezed, 0)
		words.squeeze_effects.append(moved(_name_of(state, squeezed), lift))
		words.squeeze_change = lift
	var ended: Array[StringName] = []
	for company_id: StringName in result.squeeze_moves:
		if company_id != squeezed:
			ended.append(company_id)
	ended.sort_custom(_by_text)
	for company_id: StringName in ended:
		var fall: int = result.squeeze_moves[company_id]
		words.squeeze_effects.append("Short squeeze over: %s" % moved(_name_of(state, company_id), fall))
		if words.squeeze_change == 0:
			words.squeeze_change = fall
	# A squeeze that held, and which way its lift drifted (D220).
	var held: Array[StringName] = []
	for company_id: StringName in result.squeeze_drift_moves:
		held.append(company_id)
	held.sort_custom(_by_text)
	for company_id: StringName in held:
		var drift: int = result.squeeze_drift_moves[company_id]
		words.squeeze_effects.append("Short squeeze holds: %s" % moved(_name_of(state, company_id), drift))
		if words.squeeze_change == 0:
			words.squeeze_change = drift
	return words


## "Name rose by 10" or "Name fell by 10".
static func moved(name: String, change: int) -> String:
	return "%s %s by %d" % [name, "rose" if change >= 0 else "fell", absi(change)]


## True when there is nothing to say: no market news and no squeeze.
func is_empty() -> bool:
	return headline.is_empty() and squeeze_effects.is_empty()


## The one line the top strip's description shows: the headline, or the
## squeeze's words in a year without market news.
func strip_text() -> String:
	if not headline.is_empty():
		return headline
	return squeeze_text


## The strip's effect line: every effect, market news first.
func strip_effect() -> String:
	var parts: PackedStringArray = []
	if not effect.is_empty():
		parts.append(effect)
	parts.append_array(squeeze_effects)
	return "; ".join(parts)


## The color the strip's effect line takes: the first effect's direction.
func strip_change() -> int:
	if not effect.is_empty():
		return effect_change
	return squeeze_change


## Everything, for the news panel: headline, text, squeeze, each on its own line.
func full_text() -> String:
	var parts: PackedStringArray = []
	for part: String in [headline, body, squeeze_text]:
		if not part.is_empty():
			parts.append(part)
	return "\n".join(parts)


static func _name_of(state: GameState, stalk_id: StringName) -> String:
	var row: StalkState = state.stalk_by_id(stalk_id)
	if row == null:
		return String(stalk_id)
	return row.definition.display_name


static func _industry_name(state: GameState, industry_id: StringName) -> String:
	var industry: IndustryState = state.market.industry_by_id(industry_id)
	if industry == null:
		return String(industry_id)
	return industry.definition.display_name


static func _industry_of_company(state: GameState, company_id: StringName) -> String:
	var company: CompanyState = state.market.company_by_id(company_id)
	if company == null:
		return ""
	return _industry_name(state, company.profile.industry)


static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
