class_name CompanyRow
extends PanelContainer
## One line of the StalkleHeads Exchange board (docs/stalkleheads-design.md
## §7.2): a company, the bond or the index - or, configured differently, the
## column header or an industry's header.
##
## **One scene for all three, so the columns cannot drift apart** - the same
## reason the base board's header is its row in header mode (decisions.md
## D36). The widths are the design's, in characters:
##
## | Marker | SYM | NAME | PRICE | CHG | EPS | P/E | DIV | HELD | QTY + BUY + SELL |
## |---|---|---|---|---|---|---|---|---|---|
## | 2 | 6 | 16 | 7 | 5 | 7 | 6 | 5 | 6 | 16 |
##
## An industry header puts its name across SYM and NAME together (22 wide, the
## same total), its year's move under CHG and its average P/E under P/E, so a
## member's P/E is compared with the industry's by moving the eyes two lines
## (§7.2). There is deliberately no column saying cheap or expensive (§14 q9).
##
## Shows what it is given. Every figure arrives already derived
## (`MarketReadouts`); this formats and colours, and turns clicks into signals
## carrying ids.


signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)

## The row was clicked: open this company on the Company tab.
signal info_requested(stalk_id: StringName)

## A column header was clicked.
signal sort_requested(column: StringName)

## An industry header was clicked: collapse or expand its members.
signal group_toggled(group_id: StringName)


## The sortable columns, by the header label each one is.
const SORT_TICKER: StringName = &"ticker"
const SORT_NAME: StringName = &"name"
const SORT_PRICE: StringName = &"price"
const SORT_CHANGE: StringName = &"change"
const SORT_EPS: StringName = &"eps"
const SORT_PE: StringName = &"pe"
const SORT_DIVIDEND: StringName = &"dividend"
const SORT_HELD: StringName = &"held"

const MARKER_OPEN: String = "-"
const MARKER_CLOSED: String = "+"

## The sorted column's heading carries one of these after its caption:
## ascending, descending. A right-aligned heading always keeps a trailing space
## where the mark goes, so marking it moves nothing (decisions.md D185).
const SORT_UP: String = "^"
const SORT_DOWN: String = "v"

## Each heading's caption and what it means (`TermTips`).
const HEADINGS: Dictionary[StringName, String] = {
	SORT_TICKER: "SYM", SORT_NAME: "NAME", SORT_PRICE: "PRICE",
	SORT_CHANGE: "CHG", SORT_EPS: "EPS", SORT_PE: "P/E",
	SORT_DIVIDEND: "DIV", SORT_HELD: "HELD",
}

## The width of SYM and NAME together, which an industry's name takes.
const GROUP_NAME_CHARS: int = 22

## The price and change columns, in characters. A bankrupt row hides the change
## column and gives its width to the price, so "BANKRUPT" fits and every column
## after it stays where it was (the row has no separation, `TightHBox`).
const PRICE_CHARS: int = 7
const CHANGE_CHARS: int = 5

enum Kind { COMPANY, GROUP, HEADER }


var _kind: Kind = Kind.COMPANY
var _stalk_id: StringName = &""
var _group_id: StringName = &""
var _is_bankrupt: bool = false
var _held: int = 0

## The header's state: which column is sorted, which way, and each heading's
## tooltip (a scrolling label replaces its tooltip with its text).
var _sort_column: StringName = &""
var _sort_descending: bool = false
var _heading_tips: Dictionary[StringName, String] = {}

@onready var _marker: Label = %Marker
@onready var _ticker: Label = %Ticker
@onready var _name: MarqueeLabel = %Name
@onready var _price: Label = %Price
@onready var _change: Label = %Change
@onready var _eps: Label = %Eps
@onready var _pe: Label = %Pe
@onready var _dividend: Label = %Dividend
@onready var _held_label: Label = %Held
@onready var _trade: TradeBox = %Trade


func _ready() -> void:
	_trade.buy_requested.connect(_on_trade_buy_requested)
	_trade.sell_requested.connect(_on_trade_sell_requested)
	_trade.amount_changed.connect(_on_trade_amount_changed)


# ------------------------------------------------------------- configuration

