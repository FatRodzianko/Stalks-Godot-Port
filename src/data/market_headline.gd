class_name MarketHeadline
extends Resource
## One market headline: at most one is shown a year, on the Market tab, chosen
## by the year's mood and how far the index moved (docs/stalkleheads-design.md
## §8.1). Lives in a `NewsBook` in src/data/news/.
##
## **The words are the owner's.** Until written, `text` is a placeholder that
## names its slot - `MARKET HEADLINE: bull, surge` (§8.3). How to write one:
## docs/development.md, "Writing StalkleHeads news".


## Unique across every news line. Never shown.
@export var id: StringName = &""

@export var mood: NewsBands.Mood = NewsBands.Mood.ANY

## The index's move this year.
@export var move: NewsBands.Move = NewsBands.Move.ANY

## No `{...}` tokens: a headline is about the whole market.
@export_multiline var text: String = ""
