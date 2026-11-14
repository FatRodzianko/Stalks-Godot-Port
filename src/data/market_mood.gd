class_name MarketMood
extends RefCounted
## The market's disposition for a single year.
##
## Bull years generally push prices up and bear years down, with a 10% chance per
## stalk of moving against the mood. See docs/game-rules.md §4.2 and §4.3.


enum Value {
	BULL,
	BEAR,
}


## The label as the original game displayed it.
static func label(mood: Value) -> String:
	match mood:
		Value.BULL:
			return "BULL!!!"
		Value.BEAR:
			return "bear..."
	return "unknown"


## Picks a mood using weighted odds. The original ships 7 bull to 5 bear (58.3%
## bull), encoded as a 12-element string array; here it is explicit and tunable.
##
## Falls back to BULL on nonsense weights rather than dividing by zero.
static func pick(
	bull_weight: int,
	bear_weight: int,
	rng: RandomNumberGenerator,
) -> Value:
	var total: int = bull_weight + bear_weight
	if total <= 0:
		return Value.BULL
	return Value.BULL if rng.randi_range(1, total) <= bull_weight else Value.BEAR
