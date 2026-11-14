class_name StalkState
extends RefCounted
## The live, changing state of one stalk during a match.
##
## Pairs with an immutable StalkDefinition: the definition says how the stalk
## behaves, this says where it currently stands. Pure data — no nodes, no signals.


var definition: StalkDefinition

var price: int = 0

## The normal yearly change only. This is the "Yearly Change" figure shown on the
## board, and it deliberately EXCLUDES any special-event delta — matching the
## original. See docs/game-rules.md §5.
var last_yearly_change: int = 0

var is_bankrupt: bool = false

## Set during the year a split happened, so the UI can call it out. Cleared at the
## start of the next year advance.
var did_split: bool = false


## Convenience passthrough — stalks are referenced by id constantly.
var id: StringName:
	get:
		return definition.id if definition != null else &""


func _init(stalk_definition: StalkDefinition) -> void:
	definition = stalk_definition
	if definition != null:
		price = definition.starting_price


## A static-price instrument (BERRY BONDS) can never move, split, or fail.
func is_price_static() -> bool:
	return definition != null and definition.is_price_static


## The dividend this stalk pays per share in the given mood.
func dividend_per_share(mood: MarketMood.Value) -> int:
	if definition == null:
		return 0
	return (
		definition.bear_dividend
		if mood == MarketMood.Value.BEAR
		else definition.bull_dividend
	)


## Whether holdings in this stalk currently carry any value.
func has_value() -> bool:
	return not is_bankrupt and price > 0


func _to_string() -> String:
	return "StalkState(%s @ %d%s)" % [id, price, " BANKRUPT" if is_bankrupt else ""]
