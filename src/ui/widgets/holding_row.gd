class_name HoldingRow
extends PanelContainer
## One of the player's positions on the Your Stalks board.
##
## Columns match the original: name of stalk, number owned, and the sell control.
## The price is not repeated here — it is on the Available Stalks board.
##
## **StalkleHeads' HOLDINGS panel uses this row too**, made compact
## (`set_compact`): the ticker in place of the name, so it fits the panel, and no
## ALL button (decisions.md D184). Clicking the ticker asks for the company's
## page (`info_requested`); the base board does not listen for it.


signal sell_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)
signal sell_all_requested(stalk_id: StringName)

## The name was clicked. Only StalkleHeads' panel listens.
signal info_requested(stalk_id: StringName)


@onready var _name_label: MarqueeLabel = %Name
@onready var _owned_label: Label = %Owned
@onready var _amount_field: LineEdit = %Amount
@onready var _sell_button: Button = %SellButton
@onready var _sell_all_button: Button = %SellAllButton

var _stalk_id: StringName = &""
var _is_header: bool = false
var _compact: bool = false


func _ready() -> void:
	_sell_button.pressed.connect(_on_sell_pressed)
	_sell_all_button.pressed.connect(_on_sell_all_pressed)
	_amount_field.text_changed.connect(_on_amount_changed)
	_amount_field.text_submitted.connect(_on_amount_submitted)
	_name_label.gui_input.connect(_on_name_input)


## The panel's version: ticker for name, HELD for OWNED, no ALL. Call before
## `configure_as_header` or the first `display`.
func set_compact() -> void:
	_compact = true
	_sell_all_button.visible = false


func configure_as_header() -> void:
	_is_header = true
	theme_type_variation = &"HeaderCard"

	_name_label.set_full_text("SYM" if _compact else "NAME")
	_owned_label.text = "HELD" if _compact else "OWNED"
	for label: Label in [_name_label, _owned_label]:
		label.theme_type_variation = &"Faint"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD

	_amount_field.editable = false
	_amount_field.text = ""
	_amount_field.placeholder_text = ""
	_amount_field.theme_type_variation = &"HeaderField"
	_sell_button.disabled = true
	_sell_button.text = "SELL"
	_sell_button.focus_mode = Control.FOCUS_NONE
	_sell_all_button.visible = false


func display(stalk: StalkState, shares_held: int) -> void:
	if _is_header:
		return
	_stalk_id = stalk.id
	# The full name is shown, and scrolls on hover when it does not fit. The
	# compact row shows the ticker, with the name as its tooltip.
	if _compact:
		_name_label.set_full_text(String(stalk.definition.ticker))
		_name_label.tooltip_text = TermTips.fit(stalk.definition.display_name)
		_name_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		_name_label.set_full_text(stalk.definition.display_name)
	_owned_label.text = str(shares_held)
	# Just the number — the field is too narrow for "max N" plus more than three
	# digits. The word lives in the tooltip.
	_amount_field.placeholder_text = str(shares_held)
	_amount_field.tooltip_text = "Most you can sell: %d" % shares_held


func set_trading_open(is_open: bool) -> void:
	if _is_header:
		return
	_amount_field.editable = is_open
	_sell_button.disabled = not is_open
	_sell_all_button.disabled = not is_open


func set_sell_blocked(reason: String) -> void:
	if _is_header:
		return
	var blocked: bool = not reason.is_empty()
	_sell_button.disabled = blocked
	_sell_button.tooltip_text = reason
	_amount_field.theme_type_variation = (
		&"InvalidLineEdit" if blocked and not _amount_field.text.is_empty() else &""
	)


func shares_entered() -> int:
	return _amount_field.text.strip_edges().to_int()


func clear_amount() -> void:
	if _is_header:
		return
	_amount_field.text = ""
	_amount_field.theme_type_variation = &""


func stalk_id() -> StringName:
	return _stalk_id


func _on_sell_pressed() -> void:
	if not _is_header:
		sell_requested.emit(_stalk_id, shares_entered())


func _on_name_input(event: InputEvent) -> void:
	if _is_header:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		info_requested.emit(_stalk_id)


func _on_sell_all_pressed() -> void:
	if not _is_header:
		sell_all_requested.emit(_stalk_id)


func _on_amount_changed(_text: String) -> void:
	if not _is_header:
		amount_changed.emit(_stalk_id, shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if not _is_header and not _sell_button.disabled:
		sell_requested.emit(_stalk_id, shares_entered())
