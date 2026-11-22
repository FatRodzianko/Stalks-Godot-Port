class_name ShortInterestRules
extends RefCounted
## Short interest and the squeeze it makes possible, in StalkleHeads mode
## (docs/stalkleheads-design.md §5.3, decisions.md D165).
##
## **Foreshadowing is a real state variable or it is not foreshadowing** (§15 M).
## The short interest on a company is the number of shares the desk's SHORT
## traders are short in it, summed - nothing more. When that is a large enough
## share of the company, the company is *flagged*: the news may say so (S8),
## and while the flag is set, and only then, a short squeeze can be the year's
## event. So a player told "short interest is high" has been told something
## true, by a stated amount.
##
## Players cannot short (§14 q10). Pure rules, no state, no randomness.


## A company is flagged when its short interest is at least this percent of its
## shares outstanding. Three SHORT traders committing about 45% of 8,000 each are
## short about 11% of a 1,000-share company priced at 100, and more of a cheaper
## one, so a weak, cheap company is flagged and a weak, expensive one may not be.
const FLAG_AT_PERCENT: float = 10.0

## The chance, in percent, that a flagged company's squeeze is the year's event
## instead of a draw from the mood bag. **0 when nothing is flagged**: the
## squeeze is not in the bag at all, so without the flag it cannot happen.
## Asserted as a constant in a test.
const SQUEEZE_CHANCE_PERCENT: int = 25


## Short interest as a percent of shares outstanding. 0 for a company with no
## shares (which content validation refuses anyway).
static func percent_of(short_interest: int, shares_outstanding: int) -> float:
	if shares_outstanding <= 0:
		return 0.0
	return float(short_interest) * 100.0 / float(shares_outstanding)


static func is_flagged(short_interest: int, shares_outstanding: int) -> bool:
	return short_interest > 0 and percent_of(short_interest, shares_outstanding) >= FLAG_AT_PERCENT


## The squeeze chance for a year: SQUEEZE_CHANCE_PERCENT when any company is
## flagged, else 0. A squeeze fires when the year's roll (1-100, drawn every year
## whether or not it is used) is at most this.
static func squeeze_chance_percent(any_flagged: bool) -> int:
	if any_flagged:
		return SQUEEZE_CHANCE_PERCENT
	return 0


## The squeeze aimed at one company, built from the authored template: the
## template's size and mood, its text with `{company}` filled in, and an id of
## `short_squeeze_<company>`. Built when it fires, never saved.
static func squeeze_event(
	template: SpecialEventDefinition,
	company_id: StringName,
	company_name: String,
) -> SpecialEventDefinition:
	var event: SpecialEventDefinition = SpecialEventDefinition.new()
	event.id = StringName("%s_%s" % [template.id, company_id])
	event.target_stalk_id = company_id
	event.mood = template.mood
	event.price_change = template.price_change
	event.flavour_text = template.flavour_text.replace("{company}", company_name)
	return event
