class_name NewsBands
extends RefCounted
## The named conditions StalkleHeads news is chosen by
## (docs/stalkleheads-design.md §8.1). **Bands, not expressions**: every
## condition a news line can carry is one of these values, never a formula in a
## string, so `ContentLibrary.validate()` can check every line at load and a
## typo cannot write a line that never fires.
##
## `ANY` is first in every enum that has it, so a line that leaves a condition
## alone matches every year - and a `.tres` that never mentions a field means
## `ANY`, because Godot does not write a field that holds its default.
##
## Which band a year falls in is a rule, so it is worked out in `src/sim`
## (`NewsSelector`), not here. This file only names the bands.


## The year's reported mood.
enum Mood { ANY, BULL, BEAR }

## A move in percent: the index's for a headline, an industry's for a report.
## The edges are `NewsSelector.move_band`'s: CRASH at -15 or below, DOWN below
## -3, FLAT from -3 to +3, UP below +15, SURGE at +15 or above.
enum Move { ANY, CRASH, DOWN, FLAT, UP, SURGE }

## A company's earnings regime this year (design §3.3), or ANY.
enum Regime { ANY, GROWTH, STEADY, SLOWING, DECLINE, DISTRESS }

## How a company's revenue growth compared with what its regime leads one to
## expect: the middle of the regime's growth band (`NewsSelector.surprise_band`).
enum Surprise { ANY, MUCH_WORSE, WORSE, AS_EXPECTED, BETTER, MUCH_BETTER }

## What a whisper is about: a real condition on real state, worked out in
## `NewsSelector.trigger_holds` and asserted in tests (design §8.1).
enum Trigger {
	## The SHORT traders' position in a company was flagged this year (§5.3).
	HIGH_SHORT_INTEREST,
	## A company is in its third year (or later) of GROWTH: ageing is about to bite.
	THIRD_GROWTH_YEAR,
	## A company's margin fell while its revenue rose.
	MARGIN_SLIPPING,
	## A company's P/E is more than 20% above its industry's average.
	PE_ABOVE_INDUSTRY,
	## A company's P/E is more than 20% below its industry's average.
	PE_BELOW_INDUSTRY,
	## An industry has moved the same way three years running. About an industry.
	SECTOR_RUN,
	## A company's price is close enough to the split line that a split is in reach.
	NEAR_SPLIT,
	## A company is in DISTRESS with a price under 20.
	NEAR_FAILURE,
}

## Every trigger, in the order above.
const ALL_TRIGGERS: Array[Trigger] = [
	Trigger.HIGH_SHORT_INTEREST,
	Trigger.THIRD_GROWTH_YEAR,
	Trigger.MARGIN_SLIPPING,
	Trigger.PE_ABOVE_INDUSTRY,
	Trigger.PE_BELOW_INDUSTRY,
	Trigger.SECTOR_RUN,
	Trigger.NEAR_SPLIT,
	Trigger.NEAR_FAILURE,
]


## The band for an `EarningsRegime` value.
static func regime_band(regime: EarningsRegime.Value) -> Regime:
	match regime:
		EarningsRegime.Value.GROWTH:
			return Regime.GROWTH
		EarningsRegime.Value.STEADY:
			return Regime.STEADY
		EarningsRegime.Value.SLOWING:
			return Regime.SLOWING
		EarningsRegime.Value.DECLINE:
			return Regime.DECLINE
	return Regime.DISTRESS


## True when a trigger is about an industry rather than a company.
static func is_industry_trigger(trigger: Trigger) -> bool:
	return trigger == Trigger.SECTOR_RUN
