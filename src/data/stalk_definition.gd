class_name StalkDefinition
extends Resource
## Authored content for one stalk: its identity, how its price moves, and what it
## pays. Saved as a .tres in src/data/stalks/.
##
## This is content, not behaviour, and holds nothing that changes during a game —
## that lives in StalkState. See docs/game-rules.md §3 for the shipped values.


## Stable key used everywhere a stalk is referenced. NEVER the display name: the
## original matched stalks by comparing display strings, which is why it needed a
## hardcoded name check for BERRY BONDS and why an event could silently fail to
## find its target.
@export var id: StringName = &""

@export var display_name: String = ""

@export var starting_price: int = 100

## Magnitude of the normal yearly change in a BEAR year, as (min, max).
## Stored positive and applied negatively, matching the original's data.
@export var bear_change: Vector2i = Vector2i.ZERO

## Magnitude of the normal yearly change in a BULL year, as (min, max).
@export var bull_change: Vector2i = Vector2i.ZERO

## Paid per share held, every bear year. Fixed — no randomness.
@export var bear_dividend: int = 0

## Paid per share held, every bull year. Fixed — no randomness.
@export var bull_dividend: int = 0

## True for an instrument whose price never moves — BERRY BONDS, the risk-free
## bond. Such a stalk cannot change price, split, or go bankrupt, and carries no
## special events.
##
## Replaces the original's `stalkName != "BERRY BONDS FROM DIE HARD"` comparison,
## making the behaviour data rather than a special case.
@export var is_price_static: bool = false

## Reserved for "StalkleHeads" mode, where each stalk belongs to a sector whose
## performance modifies its earnings. Unused by the current price model; present
## now so content authored today needs no migration later.
@export var industry: StringName = &""


func _to_string() -> String:
	return "StalkDefinition(%s)" % id
