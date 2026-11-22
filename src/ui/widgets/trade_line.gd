class_name TradeLine
extends HBoxContainer
## A line of text cells with a trade box at its end: a holding in the side
## panel, a company in an industry's member list. The owner chooses the cells
## (`configure`, in characters, as `CellRow`); the trade box is always the same
## (`TradeBox`). Signals carry the company's id, never this line.


signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)

## The text part was clicked: open this company on the Company tab.
signal info_requested(stalk_id: StringName)


## The company this line trades.
var stalk_id: StringName = &""

@onready var _cells: CellRow = %Cells
@onready var _trade: TradeBox = %Trade


func _ready() -> void:
	_trade.buy_requested.connect(_on_trade_buy_requested)
	_trade.sell_requested.connect(_on_trade_sell_requested)
	_trade.amount_changed.connect(_on_trade_amount_changed)
	_cells.pressed.connect(_on_cells_pressed)


## The text cells, as `CellRow.configure`. Call once.
func configure(widths: Array[int], aligns: Array[int] = []) -> void:
	_cells.configure(widths, aligns)
	_cells.set_clickable(true)


func cells() -> CellRow:
	return _cells


func trade_box() -> TradeBox:
	return _trade


func line_text() -> String:
	return _cells.line_text()


func _on_trade_buy_requested(shares: int) -> void:
	buy_requested.emit(stalk_id, shares)


func _on_trade_sell_requested(shares: int) -> void:
	sell_requested.emit(stalk_id, shares)


func _on_trade_amount_changed(shares: int) -> void:
	amount_changed.emit(stalk_id, shares)


func _on_cells_pressed(_key: StringName) -> void:
	info_requested.emit(stalk_id)
