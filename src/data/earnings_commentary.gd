class_name EarningsCommentary
extends Resource
## One line of earnings commentary: at most one per company a year, on the
## Company tab, chosen by the company's regime and how its revenue growth
## compared with what the regime leads one to expect
## (docs/stalkleheads-design.md §8.1). Lives in a `NewsBook` in src/data/news/.
##
## A line naming a company is preferred to one that leaves it empty, which can
## be about any company and says which with `{company}`.
##
## **The words are the owner's.** Until written, `text` is a placeholder that
## names its slot - `EARNINGS: {company}, slowing, worse than expected` (§8.3).


## Unique across every news line. Never shown.
@export var id: StringName = &""

## The `CompanyProfile.id` this is about, or empty for any company.
@export var company_id: StringName = &""

@export var regime: NewsBands.Regime = NewsBands.Regime.ANY

@export var surprise: NewsBands.Surprise = NewsBands.Surprise.ANY

## May contain `{company}` and `{industry}`.
@export_multiline var text: String = ""

## Ids of news lines, of any kind, that must have been shown in an earlier
## year before this one can be (decisions.md D210).
@export var requires: Array[StringName] = []
