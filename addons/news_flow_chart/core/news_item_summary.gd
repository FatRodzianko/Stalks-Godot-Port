class_name NewsItemSummary
extends RefCounted
## What the News Flow Chart shows about one news item: the short form on its
## box (kind, conditions, the first words of its headline or text) and the long
## form in the details panel (every field). docs/news-flow-chart.md §2.
##
## **Every word shown comes from the item's own file.** Nothing here writes
## text of its own beyond field names and the "(any)" / "(empty)" markers, which
## explain a value rather than add to it.
##
## **Property access only, never a method call on the item.** Inside the
## running editor a news item loaded from a book is a *placeholder*: its script
## is not a `@tool` script, so Godot keeps its fields but will not run its code
## (decisions.md D224). `get()` and `is` work on a placeholder, and the field
## list comes from the script itself; `line.has_target()` would fail. Keep it
## that way here.


## How many words of the headline or text a box shows.
const FIRST_WORDS: int = 8

## What a box calls each condition field, where its property name reads badly.
const FIELD_LABELS: Dictionary[StringName, String] = {
	&"industry_id": "Industry",
	&"company_id": "Company",
	&"target_company": "Target",
	&"target_industry": "Target",
	&"npc_id": "Trader",
}

## The condition fields a box shows, by kind, in the order shown.
const CONDITION_FIELDS: Dictionary[NewsKind.Value, Array] = {
	NewsKind.Value.MARKET: [&"mood", &"move", &"target_company", &"target_industry", &"amount"],
	NewsKind.Value.INDUSTRY: [&"industry_id", &"mood", &"move"],
	NewsKind.Value.COMPANY: [&"company_id", &"move"],
	NewsKind.Value.WHISPER: [&"about", &"subject", &"outcome"],
	NewsKind.Value.CHATTER: [&"npc_id", &"strategy", &"situation"],
}

## Condition fields left off a box when empty, because empty means "nothing"
## rather than "any": market news that hits nothing, chatter for every trader
## of a strategy.
const HIDDEN_WHEN_EMPTY: Array[StringName] = [&"target_company", &"target_industry", &"amount", &"npc_id"]

## The fields the box's words come from, the first one with any text.
const WORD_FIELDS: Array[StringName] = [&"headline", &"text"]

const SEPARATOR: String = "  ·  "


## The kind's name, or an empty string for something that is not a news item.
static func kind_name(line: Resource) -> String:
	var kind: int = NewsKind.of(line)
	if kind < 0:
		return ""
	return NewsKind.display_name(kind)


## The item's conditions on one line: `Mood: Bear  ·  Move: Crash`.
static func conditions(line: Resource) -> String:
	var kind: int = NewsKind.of(line)
	if kind < 0:
		return ""
	var parts: PackedStringArray = []
	for field: StringName in CONDITION_FIELDS[kind]:
		var value: Variant = line.get(field)
		if HIDDEN_WHEN_EMPTY.has(field) and _is_empty(value):
			continue
		var shown: String = value_text(line, field)
		if (value is StringName or value is String) and _is_empty(value):
			shown = "(any)"
		parts.append("%s: %s" % [field_label(field), shown])
	return SEPARATOR.join(parts)


## The first `count` words of the headline, or of the text if there is no
## headline, with "…" when there are more.
static func first_words(line: Resource, count: int = FIRST_WORDS) -> String:
	var words: PackedStringArray = []
	for field: StringName in WORD_FIELDS:
		var text: Variant = line.get(field)
		if text is String and not String(text).strip_edges().is_empty():
			words = String(text).strip_edges().split(" ", false)
			break
	var shown: String = " ".join(words.slice(0, count)).replace("\n", " ")
	if words.size() > count:
		shown += " …"
	return shown


## What the search box matches against: the id and the words, lower case.
static func search_text(line: Resource) -> String:
	var parts: PackedStringArray = [String(line.get("id"))]
	for field: StringName in WORD_FIELDS:
		var text: Variant = line.get(field)
		if text is String:
			parts.append(text)
	return " ".join(parts).to_lower()


## Every field of the item, in the order its script declares them, as
## `[label, value]` pairs: what the details panel lists.
static func fields(line: Resource) -> Array[PackedStringArray]:
	var found: Array[PackedStringArray] = []
	for property: Dictionary in stored_properties(line):
		var field: StringName = property["name"]
		found.append(PackedStringArray([String(field).capitalize(), value_text(line, field)]))
	return found


## One field's value as text: an enum by its name, a list joined, an empty
## value as "(empty)".
static func value_text(line: Resource, field: StringName) -> String:
	var value: Variant = line.get(field)
	if _is_empty(value) and not (value is int):
		return "(empty)"
	if value is Array:
		var items: PackedStringArray = []
		for item: Variant in value:
			items.append(str(item))
		return ", ".join(items)
	if value is int:
		var names: Dictionary[int, String] = enum_names(line, field)
		if names.has(value):
			return names[value]
	return str(value)


static func field_label(field: StringName) -> String:
	return FIELD_LABELS.get(field, String(field).capitalize())


## The fields the item's own script declares and saves. Read from the
## script, not the item: a placeholder's own property list (D224) has neither
## the usage flags nor the enum names.
static func stored_properties(line: Resource) -> Array[Dictionary]:
	var stored: Array[Dictionary] = []
	var script: Script = line.get_script() as Script
	if script == null:
		return stored
	for property: Dictionary in script.get_script_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			stored.append(property)
	return stored


## The names of an enum field's values, from its export hint
## (`Any:0,Bull:1,Bear:2`). Empty for a field that is not an enum.
static func enum_names(line: Resource, field: StringName) -> Dictionary[int, String]:
	var names: Dictionary[int, String] = {}
	for property: Dictionary in stored_properties(line):
		if property["name"] != field or property["hint"] != PROPERTY_HINT_ENUM:
			continue
		var entries: PackedStringArray = String(property["hint_string"]).split(",")
		for index: int in entries.size():
			var parts: PackedStringArray = entries[index].split(":")
			var number: int = index
			if parts.size() > 1:
				number = int(parts[1])
			names[number] = parts[0]
	return names


static func _is_empty(value: Variant) -> bool:
	if value is String or value is StringName:
		return String(value).is_empty()
	if value is Array:
		return (value as Array).is_empty()
	if value is int:
		return value == 0
	return value == null
