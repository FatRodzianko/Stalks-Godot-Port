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

## The color of the selected arrow. Godot colors a connection with its
## "activity" theme color, which is white by default, the same as every other
## arrow, so a selected one looked unchanged (D229). This is an editor tool, not
## the game, so it does not use the game's theme.
const SELECTED_COLOR: Color = Color(1.0, 0.65, 0.15)

## The box a drag started on, and whether from its bottom dot; empty when no
## arrow is being drawn.
var _dragged_from: StringName = &""
var _dragged_from_bottom: bool = true
## The selected arrow's two boxes; empty when none is selected.
var _selected_from: StringName = &""
var _selected_to: StringName = &""


func _ready() -> void:
	right_disconnects = false
	add_theme_color_override(&"activity", SELECTED_COLOR)
	connection_drag_started.connect(_on_connection_drag_started)
	connection_drag_ended.connect(_on_connection_drag_ended)
	connection_request.connect(_on_connection_request)
	connection_to_empty.connect(_on_connection_to_empty)
	connection_from_empty.connect(_on_connection_from_empty)
	delete_nodes_request.connect(_on_delete_nodes_request)
	gui_input.connect(_on_gui_input)


## Ends a line still being drawn once the mouse moves with its button no longer
## held. That happens when something else took the button's release, such as a
## screenshot tool opened mid-drag; Godot would otherwise keep the line on the
## mouse until the next click (found by hand, D228).
func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null or _dragged_from.is_empty():
		return
	if motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
		force_connection_drag_end()
		_on_connection_drag_ended()


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
## which for a finished arrow are `(box offset + port position) * zoom`; the
## boxes they belong to are found from those, and the arrow drawn between their
## bottom and top. The line still being dragged is handled first
## (`_dragged_line`).
func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var dragged: PackedVector2Array = _dragged_line(from_position, to_position)
	if not dragged.is_empty():
		return dragged
	var from_box: GraphNode = _box_with_port(from_position, false, Vector2.ZERO)
	var to_box: GraphNode = _box_with_port(to_position, true, Vector2.ZERO)
	if from_box != null and to_box != null:
		var start: Vector2 = (from_box.position_offset + NewsItemBox.bottom_dot(from_box.size)) * zoom
		var end: Vector2 = (to_box.position_offset + NewsItemBox.top_dot(to_box.size)) * zoom
		var points: PackedVector2Array = curve_points(start, end, connection_lines_curvature, true)
		points.append_array(head(end, Vector2.DOWN, zoom))
		return points
	var plain: PackedVector2Array = PackedVector2Array([from_position, to_position])
	plain.append_array(head(to_position, _direction(from_position, to_position), zoom))
	return plain

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


## The line being dragged, or nothing when no line is being dragged or these
## two points are not it. It is drawn from the dot pressed to the mouse, head
## at the mouse, since the box pressed is the one required. When the mouse is
## over a dot Godot would join, Godot hands over that box's side dot instead of
## the mouse, and the line ends on the matching top or bottom dot.
##
## Godot hands the dragged line over in a different space from a finished
## arrow: shifted by the scroll, `(box offset + port position) * zoom - scroll`.
## Both are tried. (Found by hand: once the chart had been scrolled, the line
## was drawn from side dot to side dot, D228.)
func _dragged_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	if _dragged_from.is_empty():
		return PackedVector2Array()
	var pressed: GraphNode = get_node_or_null(NodePath(String(_dragged_from))) as GraphNode
	if pressed == null:
		return PackedVector2Array()
	for shift: Vector2 in [-scroll_offset, Vector2.ZERO]:
		var other_end: Vector2 = from_position
		if _port_of(pressed, not _dragged_from_bottom, shift).distance_to(from_position) <= PORT_MATCH_DISTANCE:
			other_end = to_position
		elif _port_of(pressed, not _dragged_from_bottom, shift).distance_to(to_position) > PORT_MATCH_DISTANCE:
			continue
		var start: Vector2 = _dot_of(pressed, _dragged_from_bottom, shift)
		var end: Vector2 = other_end
		var target: GraphNode = _box_with_port(other_end, _dragged_from_bottom, shift)
		if target != null and target != pressed:
			if is_node_connected(pressed.name, 0, target.name, 0) or is_node_connected(target.name, 0, pressed.name, 0):
				# Not the dragged line: a finished arrow between the same two boxes.
				return PackedVector2Array()
			end = _dot_of(target, not _dragged_from_bottom, shift)
		var line: PackedVector2Array = PackedVector2Array([start, end])
		line.append_array(head(end, _direction(start, end), zoom))
		return line
	return PackedVector2Array()


## Where Godot's side dot of `box` is: the left (incoming) one when
## `is_input`, in the space shifted by `shift`.
func _port_of(box: GraphNode, is_input: bool, shift: Vector2) -> Vector2:
	var port: Vector2 = box.get_output_port_position(0)
	if is_input:
		port = box.get_input_port_position(0)
	return (box.position_offset + port) * zoom + shift


## Where the tool's own dot of `box` is: the bottom one when `bottom`, else the
## top one, in the space shifted by `shift`.
func _dot_of(box: GraphNode, bottom: bool, shift: Vector2) -> Vector2:
	var dot: Vector2 = NewsItemBox.top_dot(box.size)
	if bottom:
		dot = NewsItemBox.bottom_dot(box.size)
	return (box.position_offset + dot) * zoom + shift


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


## The box whose side dot, the incoming one when `is_input`, is at `at` in the
## space shifted by `shift`; null when none is.
func _box_with_port(at: Vector2, is_input: bool, shift: Vector2) -> GraphNode:
	for child: Node in get_children():
		var box: GraphNode = child as GraphNode
		if box == null or box.get_input_port_count() == 0:
			continue
		if _port_of(box, is_input, shift).distance_to(at) <= PORT_MATCH_DISTANCE:
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
