class_name StalkRow
extends PanelContainer
## One stalk on the Available Stalks board.
##
## Columns match the original game exactly: name, price per share, bull dividend,
## bear dividend, yearly change, then the buy control. See docs/ui-reference.md.
##
## The board's column header is this same scene in header mode, via
## `configure_as_header()`, so the header's columns cannot drift out of alignment
## with the rows'.


signal buy_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)


@onready var _name_label: Label = %Name
@onready var _price_label: Label = %Price
@onready var _bull_label: Label = %BullDividend
@onready var _bear_label: Label = %BearDividend
@onready var _change_label: Label = %Change
@onready var _amount_field: LineEdit = %Amount
@onready var _buy_button: Button = %BuyButton

var _stalk_id: StringName = &""
var _is_bankrupt: bool = false
var _is_header: bool = false


func _ready() -> void:
	_buy_button.pressed.connect(_on_buy_pressed)
	_amount_field.text_changed.connect(_on_amount_changed)
	_amount_field.text_submitted.connect(_on_amount_submitted)


func configure_as_header() -> void:
	_is_header = true
	theme_type_variation = &"HeaderCard"

	_name_label.text = "NAME"
	_price_label.text = "PRICE"
	_bull_label.text = "BULL"
	_bear_label.text = "BEAR"
	_change_label.text = "CHG"

	for label: Label in [_name_label, _price_label, _bull_label, _bear_label, _change_label]:
		label.theme_type_variation = &"Faint"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.remove_theme_color_override("font_color")

	_amount_field.editable = false
	_amount_field.text = ""
	_amount_field.placeholder_text = ""
	_amount_field.theme_type_variation = &"HeaderField"
	_buy_button.disabled = true
	_buy_button.text = "BUY"
	_buy_button.focus_mode = Control.FOCUS_NONE


func display(stalk: StalkState) -> void:
	if _is_header:
		return

	_stalk_id = stalk.id
	_is_bankrupt = stalk.is_bankrupt

	_name_label.text = stalk.definition.board_symbol()
	_name_label.tooltip_text = stalk.definition.display_name
	_bull_label.text = str(stalk.definition.bull_dividend)
	_bear_label.text = str(stalk.definition.bear_dividend)

	if stalk.is_bankrupt:
		_price_label.text = "BNKRT"
		_price_label.theme_type_variation = &"Danger"
		_change_label.text = "—"
		_change_label.remove_theme_color_override("font_color")
	else:
		_price_label.text = str(stalk.price)
		_price_label.theme_type_variation = &"Numeric"
		_change_label.text = Palette.format_change(stalk.last_yearly_change)
		_change_label.add_theme_color_override(
			"font_color", Palette.for_change(stalk.last_yearly_change)
		)

	_amount_field.editable = not stalk.is_bankrupt
	_buy_button.disabled = stalk.is_bankrupt
	if stalk.is_bankrupt:
		_amount_field.text = ""
		_buy_button.tooltip_text = "%s is bankrupt." % stalk.definition.display_name

	theme_type_variation = &"BankruptCard" if stalk.is_bankrupt else &"Card"


## Trading is closed in year 0 and once the game is over. The original simply did
## not allow buying then, so the control is disabled rather than hidden.
func set_trading_open(is_open: bool) -> void:
	if _is_header:
		return
	_amount_field.editable = is_open and not _is_bankrupt
	_buy_button.disabled = not is_open or _is_bankrupt


func set_buy_blocked(reason: String) -> void:
	if _is_header or _is_bankrupt:
		return
	var blocked: bool = not reason.is_empty()
	_buy_button.disabled = blocked
	_buy_button.tooltip_text = reason
	_amount_field.theme_type_variation = (
		&"InvalidLineEdit" if blocked and not _amount_field.text.is_empty() else &""
	)


func set_affordable_hint(maximum: int) -> void:
	if _is_header or _is_bankrupt:
		return
	_amount_field.placeholder_text = "max %d" % maximum


func shares_entered() -> int:
	return _amount_field.text.strip_edges().to_int()


func clear_amount() -> void:
	if _is_header:
		return
	_amount_field.text = ""
	_amount_field.theme_type_variation = &""


func stalk_id() -> StringName:
	return _stalk_id


func is_bankrupt_row() -> bool:
	return _is_bankrupt


func _on_buy_pressed() -> void:
	if not _is_header:
		buy_requested.emit(_stalk_id, shares_entered())


func _on_amount_changed(_text: String) -> void:
	if not _is_header:
		amount_changed.emit(_stalk_id, shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if not _is_header and not _buy_button.disabled:
		buy_requested.emit(_stalk_id, shares_entered())
