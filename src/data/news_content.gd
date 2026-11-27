class_name NewsContent
extends RefCounted
## Every StalkleHeads news line a match can show, gathered from the `NewsBook`
## files in src/data/news/ and the chatter on each NPC trader's own file, one
## list per category, each **sorted by id** so the selector meets the lines in
## the same order on every machine (decisions.md D30, D200).
##
## Built by `ContentLibrary.load_fundamentals` and checked by its validator;
## held by `EarningsMarket.news` for `NewsSelector` and, for market news, the
## year's resolver. Pure data.


var market_news: Array[MarketNews] = []
var industry_reports: Array[IndustryReport] = []
var company_news: Array[CompanyNews] = []
var whispers: Array[Whisper] = []
var chatter: Array[NpcChatter] = []


## The books' lines plus every trader's own chatter. A trader's line for a
## situation becomes an `NpcChatter` with `npc_id` set and the id
## `<trader id>_<situation>`, so one selector handles both kinds. An empty
## trader line is left out: §8.2 shows nothing rather than a generic line.
static func build(books: Array[NewsBook], traders: Array[NpcTraderDefinition]) -> NewsContent:
	var content: NewsContent = NewsContent.new()
	for book: NewsBook in books:
		content.market_news.append_array(book.market_news)
		content.industry_reports.append_array(book.industry_reports)
		content.company_news.append_array(book.company_news)
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
	content.market_news.sort_custom(_by_id)
	content.industry_reports.sort_custom(_by_id)
	content.company_news.sort_custom(_by_id)
	content.whispers.sort_custom(_by_id)
	content.chatter.sort_custom(_by_id)
	return content


## How many lines there are, all categories together.
func size() -> int:
	return all_lines().size()


## Every line of every category, market news first. What the validator walks
## to check that ids are unique and that every required id exists.
func all_lines() -> Array[Resource]:
	var lines: Array[Resource] = []
	lines.append_array(market_news)
	lines.append_array(industry_reports)
	lines.append_array(company_news)
	lines.append_array(whispers)
	lines.append_array(chatter)
	return lines


## The market news line with this id, or null.
func market_news_by_id(id: StringName) -> MarketNews:
	for line: MarketNews in market_news:
		if line.id == id:
			return line
	return null


## Every loop in the `requires` lists, each as the ids around it: `[a, b]`
## means a requires b and b requires a, so neither could ever be shown (D210).
## Each loop starts at its smallest id and is listed once; a line that requires
## itself is not reported here, since the validator names that on its own. An
## id that is not a line is skipped. Finds at least one loop wherever there is
## one, in the same order on every machine.
func requires_loops() -> Array[Array]:
	var required_by_id: Dictionary[StringName, Array] = {}
	for line: Resource in all_lines():
		var required: Array[StringName] = line.get("requires")
		required_by_id[line.get("id")] = required
	var ids: Array[StringName] = []
	ids.assign(required_by_id.keys())
	ids.sort_custom(_string_name_order)
	var state: Dictionary[StringName, int] = {}
	var path: Array[StringName] = []
	var found: Dictionary[String, Array] = {}
	for id: StringName in ids:
		if not state.has(id):
			_walk_requires(id, required_by_id, state, path, found)
	var keys: Array[String] = []
	keys.assign(found.keys())
	keys.sort()
	var loops: Array[Array] = []
	for key: String in keys:
		loops.append(found[key])
	return loops


## Depth-first walk for `requires_loops`. `state` is 1 while an id is on the
## current path and 2 once everything it leads to has been walked.
static func _walk_requires(
	id: StringName,
	required_by_id: Dictionary[StringName, Array],
	state: Dictionary[StringName, int],
	path: Array[StringName],
	found: Dictionary[String, Array],
) -> void:
	state[id] = 1
	path.append(id)
	var required: Array = required_by_id[id]
	for next: StringName in required:
		if next == id or not required_by_id.has(next):
			continue
		if state.get(next, 0) == 1:
			var loop: Array[StringName] = []
			loop.assign(path.slice(path.find(next)))
			_record_loop(loop, found)
		elif not state.has(next):
			_walk_requires(next, required_by_id, state, path, found)
	path.pop_back()
	state[id] = 2


## Stores a loop turned to start at its smallest id, so one loop reached from
## two places is stored once.
static func _record_loop(loop: Array[StringName], found: Dictionary[String, Array]) -> void:
	var start: int = 0
	for index: int in loop.size():
		if String(loop[index]) < String(loop[start]):
			start = index
	var turned: Array[StringName] = []
	turned.assign(loop.slice(start) + loop.slice(0, start))
	found[" ".join(turned)] = turned


static func _string_name_order(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)


static func _by_id(a: Resource, b: Resource) -> bool:
	return String(a.get("id")) < String(b.get("id"))
