class_name NpcStrategy
extends RefCounted
## The eight rules an NPC trader can trade by in StalkleHeads mode. Every trader
## on the desk follows exactly one, and the rules are **published in the game**,
## because a trader whose logic is secret is just more randomness
## (docs/stalkleheads-design.md §5.1).
##
## An enum rather than content, because the desk branches on each value: each is
## a different piece of code in `NpcDesk.target_for`. A new strategy is a code
## change; a new trader following an existing strategy is a file.
##
## The rule each one follows, as the player is told it:
##
## | Strategy     | Rule |
## |---|---|
## | `VALUE`      | Buys the lowest P/E |
## | `MOMENTUM`   | Buys whatever rose most last year |
## | `CONTRARIAN` | Buys whatever fell most last year |
## | `INCOME`     | Buys the highest dividend yield |
## | `INDEXER`    | Buys My Mutuals and Me Inc., and nothing else, ever |
## | `PANIC`      | Sells everything for the bond in a bear year, buys back in a bull one |
## | `GROWTH`     | Buys whatever grew its earnings fastest |
## | `SHORT`      | Bets against whichever company's earnings grew slowest |


enum Value {
	VALUE,
	MOMENTUM,
	CONTRARIAN,
	INCOME,
	INDEXER,
	PANIC,
	GROWTH,
	SHORT,
}


## Every strategy, in the design document's order.
const ALL: Array[Value] = [
	Value.VALUE,
	Value.MOMENTUM,
	Value.CONTRARIAN,
	Value.INCOME,
	Value.INDEXER,
	Value.PANIC,
	Value.GROWTH,
	Value.SHORT,
]


## The strategy's name as the design document writes it. A plain identifier,
## not display text.
static func name_of(strategy: Value) -> String:
	match strategy:
		Value.VALUE:
			return "VALUE"
		Value.MOMENTUM:
			return "MOMENTUM"
		Value.CONTRARIAN:
			return "CONTRARIAN"
		Value.INCOME:
			return "INCOME"
		Value.INDEXER:
			return "INDEXER"
		Value.PANIC:
			return "PANIC"
		Value.GROWTH:
			return "GROWTH"
		Value.SHORT:
			return "SHORT"
	return "UNKNOWN"


## True for the one strategy that holds short positions instead of shares.
static func is_short(strategy: Value) -> bool:
	return strategy == Value.SHORT
