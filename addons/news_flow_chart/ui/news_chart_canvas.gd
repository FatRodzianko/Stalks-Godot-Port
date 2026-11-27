@tool
class_name NewsChartCanvas
extends GraphEdit
## The News Flow tab's chart: Godot's `GraphEdit`, with its arrows drawn **top
## to bottom** and given a head, so you can see which way a chain runs
## (decisions.md D226). A plain `GraphEdit` draws a line, with no head, from the
## dot on the right of one box to the dot on the left of the next.
##
## An arrow leaves the bottom middle of the box that is required and ends, head
## down, on the top middle of the box that requires it: an arrow from A to B
## means "B requires A" (docs/news-flow-chart.md, "Words used here"). The dots
## on the sides of each box are still where an arrow is drawn from and to with
## the mouse; while one is being dragged, the line follows the mouse from the
## dot as Godot draws it.
##
## `@tool` because it runs inside the editor.


## The length and half-width of the head, before zoom.
const HEAD_LENGTH: float = 14.0
const HEAD_HALF_WIDTH: float = 7.0

## How finely the curve is drawn, as `Curve2D.tessellate` takes it.
const CURVE_STAGES: int = 5
const CURVE_TOLERANCE_DEGREES: float = 2.0

## How near, in pixels, a port must be to the point Godot hands over for it
## to count as that box's port.
const PORT_MATCH_DISTANCE: float = 1.0


## The points of one connection. Godot hands over the two ports' positions,
## which are `(box offset + port position) * zoom`; the boxes they belong to
## are found from those, and the arrow drawn between their bottom and top.
## A connection still being dragged ends at the mouse, not a box, and is drawn
## as Godot would, with a head.
func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var from_box: GraphNode = _box_with_port(from_position, false)
	var to_box: GraphNode = _box_with_port(to_position, true)
	if from_box == null or to_box == null:
		var sideways: PackedVector2Array = curve_points(from_position, to_position, connection_lines_curvature, false)
		sideways.append_array(head(to_position, Vector2.RIGHT, zoom))
		return sideways
	var start: Vector2 = (from_box.position_offset + Vector2(from_box.size.x / 2.0, from_box.size.y)) * zoom
	var end: Vector2 = (to_box.position_offset + Vector2(to_box.size.x / 2.0, 0.0)) * zoom
	var points: PackedVector2Array = curve_points(start, end, connection_lines_curvature, true)
	points.append_array(head(end, Vector2.DOWN, zoom))
	return points


## A curve from `start` to `end` that leaves and arrives straight: downwards
## when `downwards`, else sideways, as `GraphEdit` draws by default. Bent by
## `curvature`.
static func curve_points(start: Vector2, end: Vector2, curvature: float, downwards: bool) -> PackedVector2Array:
	if curvature <= 0.0:
		return PackedVector2Array([start, end])
	var handle: Vector2 = Vector2(absf(end.x - start.x) * curvature, 0.0)
	if downwards:
		handle = Vector2(0.0, absf(end.y - start.y) * curvature)
	var curve: Curve2D = Curve2D.new()
	curve.add_point(start, Vector2.ZERO, handle)
	curve.add_point(end, -handle, Vector2.ZERO)
	return curve.tessellate(CURVE_STAGES, CURVE_TOLERANCE_DEGREES)


## The strokes of an arrowhead whose point is at `tip`, pointing along
## `direction`: out to one barb, back to the tip, out to the other.
static func head(tip: Vector2, direction: Vector2, scale: float) -> PackedVector2Array:
	var back: Vector2 = -direction * HEAD_LENGTH * scale
	var side: Vector2 = direction.orthogonal() * HEAD_HALF_WIDTH * scale
	return PackedVector2Array([tip + back + side, tip, tip + back - side])


func _box_with_port(at: Vector2, is_input: bool) -> GraphNode:
	for child: Node in get_children():
		var box: GraphNode = child as GraphNode
		if box == null or box.get_input_port_count() == 0:
			continue
		var port: Vector2 = box.get_output_port_position(0)
		if is_input:
			port = box.get_input_port_position(0)
		if ((box.position_offset + port) * zoom).distance_to(at) <= PORT_MATCH_DISTANCE:
			return box
	return null
