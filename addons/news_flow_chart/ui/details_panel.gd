@tool
class_name NewsDetailsPanel
extends VBoxContainer
## The right-hand side of the News Flow tab: every field of one news item,
## each editable (docs/news-flow-chart.md §2, Phase 3).
##
## Each field gets the control its type calls for: a dropdown for a choice
## (mood, move, outcome...) and for a company, industry or trader; a number
## box for the amount; a text box for words. The id is shown but never
## editable (§3.3). **Requires** lists the items this one waits for, each with
## a **Remove** button, and a dropdown to add another.
##
## A reusable widget: it is handed an item and the choices to offer, and says
## what the person changed through its signals. It changes nothing itself; the
## chart decides what to do with each change. For a new item that does not
## exist yet (a *draft*) it shows **Create** and **Cancel** instead of the
## requires list. `@tool` because it runs inside the editor.


## A field was changed to `value`.
signal field_changed(field: StringName, value: Variant)
## The person picked `id` to add to this item's requires list.
signal requirement_added(id: StringName)
## The person removed `id` from this item's requires list.
signal requirement_removed(id: StringName)
## The person clicked **Create** on a draft.
signal create_pressed
## The person clicked **Cancel** on a draft.
signal cancel_pressed

const EMPTY_TITLE: String = "Details"
const DRAFT_ID: String = "(given on Create)"
const ADD_REQUIREMENT: String = "Add a requirement..."

## The fields that are not edited as ordinary fields.
const ID_FIELD: StringName = &"id"
const REQUIRES_FIELD: StringName = &"requires"

## The amount's range: far beyond any sensible market news effect.
const AMOUNT_LIMIT: int = 100000

## The field name of each control, by the control.
var _field_of: Dictionary[Control, StringName] = {}
## The values offered by each dropdown, in item order.
var _option_values: Dictionary[OptionButton, Array] = {}

@onready var _title_label: Label = %TitleLabel
@onready var _fields: GridContainer = %Fields
@onready var _draft_buttons: HBoxContainer = %DraftButtons
@onready var _create_button: Button = %CreateButton
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	_create_button.pressed.connect(_on_create_button_pressed)
	_cancel_button.pressed.connect(_on_cancel_button_pressed)
	clear()


## Shows every field of `line`. `choices` holds, by field, the
## `NewsFieldChoices.Choice` list for each company, industry, subject or trader
## field; `requires_options` the ids it could be made to require. A draft
## shows Create and Cancel instead of the requires list.
func show_item(
	line: Resource,
	choices: Dictionary[StringName, Array],
	requires_options: Array[StringName],
	is_draft: bool = false,
) -> void:
	_remove_fields()
	_title_label.text = NewsItemSummary.kind_name(line)
	if is_draft:
		_title_label.text = "New %s" % _title_label.text.to_lower()
	_draft_buttons.visible = is_draft
	for property: Dictionary in NewsItemSummary.stored_properties(line):
		var field: StringName = property["name"]
		if field == REQUIRES_FIELD and is_draft:
			continue
		_add_name_label(field)
		var control: Control = _control_for(line, property, choices, requires_options, is_draft)
		_field_of[control] = field
		_fields.add_child(control)


## Shows nothing.
func clear() -> void:
	_remove_fields()
	_title_label.text = EMPTY_TITLE
	_draft_buttons.visible = false


func title_text() -> String:
	return _title_label.text


## The control editing `field`, or null.
func control_for(field: StringName) -> Control:
	for control: Control in _field_of:
		if _field_of[control] == field:
			return control
	return null


## The fields shown, field name to the value as text.
func shown_fields() -> Dictionary[String, String]:
	var shown: Dictionary[String, String] = {}
	var children: Array[Node] = _fields.get_children()
	for index: int in range(0, children.size() - 1, 2):
		shown[(children[index] as Label).text] = _text_of(children[index + 1])
	return shown


func is_draft_shown() -> bool:
	return _draft_buttons.visible


func _control_for(
	line: Resource,
	property: Dictionary,
	choices: Dictionary[StringName, Array],
	requires_options: Array[StringName],
	is_draft: bool,
) -> Control:
	var field: StringName = property["name"]
	var value: Variant = line.get(field)
	if field == ID_FIELD:
		return _id_label(value, is_draft)
	if field == REQUIRES_FIELD:
		return _requires_box(value, requires_options)
	if property["hint"] == PROPERTY_HINT_ENUM:
		return _enum_option(line, field, value)
	if choices.has(field):
		return _choice_option(field, value, choices[field])
	if property["type"] == TYPE_INT:
		return _number_box(field, value)
	if property["type"] == TYPE_STRING:
		return _text_box(field, value)
	return _line_box(field, value)


func _id_label(value: Variant, is_draft: bool) -> Label:
	var label: Label = Label.new()
	label.text = str(value)
	if is_draft:
		label.text = DRAFT_ID
	return label


