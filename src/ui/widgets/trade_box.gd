class_name TradeBox
extends HBoxContainer
## A quantity box with Buy and Sell beside it: every place a StalkleHeads player
## can trade a company from - the board, the holdings list, an industry's
## members, the Company tab. One scene, so they all behave alike
## (CLAUDE.md: a repeated control is one reusable scene).
##
## **Fixed in place.** The box and both buttons always take their width. SELL
## is greyed, never hidden, when there is nothing to sell, so nothing beside it
## moves when a player first buys (manual-testing.md E, decisions.md D183).
## 5 + 5 + 6 characters: the box shows four digits whole, and the buttons say
## BUY and SELL in full (D184).
##
## Knows nothing about rules. Its owner says whether trading is open and why a
## buy or sell would be refused (`set_checks`), from the same rules the
## authority enforces, and carries the company id this box trades.


signal buy_requested(shares: int)
signal sell_requested(shares: int)
signal amount_changed(shares: int)


## The three parts' widths, in characters (CellRow.CELL_WIDTH each).
const AMOUNT_CHARS: int = 5
const BUY_CHARS: int = 5
const SELL_CHARS: int = 6
const WIDTH_CHARS: int = AMOUNT_CHARS + BUY_CHARS + SELL_CHARS


var _open: bool = false
var _held: int = 0

@onready var _amount: LineEdit = %Amount
@onready var _buy: Button = %BuyButton
@onready var _sell: Button = %SellButton


func _ready() -> void:
	_amount.custom_minimum_size.x = AMOUNT_CHARS * CellRow.CELL_WIDTH
	_buy.custom_minimum_size.x = BUY_CHARS * CellRow.CELL_WIDTH
	_sell.custom_minimum_size.x = SELL_CHARS * CellRow.CELL_WIDTH
	_buy.pressed.connect(_on_buy_pressed)
	_sell.pressed.connect(_on_sell_pressed)
	_amount.text_changed.connect(_on_amount_text_changed)
	_amount.text_submitted.connect(_on_amount_submitted)
	set_open(false)


## Whether this player may trade right now, and how many shares they hold.
## Closed greys everything; with nothing held, S stays greyed.
func set_open(is_open: bool, held: int = 0) -> void:
	_open = is_open
	_held = held
	_amount.editable = is_open
	_buy.disabled = not is_open
	_sell.disabled = not is_open or held <= 0
	_buy.tooltip_text = "Buy"
	_sell.tooltip_text = "Sell"
	if held <= 0:
		_sell.tooltip_text = "Nothing to sell"


## The refusals for what is typed, empty when allowed. Greys a button with the
## reason as its tooltip, as the base board does.
func set_checks(buy_reason: String, sell_reason: String) -> void:
	if not _open:
		return
	var shares: int = shares_entered()
	_buy.disabled = shares > 0 and not buy_reason.is_empty()
	_buy.tooltip_text = buy_reason if _buy.disabled else "Buy"
	_sell.disabled = _held <= 0 or (shares > 0 and not sell_reason.is_empty())
	_sell.tooltip_text = "Sell"
	if _held <= 0:
		_sell.tooltip_text = "Nothing to sell"
	elif _sell.disabled:
		_sell.tooltip_text = sell_reason
	_amount.theme_type_variation = &""
	if _buy.disabled and shares > 0 and _sell.disabled:
		_amount.theme_type_variation = &"InvalidLineEdit"


## The most this player can afford, as the box's placeholder.
func set_affordable_hint(maximum: int) -> void:
	_amount.placeholder_text = str(maximum)
	_amount.tooltip_text = "Most you can afford: %d" % maximum


## Empty, greyed, and its hint cleared: a bankrupt company's row.
func set_dead() -> void:
	set_open(false)
	_amount.text = ""
	_amount.placeholder_text = ""


func shares_entered() -> int:
	return _amount.text.strip_edges().to_int()


func clear_amount() -> void:
	_amount.text = ""
	_amount.theme_type_variation = &""


func buy_is_blocked() -> bool:
	return _buy.disabled


func sell_is_blocked() -> bool:
	return _sell.disabled


## Types into the box as a player would. For tests.
func type_amount(text: String) -> void:
	_amount.text = text
	_amount.text_changed.emit(text)


func press_buy() -> void:
	_buy.pressed.emit()


func press_sell() -> void:
	_sell.pressed.emit()


func _on_buy_pressed() -> void:
	buy_requested.emit(shares_entered())


func _on_sell_pressed() -> void:
	sell_requested.emit(shares_entered())


func _on_amount_text_changed(_text: String) -> void:
	amount_changed.emit(shares_entered())


func _on_amount_submitted(_text: String) -> void:
	if not _buy.disabled:
		buy_requested.emit(shares_entered())
