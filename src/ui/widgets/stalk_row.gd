class_name StalkRow
extends PanelContainer
## One stalk on the Available Stalks board: its price, movement, dividends, and a
## buy control.
##
## Knows nothing about the session or the screen holding it. It is handed a
## StalkState to display and emits intent outward; the screen decides what to do
## with that. See CLAUDE.md, "Signals for Decoupling".
##
## **The board's column header is this same scene** in header mode, via
## `configure_as_header()`. That is deliberate: a separately built header drifts
## out of alignment the moment a column changes, which is exactly what happened
## the first time — the header had six children and the row seven, so the rows
## lost 10px more to separations and every column sat 20px off. Sharing the scene
## makes misalignment impossible by construction.


signal buy_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)


@onready var _name_label: Label = %Name
@onready var _price_label: Label = %Price
@onready var _change_label: Label = %Change
@onready var _dividends_label: Label = %Dividends
@onready var _amount_field: LineEdit = %Amount
@onready var _buy_button: Button = %BuyButton

var _stalk_id: StringName = &""
var _is_bankrupt: bool = false
var _is_header: bool = false


func _ready() -> void:
	_buy_button.pressed.connect(_on_buy_pressed)
	_amount_field.text_changed.connect(_on_amount_changed)
	_amount_field.text_submitted.connect(_on_amount_submitted)


## Turns this row into the board's column header: captions instead of values, and
## the interactive controls replaced by inert labels of identical width.
func configure_as_header() -> void:
	_is_header = true
	theme_type_variation = &"HeaderCard"

	_name_label.text = "STALK"
	_price_label.text = "PRICE"
	_change_label.text = "CHANGE"
	_dividends_label.text = "DIV B/B"
	_name_label.tooltip_text = ""
	_dividends_label.tooltip_text = "Dividend per share in a bull year / a bear year"

	for label: Label in [_name_label, _price_label, _change_label, _dividends_label]:
		label.theme_type_variation = &"Faint"

	# Keep the controls in place so the columns line up, but make them inert and
	# label them.
	_amount_field.editable = false
	_amount_field.text = ""
	_amount_field.placeholder_text = "AMOUNT"
	_amount_field.theme_type_variation = &"HeaderField"
	_buy_button.disabled = true
	_buy_button.text = "BUY"
	_buy_button.focus_mode = Control.FOCUS_NONE


## Fills the row from a stalk's current state.
func display(stalk: StalkState) -> void:
	if _is_header:
		return

	_stalk_id = stalk.id
	_is_bankrupt = stalk.is_bankrupt

	_name_label.text = stalk.definition.display_name
	# Long names are trimmed with an ellipsis rather than hard-clipped, and the
	# full name is always available on hover.
	_name_label.tooltip_text = stalk.definition.display_name

	_dividends_label.text = "%d / %d" % [
		stalk.definition.bull_dividend, stalk.definition.bear_dividend,
	]

	if stalk.is_bankrupt:
		_price_label.text = "BANKRUPT"
		_price_label.theme_type_variation = &"Danger"
		_change_label.text = "—"
		_change_label.remove_theme_color_override("font_color")
	else:
		_price_label.text = Palette.format_money(stalk.price)
		_price_label.theme_type_variation = &"Numeric"
		_change_label.text = Palette.format_change(stalk.last_yearly_change)
		_change_label.add_theme_color_override(
			"font_color", Palette.for_change(stalk.last_yearly_change)
		)

	# Controls stay in the tree when bankrupt so the columns keep their width;
	# they are simply disabled.
	_amount_field.editable = not stalk.is_bankrupt
	_buy_button.disabled = stalk.is_bankrupt
	if stalk.is_bankrupt:
		_amount_field.text = ""
		_buy_button.tooltip_text = "%s is bankrupt." % stalk.definition.display_name

	theme_type_variation = &"BankruptCard" if stalk.is_bankrupt else &"Card"


## Enables or disables the buy control, with `reason` shown as a tooltip when it
## is disabled. An empty reason means the action is allowed.
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
	if _is_header:
		return
	buy_requested.emit(_stalk_id, shares_entered())


func _on_amount_changed(_text: String) -> void:
	if _is_header:
		return
	amount_changed.emit(_stalk_id, shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if not _is_header and not _buy_button.disabled:
		buy_requested.emit(_stalk_id, shares_entered())
