class_name StalkRow
extends PanelContainer
## One stalk on the Available Stalks board: its price, movement, dividends, and a
## buy control.
##
## Knows nothing about the session or the screen holding it. It is handed a
## StalkState to display and emits intent outward; the screen decides what to do
## with that. See CLAUDE.md, "Signals for Decoupling".
##
## Column widths are set in stalk_row.tscn and the board header in
## gameplay_screen.tscn repeats them. If you change one, change the other.


## The player wants to buy. The screen validates and forwards to the session.
signal buy_requested(stalk_id: StringName, shares: int)

## The amount field changed and is worth re-validating for live feedback.
signal amount_changed(stalk_id: StringName, shares: int)


@onready var _name_label: Label = %Name
@onready var _price_label: Label = %Price
@onready var _change_label: Label = %Change
@onready var _bull_label: Label = %BullDividend
@onready var _bear_label: Label = %BearDividend
@onready var _amount_field: LineEdit = %Amount
@onready var _buy_button: Button = %BuyButton
@onready var _bankrupt_label: Label = %BankruptBanner

var _stalk_id: StringName = &""
var _is_bankrupt: bool = false


func _ready() -> void:
	_buy_button.pressed.connect(_on_buy_pressed)
	_amount_field.text_changed.connect(_on_amount_changed)
	_amount_field.text_submitted.connect(_on_amount_submitted)


## Fills the row from a stalk's current state.
func display(stalk: StalkState) -> void:
	_stalk_id = stalk.id
	_is_bankrupt = stalk.is_bankrupt

	_name_label.text = stalk.definition.display_name
	_price_label.text = Palette.format_money(stalk.price)
	_bull_label.text = str(stalk.definition.bull_dividend)
	_bear_label.text = str(stalk.definition.bear_dividend)

	# The displayed change is the base move only, excluding any special event —
	# matching the original. See docs/game-rules.md §5.
	_change_label.text = Palette.format_change(stalk.last_yearly_change)
	_change_label.add_theme_color_override(
		"font_color", Palette.for_change(stalk.last_yearly_change)
	)

	_bankrupt_label.visible = stalk.is_bankrupt
	_amount_field.visible = not stalk.is_bankrupt
	_buy_button.visible = not stalk.is_bankrupt

	theme_type_variation = &"BankruptCard" if stalk.is_bankrupt else &"Card"
	if stalk.is_bankrupt:
		_price_label.text = "—"
		_change_label.text = "—"


## Enables or disables the buy control, with `reason` shown as a tooltip when it
## is disabled. An empty reason means the action is allowed.
func set_buy_blocked(reason: String) -> void:
	if _is_bankrupt:
		return
	var blocked: bool = not reason.is_empty()
	_buy_button.disabled = blocked
	_buy_button.tooltip_text = reason
	_amount_field.theme_type_variation = (
		&"InvalidLineEdit" if blocked and not _amount_field.text.is_empty() else &""
	)


## The affordable maximum, shown as placeholder text so the player always knows
## the ceiling without having to guess.
func set_affordable_hint(maximum: int) -> void:
	_amount_field.placeholder_text = "max %d" % maximum


func shares_entered() -> int:
	return _amount_field.text.strip_edges().to_int()


func clear_amount() -> void:
	_amount_field.text = ""
	_amount_field.theme_type_variation = &""


func stalk_id() -> StringName:
	return _stalk_id


func _on_buy_pressed() -> void:
	buy_requested.emit(_stalk_id, shares_entered())


func _on_amount_changed(_text: String) -> void:
	amount_changed.emit(_stalk_id, shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if not _buy_button.disabled:
		buy_requested.emit(_stalk_id, shares_entered())
