class_name NewsFieldChoices
extends RefCounted
## What each dropdown in the News Flow Chart offers: every company, industry
## or trader that exists, read from their files, so a new company appears with
## no code change (docs/news-flow-chart.md §3.4). Used by the tool's details
## panel and by the Inspector's dropdowns alike.
##
## The empty id is offered first wherever leaving the field empty means
## something: **(any)** for an item about whichever company or industry comes
## up, **(none)** for market news that moves nothing.


## One choice: the id saved in the file, and what the dropdown shows.
class Choice:
	extends RefCounted
	var id: StringName
	var label: String

	func _init(choice_id: StringName, choice_label: String) -> void:
		id = choice_id
		label = choice_label


## The fields that get a dropdown, by kind.
const FIELDS: Dictionary[NewsKind.Value, Array] = {
	NewsKind.Value.MARKET: [&"target_company", &"target_industry"],
	NewsKind.Value.INDUSTRY: [&"industry_id"],
	NewsKind.Value.COMPANY: [&"company_id"],
	NewsKind.Value.WHISPER: [&"subject"],
	NewsKind.Value.CHATTER: [&"npc_id"],
}


## True when `field` of `line` is one of the dropdown fields.
static func has_choices(line: Resource, field: StringName) -> bool:
	var kind: int = NewsKind.of(line)
	if kind < 0:
		return false
	return FIELDS[kind].has(field)


## The choices for `field` of `line`, from `library`'s companies, industries
## and traders. A whisper's subject lists industries for an industry whisper
## and companies otherwise. Empty for a field with no dropdown.
static func choices_for(line: Resource, field: StringName, library: ContentLibrary) -> Array[Choice]:
	var choices: Array[Choice] = []
	if not has_choices(line, field):
		return choices
	match field:
		&"target_company":
			choices.append(Choice.new(&"", "(none)"))
			_add_companies(choices, library)
		&"target_industry":
			choices.append(Choice.new(&"", "(none)"))
			_add_industries(choices, library)
		&"industry_id":
			choices.append(Choice.new(&"", "(any)"))
			_add_industries(choices, library)
		&"company_id":
			choices.append(Choice.new(&"", "(any)"))
			_add_companies(choices, library)
		&"subject":
			choices.append(Choice.new(&"", "(any)"))
			var whisper: Whisper = line as Whisper
			if whisper.about == NewsBands.Subject.INDUSTRY:
				_add_industries(choices, library)
			else:
				_add_companies(choices, library)
		&"npc_id":
			choices.append(Choice.new(&"", "(every trader of the strategy)"))
			for trader: NpcTraderDefinition in library.traders:
				choices.append(Choice.new(trader.id, _label(trader.display_name, trader.id)))
	return choices


## The ids `line` could require: every other item, sorted. Items it already
## requires are left in; the picker shows them as chosen.
static func requires_choices(line: Resource, graph: NewsGraph) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in graph.ids():
		if id != line.get("id"):
			ids.append(id)
	return ids


## The ids `line` could be made to require without making a loop: every
## other item that does not already wait for `line`, sorted. What the
## Inspector's requires picker offers, since it has nowhere to say why an id
## was refused.
static func requires_choices_without_loops(line: Resource, graph: NewsGraph) -> Array[StringName]:
	var own_id: StringName = line.get("id")
	var ids: Array[StringName] = []
	for id: StringName in requires_choices(line, graph):
		if not graph.has(own_id) or not graph.would_loop(id, own_id):
			ids.append(id)
	return ids


static func _add_companies(choices: Array[Choice], library: ContentLibrary) -> void:
	for company: CompanyProfile in library.companies:
		choices.append(Choice.new(company.id, _label(company.display_name, company.id)))


static func _add_industries(choices: Array[Choice], library: ContentLibrary) -> void:
	for industry: IndustryDefinition in library.industries:
		choices.append(Choice.new(industry.id, _label(industry.display_name, industry.id)))


## "Stryker Industries (stryker)": the name a person knows, and the id the file
## holds, so the two can be matched up in a text editor.
static func _label(display_name: String, id: StringName) -> String:
	if display_name.is_empty():
		return String(id)
	return "%s (%s)" % [display_name, id]



## A library holding only the companies, industries and traders, read from
## their files and sorted by id, with no method of theirs called and nothing
## validated. What the dropdowns need, and what the editor can load: there,
## every one of them is a placeholder (decisions.md D224), and
## `ContentLibrary.load_fundamentals` would fail.
static func library_from_files(
	companies_dir: String = ContentLibrary.COMPANIES_DIR,
	industries_dir: String = ContentLibrary.INDUSTRIES_DIR,
	traders_dir: String = ContentLibrary.TRADERS_DIR,
) -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.new()
	for resource: Resource in _load_dir(companies_dir):
		if resource is CompanyProfile:
			library.companies.append(resource)
	for resource: Resource in _load_dir(industries_dir):
		if resource is IndustryDefinition:
			library.industries.append(resource)
	for resource: Resource in _load_dir(traders_dir):
		if resource is NpcTraderDefinition:
			library.traders.append(resource)
	library.companies.sort_custom(_by_id)
	library.industries.sort_custom(_by_id)
	library.traders.sort_custom(_by_id)
	return library


static func _load_dir(dir_path: String) -> Array[Resource]:
	var loaded: Array[Resource] = []
	var names: Array[String] = []
	names.assign(DirAccess.get_files_at(dir_path))
	names.sort()
	for file_name: String in names:
		var usable: String = file_name.trim_suffix(".remap")
		if not usable.ends_with(".tres"):
			continue
		var resource: Resource = load("%s/%s" % [dir_path, usable])
		if resource != null:
			loaded.append(resource)
	return loaded


static func _by_id(a: Resource, b: Resource) -> bool:
	return String(a.get("id")) < String(b.get("id"))
