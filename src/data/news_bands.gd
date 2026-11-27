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

## A move in percent: the index's last year for market news, an industry's for
## its reports, a company's price for company news.
## The edges are `NewsSelector.move_band`'s: CRASH at -15 or below, DOWN below
## -3, FLAT from -3 to +3, UP below +15, SURGE at +15 or above.
enum Move { ANY, CRASH, DOWN, FLAT, UP, SURGE }

## A company's earnings regime this year (design §3.3), or ANY.
enum Regime { ANY, GROWTH, STEADY, SLOWING, DECLINE, DISTRESS }

## How a company's revenue growth compared with what its regime leads one to
## expect: the middle of the regime's growth band (`NewsSelector.surprise_band`).
## Also what a whisper foretells for next year (design §8.4).
enum Surprise { ANY, MUCH_WORSE, WORSE, AS_EXPECTED, BETTER, MUCH_BETTER }

## What a whisper is about (design §8.4): next year's earnings of a company or
## an industry, or a short squeeze - one coming (SQUEEZE), or one about to end
## (CRASH) - on a company (D214).
enum Subject { COMPANY, INDUSTRY, SQUEEZE, CRASH }


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

