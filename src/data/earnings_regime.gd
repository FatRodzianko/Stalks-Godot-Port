class_name EarningsRegime
extends RefCounted
## The five earnings regimes of StalkleHeads mode. Every company is in exactly one
## of them each year, and the regime decides how its revenue moves.
##
## An enum rather than content, because the code branches on each value: each has
## its own row in the transition matrix, its own growth band, margin target,
## valuation premium and payout scale, and ageing applies to two of them only.
## See docs/stalkleheads-design.md §3.2.1 and §3.3. The rules attached to each
## value live in `RegimeRules`, not here.
##
## The order matters: it is the column order of the transition matrix, best to
## worst, and the quality bias pushes a roll toward the left of it.


enum Value {
	GROWTH,
	STEADY,
	SLOWING,
	DECLINE,
	DISTRESS,
}


## Every regime, in matrix order.
const ALL: Array[Value] = [
	Value.GROWTH,
	Value.STEADY,
	Value.SLOWING,
	Value.DECLINE,
	Value.DISTRESS,
]


## The regime's name as the design document writes it. A plain identifier, not
## display text: how a regime is named on screen is the interface phase's.
static func name_of(regime: Value) -> String:
	match regime:
		Value.GROWTH:
			return "GROWTH"
		Value.STEADY:
			return "STEADY"
		Value.SLOWING:
			return "SLOWING"
		Value.DECLINE:
			return "DECLINE"
		Value.DISTRESS:
			return "DISTRESS"
	return "UNKNOWN"
