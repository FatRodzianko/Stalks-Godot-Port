class_name NewsLayout
extends RefCounted
## Where the News Flow Chart puts its boxes: **top to bottom**, the way a chain
## is read (decisions.md D226). An item sits one row below the lowest item it
## requires, so every arrow points down. Items that require nothing on the
## chart share the top row.
##
## Godot's own `GraphEdit.arrange_nodes` lays out left to right and cannot be
## turned, so the tool does its own. It is kept simple: rows by depth, and
## within a row each item placed under the middle of the items it requires,
## which keeps most arrows from crossing.
##
## Part of the News Flow Chart's `core/`: pure logic, tested headless.


## The space between one row and the next, and between boxes in a row.
const ROW_GAP: float = 80.0
const COLUMN_GAP: float = 40.0


## The rows of `ids`, top first. Only arrows between items in `ids` count, so
## an item whose requirements are all off the chart starts a row of its own
## at the top.
static func rows(graph: NewsGraph, ids: Array[StringName]) -> Array[Array]:
	var depth: Dictionary[StringName, int] = {}
	var visiting: Dictionary[StringName, bool] = {}
	var deepest: int = 0
	for id: StringName in ids:
		deepest = maxi(deepest, _depth_of(id, graph, ids, depth, visiting))
	var found: Array[Array] = []
	for row_number: int in deepest + 1:
		found.append([])
	var sorted_ids: Array[StringName] = ids.duplicate()
	sorted_ids.sort_custom(_by_text)
	for id: StringName in sorted_ids:
		found[depth[id]].append(id)
	for row_number: int in range(1, found.size()):
		_order_under_parents(found, row_number, graph)
	return found


## The top-left corner of each box, given each box's size: rows top to bottom,
## each row centered on the same line.
static func positions(laid_out: Array[Array], sizes: Dictionary[StringName, Vector2]) -> Dictionary[StringName, Vector2]:
	var placed: Dictionary[StringName, Vector2] = {}
	var y: float = 0.0
	for row: Array in laid_out:
		var width: float = -COLUMN_GAP
		var height: float = 0.0
		for id: StringName in row:
			var size: Vector2 = sizes.get(id, Vector2.ZERO)
			width += size.x + COLUMN_GAP
			height = maxf(height, size.y)
		var x: float = -width / 2.0
		for id: StringName in row:
			placed[id] = Vector2(x, y)
			x += sizes.get(id, Vector2.ZERO).x + COLUMN_GAP
		y += height + ROW_GAP
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


## How far down `id` sits: one below the deepest item it requires on the chart.
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


## Sorts row `row_number` by the average place, in the rows above, of the items
## each one requires; ties by id.
static func _order_under_parents(laid_out: Array[Array], row_number: int, graph: NewsGraph) -> void:
	var place: Dictionary[StringName, float] = {}
	for above: int in row_number:
		var row: Array = laid_out[above]
		for index: int in row.size():
			place[row[index]] = float(index) - float(row.size() - 1) / 2.0
	var middle: Dictionary[StringName, float] = {}
	for id: StringName in laid_out[row_number]:
		var total: float = 0.0
		var count: int = 0
		for required: StringName in graph.requires_of(id):
			if place.has(required):
				total += place[required]
				count += 1
		middle[id] = total / maxf(count, 1)
	laid_out[row_number].sort_custom(_by_middle.bind(middle))


static func _by_middle(a: StringName, b: StringName, middle: Dictionary[StringName, float]) -> bool:
	if not is_equal_approx(middle[a], middle[b]):
		return middle[a] < middle[b]
	return String(a) < String(b)


static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
