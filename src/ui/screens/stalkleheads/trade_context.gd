class_name TradeContext
extends RefCounted
## What every trade box on the StalkleHeads tabs needs to know, handed to each
## tab with its refresh: whether this player may trade now, what they hold, and
## why a given buy or sell would be refused.
##
## **The refusals are the screen's**, passed in as two named methods of
## `GameplayScreen` that ask the session (`why_not_buy`, `why_not_sell`): the
## same rules the authority enforces (docs/architecture.md 5.1). No tab works
## out a rule; it asks this.


var state: GameState
var player: PlayerState
var trading: bool = false

## (stalk_id: StringName, shares: int) -> String, empty when allowed.
var _buy_check: Callable
var _sell_check: Callable


func _init(
	game: GameState,
	who: PlayerState,
	is_trading: bool,
	buy_check: Callable,
	sell_check: Callable,
) -> void:
	state = game
	player = who
	trading = is_trading
	_buy_check = buy_check
	_sell_check = sell_check


func held(stalk_id: StringName) -> int:
	if player == null:
		return 0
	return player.shares_of(stalk_id)


## Sets `box` up for `stalk_id`: open or closed, what is held, the affordable
## hint, and the checks for whatever is already typed.
func prepare(box: TradeBox, stalk_id: StringName) -> void:
	var stalk: StalkState = state.stalk_by_id(stalk_id)
	if stalk == null or stalk.is_bankrupt:
		box.set_dead()
		return
	box.set_open(trading and player != null, held(stalk_id))
	if player != null:
		box.set_affordable_hint(TradeRules.max_affordable(player, stalk))
	check(box, stalk_id)


## Re-checks what is typed in `box`, after the player types.
## The holdings panel's rows are the base game's `HoldingRow`, sell only
## (decisions.md D184): open while trading, and greyed with the reason when
## what is typed would be refused.
func prepare_holding(row: HoldingRow, stalk_id: StringName) -> void:
	row.set_trading_open(trading and player != null)
	check_holding(row, stalk_id)


func check_holding(row: HoldingRow, stalk_id: StringName) -> void:
	if not trading or player == null:
		return
	var shares: int = row.shares_entered()
	if shares <= 0 or not _sell_check.is_valid():
		row.set_sell_blocked("")
		return
	row.set_sell_blocked(_sell_check.call(stalk_id, shares))


func check(box: TradeBox, stalk_id: StringName) -> void:
	if not trading or player == null:
		return
	var shares: int = box.shares_entered()
	if shares <= 0 or not _buy_check.is_valid():
		box.set_checks("", "")
		return
	box.set_checks(_buy_check.call(stalk_id, shares), _sell_check.call(stalk_id, shares))
