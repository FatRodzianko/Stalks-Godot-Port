class_name IndustryReport
extends Resource
## One industry report: at most one per industry a year, on the Industries
## tab, chosen by how far that industry moved (docs/stalkleheads-design.md
## §8.1). Lives in a `NewsBook` in src/data/news/.
##
## A report naming an industry is preferred to one that leaves it empty, which
## can be about any industry and says which with `{industry}`.
##
## **The words are the owner's.** Until written, `text` is a placeholder that
## names its slot - `INDUSTRY REPORT: energy, down` (§8.3).


## Unique across every news line. Never shown.
@export var id: StringName = &""

## The `IndustryDefinition.id` this is about, or empty for any industry.
@export var industry_id: StringName = &""

@export var mood: NewsBands.Mood = NewsBands.Mood.ANY

## The industry's own performance this year.
@export var move: NewsBands.Move = NewsBands.Move.ANY

## May contain `{industry}`, the industry's display name.
@export_multiline var text: String = ""

## Ids of news lines, of any kind, that must have been shown in an earlier
## year before this one can be (decisions.md D210).
@export var requires: Array[StringName] = []
