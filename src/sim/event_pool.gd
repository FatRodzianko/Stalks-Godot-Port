class_name EventPool
extends RefCounted
## Draws one special event per year from a mood-specific pool.
##
## Events must not repeat, so each mood has a shuffled "bag" that is drawn from
## without replacement. When a bag empties it is refilled and reshuffled, so an
## event cannot recur until every other event in its pool has been seen.
##
## This matters: a 99-year match has roughly 58 bull years against only 45 bull
## events, so exhaustion is genuinely reachable and needs defined behaviour.
##
## An event whose target stalk is already bankrupt is SKIPPED and left in the bag
## rather than consumed — in the current model an event affects exactly one stalk,
## so a dead target makes it a no-op. Keeping that decision here, in the selection
## strategy, means "StalkleHeads" mode can choose differently once events also
## move an industry. See docs/game-rules.md §5.


## Full pools by mood, never mutated after construction.
var _pools: Dictionary[int, Array] = {}

## Remaining undrawn events by mood.
var _bags: Dictionary[int, Array] = {}


func _init(events: Array[SpecialEventDefinition] = []) -> void:
	for mood: int in [MarketMood.Value.BULL, MarketMood.Value.BEAR]:
		_pools[mood] = [] as Array[SpecialEventDefinition]
		_bags[mood] = [] as Array[SpecialEventDefinition]
	for event: SpecialEventDefinition in events:
		if event != null:
			_pools[event.mood].append(event)


## Draws a viable event for this mood, or null if none is viable — which happens
## when every candidate targets an already-bankrupt stalk.
func draw(
	mood: MarketMood.Value,
	state: GameState,
	rng: RandomNumberGenerator,
) -> SpecialEventDefinition:
	if _bags[mood].is_empty():
		_refill(mood, rng)

	var drawn: SpecialEventDefinition = _take_viable(mood, state)
	if drawn != null:
		return drawn

	# Everything still in the bag targets a bankrupt stalk. Refilling may expose
	# viable events already drawn earlier this cycle.
	_refill(mood, rng)
	return _take_viable(mood, state)


## How many events remain undrawn in this mood's bag. For tests and debug UI.
func remaining(mood: MarketMood.Value) -> int:
	return _bags[mood].size()


## Total authored events for this mood.
func pool_size(mood: MarketMood.Value) -> int:
	return _pools[mood].size()


## Removes and returns the first event in the (already shuffled) bag whose target
## stalk still exists and can be affected. Non-viable candidates are left in place.
func _take_viable(mood: MarketMood.Value, state: GameState) -> SpecialEventDefinition:
	var bag: Array = _bags[mood]
	for index: int in bag.size():
		var candidate: SpecialEventDefinition = bag[index]
		var target: StalkState = state.stalk_by_id(candidate.target_stalk_id)
		if target != null and not target.is_bankrupt and not target.is_price_static():
			bag.remove_at(index)
			return candidate
	return null


func _refill(mood: MarketMood.Value, rng: RandomNumberGenerator) -> void:
	var refilled: Array[SpecialEventDefinition] = []
	for event: SpecialEventDefinition in _pools[mood]:
		refilled.append(event)
	_shuffle(refilled, rng)
	_bags[mood] = refilled


## Fisher-Yates using the injected RNG. Array.shuffle() uses the global generator,
## which would break determinism — see docs/architecture.md §8.
func _shuffle(items: Array[SpecialEventDefinition], rng: RandomNumberGenerator) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: SpecialEventDefinition = items[i]
		items[i] = items[j]
		items[j] = swap
