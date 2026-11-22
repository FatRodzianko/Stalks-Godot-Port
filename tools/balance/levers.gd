extends RefCounted
## Balance levers the tool can override for a sweep, **without changing the
## defaults in `src/sim/`** (decisions.md D150). A sweep asks "what if this number
## were different?"; the owner decides afterwards whether to change the real one.
##
## Three levers, each defaulting to "use the published value":
##
## - `premium`: the regime premium, turns of multiple per regime, in
##   `EarningsRegime.ALL` order. Empty = `RegimeRules.PREMIUM`.
## - `growth_stay`: GROWTH's chance of staying GROWTH, in percent. The removed
##   (or added) weight goes to the other four columns in proportion to the
##   published row, rounded by largest remainder so the row still sums to 100.
##   -1 = the published value (42 since decisions.md D151).
## - `ageing`: points a year added to the roll in GROWTH and SLOWING, as §3.3's
##   ageing does. -1 = the published 10.
##
## **How each reaches the real code.** The premium enters through
## `CompanyState.reprice`'s industry-performance argument, shifted so the
## multiple comes out exactly as if the premium table had the override (see
## `valuation_performance`). The regime levers replace only the regime roll; the
## accounts still move by the real `CompanyState.move_accounts`, and the draw
## count is the real one: one roll, one growth draw. With every lever at its
## default the stand-in calls `advance_earnings` itself, and
## `test_balance_smoke.gd` checks the override path reproduces it exactly.


var premium: Array[float] = []
var growth_stay: int = -1
var ageing: float = -1.0

## False turns the short squeeze off (§5.3), to measure what it does. Not a
## number in src/sim/: the tool builds the resolver without the template.
var squeeze: bool = true

## The squeeze's chance in a flagged year, in percent. -1 = the published 25
## (`ShortInterestRules.SQUEEZE_CHANCE_PERCENT`).
var squeeze_chance: int = -1

## The squeeze's price change. -1 = the authored template's (+25).
var squeeze_size: int = -1

## What the desk's SHORT traders bet against: `slowest` (the published rule,
## D164) or `highpe` (tools/balance/lever_desk.gd, D168).
var short_target: StringName = &"slowest"

var _transition: Dictionary[EarningsRegime.Value, Array] = {}


## True when the regime roll is overridden, so the stand-in must roll it here.
func changes_regimes() -> bool:
	return growth_stay >= 0 or ageing >= 0.0


func changes_anything() -> bool:
	if changes_regimes() or not premium.is_empty() or not squeeze:
		return true
	return squeeze_chance >= 0 or squeeze_size >= 0 or short_target != &"slowest"


## The published premium spread scaled by `factor` (1.0 = today's, 2.5 = the
## first draft's).
static func scaled_premium(factor: float) -> Array[float]:
	var scaled: Array[float] = []
	for regime: EarningsRegime.Value in EarningsRegime.ALL:
		scaled.append(RegimeRules.PREMIUM[regime] * factor)
	return scaled


## The transition matrix in use: the published one, with GROWTH's row rebuilt
## if `growth_stay` is set.
func transition() -> Dictionary[EarningsRegime.Value, Array]:
	if not _transition.is_empty():
		return _transition
	_transition = RegimeRules.TRANSITION.duplicate(true)
	if growth_stay >= 0:
		_transition[EarningsRegime.Value.GROWTH] = growth_row(growth_stay)
	return _transition


## GROWTH's row with its stay chance set to `stay`. The other four columns share
## `100 - stay` in proportion to the published row (19 : 28 : 8 : 3 since D151;
## the sweep that chose it used the earlier 14 : 20 : 6 : 2), by largest
## remainder (ties to the better regime, the left-hand column).
static func growth_row(stay: int) -> Array[int]:
	var published: Array = RegimeRules.TRANSITION[EarningsRegime.Value.GROWTH]
	var others_total: int = 0
	for index: int in range(1, 5):
		others_total += int(published[index])
	var share: int = 100 - stay
	var row: Array[int] = [stay, 0, 0, 0, 0]
	var remainders: Array[Array] = []
	var given: int = 0
	for index: int in range(1, 5):
		# Integer arithmetic, so a tie is a real tie and not float noise.
		var scaled: int = share * int(published[index])
		row[index] = scaled / others_total
		given += row[index]
		remainders.append([scaled % others_total, index])
	remainders.sort_custom(_bigger_remainder_first)
	for spare: int in share - given:
		row[int(remainders[spare][1])] += 1
	return row


## The regime a roll lands on, as `RegimeRules.regime_for_roll` but with this
## matrix and ageing. Recovery from DISTRESS and the quality bias are the real ones.
func regime_for_roll(
	current: EarningsRegime.Value,
	roll: int,
	quality: int,
	years_in_regime: int,
) -> EarningsRegime.Value:
	var shift: float = RegimeRules.age_shift(current, years_in_regime)
	if ageing >= 0.0 and (current == EarningsRegime.Value.GROWTH or current == EarningsRegime.Value.SLOWING):
		shift = float(years_in_regime) * ageing
	var adjusted: float = float(roll) - RegimeRules.quality_bias(quality) + shift
	adjusted = clampf(adjusted, 1.0, 100.0)
	var row: Array = transition()[current]
	var running: float = 0.0
	for index: int in row.size():
		running += float(row[index])
		if adjusted <= running:
			return EarningsRegime.ALL[index]
	return EarningsRegime.Value.DISTRESS


## The industry performance to hand `reprice` so its multiple uses this premium:
## standing is `performance * STANDING_GAIN`, so shifting performance by
## `(override - published) / STANDING_GAIN` adds exactly the premium difference.
## The multiple's clamp sees the same sum, so it clamps identically. The
## company's `industry_standing` readout is off by the difference, which the
## tool never reads.
func valuation_performance(regime: EarningsRegime.Value, performance: float) -> float:
	if premium.is_empty():
		return performance
	var extra: float = premium[EarningsRegime.ALL.find(regime)] - RegimeRules.PREMIUM[regime]
	return performance + extra / IndustryState.STANDING_GAIN


## One line naming the overrides, for the report.
func describe() -> String:
	if not changes_anything():
		return "published values"
	var parts: PackedStringArray = []
	if not premium.is_empty():
		var numbers: PackedStringArray = []
		for value: float in premium:
			numbers.append("%.2f" % value)
		parts.append("premium %s" % "/".join(numbers))
	if growth_stay >= 0:
		parts.append("GROWTH row %s" % [growth_row(growth_stay)])
	if ageing >= 0.0:
		parts.append("ageing %.0f" % ageing)
	if not squeeze:
		parts.append("no short squeeze")
	if squeeze_chance >= 0:
		parts.append("squeeze chance %d%%" % squeeze_chance)
	if squeeze_size >= 0:
		parts.append("squeeze size %+d" % squeeze_size)
	if short_target != &"slowest":
		parts.append("SHORT target %s" % short_target)
	return ", ".join(parts)


static func _bigger_remainder_first(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	return a[1] < b[1]
