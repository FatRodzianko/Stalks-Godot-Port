class_name NewsBook
extends Resource
## A file of StalkleHeads news lines: any mix of the categories of
## docs/stalkleheads-design.md §8.1. Saved as a .tres in src/data/news/.
## `ContentLibrary` loads **every** `.tres` there, so how lines are split
## between files is a matter of convenience; the game ships one file for the
## market and one per industry (decisions.md D199).
##
## The sixth category, special events, is not here: it is the existing
## `SpecialEventDefinition`, carried on a stalk (D29).


@export var headlines: Array[MarketHeadline] = []
@export var industry_reports: Array[IndustryReport] = []
@export var earnings_commentary: Array[EarningsCommentary] = []
@export var whispers: Array[Whisper] = []
@export var chatter: Array[NpcChatter] = []
