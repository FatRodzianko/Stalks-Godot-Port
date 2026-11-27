class_name NewsChainNames
extends RefCounted
## The names given to chains, the one thing about a chain the News Flow Chart
## stores (docs/news-flow-chart.md §3.1). A chain without one is called by its
## key, its first root's id (`NewsGraph.chain_key`).
##
## Kept in `src/data/news_chains.cfg`, a plain `ConfigFile`: one line per
## name, `root id = "name"`, under `[names]`. Outside src/data/news/, so the
## game never reads it as a book, and it holds names only - the arrows are in
## the `requires` lists and nowhere else.
##
## **A name follows its chain** when the chain changes (`follow`): to the new
## first root when an item is put in front of the old one, to another member
## when the root is deleted. A name that can no longer be placed is dropped and
## reported, never kept silently.


const PATH: String = "res://src/data/news_chains.cfg"
const SECTION: String = "names"

## Names by chain key.
var names: Dictionary[StringName, String] = {}


## The names in `path`; none if there is no file.
static func read(path: String = PATH) -> NewsChainNames:
	var chain_names: NewsChainNames = NewsChainNames.new()
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK or not file.has_section(SECTION):
		return chain_names
	for key: String in file.get_section_keys(SECTION):
		chain_names.names[StringName(key)] = str(file.get_value(SECTION, key, ""))
	return chain_names


func write(path: String = PATH) -> Error:
	var file: ConfigFile = ConfigFile.new()
	var keys: Array[StringName] = _sorted_keys()
	for key: StringName in keys:
		file.set_value(SECTION, String(key), names[key])
	return file.save(path)


## What the chain is called: its own name, or its key.
func name_for(graph: NewsGraph, chain: Array[StringName]) -> String:
	var key: StringName = graph.chain_key(chain)
	return names.get(key, String(key))


## Gives a chain a name. An empty name takes it away, back to its key.
func rename(graph: NewsGraph, chain: Array[StringName], new_name: String) -> void:
	var key: StringName = graph.chain_key(chain)
	if new_name.strip_edges().is_empty():
		names.erase(key)
	else:
		names[key] = new_name.strip_edges()


## Moves each name to where its chain now is, after an edit turned `before`
## into `after`. Returns a message for each name that had to be dropped. With
## no `before` (the chart has just been opened, and the books may have been
## edited by hand), a name can only follow its key.
func follow(after: NewsGraph, before: NewsGraph = null) -> Array[String]:
	var problems: Array[String] = []
	var placed: Dictionary[StringName, String] = {}
	for key: StringName in _sorted_keys():
		var chain_name: String = names[key]
		var chain: Array[StringName] = _chain_now(key, after, before)
		if chain.size() < 2:
			problems.append("The chain named \"%s\" is gone, so its name was dropped." % chain_name)
			continue
		var new_key: StringName = after.chain_key(chain)
		if placed.has(new_key):
			problems.append("Two named chains became one; it keeps \"%s\" and \"%s\" was dropped."
				% [placed[new_key], chain_name])
			continue
		placed[new_key] = chain_name
	names = placed
	return problems


## The chain a name stored under `key` now belongs to, or an empty list: the
## key's own chain if it still is one, else the chain of the first other
## member of the chain it had before.
func _chain_now(key: StringName, after: NewsGraph, before: NewsGraph) -> Array[StringName]:
	var candidates: Array[StringName] = [key]
	if before != null and before.has(key):
		candidates.append_array(before.chain_of(key))
	for candidate: StringName in candidates:
		if after.has(candidate):
			var chain: Array[StringName] = after.chain_of(candidate)
			if chain.size() >= 2:
				return chain
	return [] as Array[StringName]


func _sorted_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	keys.assign(names.keys())
	keys.sort_custom(_by_text)
	return keys


static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