func _enum_option(line: Resource, field: StringName, value: Variant) -> OptionButton:
	var option: OptionButton = _option(field)
	var names: Dictionary[int, String] = NewsItemSummary.enum_names(line, field)
	var numbers: Array[int] = []
	numbers.assign(names.keys())
	numbers.sort()
	for number: int in numbers:
		_add_option_item(option, names[number], number)
	_select_value(option, value)
	return option


func _choice_option(field: StringName, value: Variant, field_choices: Array) -> OptionButton:
	var option: OptionButton = _option(field)
	for choice: NewsFieldChoices.Choice in field_choices:
		_add_option_item(option, choice.label, choice.id)
	if not _option_values[option].has(value):
		_add_option_item(option, "%s (not found)" % value, value)
	_select_value(option, value)
	return option


func _number_box(field: StringName, value: Variant) -> SpinBox:
	var box: SpinBox = SpinBox.new()
	box.min_value = -AMOUNT_LIMIT
	box.max_value = AMOUNT_LIMIT
	box.step = 1
	box.rounded = true
	box.value = value
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_of[box] = field
	box.value_changed.connect(_on_number_box_value_changed.bind(box))
	return box


func _text_box(field: StringName, value: Variant) -> TextEdit:
	var box: TextEdit = TextEdit.new()
	box.text = str(value)
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.scroll_fit_content_height = true
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_of[box] = field
	box.text_changed.connect(_on_text_box_text_changed.bind(box))
	return box


func _line_box(field: StringName, value: Variant) -> LineEdit:
	var box: LineEdit = LineEdit.new()
	box.text = str(value)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_of[box] = field
	box.text_changed.connect(_on_line_box_text_changed.bind(box))
	return box


## The requires list: one row per id with a Remove button, then a dropdown of
## every id that could be added.
func _requires_box(value: Variant, requires_options: Array[StringName]) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_of[box] = REQUIRES_FIELD
	var required: Array[StringName] = []
	required.assign(value)
	for id: StringName in required:
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = String(id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove: Button = Button.new()
		remove.text = "Remove"
		remove.name = "Remove_%s" % String(id).validate_node_name()
		remove.pressed.connect(_on_remove_button_pressed.bind(id))
		row.add_child(remove)
		box.add_child(row)
	var adder: OptionButton = OptionButton.new()
	adder.name = "AddRequirement"
	_option_values[adder] = []
	_add_option_item(adder, ADD_REQUIREMENT, &"")
	for id: StringName in requires_options:
		if not required.has(id):
			_add_option_item(adder, String(id), id)
	adder.select(0)
	adder.item_selected.connect(_on_add_requirement_item_selected.bind(adder))
	box.add_child(adder)
	return box


func _option(field: StringName) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	_field_of[option] = field
	_option_values[option] = []
	option.item_selected.connect(_on_option_item_selected.bind(option))
	return option


func _add_option_item(option: OptionButton, text: String, value: Variant) -> void:
	option.add_item(text)
	_option_values[option].append(value)


func _select_value(option: OptionButton, value: Variant) -> void:
	option.select(_option_values[option].find(value))


func _add_name_label(field: StringName) -> void:
	var label: Label = Label.new()
	label.text = String(field).capitalize()
	_fields.add_child(label)


func _text_of(node: Node) -> String:
	if node is Label:
		return (node as Label).text
	if node is OptionButton:
		var option: OptionButton = node as OptionButton
		return option.get_item_text(option.selected)
	if node is SpinBox:
		return str(int((node as SpinBox).value))
	if node is TextEdit:
		return (node as TextEdit).text
	if node is LineEdit:
		return (node as LineEdit).text
	var ids: PackedStringArray = []
	for label: Node in node.find_children("*", "Label", true, false):
		ids.append((label as Label).text)
	return ", ".join(ids)


func _remove_fields() -> void:
	_field_of.clear()
	_option_values.clear()
	for child: Node in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()


func _on_option_item_selected(index: int, option: OptionButton) -> void:
	field_changed.emit(_field_of[option], _option_values[option][index])


func _on_number_box_value_changed(value: float, box: SpinBox) -> void:
	field_changed.emit(_field_of[box], int(value))


func _on_text_box_text_changed(box: TextEdit) -> void:
	field_changed.emit(_field_of[box], box.text)


func _on_line_box_text_changed(text: String, box: LineEdit) -> void:
	field_changed.emit(_field_of[box], StringName(text))


func _on_add_requirement_item_selected(index: int, adder: OptionButton) -> void:
	var id: StringName = _option_values[adder][index]
	if id.is_empty():
		return
	requirement_added.emit(id)


func _on_remove_button_pressed(id: StringName) -> void:
	requirement_removed.emit(id)


func _on_create_button_pressed() -> void:
	create_pressed.emit()


func _on_cancel_button_pressed() -> void:
	cancel_pressed.emit()
