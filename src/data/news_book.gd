class_name NewsBook
extends Resource
## A file of StalkleHeads news lines: any mix of the categories of
## docs/stalkleheads-design.md §8.1. Saved as a .tres in src/data/news/.
## `ContentLibrary` loads **every** `.tres` there, so how lines are split
## between files is a matter of convenience; the game ships one file for the
## market and one per industry (decisions.md D199).
##
## The base game's special events are not used in StalkleHeads: market news
## takes their place (D209), and those for the companies both games share were
## carried over as company news (D211).


@export var market_news: Array[MarketNews] = []
@export var industry_reports: Array[IndustryReport] = []
@export var company_news: Array[CompanyNews] = []
@export var whispers: Array[Whisper] = []
@export var chatter: Array[NpcChatter] = []
