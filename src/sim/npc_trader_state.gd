class_name NpcTraderState
extends RefCounted
## One NPC trader during a StalkleHeads match: its cash, the shares it holds,
## and - for a SHORT trader - the shares it is short.
##
## Pairs with an immutable `NpcTraderDefinition`. Pure data with arithmetic
## helpers; every decision is `NpcDesk`'s. See docs/stalkleheads-design.md §5.
##
## **Money is `int`**, like a player's. A SHORT trader's cash includes the
## proceeds of what it has sold short, and its worth subtracts what buying those
## shares back would cost, so its worth is the same kind of number as anyone
## else's. A SHORT trader's cash may go below zero if a shorted price soars;
## a trader is not a player, cannot go bankrupt and is not ranked.


var definition: NpcTraderDefinition

var cash: int = 0

## Shares held, by stalk id. Never negative; a zero entry is removed.
var holdings: Dictionary[StringName, int] = {}

## Shares sold short, by company id. Only a SHORT trader has any. Never
## negative; a zero entry is removed. Summed across traders, this is the
## short interest (`NpcDesk.short_interest`).
var shorts: Dictionary[StringName, int] = {}


var id: StringName:
	get:
		return definition.id if definition != null else &""


var strategy: NpcStrategy.Value:
	get:
		return definition.strategy


func _init(trader: NpcTraderDefinition) -> void:
	definition = trader
	if definition != null:
		cash = definition.starting_cash


func shares_of(stalk_id: StringName) -> int:
	return holdings.get(stalk_id, 0)


func short_of(company_id: StringName) -> int:
	return shorts.get(company_id, 0)


func set_shares(stalk_id: StringName, count: int) -> void:
	if count <= 0:
		holdings.erase(stalk_id)
	else:
		holdings[stalk_id] = count


func set_short(company_id: StringName, count: int) -> void:
	if count <= 0:
		shorts.erase(company_id)
	else:
		shorts[company_id] = count


## Held stalk ids, sorted, so anything walking them walks in one order.
func held_ids() -> Array[StringName]:
	var ids: Array[StringName] = holdings.keys()
	ids.sort_custom(_id_order)
	return ids


## Shorted company ids, sorted.
func shorted_ids() -> Array[StringName]:
	var ids: Array[StringName] = shorts.keys()
	ids.sort_custom(_id_order)
	return ids


## Cash, plus what its shares are worth at the posted prices, minus what buying
## back its shorts would cost. A bankrupt row is worth nothing either way.
func worth(state: GameState) -> int:
	var total: int = cash
	for stalk_id: StringName in holdings:
		var row: StalkState = state.stalk_by_id(stalk_id)
		if row != null and row.price > 0:
			total += holdings[stalk_id] * row.price
	for company_id: StringName in shorts:
		var row: StalkState = state.stalk_by_id(company_id)
		if row != null and row.price > 0:
			total -= shorts[company_id] * row.price
	return total


func _to_string() -> String:
	return "NpcTraderState(%s, cash %d)" % [id, cash]


static func _id_order(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
