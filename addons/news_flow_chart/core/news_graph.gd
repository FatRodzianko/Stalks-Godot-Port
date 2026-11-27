class_name NewsGraph
extends RefCounted
## The news items and the arrows between them, worked out from the `requires`
## lists every time; nothing about a chain is stored (docs/news-flow-chart.md
## §3.1).
##
## **An arrow from A to B means "B requires A"**: B may only appear once A has
## appeared in an earlier year (decisions.md D210). A **chain** is a set of
## items joined by arrows, whichever way they point. Its **roots** are the items
## in it that require nothing, where it starts. An id in a `requires` list that
## is not an item makes no arrow; the validator reports it.
##
## Everything comes back sorted by id, so the chart is the same on every
## machine and every run.


var _lines: Dictionary[StringName, Resource] = {}
var _requires: Dictionary[StringName, Array] = {}
var _followers: Dictionary[StringName, Array] = {}


## The graph of every news item in `content`, the traders' own chatter
## included (it has no `requires`, but another item may require it).
static func build(content: NewsContent) -> NewsGraph:
	var lines: Array[Resource] = content.all_lines()
	return from_lines(lines)


## The graph of these items.
static func from_lines(lines: Array[Resource]) -> NewsGraph:
	var graph: NewsGraph = NewsGraph.new()
	for line: Resource in lines:
		var id: StringName = line.get("id")
		graph._lines[id] = line
		graph._requires[id] = []
		graph._followers[id] = []
	for id: StringName in graph.ids():
		var required: Array[StringName] = graph._lines[id].get("requires")
		for other: StringName in required:
			if other == id or not graph._lines.has(other) or graph._requires[id].has(other):
				continue
			graph._requires[id].append(other)
			graph._followers[other].append(id)
	for id: StringName in graph.ids():
		graph._requires[id].sort_custom(_by_text)
		graph._followers[id].sort_custom(_by_text)
	return graph


## Every item's id.
func ids() -> Array[StringName]:
	var all: Array[StringName] = []
	all.assign(_lines.keys())
	all.sort_custom(_by_text)
	return all


func has(id: StringName) -> bool:
	return _lines.has(id)


## The item with this id, or null.
func line(id: StringName) -> Resource:
	return _lines.get(id, null)


## The items `id` requires: where its incoming arrows come from.
func requires_of(id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_requires.get(id, []))
	return found


## The items that require `id`: where its outgoing arrows go.
func followers_of(id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_followers.get(id, []))
	return found


## How many arrows touch `id`, in and out. Deleting an item with any asks first.
func arrow_count(id: StringName) -> int:
	return requires_of(id).size() + followers_of(id).size()


## Every chain: each a sorted list of ids, at least two items long. Listed in
## order of their keys (`chain_key`).
func chains() -> Array[Array]:
	var seen: Dictionary[StringName, bool] = {}
	var found: Array[Array] = []
	for id: StringName in ids():
		if seen.has(id) or arrow_count(id) == 0:
			continue
		var chain: Array[StringName] = chain_of(id)
		for member: StringName in chain:
			seen[member] = true
		found.append(chain)
	found.sort_custom(_by_key.bind(self))
	return found


## The items with no arrows at all.
func unchained() -> Array[StringName]:
	var alone: Array[StringName] = []
	for id: StringName in ids():
		if arrow_count(id) == 0:
			alone.append(id)
	return alone


## The chain `id` is in, sorted; just `[id]` for an item with no arrows.
func chain_of(id: StringName) -> Array[StringName]:
	var chain: Array[StringName] = []
	if not has(id):
		return chain
	var seen: Dictionary[StringName, bool] = {id: true}
	var waiting: Array[StringName] = [id]
	while not waiting.is_empty():
		var current: StringName = waiting.pop_back()
		chain.append(current)
		for next: StringName in requires_of(current) + followers_of(current):
			if not seen.has(next):
				seen[next] = true
				waiting.append(next)
	chain.sort_custom(_by_text)
	return chain


## The items in `chain` that require nothing: where it starts.
func roots(chain: Array[StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: StringName in chain:
		if requires_of(id).is_empty():
			found.append(id)
	return found


## What a chain is known by: its first root in id order, or, for a chain that
## is all loop and so has no root, its first id. Its automatic name, and the key
## its own name is stored under (`NewsChainNames`).
func chain_key(chain: Array[StringName]) -> StringName:
	var starts: Array[StringName] = roots(chain)
	if not starts.is_empty():
		return starts[0]
	if chain.is_empty():
		return &""
	return chain[0]


## True if an arrow from `from_id` to `to_id` (so `to_id` requires `from_id`)
## would close a loop: `from_id` already waits, directly or further back, for
## `to_id`, or they are the same item.
func would_loop(from_id: StringName, to_id: StringName) -> bool:
	if from_id == to_id:
		return true
	var seen: Dictionary[StringName, bool] = {}
	var waiting: Array[StringName] = [from_id]
	while not waiting.is_empty():
		var current: StringName = waiting.pop_back()
		if current == to_id:
			return true
		if seen.has(current):
			continue
		seen[current] = true
		waiting.append_array(requires_of(current))
	return false


static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)


static func _by_key(a: Array, b: Array, graph: NewsGraph) -> bool:
	var a_ids: Array[StringName] = []
	a_ids.assign(a)
	var b_ids: Array[StringName] = []
	b_ids.assign(b)
	return String(graph.chain_key(a_ids)) < String(graph.chain_key(b_ids))
