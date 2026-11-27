class_name MarketNews
extends Resource
## One piece of StalkleHeads market news: the mode's own special event
## (docs/stalkleheads-design.md §8.5, decisions.md D209). A headline, the event
## text under it and, if it has one, an effect: an amount of coins added to one
## company's price or to every living company of one industry. At most one a
## year, shown under THIS YEAR'S NEWS on the Market tab. Lives in a `NewsBook`
## in src/data/news/.
##
## **It moves prices**, so unlike every other news line it is chosen by the
## economy (`EarningsYearResolver`), with the match's own generator, before the
## year's prices are set - from **last year's** mood and index move, since this
## year's are not known until the prices are (D154). Like a base-game special
## event, its amount fades by half each year after.
##
## **The words are the owner's.**


## Unique across every news line. Never shown.
@export var id: StringName = &""

## Last year's mood: drawn in the year after a bull or a bear year, or either.
@export var mood: NewsBands.Mood = NewsBands.Mood.ANY

## Last year's index move.
@export var move: NewsBands.Move = NewsBands.Move.ANY

## The headline, in large type. No `{...}` tokens.
@export_multiline var headline: String = ""

## The event text under the headline. May contain `{company}` and
## `{industry}`, the target's names. May be empty.
@export_multiline var text: String = ""

## The `CompanyProfile.id` the effect hits, or empty.
@export var target_company: StringName = &""

## The `IndustryDefinition.id` whose every living company the effect hits, or
## empty. At most one of the two targets is set.
@export var target_industry: StringName = &""

## Coins added to each target's price this year: negative for a fall, 0 for
## news with no effect.
@export var amount: int = 0

## Ids of news lines, of any kind, that must have been shown in an earlier
## year before this one can be (D210).
@export var requires: Array[StringName] = []


## True when it names something for its amount to hit.
func has_target() -> bool:
	return not target_company.is_empty() or not target_industry.is_empty()
