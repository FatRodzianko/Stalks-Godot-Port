class_name NewsIdMaker
extends RefCounted
## Writes the id of a new news item, so nobody types one
## (docs/news-flow-chart.md §3.3).
##
## An id is a prefix that says what the item was made as, then a number:
##
## | Kind | Prefix |
## |---|---|
## | Market news | `mkt_<mood>_<move>` |
## | Industry headline | `ind_<industry or any>_<move>` |
## | Company news | `cnews_<company or any>_<move>` |
## | Whisper about a company or an industry | `whisp_<about>_<outcome>` |
## | Squeeze or crash whisper | `whisp_<squeeze or crash>` |
## | Chatter | `chat_<trader id, or the strategy>_<situation>` |
##
## The number is one more than the highest ever used with that prefix,
## counting the live items **and the retired ids**, so a deleted item's id is
## never given out again. An id is made once and then fixed: changing an item's
## mood later does not rename it, because other items' `requires` lists name it.


## The id for `line`, given every id taken: live items and retired ones.
static func next_id(line: Resource, taken: Array[StringName]) -> StringName:
	var prefix: String = prefix_for(line)
	var pattern: RegEx = RegEx.create_from_string("^%s_(\\d+)$" % prefix)
	var highest: int = 0
	for id: StringName in taken:
		var found: RegExMatch = pattern.search(String(id))
		if found != null:
			highest = maxi(highest, found.get_string(1).to_int())
	return StringName("%s_%d" % [prefix, highest + 1])


## The part of the id before the number, from the item's own fields.
static func prefix_for(line: Resource) -> String:
	if line is MarketNews:
		var market: MarketNews = line as MarketNews
		return "mkt_%s_%s" % [_name(NewsBands.Mood, market.mood), _name(NewsBands.Move, market.move)]
	if line is IndustryReport:
		var report: IndustryReport = line as IndustryReport
		return "ind_%s_%s" % [_subject(report.industry_id), _name(NewsBands.Move, report.move)]
	if line is CompanyNews:
		var company: CompanyNews = line as CompanyNews
		return "cnews_%s_%s" % [_subject(company.company_id), _name(NewsBands.Move, company.move)]
	if line is Whisper:
		var whisper: Whisper = line as Whisper
		var about: String = _name(NewsBands.Subject, whisper.about)
		if whisper.about == NewsBands.Subject.SQUEEZE or whisper.about == NewsBands.Subject.CRASH:
			return "whisp_%s" % about
		return "whisp_%s_%s" % [about, _name(NewsBands.Surprise, whisper.outcome)]
	var chatter: NpcChatter = line as NpcChatter
	var speaker: String = String(chatter.npc_id)
	if speaker.is_empty():
		speaker = _name(NpcStrategy.Value, chatter.strategy)
	return "chat_%s_%s" % [speaker, _name(NpcTraderDefinition.Situation, chatter.situation)]


## An enum value's name in lower case: `NewsBands.Move.CRASH` is `crash`.
static func _name(enum_type: Dictionary, value: int) -> String:
	for key: String in enum_type.keys():
		if enum_type[key] == value:
			return key.to_lower()
	return str(value)


static func _subject(id: StringName) -> String:
	if id.is_empty():
		return "any"
	return String(id)
