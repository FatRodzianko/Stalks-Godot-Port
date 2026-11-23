class_name KeptDraws
extends RefCounted
## Next year's earnings draws, made a year early and kept until they are used
## (docs/stalkleheads-design.md §8.4, decisions.md D205).
##
## A StalkleHeads year's earnings take, per industry, one swing, and per living
## company, a regime and a growth roll. None of them depends on anything a
## player does, so `EarningsYearResolver` draws them at the **end** of the year
## before (and once at match start, for year 1) and keeps them here, on
## `EarningsMarket.next_draws`. The next year uses them instead of drawing.
##
## **Why early.** A whisper foreshadows next year's earnings, and it can only
## do that honestly if next year is already decided. The draws come from the
## same distributions as before, only sooner, so nothing about a price is
## nudged to make a rumor come true.
##
## Travels in the snapshot (`MarketSync`), so every peer chooses the same
## whispers and a promoted host goes on using the departed host's draws. Pure
## data; no rules.


## Each industry's swing for next year, by industry id.
var industry_rolls: Dictionary[StringName, int] = {}

## The regime each living company enters next year, by company id.
var regimes: Dictionary[StringName, EarningsRegime.Value] = {}

## Each living company's growth roll for next year, from its new regime's band.
var growth_rolls: Dictionary[StringName, int] = {}


func copy() -> KeptDraws:
	var twin: KeptDraws = KeptDraws.new()
	twin.industry_rolls = industry_rolls.duplicate()
	twin.regimes = regimes.duplicate()
	twin.growth_rolls = growth_rolls.duplicate()
	return twin


## The draws a played year used, read back from its record.
static func of_year(result: EarningsYearResult) -> KeptDraws:
	var draws: KeptDraws = KeptDraws.new()
	draws.industry_rolls = result.industry_rolls.duplicate()
	draws.regimes = result.regimes.duplicate()
	draws.growth_rolls = result.growth_rolls.duplicate()
	return draws
