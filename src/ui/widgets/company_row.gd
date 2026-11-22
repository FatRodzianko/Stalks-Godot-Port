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
## | Marker | SYM | NAME | PRICE | CHG | EPS | P/E | DIV | HELD | QTY + B + S |
## |---|---|---|---|---|---|---|---|---|---|
## | 2 | 6 | 18 | 6 | 6 | 7 | 6 | 6 | 5 | 13 |
##
## An industry header puts its name across SYM and NAME together (24 wide, the
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

## The width of SYM and NAME together, which an industry's name takes.
const GROUP_NAME_CHARS: int = 24

## The price and change columns, in characters. A bankrupt row hides the change
## column and gives its width to the price, so "BANKRUPT" fits and every column
## after it stays where it was (the row has no separation, `TightHBox`).
const PRICE_CHARS: int = 6
const CHANGE_CHARS: int = 6

enum Kind { COMPANY, GROUP, HEADER }


var _kind: Kind = Kind.COMPANY
var _stalk_id: StringName = &""
var _group_id: StringName = &""
var _is_bankrupt: bool = false
var _held: int = 0

@onready var _marker: Label = %Marker
@onready var _ticker: Label = %Ticker
@onready var _name: MarqueeLabel = %Name
@onready var _price: Label = %Price
@onready var _change: Label = %Change
@onready var _eps: Label = %Eps
@onready var _pe: Label = %Pe
@onready var _dividend: Label = %Dividend
@onready var _held_label: Label = %Held
@onready var _trade: HBoxContainer = %Trade
@onready var _amount: LineEdit = %Amount
@onready var _buy: Button = %BuyButton
@onready var _sell: Button = %SellButton


func _ready() -> void:
	_buy.pressed.connect(_on_buy_pressed)
	_sell.pressed.connect(_on_sell_pressed)
	_amount.text_changed.connect(_on_amount_changed)
	_amount.text_submitted.connect(_on_amount_submitted)


# ------------------------------------------------------------- configuration

## The column header. Each sortable label takes clicks and asks for its sort.
func configure_as_header() -> void:
	_kind = Kind.HEADER
	theme_type_variation = &"HeaderCard"
	_marker.text = ""
	_ticker.text = "SYM"
	_name.set_full_text("NAME")
	_price.text = "PRICE"
	_change.text = "CHG"
	_eps.text = "EPS"
	_pe.text = "P/E"
	_dividend.text = "DIV"
	_held_label.text = "HELD"
	_trade.modulate.a = 0.0
	_amount.editable = false
	_amount.focus_mode = Control.FOCUS_NONE
	_buy.disabled = true
	_sell.disabled = true

	var columns: Dictionary[StringName, Label] = {
		SORT_TICKER: _ticker, SORT_NAME: _name, SORT_PRICE: _price,
		SORT_CHANGE: _change, SORT_EPS: _eps, SORT_PE: _pe,
		SORT_DIVIDEND: _dividend, SORT_HELD: _held_label,
	}
	for column: StringName in columns:
		var label: Label = columns[column]
		label.theme_type_variation = &"Faint"
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.tooltip_text = "Sort by %s, within each industry" % label.text
		label.gui_input.connect(_on_header_cell_input.bind(column))


## An industry's header: its name across SYM and NAME, its year's move, and
## its members' average P/E. `group_id` is what `group_toggled` carries.
func configure_as_group(group_id: StringName) -> void:
	_kind = Kind.GROUP
	_group_id = group_id
	theme_type_variation = &"HeaderCard"
	_ticker.visible = false
	_name.custom_minimum_size.x = GROUP_NAME_CHARS * CellRow.CELL_WIDTH
	_name.theme_type_variation = &"SubHeading"
	_trade.modulate.a = 0.0
	_amount.editable = false
	_amount.focus_mode = Control.FOCUS_NONE
	_buy.disabled = true
	_sell.disabled = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Fills an industry header. `performance` and `average_pe` are percent and
## turns; `NONE` (NAN) prints as "--". Empty performance text for a group with
## no year behind it, such as the index and the bond.
func display_group(title: String, collapsed: bool, performance: float, average_pe: float) -> void:
	_marker.text = MARKER_CLOSED if collapsed else MARKER_OPEN
	_name.set_full_text(title)
	_change.text = ""
	if not is_nan(performance):
		_change.text = Palette.format_percent_change(performance)
		_change.add_theme_color_override("font_color", Palette.for_percent(performance))
	_pe.text = ""
	if not is_nan(average_pe):
		_pe.text = Palette.format_decimal(average_pe, 1)
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
		_amount.text = ""
		_amount.placeholder_text = ""
		_amount.editable = false
		_buy.visible = false
		_sell.visible = false
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
	_buy.visible = true
	# Nothing to sell, so no sell button (§7.2). Hidden rather than removed:
	# the trade box keeps its width, so the columns do not move.
	_sell.visible = held > 0


func set_trading_open(is_open: bool) -> void:
	if _kind != Kind.COMPANY:
		return
	var open: bool = is_open and not _is_bankrupt
	_amount.editable = open
	_buy.disabled = not open
	_sell.disabled = not open


## Why a buy of what is typed would be refused, or empty. Greys the button with
## the reason as its tooltip, as the base board does.
func set_buy_blocked(reason: String) -> void:
	if _kind != Kind.COMPANY or _is_bankrupt:
		return
	var blocked: bool = not reason.is_empty()
	_buy.disabled = blocked
	_buy.tooltip_text = reason if blocked else "Buy"
	_amount.theme_type_variation = &""
	if blocked and not _amount.text.is_empty():
		_amount.theme_type_variation = &"InvalidLineEdit"


func set_sell_blocked(reason: String) -> void:
	if _kind != Kind.COMPANY or _is_bankrupt:
		return
	_sell.disabled = not reason.is_empty()
	_sell.tooltip_text = "Sell" if reason.is_empty() else reason


## The affordable maximum, as the quantity field's placeholder.
func set_affordable_hint(maximum: int) -> void:
	if _kind != Kind.COMPANY or _is_bankrupt:
		return
	_amount.placeholder_text = str(maximum)
	_amount.tooltip_text = "Most you can afford: %d" % maximum


func shares_entered() -> int:
	return _amount.text.strip_edges().to_int()


func clear_amount() -> void:
	if _kind == Kind.COMPANY:
		_amount.text = ""
		_amount.theme_type_variation = &""


# ---------------------------------------------------------------- for tests

func stalk_id() -> StringName:
	return _stalk_id


func group_id() -> StringName:
	return _group_id


func is_group() -> bool:
	return _kind == Kind.GROUP


func buy_is_blocked() -> bool:
	return _buy.disabled


func sell_is_shown() -> bool:
	return _sell.visible


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
	_amount.text = text
	_amount.text_changed.emit(text)


func press_buy() -> void:
	_buy.pressed.emit()


func press_sell() -> void:
	_sell.pressed.emit()


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
			accept_event()
			info_requested.emit(_stalk_id)


func _on_header_cell_input(event: InputEvent, column: StringName) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	sort_requested.emit(column)


func _on_buy_pressed() -> void:
	if _kind == Kind.COMPANY:
		buy_requested.emit(_stalk_id, shares_entered())


func _on_sell_pressed() -> void:
	if _kind == Kind.COMPANY:
		sell_requested.emit(_stalk_id, shares_entered())


func _on_amount_changed(_text: String) -> void:
	if _kind == Kind.COMPANY:
		amount_changed.emit(_stalk_id, shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if _kind == Kind.COMPANY and not _buy.disabled:
		buy_requested.emit(_stalk_id, shares_entered())
