class_name PriceModel
extends RefCounted
## Strategy for how a stalk's price moves in one year. Abstract — subclass it.
##
## This is the main extensibility seam in the project. The faithful port uses
## RandomRangePriceModel; "StalkleHeads" mode will add an earnings-driven model
## without touching the year pipeline. See docs/architecture.md §4.
##
## `next_change` receives the WHOLE market state, not just one stalk, so a future
## model can price a stalk relative to the others — which is what lets
## "My Mutuals and Me Inc." eventually behave as a genuine index.


## Returns this year's base price delta for one stalk, excluding any special event.
##
## Implementations must take all randomness from `rng` and never touch global
## randi()/randf(), or determinism is lost. See docs/architecture.md §8.
func next_change(
	_stalk: StalkState,
	_mood: MarketMood.Value,
	_state: GameState,
	_rng: RandomNumberGenerator,
) -> int:
	push_error("PriceModel.next_change is abstract — use a subclass.")
	return 0


## Short name for logs and debug UI.
func model_name() -> String:
	return "abstract"
