class_name CompanyPicker
extends ScrollContainer
## The Company tab's list of every company, opened by its **COMPANIES** button
## and drawn over the tab rather than beside it, so the tab never moves
## (decisions.md D184). Click a company: the list closes and the Company tab
## shows it.
##
## One line per board row in the match's own order - the order `<` and `>`
## walk - with its ticker, its name and **NPC**, how many of the desk's traders
## hold it or are short it now, blank for none. That column answers "which
## companies has the desk got into" without opening each one.
##
## **A company you own has `*` before its name**, and the heading says so:
## NAME (* OWNED). Every other name has a space there, so the names line up
## (decisions.md D191).
##
## **Click a heading to sort** by it; again to reverse. The mark goes after the
## caption, as on the board (decisions.md D185). The sort is this viewer's
## alone and is kept while the list is open and closed.
##
## Shows what it is handed: every figure comes from `MarketReadouts`.


## A company was clicked.
signal company_chosen(stalk_id: StringName)


## The columns, in characters.
const SYM_CHARS: int = 6
const NAME_CHARS: int = 32
const NPC_CHARS: int = 4
const WIDTH_CHARS: int = SYM_CHARS + NAME_CHARS + NPC_CHARS

const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")

## The headings, by column index, and the sort marks (as on the board).
const CAPTIONS: Array[String] = ["SYM", "NAME (* OWNED)", "NPC"]

## Before a company's name: owned, or not.
const OWNED_MARK: String = "*"
const NOT_OWNED_MARK: String = " "
const SORT_UP: String = "^"
const SORT_DOWN: String = "v"
const NO_SORT: int = -1


var _rows: Dictionary[StringName, CellRow] = {}
## The match's order, and each company's sort keys, from the last refresh.
var _order: Array[StringName] = []
var _keys: Dictionary[StringName, Array] = {}
var _sort_column: int = NO_SORT
var _sort_descending: bool = false

@onready var _header: CellRow = %Header
@onready var _list: VBoxContainer = %List


func _ready() -> void:
	custom_minimum_size.x = WIDTH_CHARS * CellRow.CELL_WIDTH
	_header.configure(_widths(), _aligns())
	_header.set_row_variation(&"Faint")
	_header.set_framed(&"HeaderCard")
	_header.set_cell_tooltip(0, "%s\nClick to sort." % TermTips.SYM)
	_header.set_cell_tooltip(1, "The company's name; * before it if you own shares in it.\nClick to sort.")
	_header.set_cell_tooltip(2, "%s\nClick to sort." % TermTips.NPC_HOLDERS)
	for index: int in CAPTIONS.size():
		_header.set_cell_clickable(index)
	_header.cell_pressed.connect(_on_header_cell_pressed)
	_show_sort_marks()


## Redraws every line; `shown_id` is the company on the tab, which is marked,
## and `context` says what you hold.
func refresh(context: TradeContext, shown_id: StringName) -> void:
	var state: GameState = context.state
	_order.clear()
	for stalk: StalkState in state.stalks:
		_order.append(stalk.id)
		var row: CellRow = _rows.get(stalk.id)
		if row == null:
			row = CellRowScene.instantiate()
			_list.add_child(row)
			row.configure(_widths(), _aligns())
			row.key = stalk.id
			row.set_clickable(true)
			row.set_cell_variation(0, &"Faint")
			row.pressed.connect(_on_row_pressed)
			_rows[stalk.id] = row
		var holders: int = MarketReadouts.npc_holder_count(state, stalk.id)
		var npc: String = ""
		if holders > 0:
			npc = str(holders)
		var mark: String = NOT_OWNED_MARK
		if context.held(stalk.id) > 0:
			mark = OWNED_MARK
		row.set_texts([String(stalk.definition.ticker), mark + stalk.definition.display_name, npc])
		row.set_framed(&"Card" if stalk.id == shown_id else &"BareRow")
		_keys[stalk.id] = [String(stalk.definition.ticker), stalk.definition.display_name.to_lower(), holders]
	_apply_sort()


## The companies' ids in the order the list shows them.
func shown_order() -> Array[StringName]:
	var ids: Array[StringName] = []
	for child: Node in _list.get_children():
		ids.append((child as CellRow).key)
	return ids


## Every company's line, in the order shown. For tests.
func lines_text() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in _list.get_children():
		lines.append((child as CellRow).line_text())
	return lines


func header_text() -> String:
	return _header.line_text()


## Clicks a heading as a player would. For tests.
func press_heading(index: int) -> void:
	_header.cell_pressed.emit(index)


# ------------------------------------------------------------ for tests

func line_text(stalk_id: StringName) -> String:
	var row: CellRow = _rows.get(stalk_id)
	if row == null:
		return ""
	return row.line_text()


func line_count() -> int:
	return _rows.size()


## Clicks a line as a player would.
func choose(stalk_id: StringName) -> void:
	var row: CellRow = _rows.get(stalk_id)
	if row != null:
		row.pressed.emit(stalk_id)


func _widths() -> Array[int]:
	return [SYM_CHARS, 0, NPC_CHARS]


func _aligns() -> Array[int]:
	return [CellRow.LEFT, CellRow.LEFT, CellRow.RIGHT]


func _apply_sort() -> void:
	var ids: Array[StringName] = _order.duplicate()
	if _sort_column != NO_SORT:
		ids.sort_custom(_sorts_before)
	for index: int in ids.size():
		var row: CellRow = _rows.get(ids[index])
		if row != null:
			_list.move_child(row, index)


## By the sorted column, ties in the match's order, so the list is stable.
func _sorts_before(a: StringName, b: StringName) -> bool:
	var key_a: Variant = _keys[a][_sort_column]
	var key_b: Variant = _keys[b][_sort_column]
	if key_a != key_b:
		if _sort_descending:
			return key_a > key_b
		return key_a < key_b
	return _order.find(a) < _order.find(b)


func _show_sort_marks() -> void:
	for index: int in CAPTIONS.size():
		var slot: String = ""
		if index == 2:
			slot = " "
		if index == _sort_column:
			slot = SORT_DOWN if _sort_descending else SORT_UP
		_header.set_cell(index, CAPTIONS[index] + slot)


func _on_header_cell_pressed(index: int) -> void:
	if index == _sort_column:
		_sort_descending = not _sort_descending
	else:
		_sort_column = index
		_sort_descending = false
	_show_sort_marks()
	_apply_sort()


func _on_row_pressed(stalk_id: StringName) -> void:
	company_chosen.emit(stalk_id)
