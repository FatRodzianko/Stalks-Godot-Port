@tool
class_name NewsItemBox
extends GraphNode
## One news item on the News Flow Chart: a box showing its kind (the title),
## its id, its conditions and the first words of its headline or text
## (docs/news-flow-chart.md §2). Arrows come in on the left, from the items it
## requires, and go out on the right, to the items that require it.
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
