class_name StalkYearChange
extends RefCounted
## What happened to one stalk during one year advance.
##
## Part of YearResult. Records the base move and the event move separately,
## because players are shown only the base figure as "Yearly Change" while the
## event delta is reported in the event text — see docs/game-rules.md §5.


var stalk_id: StringName = &""

var price_before: int = 0

## The normal mood-driven move, after any long-game softening. This is the figure
## displayed as "Yearly Change".
var base_delta: int = 0

## Extra movement from this year's special event, if it targeted this stalk.
## Excluded from the displayed yearly change.
var event_delta: int = 0

var did_split: bool = false

var went_bankrupt: bool = false

## Final price once the base move, the event, and any split have been applied.
var price_after: int = 0


## Total movement including the event. Not shown to players, but useful in tests
## and for charts later.
func total_delta() -> int:
	return base_delta + event_delta


func _to_string() -> String:
	var notes: String = ""
	if did_split:
		notes += " SPLIT"
	if went_bankrupt:
		notes += " BANKRUPT"
	return "StalkYearChange(%s %d -> %d base=%+d event=%+d%s)" % [
		stalk_id, price_before, price_after, base_delta, event_delta, notes,
	]
