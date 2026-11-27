@tool
class_name NewsChartCanvas
extends GraphEdit
## The News Flow tab's chart: Godot's `GraphEdit`, with its arrows drawn **top
## to bottom**, given a head, drawn with the mouse from either dot, and
## selectable (decisions.md D226, D227).
##
## An arrow leaves the bottom middle of the box that is required and ends, head
## down, on the top middle of the box that requires it: an arrow from A to B
## means "B requires A" (docs/news-flow-chart.md, "Words used here").
##
## **Drawing one.** Each box has a dot at its top and bottom middle
## (`NewsItemBox`). Press on either dot of a box, drag, and let go on either dot
## of another box, or anywhere on it: the box pressed first is the one required,
## as in other node editors where the first thing clicked is where a link comes
## from. `GraphEdit` itself only joins a right-hand dot to a left-hand one, and
## says which end is which by the side, so the canvas tells it where the dots
## are (`_is_in_input_hotzone`, `_is_in_output_hotzone`), notes which box a drag
## started on, and turns whatever Godot reports into `arrow_drawn`, from that box.
##
## **Removing one.** Click on an arrow to select it, then press Delete
## (`arrow_delete_requested`).
##
## `@tool` because it runs inside the editor.


## An arrow was drawn with the mouse from `from_box`, the box pressed first, to
## `to_box`. Box names, as `GraphEdit` knows them.
signal arrow_drawn(from_box: StringName, to_box: StringName)
## Delete was pressed while the arrow from `from_box` to `to_box` was selected.
signal arrow_delete_requested(from_box: StringName, to_box: StringName)

## The length and half-width of the head, before zoom.
const HEAD_LENGTH: float = 14.0
const HEAD_HALF_WIDTH: float = 7.0

## How finely the curve is drawn, as `Curve2D.tessellate` takes it.
const CURVE_STAGES: int = 5
const CURVE_TOLERANCE_DEGREES: float = 2.0

## How near, in pixels, a port must be to the point Godot hands over for it
## to count as that box's port.
const PORT_MATCH_DISTANCE: float = 1.0

## How near, in screen pixels, the mouse must be to a dot to press it, and to
## an arrow to select it.
const DOT_REACH: float = 12.0
const LINE_REACH: float = 8.0

## The box a drag started on, and whether from its bottom dot; empty when no
## arrow is being drawn.
var _dragged_from: StringName = &""
var _dragged_from_bottom: bool = true
## The selected arrow's two boxes; empty when none is selected.
var _selected_from: StringName = &""
var _selected_to: StringName = &""


func _ready() -> void:
	right_disconnects = false
	connection_drag_started.connect(_on_connection_drag_started)
	connection_drag_ended.connect(_on_connection_drag_ended)
	connection_request.connect(_on_connection_request)
	connection_to_empty.connect(_on_connection_to_empty)
	connection_from_empty.connect(_on_connection_from_empty)
	delete_nodes_request.connect(_on_delete_nodes_request)
	gui_input.connect(_on_gui_input)


## The selected arrow as `[from box, to box]`, or empty.
func selected_arrow() -> Array[StringName]:
	if _selected_from.is_empty() or not is_node_connected(_selected_from, 0, _selected_to, 0):
		return []
	return [_selected_from, _selected_to]


## Selects the arrow nearest `at` (in the chart's own coordinates), or none if
## no arrow is that near. True when one was selected.
func select_arrow_at(at: Vector2) -> bool:
	_show_selected(0.0)
	_selected_from = &""
	_selected_to = &""
	var nearest: Dictionary = get_closest_connection_at_point(at, LINE_REACH)
	if nearest.is_empty():
		return false
	_selected_from = nearest["from_node"]
	_selected_to = nearest["to_node"]
	_show_selected(1.0)
	return true


## The box under `at`, in the chart's own coordinates, or, failing that, the
## box whose dots or edge are within reach of it; null when there is none.
func box_at(at: Vector2) -> GraphNode:
	for reach: float in [0.0, DOT_REACH]:
		for child: Node in get_children():
			var box: GraphNode = child as GraphNode
			if box != null and Rect2(box.position, box.size * zoom).grow(reach).has_point(at):
				return box
	return null


## Godot asks whether the mouse is on a box's incoming dot: the top one.
func _is_in_input_hotzone(in_node: Object, _in_port: int, mouse_position: Vector2) -> bool:
	var box: GraphNode = in_node as GraphNode
	return box != null and _is_near_dot(box, NewsItemBox.top_dot(box.size), mouse_position)


## Godot asks whether the mouse is on a box's outgoing dot: the bottom one.
func _is_in_output_hotzone(in_node: Object, _in_port: int, mouse_position: Vector2) -> bool:
	var box: GraphNode = in_node as GraphNode
	return box != null and _is_near_dot(box, NewsItemBox.bottom_dot(box.size), mouse_position)


