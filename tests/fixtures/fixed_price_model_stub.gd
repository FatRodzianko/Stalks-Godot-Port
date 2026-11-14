class_name FixedPriceModelStub
extends PriceModel
## Test double returning the same delta for every stalk, so a test can isolate
## splits, bankruptcy or dividends from the real random model.
##
## Static-price stalks still return 0, because that rule belongs to the stalk and
## not to the model being stubbed.


var delta: int = 0


func _init(fixed_delta: int = 0) -> void:
	delta = fixed_delta


func next_change(
	stalk: StalkState,
	_mood: MarketMood.Value,
	_state: GameState,
	_rng: RandomNumberGenerator,
) -> int:
	return 0 if stalk.is_price_static() else delta


func model_name() -> String:
	return "fixed_stub"
