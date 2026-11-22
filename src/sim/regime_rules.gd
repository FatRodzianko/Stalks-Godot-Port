class_name RegimeRules
extends RefCounted
## Earnings regimes in StalkleHeads mode: which regime follows which, and what
## each one does to revenue, margin, valuation and dividends.
## See docs/stalkleheads-design.md §3.3, §3.4 and §3.10a; every number here is
## copied from there.
##
## Pure rules, no state. The roll is split in two on purpose: `regime_for_roll`
## is a plain function of a roll from 1 to 100, so the odds can be enumerated
## exactly in a test, and `roll_next` is the only part that touches the RNG - one
## draw, every call, whatever the outcome (decisions.md D131).


## The published transition matrix. Row = this year's regime, column = next
## year's, both in `EarningsRegime.ALL` order. Percentages; each row sums to 100.
## GROWTH's row was [58, 14, 20, 6, 2] until the owner adopted the balance sweep's
## fix for P4 (decisions.md D151): its stay chance is 42, the other columns
## respread in the same proportions.
const TRANSITION: Dictionary[EarningsRegime.Value, Array] = {
	EarningsRegime.Value.GROWTH: [42, 19, 28, 8, 3],
	EarningsRegime.Value.STEADY: [16, 50, 18, 13, 3],
	EarningsRegime.Value.SLOWING: [10, 28, 38, 21, 3],
	EarningsRegime.Value.DECLINE: [6, 18, 16, 46, 14],
	EarningsRegime.Value.DISTRESS: [5, 10, 10, 25, 50],
}

## Quality bias: (quality - 50) / 5 points are subtracted from the roll, so a
## good company leans toward the left-hand, better columns. Range -10 to +10.
const QUALITY_NEUTRAL: int = 50
const QUALITY_DIVISOR: float = 5.0

## Ageing: each consecutive year already spent in GROWTH or SLOWING adds this
## many points to the roll, pushing it toward worse regimes.
const AGEING_POINTS: float = 10.0

## Recovery: each consecutive year already spent in DISTRESS subtracts this many.
const RECOVERY_POINTS: float = 12.0

## Revenue growth band per regime, in percent, as (min, max) inclusive.
const GROWTH_BAND: Dictionary[EarningsRegime.Value, Vector2i] = {
	EarningsRegime.Value.GROWTH: Vector2i(15, 35),
	EarningsRegime.Value.STEADY: Vector2i(-3, 6),
	EarningsRegime.Value.SLOWING: Vector2i(2, 12),
	EarningsRegime.Value.DECLINE: Vector2i(-20, -5),
	EarningsRegime.Value.DISTRESS: Vector2i(-45, -15),
}

## The margin each regime pulls a company toward, in percent of revenue.
const MARGIN_TARGET: Dictionary[EarningsRegime.Value, float] = {
	EarningsRegime.Value.GROWTH: 14.0,
	EarningsRegime.Value.STEADY: 12.0,
	EarningsRegime.Value.SLOWING: 11.0,
	EarningsRegime.Value.DECLINE: 7.0,
	EarningsRegime.Value.DISTRESS: 1.0,
}

## Margin moves one third of the way to its target each year:
## `margin += (target - margin) / 3`. Not truncated - margin is a float ratio
## (decisions.md D130).
const MARGIN_DIVISOR: float = 3.0

## Turns added to the multiple, per regime. 40% of the first draft's spread,
## and that narrowing is measured (§3.4, decision D2) - except GROWTH, raised
## from 0.6 to 1.2 with the stay chance above (D151). The other four are D2's.
const PREMIUM: Dictionary[EarningsRegime.Value, float] = {
	EarningsRegime.Value.GROWTH: 1.2,
	EarningsRegime.Value.STEADY: 0.0,
	EarningsRegime.Value.SLOWING: 0.24,
	EarningsRegime.Value.DECLINE: -0.6,
	EarningsRegime.Value.DISTRESS: -1.4,
}

## How much of a company's dividend policy it pays in each regime (§3.10a).
const PAYOUT_SCALE: Dictionary[EarningsRegime.Value, float] = {
	EarningsRegime.Value.GROWTH: 0.30,
	EarningsRegime.Value.STEADY: 1.00,
	EarningsRegime.Value.SLOWING: 0.85,
	EarningsRegime.Value.DECLINE: 0.55,
	EarningsRegime.Value.DISTRESS: 0.0,
}


## The regime a roll lands on, after the quality bias and ageing or recovery.
##
## `roll` is the raw draw, 1 to 100. `years_in_regime` counts the consecutive
## years the company has already spent in `current` beyond the year it entered
## it, so a company in its first year of GROWTH is not yet aged (D131).
##
## The adjusted roll is clamped to 1-100. With rows that sum to 100 the clamp
## changes no outcome; it is there so the boundary cases read plainly.
static func regime_for_roll(
	current: EarningsRegime.Value,
	roll: int,
	quality: int,
	years_in_regime: int,
) -> EarningsRegime.Value:
	var adjusted: float = float(roll) - quality_bias(quality) + age_shift(current, years_in_regime)
	adjusted = clampf(adjusted, 1.0, 100.0)

	var row: Array = TRANSITION[current]
	var running: float = 0.0
	for index: int in row.size():
		running += float(row[index])
		if adjusted <= running:
			return EarningsRegime.ALL[index]
	return EarningsRegime.Value.DISTRESS


## Next year's regime. Exactly one draw from `rng`, always.
static func roll_next(
	current: EarningsRegime.Value,
	quality: int,
	years_in_regime: int,
	rng: RandomNumberGenerator,
) -> EarningsRegime.Value:
	var roll: int = rng.randi_range(1, 100)
	return regime_for_roll(current, roll, quality, years_in_regime)


## Points subtracted from the roll for quality. Positive for a good company.
static func quality_bias(quality: int) -> float:
	return float(quality - QUALITY_NEUTRAL) / QUALITY_DIVISOR


## Points added to the roll for time already spent in `current`: ageing pushes
## GROWTH and SLOWING right, recovery pulls DISTRESS left, and STEADY and
## DECLINE get neither (§3.3).
static func age_shift(current: EarningsRegime.Value, years_in_regime: int) -> float:
	match current:
		EarningsRegime.Value.GROWTH, EarningsRegime.Value.SLOWING:
			return float(years_in_regime) * AGEING_POINTS
		EarningsRegime.Value.DISTRESS:
			return -float(years_in_regime) * RECOVERY_POINTS
	return 0.0


## The chance of landing on each regime next year, in percent, in matrix order.
## Computed by enumerating all hundred rolls, so it is exact and draws nothing.
## For tests and, later, for the Company tab's published odds.
static func odds(
	current: EarningsRegime.Value,
	quality: int,
	years_in_regime: int,
) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for roll: int in range(1, 101):
		var landed: EarningsRegime.Value = regime_for_roll(current, roll, quality, years_in_regime)
		counts[EarningsRegime.ALL.find(landed)] += 1
	return counts


## The long-match damping on growth bands, by the same ladder the base game uses
## for price swings (docs/game-rules.md §4.4): over 49 years x0.50, over 19
## years x0.80, otherwise x1.00. `match_years` is the match's length.
static func growth_damping(match_years: int) -> float:
	if match_years > 49:
		return 0.50
	if match_years > 19:
		return 0.80
	return 1.00
