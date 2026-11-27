@tool
class_name NewsItemBox
extends GraphNode
## One news item on the News Flow Chart: a box showing its kind (the title),
## its id, its conditions and the first words of its headline or text
## (docs/news-flow-chart.md §2). Arrows come in at the top, from the items it
## requires, and go out at the bottom, to the items that require it.
##
## It has one dot at the top middle and one at the bottom middle, where an arrow
## is drawn from with the mouse (decisions.md D227). Godot's `GraphNode` only
## puts its dots on the left and right sides, so it is given one slot as usual,
## its side dots are not drawn (`_draw_port`), and these two are drawn instead.
## `NewsChartCanvas` makes them the places that answer the mouse.
##
## A reusable widget: it knows its item and nothing about the chart holding
## it. Its node name is the item's id, which is what `GraphEdit` arrows name.
## `@tool` because it runs inside the editor, in the News Flow tab.


## The one slot, on the id label, that every arrow joins.
const LINK_SLOT: int = 0

## The id of the item shown.
var item_id: StringName = &""

@onready var _id_label: Label = %IdLabel
@onready var _conditions_label: Label = %ConditionsLabel
@onready var _words_label: Label = %WordsLabel


func _ready() -> void:
	set_slot_enabled_left(LINK_SLOT, true)
	set_slot_enabled_right(LINK_SLOT, true)
	resized.connect(queue_redraw)


func _draw() -> void:
	var dot: Texture2D = get_theme_icon(&"port", &"GraphNode")
	var half: Vector2 = dot.get_size() / 2.0
	draw_texture(dot, top_dot(size) - half, get_slot_color_left(LINK_SLOT))
	draw_texture(dot, bottom_dot(size) - half, get_slot_color_right(LINK_SLOT))


## Godot's side dots are not drawn: `_draw` draws the top and bottom ones.
func _draw_port(_slot_index: int, _position: Vector2i, _left: bool, _color: Color) -> void:
	pass


## Where the top dot is, inside a box of `box_size`: arrows come in here.
static func top_dot(box_size: Vector2) -> Vector2:
	return Vector2(box_size.x / 2.0, 0.0)


## Where the bottom dot is: arrows go out here.
static func bottom_dot(box_size: Vector2) -> Vector2:
	return Vector2(box_size.x / 2.0, box_size.y)


## Fills the box from `line`. Call once the box is in the tree.
func show_item(line: Resource) -> void:
	item_id = line.get("id")
	title = NewsItemSummary.kind_name(line)
	_id_label.text = String(item_id)
	_conditions_label.text = NewsItemSummary.conditions(line)
	_words_label.text = NewsItemSummary.first_words(line)


func id_text() -> String:
	return _id_label.text


func conditions_text() -> String:
	return _conditions_label.text


func words_text() -> String:
	return _words_label.text
