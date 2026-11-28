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
## lowered it, the lift covers that too.
##
## **How long it runs is not known in advance (D220).** Every later year, the
## squeeze either ends - the whole lift comes off at once - or holds, and the
## lift drifts up or down a little. Two things decide it, both on screen: how
## much of the short interest is still open (`squeeze_remaining_percent`, the
## fuel), and the market's mood. Shorts still open push the lift up and keep the
## squeeze going; a bull market helps it hold, a bear market helps end it. The
## short sellers buy back an uneven, random part each year, so no number counts
## down to the end. It can end in its second year; it has no last year.
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
const SPIKE_PERCENT_PER_POINT: float = 4.0

## ...up to this percent of the price.
const SPIKE_MAX_PERCENT: float = 150.0

## The part of their squeezed shorts the short sellers buy back each year, in
## percent, drawn evenly from this range (one roll a year for every squeeze).
const COVER_MIN: int = 20
const COVER_MAX: int = 50

## At or below this percent of the short interest still open, the rest is
## bought back at once: the fuel is gone.
const FUEL_GONE_PERCENT: int = 10

## The chance a squeeze ends in a year, in percent: `END_BASE` plus
## `END_PER_COVERED` times the share of the shorts already bought back, then
## `END_MOOD` more after a bear year or less after a bull one, within
## `END_MIN`-`END_MAX`. About a third of squeezes end in their second year,
## a tenth run five years or more (measured in decisions.md D220).
const END_BASE: int = 15
const END_PER_COVERED: int = 70
const END_MOOD: int = 10
const END_MIN: int = 5
const END_MAX: int = 95

## A held squeeze's lift moves by a roll of plus or minus `DRIFT_SPREAD`
## percent, plus `DRIFT_PUSH` percent times the share of shorts still open,
## plus `DRIFT_BASE`, and `DRIFT_MOOD` more after a bull year or less after a
## bear one. With most shorts open it tends up; with few, down.
const DRIFT_SPREAD: int = 15
const DRIFT_PUSH: int = 25
const DRIFT_BASE: int = -5
const DRIFT_MOOD: int = 5


## The lift, in whole coins (rounded down), for a company priced at `price`
## with `short_percent` of its shares sold short.
static func spike_for(price: int, short_percent: float) -> int:
	if price <= 0 or short_percent <= 0.0:
		return 0
	var lift_percent: float = minf(SPIKE_MAX_PERCENT, short_percent * SPIKE_PERCENT_PER_POINT)
	return int(float(price) * lift_percent / 100.0)


## How much of `owed` shares a short seller buys back this year from a company
## in a squeeze: `cover_percent` of them, rounded up, or all of them once the
## company's remaining short interest is gone (`remaining_percent` 0).
static func cover_now(owed: int, cover_percent: int, remaining_percent: int) -> int:
	if owed <= 0:
		return 0
	if remaining_percent <= 0:
		return owed
	@warning_ignore("integer_division")
	return mini(owed, (owed * cover_percent + 99) / 100)


## The share of a squeeze's short interest still open after a year in which
## `cover_percent` of it was bought back, in whole percent; 0 once it is at or
## below `FUEL_GONE_PERCENT`.
static func remaining_after(remaining_percent: int, cover_percent: int) -> int:
	@warning_ignore("integer_division")
	var left: int = remaining_percent * (100 - cover_percent) / 100
	if left <= FUEL_GONE_PERCENT:
		return 0
	return left


## The chance, in percent, that a squeeze with `remaining_percent` of its short
## interest still open ends this year, after a year whose mood was `mood`.
static func end_chance_percent(remaining_percent: int, mood: MarketMood.Value) -> int:
	@warning_ignore("integer_division")
	var chance: int = END_BASE + END_PER_COVERED * (100 - remaining_percent) / 100
	if mood == MarketMood.Value.BEAR:
		chance += END_MOOD
	else:
		chance -= END_MOOD
	return clampi(chance, END_MIN, END_MAX)


## How much a held squeeze's lift moves this year, in percent of itself, from
## the drift roll (`-DRIFT_SPREAD` to `DRIFT_SPREAD`).
static func drift_percent(roll: int, remaining_percent: int, mood: MarketMood.Value) -> int:
	@warning_ignore("integer_division")
	var drift: int = roll + DRIFT_BASE + DRIFT_PUSH * remaining_percent / 100
	if mood == MarketMood.Value.BULL:
		drift += DRIFT_MOOD
	else:
		drift -= DRIFT_MOOD
	return drift


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
