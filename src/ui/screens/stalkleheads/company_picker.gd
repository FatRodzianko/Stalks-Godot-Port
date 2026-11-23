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
## Shows what it is handed: every figure comes from `MarketReadouts`.


## A company was clicked.
signal company_chosen(stalk_id: StringName)


## The columns, in characters.
const SYM_CHARS: int = 6
const NAME_CHARS: int = 32
const NPC_CHARS: int = 4
const WIDTH_CHARS: int = SYM_CHARS + NAME_CHARS + NPC_CHARS

const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")


var _rows: Dictionary[StringName, CellRow] = {}

@onready var _header: CellRow = %Header
@onready var _list: VBoxContainer = %List


func _ready() -> void:
	custom_minimum_size.x = WIDTH_CHARS * CellRow.CELL_WIDTH
	_header.configure(_widths(), _aligns())
	_header.set_texts(["SYM", "NAME", "NPC"])
	_header.set_row_variation(&"Faint")
	_header.set_framed(&"HeaderCard")
	_header.set_cell_tooltip(2, TermTips.NPC_HOLDERS)


## Redraws every line; `shown_id` is the company on the tab, which is marked.
func refresh(state: GameState, shown_id: StringName) -> void:
	for stalk: StalkState in state.stalks:
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
		row.set_texts([String(stalk.definition.ticker), stalk.definition.display_name, npc])
		row.set_framed(&"Card" if stalk.id == shown_id else &"BareRow")


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


func _on_row_pressed(stalk_id: StringName) -> void:
	company_chosen.emit(stalk_id)
