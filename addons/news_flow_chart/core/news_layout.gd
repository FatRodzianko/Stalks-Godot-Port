class_name NewsLayout
extends RefCounted
## Where the News Flow Chart puts its boxes: **top to bottom, as a tree**, the
## way a chain is read (decisions.md D226, D227). An item sits one row below
## the lowest item it requires, so every arrow points down, and it is centered
## under that item together with the item's other followers, so a chain
## branches out the way a family tree does. Items that require nothing on the
## chart share the top row, side by side.
##
## Godot's own `GraphEdit.arrange_nodes` lays out left to right and cannot be
## turned, so the tool does its own. An item that requires two items on the
## chart is placed under one of them, its **parent**: the one in the row just
## above it, first by id. Its arrow from the other still points down, but may
## cross another.
##
## Part of the News Flow Chart's `core/`: pure logic, tested headless.


## The space between one row and the next, and between boxes side by side.
const ROW_GAP: float = 80.0
const COLUMN_GAP: float = 40.0


## The rows of `ids`, top first, each in id order. Only arrows between items in
## `ids` count, so an item whose requirements are all off the chart sits in the
## top row.
static func rows(graph: NewsGraph, ids: Array[StringName]) -> Array[Array]:
	var depth: Dictionary[StringName, int] = _depths(graph, ids)
	var deepest: int = 0
	for id: StringName in ids:
		deepest = maxi(deepest, depth[id])
	var found: Array[Array] = []
	for row_number: int in deepest + 1:
		found.append([])
	for id: StringName in _sorted(ids):
		found[depth[id]].append(id)
	return found


## The top-left corner of each box, given each box's size. Rows run top to
## bottom; each item is centered over the followers placed under it; the whole
## chart is centered on x = 0.
static func positions(
	graph: NewsGraph,
	ids: Array[StringName],
	sizes: Dictionary[StringName, Vector2],
) -> Dictionary[StringName, Vector2]:
	var depth: Dictionary[StringName, int] = _depths(graph, ids)
	var children: Dictionary[StringName, Array] = {}
	var roots: Array[StringName] = []
	for id: StringName in _sorted(ids):
		var parent: StringName = _parent_of(id, graph, ids, depth)
		if parent.is_empty():
			roots.append(id)
		else:
			if not children.has(parent):
				children[parent] = []
			children[parent].append(id)
	var row_tops: Array[float] = _row_tops(ids, depth, sizes)
	var widths: Dictionary[StringName, float] = {}
	var total: float = -COLUMN_GAP
	for root: StringName in roots:
		total += _width_of(root, children, sizes, widths) + COLUMN_GAP
	var placed: Dictionary[StringName, Vector2] = {}
	var left: float = -total / 2.0
	for root: StringName in roots:
		_place(root, left, children, sizes, widths, depth, row_tops, placed)
		left += widths[root] + COLUMN_GAP
	return placed


## Where a new box goes so it covers nothing: to the right of everything on
## the chart, level with the highest box. At the origin on an empty chart.
static func free_spot(taken: Array[Rect2]) -> Vector2:
	if taken.is_empty():
		return Vector2.ZERO
	var right: float = -INF
	var top: float = INF
	for rect: Rect2 in taken:
		right = maxf(right, rect.end.x)
		top = minf(top, rect.position.y)
	return Vector2(right + COLUMN_GAP, top)


## How far down each of `ids` sits: one row below the deepest item it requires
## on the chart.
static func _depths(graph: NewsGraph, ids: Array[StringName]) -> Dictionary[StringName, int]:
	var depth: Dictionary[StringName, int] = {}
	var visiting: Dictionary[StringName, bool] = {}
	for id: StringName in ids:
		_depth_of(id, graph, ids, depth, visiting)
	return depth


## `visiting` stops a loop, which the validator refuses anyway, from running
## forever.
static func _depth_of(
	id: StringName,
	graph: NewsGraph,
	ids: Array[StringName],
	depth: Dictionary[StringName, int],
	visiting: Dictionary[StringName, bool],
) -> int:
	if depth.has(id):
		return depth[id]
	if visiting.has(id):
		return 0
	visiting[id] = true
	var own: int = 0
	for required: StringName in graph.requires_of(id):
		if ids.has(required):
			own = maxi(own, _depth_of(required, graph, ids, depth, visiting) + 1)
	visiting.erase(id)
	depth[id] = own
	return own


## The item `id` is placed under: of those it requires on the chart, the first
## by id in the row just above it. Empty for an item in the top row.
static func _parent_of(
	id: StringName,
	graph: NewsGraph,
	ids: Array[StringName],
	depth: Dictionary[StringName, int],
) -> StringName:
	var found: StringName = &""
	for required: StringName in graph.requires_of(id):
		if not ids.has(required) or depth[required] != depth[id] - 1:
			continue
		if found.is_empty() or String(required) < String(found):
			found = required
	return found


## The y of the top of each row: each row is as tall as its tallest box.
static func _row_tops(
	ids: Array[StringName],
	depth: Dictionary[StringName, int],
	sizes: Dictionary[StringName, Vector2],
) -> Array[float]:
	var heights: Array[float] = []
	for id: StringName in ids:
		while heights.size() <= depth[id]:
			heights.append(0.0)
		heights[depth[id]] = maxf(heights[depth[id]], sizes.get(id, Vector2.ZERO).y)
	var tops: Array[float] = []
	var y: float = 0.0
	for height: float in heights:
		tops.append(y)
		y += height + ROW_GAP
	return tops


## How wide `id` and everything placed under it are, side by side. Kept in
## `widths`.
static func _width_of(
	id: StringName,
	children: Dictionary[StringName, Array],
	sizes: Dictionary[StringName, Vector2],
	widths: Dictionary[StringName, float],
) -> float:
	var below: float = -COLUMN_GAP
	for child: StringName in children.get(id, []):
		below += _width_of(child, children, sizes, widths) + COLUMN_GAP
	widths[id] = maxf(sizes.get(id, Vector2.ZERO).x, below)
	return widths[id]


## Places `id` centered in its width starting at `left`, and its followers side
## by side under it, centered the same way.
static func _place(
	id: StringName,
	left: float,
	children: Dictionary[StringName, Array],
	sizes: Dictionary[StringName, Vector2],
	widths: Dictionary[StringName, float],
	depth: Dictionary[StringName, int],
	row_tops: Array[float],
	placed: Dictionary[StringName, Vector2],
) -> void:
	var own_width: float = sizes.get(id, Vector2.ZERO).x
	placed[id] = Vector2(left + (widths[id] - own_width) / 2.0, row_tops[depth[id]])
	var below: float = -COLUMN_GAP
	for child: StringName in children.get(id, []):
		below += widths[child] + COLUMN_GAP
	var child_left: float = left + (widths[id] - below) / 2.0
	for child: StringName in children.get(id, []):
		_place(child, child_left, children, sizes, widths, depth, row_tops, placed)
		child_left += widths[child] + COLUMN_GAP


static func _sorted(ids: Array[StringName]) -> Array[StringName]:
	var sorted_ids: Array[StringName] = ids.duplicate()
	sorted_ids.sort_custom(_by_text)
	return sorted_ids


static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
