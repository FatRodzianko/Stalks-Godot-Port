class_name RandomRangePriceModel
extends PriceModel
## The faithful port of the original game's price movement.
##
## Per stalk, independently rolled each year — not one roll shared across the
## market. See docs/game-rules.md §4.3 and §4.4.
##
## Three behaviours combine:
##   1. A 10% chance of moving AGAINST the year's mood (the "contrarian" move).
##   2. Otherwise, a random move within the stalk's own range for that mood.
##   3. Long-game softening, applied to the normal move only — never to a
##      contrarian one, matching the original.


## Contrarian move in a bear year: a small gain.
const CONTRARIAN_BEAR_GAIN: Vector2i = Vector2i(0, 5)

## Contrarian move in a bull year: a small loss.
const CONTRARIAN_BULL_LOSS: Vector2i = Vector2i(-10, 0)


func next_change(
	stalk: StalkState,
	mood: MarketMood.Value,
	state: GameState,
	rng: RandomNumberGenerator,
) -> int:
	if stalk.is_price_static():
		return 0

	var settings: GameSettings = state.settings
	if settings == null:
		return 0

	var is_bear: bool = mood == MarketMood.Value.BEAR

	# 1. Contrarian roll. Deliberately NOT softened.
	if rng.randi_range(1, 100) <= settings.contrarian_chance_percent:
		var bounds: Vector2i = CONTRARIAN_BEAR_GAIN if is_bear else CONTRARIAN_BULL_LOSS
		return rng.randi_range(bounds.x, bounds.y)

	# 2. Normal move within the stalk's range for this mood. Bear magnitudes are
	#    stored positive and applied negatively.
	#
	#    Range endpoints are INCLUSIVE here. The original used C#
	#    Random.Next(min, max), which excludes max, so its stat-block maximums
	#    were unreachable — strYker could never actually gain 42 despite saying
	#    42. This is a deliberate, confirmed divergence. See docs/game-rules.md
	#    §4.5.
	var delta: int = 0
	if is_bear:
		var bear: Vector2i = stalk.definition.bear_change
		delta = -rng.randi_range(bear.x, bear.y)
	else:
		var bull: Vector2i = stalk.definition.bull_change
		delta = rng.randi_range(bull.x, bull.y)

	# 3. Long-game softening. int() truncates toward zero, matching C#'s (int)
	#    cast for both positive and negative values.
	var multiplier: float = settings.softening_multiplier(mood)
	if not is_equal_approx(multiplier, 1.0):
		delta = int(delta * multiplier)

	return delta


func model_name() -> String:
	return "random_range"