## The points of one connection. Godot hands over the two ports' positions,
## which are `(box offset + port position) * zoom`; the boxes they belong to
## are found from those, and the arrow drawn between their bottom and top.
## A connection still being dragged runs from the dot pressed to the mouse,
## with its head at the mouse.
func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var from_box: GraphNode = _box_with_port(from_position, false)
	var to_box: GraphNode = _box_with_port(to_position, true)
	if from_box != null and to_box != null:
		var start: Vector2 = (from_box.position_offset + NewsItemBox.bottom_dot(from_box.size)) * zoom
		var end: Vector2 = (to_box.position_offset + NewsItemBox.top_dot(to_box.size)) * zoom
		var points: PackedVector2Array = curve_points(start, end, connection_lines_curvature, true)
		points.append_array(head(end, Vector2.DOWN, zoom))
		return points
	return _dragged_line(from_position, to_position, from_box, to_box)


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


## The line being dragged: one end is the port of the box pressed, the other
## the mouse. It is drawn from that box's dot, the one pressed, to the mouse,
## with the head at the mouse, since the box pressed is the one required.
func _dragged_line(
	from_position: Vector2,
	to_position: Vector2,
	from_box: GraphNode,
	to_box: GraphNode,
) -> PackedVector2Array:
	var pressed: GraphNode = from_box
	var port: Vector2 = from_position
	var mouse: Vector2 = to_position
	if pressed == null:
		pressed = to_box
		port = to_position
		mouse = from_position
	if pressed == null:
		var plain: PackedVector2Array = PackedVector2Array([from_position, to_position])
		plain.append_array(head(to_position, _direction(from_position, to_position), zoom))
		return plain
	var own_port: Vector2 = pressed.get_output_port_position(0)
	if pressed == to_box:
		own_port = pressed.get_input_port_position(0)
	var dot: Vector2 = NewsItemBox.top_dot(pressed.size)
	if _dragged_from_bottom:
		dot = NewsItemBox.bottom_dot(pressed.size)
	var start: Vector2 = port + (dot - own_port) * zoom
	var line: PackedVector2Array = PackedVector2Array([start, mouse])
	line.append_array(head(mouse, _direction(start, mouse), zoom))
	return line


static func _direction(start: Vector2, end: Vector2) -> Vector2:
	if start.is_equal_approx(end):
		return Vector2.DOWN
	return (end - start).normalized()


## Whether `mouse_position`, as Godot hands it to the hotzone checks (the
## chart's own coordinates divided by zoom), is on the dot at `dot` inside
## `box`.
func _is_near_dot(box: GraphNode, dot: Vector2, mouse_position: Vector2) -> bool:
	var dot_at: Vector2 = (box.position + dot * zoom) / zoom
	return dot_at.distance_to(mouse_position) <= DOT_REACH / zoom


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


func _show_selected(activity: float) -> void:
	if not _selected_from.is_empty() and is_node_connected(_selected_from, 0, _selected_to, 0):
		set_connection_activity(_selected_from, 0, _selected_to, 0, activity)


## The box pressed first is the one required. Godot names the box whose
## bottom dot the line joins as `from_node`; when the drag started on a top
## dot, that is the other box.
func _report_arrow(pressed: StringName, other: StringName) -> void:
	if pressed.is_empty() or other.is_empty() or pressed == other:
		return
	arrow_drawn.emit(pressed, other)


func _on_connection_drag_started(from_node: StringName, _from_port: int, is_output: bool) -> void:
	_dragged_from = from_node
	_dragged_from_bottom = is_output


func _on_connection_drag_ended() -> void:
	_dragged_from = &""
	_dragged_from_bottom = true


func _on_connection_request(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	if _dragged_from == to_node and not _dragged_from_bottom:
		_report_arrow(to_node, from_node)
	else:
		_report_arrow(from_node, to_node)


## Let go somewhere that is not a dot Godot would join: anywhere on another
## box still makes the arrow.
func _on_connection_to_empty(from_node: StringName, _from_port: int, release_position: Vector2) -> void:
	var box: GraphNode = box_at(release_position)
	if box != null:
		_report_arrow(from_node, box.name)


func _on_connection_from_empty(to_node: StringName, _to_port: int, release_position: Vector2) -> void:
	var box: GraphNode = box_at(release_position)
	if box != null:
		_report_arrow(to_node, box.name)


## Delete pressed. The boxes selected are left alone: deleting an item is
## Phase 4's, with its own question.
func _on_delete_nodes_request(_nodes: Array[StringName]) -> void:
	var arrow: Array[StringName] = selected_arrow()
	if arrow.is_empty():
		return
	_selected_from = &""
	_selected_to = &""
	arrow_delete_requested.emit(arrow[0], arrow[1])


## A left click on the chart itself, not on a box, selects the arrow under it,
## or clears the selection.
func _on_gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if select_arrow_at(click.position):
		grab_focus()
