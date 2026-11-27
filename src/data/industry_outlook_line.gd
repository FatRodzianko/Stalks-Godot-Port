class_name IndustryOutlookLine
extends Resource
## The second sentence of an industry's INDUSTRY REPORT: what is expected of it
## next year (docs/stalkleheads-design.md §8.6, decisions.md D212). Lives in a
## `NewsBook`.
##
## **The expectation is public**: this year's move carried over plus the
## market's lean, the same two numbers the price model uses before next year's
## swing is drawn. It is never next year's real move, which no player may see.


## Unique across every news line. Never shown.
@export var id: StringName = &""

## The `IndustryDefinition.id` this is about, or empty for any industry.
@export var industry_id: StringName = &""

## The move expected next year.
@export var outlook: NewsBands.Move = NewsBands.Move.ANY

## May contain `{industry}`.
@export_multiline var text: String = ""

## Ids of news lines that must have been shown in an earlier year first (D210).
@export var requires: Array[StringName] = []
