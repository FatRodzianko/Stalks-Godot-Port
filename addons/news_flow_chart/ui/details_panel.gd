@tool
class_name NewsDetailsPanel
extends VBoxContainer
## The right-hand side of the News Flow tab: every field of the news item
## whose box was clicked, read-only (docs/news-flow-chart.md §2; editing
## comes in Phase 3). Field names on the left, values on the right, in the
## order the item's script declares them.
##
## A reusable widget: it is handed an item and knows nothing about the chart.
## `@tool` because it runs inside the editor.


const EMPTY_TITLE: String = "Details"

@onready var _title_label: Label = %TitleLabel
@onready var _fields: GridContainer = %Fields


func _ready() -> void:
	clear()


## Shows every field of `line`.
func show_item(line: Resource) -> void:
	_remove_fields()
	_title_label.text = NewsItemSummary.kind_name(line)
	for field: PackedStringArray in NewsItemSummary.fields(line):
		_add_label(field[0], false)
		_add_label(field[1], true)


## Shows nothing.
func clear() -> void:
	_remove_fields()
	_title_label.text = EMPTY_TITLE


func title_text() -> String:
	return _title_label.text


## What is shown, field name to value.
func shown_fields() -> Dictionary[String, String]:
	var shown: Dictionary[String, String] = {}
	var labels: Array[Node] = _fields.get_children()
	for index: int in range(0, labels.size() - 1, 2):
		shown[(labels[index] as Label).text] = (labels[index + 1] as Label).text
	return shown


func _add_label(text: String, is_value: bool) -> void:
	var label: Label = Label.new()
	label.text = text
	if is_value:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields.add_child(label)


func _remove_fields() -> void:
	for child: Node in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
