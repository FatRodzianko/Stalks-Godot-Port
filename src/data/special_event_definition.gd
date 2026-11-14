class_name SpecialEventDefinition
extends Resource
## One special event: a flavoured, one-off price shock aimed at a single named
## stalk, drawn once per year from a mood-specific pool.
##
## The original hardcoded 90 of these in StalkManager.CreateSpecialEvents().
## See docs/game-rules.md §5.


## Stable key, unique across all events. Used so a drawn event can be tracked
## without comparing flavour text.
@export var id: StringName = &""

## The stalk this event hits, by StalkDefinition.id. An event always names its
## target — it is content about a stalk, not a free-floating market shock.
@export var target_stalk_id: StringName = &""

## Which pool this event belongs to. Bull-pool events are drawn in bull years.
@export var mood: MarketMood.Value = MarketMood.Value.BULL

## Shown to players in red, above the mechanical effect.
@export_multiline var flavour_text: String = ""

## Added to the target's price on top of the normal yearly change, and
## deliberately excluded from the "Yearly Change" figure players see.
## Positive in the bull pool, negative in the bear pool.
@export var price_change: int = 0


func _to_string() -> String:
	return "SpecialEventDefinition(%s -> %s %+d)" % [id, target_stalk_id, price_change]
