class_name IndustryYearLine
extends Resource
## The first sentence of an industry's INDUSTRY REPORT on the Industries tab:
## how the industry did this year, and how that compared with what was
## expected (docs/stalkleheads-design.md §8.6, decisions.md D212). One a year
## per industry, followed by an `IndustryOutlookLine`. Lives in a `NewsBook`.
##
## **What was expected** is the part of the industry's move everybody could
## see coming - last year's move carried over and the market's lean - so the
## surprise is the year's own swing (`NewsSelector.surprise_band` of it). It
## reveals nothing a whisper hints at.
##
## Until the owner writes them, the shipped lines are plain statements of the
## facts, one for every move and surprise.


## Unique across every news line. Never shown.
@export var id: StringName = &""

## The `IndustryDefinition.id` this is about, or empty for any industry.
@export var industry_id: StringName = &""

## The industry's move this year.
@export var move: NewsBands.Move = NewsBands.Move.ANY

## How that compared with what was expected.
@export var surprise: NewsBands.Surprise = NewsBands.Surprise.ANY

## The industry's move last year, for lines such as "again". ANY for most.
@export var last_move: NewsBands.Move = NewsBands.Move.ANY

## May contain `{industry}`.
@export_multiline var text: String = ""

## Ids of news lines that must have been shown in an earlier year first (D210).
@export var requires: Array[StringName] = []