## The column header. Each sortable label takes clicks and asks for its sort.
##
## **Each heading is drawn as a cell** (`HeaderCell`: a faint line down its right
## edge), so a player can see where one column's clickable area ends and the
## next begins - the numbers are right-aligned, so the gap left of a caption
## belongs to it, not to the column before (manual-testing.md G4). The heading
## under the mouse lights up (`HeaderCellHover`); the sorted one is bright
## (`HeaderCellLit`).
func configure_as_header() -> void:
	_kind = Kind.HEADER
	theme_type_variation = &"HeaderCard"
	_marker.text = ""
	_hide_trade()
	var meanings: Dictionary[StringName, String] = {
		SORT_TICKER: TermTips.SYM, SORT_NAME: "The company's name.",
		SORT_PRICE: TermTips.PRICE, SORT_CHANGE: TermTips.CHANGE,
		SORT_EPS: TermTips.EPS, SORT_PE: TermTips.PE,
		SORT_DIVIDEND: TermTips.DIVIDEND, SORT_HELD: TermTips.HELD,
	}
	for column: StringName in HEADINGS:
		var label: Label = _heading_label(column)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_heading_tips[column] = TermTips.fit("%s
Click to sort, within each industry." % meanings[column])
		label.gui_input.connect(_on_header_cell_input.bind(column))
		label.mouse_entered.connect(_on_heading_mouse_entered.bind(column))
		label.mouse_exited.connect(_on_heading_mouse_exited.bind(column))
	show_sort(&"", false)


## Marks the sorted column's heading with ^ or v and brightens it; the others
## read plainly. `column` empty means board order.
func show_sort(column: StringName, descending: bool) -> void:
	_sort_column = column
	_sort_descending = descending
	for each: StringName in HEADINGS:
		var label: Label = _heading_label(each)
		var caption: String = HEADINGS[each]
		var slot: String = ""
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			slot = " "
		if each == column:
			slot = SORT_DOWN if descending else SORT_UP
		caption += slot
		if label == _name:
			_name.set_full_text(caption)
		else:
			label.text = caption
		label.tooltip_text = _heading_tips.get(each, "")
		_style_heading(each, false)


## A heading's look: lit under the mouse, bright when sorted, faint otherwise.
func _style_heading(column: StringName, hovered: bool) -> void:
	var label: Label = _heading_label(column)
	if hovered:
		label.theme_type_variation = &"HeaderCellHover"
	elif column == _sort_column:
		label.theme_type_variation = &"HeaderCellLit"
	else:
		label.theme_type_variation = &"HeaderCell"


func _heading_label(column: StringName) -> Label:
	match column:
		SORT_TICKER:
			return _ticker
		SORT_NAME:
			return _name
		SORT_PRICE:
			return _price
		SORT_CHANGE:
			return _change
		SORT_EPS:
			return _eps
		SORT_PE:
			return _pe
		SORT_DIVIDEND:
			return _dividend
	return _held_label


## An industry's header: its name across SYM and NAME, its year's move, and
## its members' average P/E. `group_id` is what `group_toggled` carries.
func configure_as_group(group_id: StringName) -> void:
	_kind = Kind.GROUP
	_group_id = group_id
	theme_type_variation = &"HeaderCard"
	_ticker.visible = false
	_name.custom_minimum_size.x = GROUP_NAME_CHARS * CellRow.CELL_WIDTH
	_name.theme_type_variation = &"SubHeading"
	_hide_trade()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Fills an industry header. `performance` and `average_pe` are percent and
## turns; `NONE` (NAN) prints as "--". Empty performance text for a group with
## no year behind it, such as the index and the bond.
func display_group(title: String, collapsed: bool, performance: float, average_pe: float) -> void:
	_marker.text = MARKER_CLOSED if collapsed else MARKER_OPEN
	_name.set_full_text(title)
	# The industry's name is already there to read; repeating it as a tooltip
	# only gets in the way (manual-testing.md G4).
	_name.tooltip_text = ""
	_change.text = ""
	if not is_nan(performance):
		_change.text = Palette.format_percent_change(performance)
		_change.add_theme_color_override("font_color", Palette.for_percent(performance))
	_pe.text = ""
	if not is_nan(average_pe):
		_pe.text = Palette.format_decimal(average_pe, 1)
		_pe.tooltip_text = TermTips.fit(TermTips.INDUSTRY_PE)
		_pe.mouse_filter = Control.MOUSE_FILTER_PASS
	if not is_nan(performance):
		_change.tooltip_text = TermTips.fit(TermTips.INDUSTRY_MOVE)
		_change.mouse_filter = Control.MOUSE_FILTER_PASS
	_price.text = ""
	_eps.text = ""
	_dividend.text = ""
	_held_label.text = ""


## Just the open-or-collapsed marker, when only that has changed.
func display_group_marker(collapsed: bool) -> void:
	_marker.text = MARKER_CLOSED if collapsed else MARKER_OPEN


## Fills a board row. `eps` and `pe` are NAN when the row has none (the bond,
## the index, a loss-maker's P/E), and print as "--" or nothing: P/E is blank
## for the bond and the index (§7.2), "--" for a company without earnings.
func display_row(
	row: StalkState,
	ticker: String,
	eps: float,
	pe: float,
	dividend: int,
	held: int,
	is_company: bool,
) -> void:
	_stalk_id = row.id
	_is_bankrupt = row.is_bankrupt
	_held = held
	_marker.text = ""
	_ticker.text = ticker
	_name.set_full_text(row.definition.display_name)
	_held_label.text = str(held) if held > 0 else "0"

	theme_type_variation = &"BankruptCard" if row.is_bankrupt else &"Card"
	_change.visible = not row.is_bankrupt
	_price.custom_minimum_size.x = PRICE_CHARS * CellRow.CELL_WIDTH
	if row.is_bankrupt:
		_price.custom_minimum_size.x = (PRICE_CHARS + CHANGE_CHARS) * CellRow.CELL_WIDTH
		_price.text = "BANKRUPT"
		_price.theme_type_variation = &"Danger"
		_change.text = ""
		_eps.text = ""
		_pe.text = ""
		_dividend.text = ""
		_trade.set_dead()
		return

	_price.text = str(row.price)
	_price.theme_type_variation = &"Numeric"
	_change.text = Palette.format_change(row.last_yearly_change)
	_change.add_theme_color_override("font_color", Palette.for_change(row.last_yearly_change))
	_eps.text = Palette.format_decimal(eps, 2)
	_pe.text = ""
	if is_company:
		_pe.text = Palette.format_decimal(pe, 1)
	_dividend.text = str(dividend)


func shares_entered() -> int:
	return _trade.shares_entered()


func clear_amount() -> void:
	if _kind == Kind.COMPANY:
		_trade.clear_amount()


## The column header and an industry header keep the trade box's width, so the
## columns line up, but show nothing in it.
func _hide_trade() -> void:
	_trade.modulate.a = 0.0
	_trade.set_open(false)
	_trade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in _trade.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(child as Control).focus_mode = Control.FOCUS_NONE


# ---------------------------------------------------------------- for tests

func stalk_id() -> StringName:
	return _stalk_id


func group_id() -> StringName:
	return _group_id


func is_group() -> bool:
	return _kind == Kind.GROUP


func buy_is_blocked() -> bool:
	return _trade.buy_is_blocked()


func sell_is_blocked() -> bool:
	return _trade.sell_is_blocked()


func trade_box() -> TradeBox:
	return _trade


## Every visible column's text, in order, joined by single spaces.
func line_text() -> String:
	var parts: PackedStringArray = []
	for label: Label in [_marker, _ticker, _price, _change, _eps, _pe, _dividend, _held_label]:
		if label == _price:
			parts.append(_name.full_text())
		if label.visible:
			parts.append(label.text)
	return " ".join(parts).strip_edges()


func column_text(column: StringName) -> String:
	match column:
		SORT_TICKER:
			return _ticker.text
		SORT_NAME:
			return _name.full_text()
		SORT_PRICE:
			return _price.text
		SORT_CHANGE:
			return _change.text
		SORT_EPS:
			return _eps.text
		SORT_PE:
			return _pe.text
		SORT_DIVIDEND:
			return _dividend.text
		SORT_HELD:
			return _held_label.text
	return ""


## Types into the quantity field as a player would.
func type_amount(text: String) -> void:
	_trade.type_amount(text)


func press_buy() -> void:
	_trade.press_buy()


func press_sell() -> void:
	_trade.press_sell()


# --------------------------------------------------------------- handlers

## A click on the row itself, not on its controls, which take their own.
func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	match _kind:
		Kind.GROUP:
			accept_event()
			group_toggled.emit(_group_id)
		Kind.COMPANY:
			# Only the symbol and the name open the Company tab, so a click
			# meant for the trade box or the HELD figure does not.
			if not opens_company_at(click.global_position):
				return
			accept_event()
			info_requested.emit(_stalk_id)


## The name cell, for tests that click it.
func name_cell() -> Control:
	return _name


## True when a click at `point` (global) lands on the symbol or the name: the
## two cells that open the Company tab. Public for tests.
func opens_company_at(point: Vector2) -> bool:
	return _ticker.get_global_rect().has_point(point) or _name.get_global_rect().has_point(point)


func _on_heading_mouse_entered(column: StringName) -> void:
	_style_heading(column, true)


func _on_heading_mouse_exited(column: StringName) -> void:
	_style_heading(column, false)


func _on_header_cell_input(event: InputEvent, column: StringName) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	sort_requested.emit(column)


func _on_trade_buy_requested(shares: int) -> void:
	if _kind == Kind.COMPANY:
		buy_requested.emit(_stalk_id, shares)


func _on_trade_sell_requested(shares: int) -> void:
	if _kind == Kind.COMPANY:
		sell_requested.emit(_stalk_id, shares)


func _on_trade_amount_changed(shares: int) -> void:
	if _kind == Kind.COMPANY:
		amount_changed.emit(_stalk_id, shares)
