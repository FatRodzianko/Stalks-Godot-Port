class_name CompanyNews
extends Resource
## One line of company news: at most one per company a year, under IN THE NEWS
## on the Company tab, chosen by how far the company's price moved this year
## (docs/stalkleheads-design.md §8.1, decisions.md D211). Flavor only: it moves
## nothing. Lives in a `NewsBook` in src/data/news/.
##
## A line naming a company is preferred to one that leaves it empty, which can
## be about any company and says which with `{company}`. The base game's
## special events for the companies both games share were carried over as
## company news, spread across the moves.


## Unique across every news line. Never shown.
@export var id: StringName = &""

## The `CompanyProfile.id` this is about, or empty for any company.
@export var company_id: StringName = &""

## The company's own price move this year.
@export var move: NewsBands.Move = NewsBands.Move.ANY

## May contain `{company}` and `{industry}`.
@export_multiline var text: String = ""

## Ids of news lines that must have been shown in an earlier year first (D210).
@export var requires: Array[StringName] = []
