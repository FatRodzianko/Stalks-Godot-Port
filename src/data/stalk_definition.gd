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

## Short board symbol, the way a terminal lists an instrument.
##
## Nothing displays this yet: the board shows the full `display_name` and scrolls
## it when it does not fit, because the joke names are half the point of the
## game. This is here for a future compact view, where a dense board of symbols
## would suit the terminal look. See docs/ui-reference.md.
@export var ticker: StringName = &""

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

@export_group("Special Events")
## This stalk's special events, drawn in bull and bear years respectively.
##
## Events live on the stalk rather than in separate pool files so that a stalk and
## everything about it is ONE authorable unit: adding a stalk means adding one
## .tres, and nothing else needs editing. That also matches the planned
## JSON-authored custom stalks, where a submitted stalk carries its own events.
## See docs/decisions.md D29.
##
## A static-price stalk carries none — it cannot be moved by anything.
@export var bull_events: Array[SpecialEventDefinition] = []
@export var bear_events: Array[SpecialEventDefinition] = []


## Every event on this stalk, both moods together.
func all_events() -> Array[SpecialEventDefinition]:
	var combined: Array[SpecialEventDefinition] = []
	combined.append_array(bull_events)
	combined.append_array(bear_events)
	return combined


## What the board shows in its name column: the ticker when one is authored,
## otherwise the display name.
func board_symbol() -> String:
	return String(ticker) if ticker != &"" else display_name


func _to_string() -> String:
	return "StalkDefinition(%s)" % id
