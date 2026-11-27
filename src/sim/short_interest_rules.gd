class_name ShortInterestRules
extends RefCounted
## Short interest and the squeeze it makes possible, in StalkleHeads mode
## (docs/stalkleheads-design.md §5.3, decisions.md D165, D213).
##
## **Foreshadowing is a real state variable or it is not foreshadowing** (§15 M).
## The short interest on a company is the number of shares the desk's SHORT
## traders are short in it, summed - nothing more. When that is a large enough
## share of the company, the company is *flagged*: the news may say so (S8),
## and while the flag is set, and only then, a short squeeze can be the year's
## event. So a player told "short interest is high" has been told something
## true, by a stated amount.
##
## **The squeeze is a meme stock (D213).** When it fires, the company's price
## jumps by a share of itself that grows with how much of it is sold short
## (`spike_for`), and never falls that year: if the rest of the year would have
## lowered it, the lift covers that too. The lift then stays at full size while
## the desk's short sellers buy back, an equal part each year for one to three
## years (the hold roll), and comes off all at once the year after the last
## short is covered. A player watching short interest fall to 0% is watching
## the fuel run out.
##
## Players cannot short (§14 q10). Pure rules, no state, no randomness.


## A company is flagged when its short interest is at least this percent of its
## shares outstanding. Three SHORT traders committing about 45% of 8,000 each are
## short about 11% of a 1,000-share company priced at 100, and more of a cheaper
## one, so the same bet flags a cheap target and may not flag a dear one. They bet
## against the highest P/E (decisions.md D169).
const FLAG_AT_PERCENT: float = 10.0

## The chance, in percent, that a flagged company's squeeze is the year's event
## instead of a draw from the mood bag. **0 when nothing is flagged**: the
## squeeze is not in the bag at all, so without the flag it cannot happen.
## Asserted as a constant in a test.
const SQUEEZE_CHANCE_PERCENT: int = 25


## The squeeze's lift is this percent of the price per percentage point of
## short interest: 10% short lifts the price by half.
const SPIKE_PERCENT_PER_POINT: float = 5.0

## ...up to this percent of the price.
const SPIKE_MAX_PERCENT: float = 150.0

## How many years the lift is held, drawn evenly from this range when it fires.
const HOLD_YEARS_MIN: int = 1
const HOLD_YEARS_MAX: int = 3


## The lift, in whole coins (rounded down), for a company priced at `price`
## with `short_percent` of its shares sold short.
static func spike_for(price: int, short_percent: float) -> int:
	if price <= 0 or short_percent <= 0.0:
		return 0
	var lift_percent: float = minf(SPIKE_MAX_PERCENT, short_percent * SPIKE_PERCENT_PER_POINT)
	return int(float(price) * lift_percent / 100.0)


## How much of `owed` shares a short seller buys back this year from a company
## in a squeeze with `years_left` more years to run after this one: an equal
## part, rounded up, so the last year covers the rest.
static func cover_now(owed: int, years_left: int) -> int:
	if owed <= 0:
		return 0
	@warning_ignore("integer_division")
	return mini(owed, (owed + years_left) / (years_left + 1))


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
