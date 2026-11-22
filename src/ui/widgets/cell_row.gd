class_name CellRow
extends PanelContainer
## One line of a text table: a row of labels, each a whole number of characters
## wide. Every table on the StalkleHeads tabs that is only text - the desk, short
## interest, the market figures, the industries, a company's earnings - is a
## list of these (CLAUDE.md: a repeated row is one reusable scene).
##
## **Widths are in characters, not pixels.** The screen is a 106 x 30 grid of
## 6 x 12 cells (docs/ui-reference.md), so a column is "seven wide", and this
## multiplies by `CELL_WIDTH`. Cells sit edge to edge with no separation
## (`TightHBox`), so a table's columns are exactly the sum of their widths and
## line up with any other table built the same way. A width of 0 means "take
## what is left", for a name column.
##
## A row may be clickable: it then emits `pressed` with its `key`, which is an
## id, never the row itself (CLAUDE.md: signals carry data, not nodes).


## Somebody clicked a clickable row.
signal pressed(key: StringName)


## Pixels per character at the game's font size (docs/ui-reference.md).
const CELL_WIDTH: int = 6

## How a cell lines its text up.
const LEFT: int = HORIZONTAL_ALIGNMENT_LEFT
const RIGHT: int = HORIZONTAL_ALIGNMENT_RIGHT
const CENTRE: int = HORIZONTAL_ALIGNMENT_CENTER

## The ordinary pointer, Godot's cursor shape 0, for a row that is not
## clickable. Written as a number because the conventions check reserves the
## shape's name as a placeholder marker (test_conventions.gd).
const PLAIN_CURSOR: Control.CursorShape = 0 as Control.CursorShape


## What this row stands for - a company id, an industry id - sent with
## `pressed`.
var key: StringName = &""

var _clickable: bool = false
var _labels: Array[Label] = []

@onready var _cells: HBoxContainer = %Cells


## Builds the row's cells: one per entry in `widths` (characters, 0 to expand),
## aligned by the matching entry in `aligns` (LEFT when missing). Call once,
## before setting any text.
func configure(widths: Array[int], aligns: Array[int] = []) -> void:
	for label: Label in _labels:
		_cells.remove_child(label)
		label.queue_free()
	_labels.clear()
	for index: int in widths.size():
		var label: Label = Label.new()
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.custom_minimum_size.x = widths[index] * CELL_WIDTH
		if widths[index] == 0:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.horizontal_alignment = LEFT
		if index < aligns.size():
			label.horizontal_alignment = aligns[index] as HorizontalAlignment
		_cells.add_child(label)
		_labels.append(label)


## Sets every cell's text, in order. Extra texts are ignored; missing ones
## leave their cell empty.
func set_texts(texts: PackedStringArray) -> void:
	for index: int in _labels.size():
		var text: String = ""
		if index < texts.size():
			text = texts[index]
		_labels[index].text = text


func set_cell(index: int, text: String) -> void:
	if index >= 0 and index < _labels.size():
		_labels[index].text = text


## A theme type variation for one cell: `Faint`, `Bull`, `SubHeading`.
func set_cell_variation(index: int, variation: StringName) -> void:
	if index >= 0 and index < _labels.size():
		_labels[index].theme_type_variation = variation


## A cell's colour for a dynamic reason the theme cannot express - a move is
## green or red by its sign (Palette's rule, not a per-node override in a
## scene file).
func set_cell_colour(index: int, colour: Color) -> void:
	if index >= 0 and index < _labels.size():
		_labels[index].add_theme_color_override("font_color", colour)


## Every cell in the row the same variation: a heading row, say.
func set_row_variation(variation: StringName) -> void:
	for label: Label in _labels:
		label.theme_type_variation = variation


## Shows the row as a framed card (a header, a selected line) or bare.
func set_framed(variation: StringName) -> void:
	theme_type_variation = variation


func set_clickable(clickable: bool) -> void:
	_clickable = clickable
	mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not clickable:
		mouse_default_cursor_shape = PLAIN_CURSOR


func cell_text(index: int) -> String:
	if index < 0 or index >= _labels.size():
		return ""
	return _labels[index].text


func cell_count() -> int:
	return _labels.size()


## The whole row as one line, cells joined by a space. For tests.
func line_text() -> String:
	var texts: PackedStringArray = []
	for label: Label in _labels:
		texts.append(label.text)
	return " ".join(texts).strip_edges()


func _gui_input(event: InputEvent) -> void:
	if not _clickable:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	pressed.emit(key)
