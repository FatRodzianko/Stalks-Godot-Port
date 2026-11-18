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


@onready var _name_label: MarqueeLabel = %Name
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

	_name_label.set_full_text("NAME")
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

	# The full name is shown, and scrolls on hover when it does not fit.
	_name_label.set_full_text(stalk.definition.display_name)
	_bull_label.text = str(stalk.definition.bull_dividend)
	_bear_label.text = str(stalk.definition.bear_dividend)

	_show_as_bankrupt(stalk.is_bankrupt)

	if stalk.is_bankrupt:
		_price_label.text = "BANKRUPT!!!"
		_price_label.theme_type_variation = &"Danger"
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
		_buy_button.tooltip_text = "%s is bankrupt." % stalk.definition.display_name

	theme_type_variation = &"BankruptCard" if stalk.is_bankrupt else &"Card"


## A dead stalk keeps its name and loses everything else.
##
## **This is the original's shape, restored.** It replaced the whole detail
## area of the row with `BANKRUPT!!!` and kept only the name; the port had been
## abbreviating it to `BNKRT` in the price column and leaving the dividends,
## the change and the buy controls sitting there as though they still meant
## something. The audit recorded this as ported when it was not (section 3.1).
##
## **The fault that prompted it:** the amount field kept the affordable-maximum
## placeholder it was given before the stalk died - a row offering to sell you
## five thousand shares of a company that no longer exists. Clearing the text
## was not enough, because the number lived in the placeholder.
##
## The columns are hidden rather than blanked, and the price label expands to
## take the space. The row's own height does not change, so the board does not
## shift when a stalk dies mid-match.
func _show_as_bankrupt(dead: bool) -> void:
	_bull_label.visible = not dead
	_bear_label.visible = not dead
	_change_label.visible = not dead
	_amount_field.visible = not dead
	_buy_button.visible = not dead

	if dead:
		_amount_field.text = ""
		_amount_field.placeholder_text = ""
		_amount_field.tooltip_text = ""

	if dead:
		_price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		_price_label.size_flags_horizontal = 0
		_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


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


## Shows the affordable maximum as the field's placeholder.
##
## Just the number, not "max N": the field is seven characters wide, so "max "
## left room for only three digits and anything larger was cut off. The word is
## carried by the tooltip instead, where there is room for it.
func set_affordable_hint(maximum: int) -> void:
	if _is_header or _is_bankrupt:
		return
	_amount_field.placeholder_text = str(maximum)
	_amount_field.tooltip_text = "Most you can afford: %d" % maximum


func shares_entered() -> int:
	return _amount_field.text.strip_edges().to_int()


func clear_amount() -> void:
	if _is_header:
		return
	_amount_field.text = ""
	_amount_field.theme_type_variation = &""


## Whether this row's buy control is currently refusing presses, for whatever
## reason: the stalk is bankrupt, trading is shut, or the player has readied up
## and their board has gone read-only. For tests.
func buy_is_blocked() -> bool:
	return _buy_button.disabled


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
