class_name HoldingRow
extends PanelContainer
## One of the player's positions on the Your Stalks board: how many shares, what
## they are worth now, and a sell control.
##
## Same contract as StalkRow: display what it is given, emit intent, know nothing
## about the session.


signal sell_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)

## The player asked to sell everything they hold of this stalk.
signal sell_all_requested(stalk_id: StringName)


@onready var _name_label: Label = %Name
@onready var _shares_label: Label = %Shares
@onready var _price_label: Label = %Price
@onready var _value_label: Label = %Value
@onready var _amount_field: LineEdit = %Amount
@onready var _sell_button: Button = %SellButton
@onready var _sell_all_button: Button = %SellAllButton

var _stalk_id: StringName = &""


func _ready() -> void:
	_sell_button.pressed.connect(_on_sell_pressed)
	_sell_all_button.pressed.connect(_on_sell_all_pressed)
	_amount_field.text_changed.connect(_on_amount_changed)
	_amount_field.text_submitted.connect(_on_amount_submitted)


func display(stalk: StalkState, shares_held: int) -> void:
	_stalk_id = stalk.id
	_name_label.text = stalk.definition.display_name
	_shares_label.text = str(shares_held)
	_price_label.text = Palette.format_money(stalk.price) if stalk.has_value() else "—"
	_value_label.text = Palette.format_money(stalk.price * shares_held) if stalk.has_value() else "—"
	_amount_field.placeholder_text = "max %d" % shares_held


func set_sell_blocked(reason: String) -> void:
	var blocked: bool = not reason.is_empty()
	_sell_button.disabled = blocked
	_sell_button.tooltip_text = reason
	_amount_field.theme_type_variation = (
		&"InvalidLineEdit" if blocked and not _amount_field.text.is_empty() else &""
	)


func shares_entered() -> int:
	return _amount_field.text.strip_edges().to_int()


func clear_amount() -> void:
	_amount_field.text = ""
	_amount_field.theme_type_variation = &""


func stalk_id() -> StringName:
	return _stalk_id


func _on_sell_pressed() -> void:
	sell_requested.emit(_stalk_id, shares_entered())


func _on_sell_all_pressed() -> void:
	sell_all_requested.emit(_stalk_id)


func _on_amount_changed(_text: String) -> void:
	amount_changed.emit(_stalk_id, shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if not _sell_button.disabled:
		sell_requested.emit(_stalk_id, shares_entered())
