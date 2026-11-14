class_name HoldingRow
extends PanelContainer
## One of the player's positions on the Your Stalks board: how many shares, what
## they are worth now, and a sell control.
##
## Same contract as StalkRow, including `configure_as_header()` — the holdings
## header is this scene in header mode, so its columns cannot drift out of
## alignment with the rows.
##
## The current price is deliberately NOT repeated here; it is already on the
## market board to the left. Showing it twice cost a column the layout could not
## spare.


signal sell_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)
signal sell_all_requested(stalk_id: StringName)


@onready var _name_label: Label = %Name
@onready var _shares_label: Label = %Shares
@onready var _value_label: Label = %Value
@onready var _amount_field: LineEdit = %Amount
@onready var _sell_button: Button = %SellButton
@onready var _sell_all_button: Button = %SellAllButton

var _stalk_id: StringName = &""
var _is_header: bool = false


func _ready() -> void:
	_sell_button.pressed.connect(_on_sell_pressed)
	_sell_all_button.pressed.connect(_on_sell_all_pressed)
	_amount_field.text_changed.connect(_on_amount_changed)
	_amount_field.text_submitted.connect(_on_amount_submitted)


func configure_as_header() -> void:
	_is_header = true
	theme_type_variation = &"HeaderCard"

	_name_label.text = "STALK"
	_shares_label.text = "SHARES"
	_value_label.text = "VALUE"
	for label: Label in [_name_label, _shares_label, _value_label]:
		label.theme_type_variation = &"Faint"

	_amount_field.editable = false
	_amount_field.text = ""
	_amount_field.placeholder_text = "AMOUNT"
	_amount_field.theme_type_variation = &"HeaderField"
	_sell_button.disabled = true
	_sell_button.text = "SELL"
	_sell_button.focus_mode = Control.FOCUS_NONE
	_sell_all_button.disabled = true
	_sell_all_button.text = "ALL"
	_sell_all_button.focus_mode = Control.FOCUS_NONE
	_sell_all_button.tooltip_text = ""


func display(stalk: StalkState, shares_held: int) -> void:
	if _is_header:
		return

	_stalk_id = stalk.id
	_name_label.text = stalk.definition.display_name
	_name_label.tooltip_text = stalk.definition.display_name
	_shares_label.text = str(shares_held)
	_value_label.text = (
		Palette.format_money(stalk.price * shares_held) if stalk.has_value() else "—"
	)
	_amount_field.placeholder_text = "max %d" % shares_held


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


func _on_sell_all_pressed() -> void:
	if not _is_header:
		sell_all_requested.emit(_stalk_id)


func _on_amount_changed(_text: String) -> void:
	if not _is_header:
		amount_changed.emit(_stalk_id, shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if not _is_header and not _sell_button.disabled:
		sell_requested.emit(_stalk_id, shares_entered())
