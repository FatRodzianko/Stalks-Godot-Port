class_name NewsContent
extends RefCounted
## Every StalkleHeads news line a match can show, gathered from the `NewsBook`
## files in src/data/news/ and the chatter on each NPC trader's own file, one
## list per category, each **sorted by id** so the selector meets the lines in
## the same order on every machine (decisions.md D30, D200).
##
## Built by `ContentLibrary.load_fundamentals` and checked by its validator;
## held by `EarningsMarket.news` for `NewsSelector`. Pure data.


var headlines: Array[MarketHeadline] = []
var industry_reports: Array[IndustryReport] = []
var earnings_commentary: Array[EarningsCommentary] = []
var whispers: Array[Whisper] = []
var chatter: Array[NpcChatter] = []


## The books' lines plus every trader's own chatter. A trader's line for a
## situation becomes an `NpcChatter` with `npc_id` set and the id
## `<trader id>_<situation>`, so one selector handles both kinds. An empty
## trader line is left out: §8.2 shows nothing rather than a generic line.
static func build(books: Array[NewsBook], traders: Array[NpcTraderDefinition]) -> NewsContent:
	var content: NewsContent = NewsContent.new()
	for book: NewsBook in books:
		content.headlines.append_array(book.headlines)
		content.industry_reports.append_array(book.industry_reports)
		content.earnings_commentary.append_array(book.earnings_commentary)
		content.whispers.append_array(book.whispers)
		content.chatter.append_array(book.chatter)
	for trader: NpcTraderDefinition in traders:
		for situation: NpcTraderDefinition.Situation in NpcTraderDefinition.Situation.values():
			var text: String = trader.chatter_for(situation)
			if text.is_empty():
				continue
			var line: NpcChatter = NpcChatter.new()
			var word: String = String(NpcTraderDefinition.Situation.keys()[situation]).to_lower()
			line.id = StringName("%s_%s" % [trader.id, word])
			line.npc_id = trader.id
			line.strategy = trader.strategy
			line.situation = situation
			line.text = text
			content.chatter.append(line)
	content.headlines.sort_custom(_by_id)
	content.industry_reports.sort_custom(_by_id)
	content.earnings_commentary.sort_custom(_by_id)
	content.whispers.sort_custom(_by_id)
	content.chatter.sort_custom(_by_id)
	return content


## How many lines there are, all categories together.
func size() -> int:
	return headlines.size() + industry_reports.size() + earnings_commentary.size() \
		+ whispers.size() + chatter.size()


static func _by_id(a: Resource, b: Resource) -> bool:
	return String(a.get("id")) < String(b.get("id"))
