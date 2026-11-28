extends RefCounted
## Balance levers the tool can override for a sweep, **without changing the
## defaults in `src/sim/`** (decisions.md D150). A sweep asks "what if this number
## were different?"; the owner decides afterwards whether to change the real one.
##
## The levers below, each defaulting to "use the published value":
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

## The squeeze's lift, in percent of the price per point of short interest.
## -1 = the rule's (`ShortInterestRules.SPIKE_PERCENT_PER_POINT`, 4; D213, D233).
var squeeze_size: int = -1

## What the desk's SHORT traders bet against: `highpe` (the published rule,
## D169) or `slowest` (S4's first rule, D164; tools/balance/lever_desk.gd, D168).
var short_target: StringName = &"highpe"

## The slope of the income trade-off (§3.10a): retention becomes
## `1 + slope * (35 - policy) / 100`. -1 = the published slope, 1. Applied by
## rescaling the positive growth roll in `lever_year.gd`, rounded to a whole
## roll, so a setting other than 1 is accurate to about half a point of growth
## (decisions.md D232).
var retention_slope: float = -1.0

## The flow clamp as a fraction of fair value (§3.10). -1 = the published 0.05.
var flow_limit: float = -1.0

## The flow clamp for matches longer than ten years, as a fraction of fair value:
## the published clamp at ten years or fewer, scaled linearly from there to this
## figure at 99 years (§13.2's first long-match lever). -1 = no scaling.
var flow_limit_at_99: float = -1.0

## The short-interest flag threshold, percent of shares outstanding (§5.3).
## -1 = the published 10 (`ShortInterestRules.FLAG_AT_PERCENT`).
var flag_at: float = -1.0

## Whisper levers (decisions.md D236). They change only what the WHISPER
## player hears: whispers move no price, so every other player's market is
## the same unless WHISPER's own trades feed flow.
##
## How many ordinary whispers a round. -1 = `NewsSelector.WHISPERS_PER_YEAR` (2).
var whisper_count: int = -1

## Each source's chance of telling the true band, in percent, Rock Solid to
## Gossip. Empty = `WhisperRules.ODDS`. The one-band-away chance of each source
## is kept, cut down if the two would pass 100.
var whisper_odds: Array[int] = []

## False: no squeeze or crash whisper is heard.
var squeeze_whispers: bool = true

## How often each source is picked, as weights, Rock Solid to Gossip (D237).
## Empty = `WhisperRules.SOURCE_WEIGHTS`, the game's rule (D238).
var whisper_sources: Array[int] = []

var _transition: Dictionary[EarningsRegime.Value, Array] = {}


## True when the regime roll is overridden, so the stand-in must roll it here.
func changes_regimes() -> bool:
	return growth_stay >= 0 or ageing >= 0.0


## True when any whisper lever is set, so the WHISPER player hears rounds the
## tool works out itself rather than the game's.
func changes_whispers() -> bool:
	if not whisper_sources.is_empty():
		return true
	return whisper_count >= 0 or not whisper_odds.is_empty() or not squeeze_whispers


## The odds table in use: `WhisperRules.ODDS`, or the override.
func whisper_odds_table() -> Dictionary[WhisperRules.Source, Vector2i]:
	if whisper_odds.is_empty():
		return WhisperRules.ODDS
	var table: Dictionary[WhisperRules.Source, Vector2i] = {}
	for index: int in WhisperRules.ALL_SOURCES.size():
		var source: WhisperRules.Source = WhisperRules.ALL_SOURCES[index]
		var true_chance: int = clampi(whisper_odds[index], 0, 100)
		var near: int = mini(WhisperRules.ODDS[source].y, 100 - true_chance)
		table[source] = Vector2i(true_chance, near)
	return table


## The source weights in use: `WhisperRules.SOURCE_WEIGHTS`, or the override.
func whisper_source_weights() -> Array[int]:
	if whisper_sources.is_empty():
		return WhisperRules.SOURCE_WEIGHTS
	return whisper_sources


## True when the growth roll is rescaled for the income trade-off.
func changes_retention() -> bool:
	return retention_slope >= 0.0 and retention_slope != 1.0


## The flow clamp for a match of `years`, as a fraction of fair value.
func flow_limit_for(years: int) -> float:
	var base: float = PriceIdentity.FLOW_LIMIT_FRACTION
	if flow_limit >= 0.0:
		base = flow_limit
	if flow_limit_at_99 < 0.0 or years <= 10:
		return base
	var along: float = float(mini(years, 99) - 10) / 89.0
	return base + (flow_limit_at_99 - base) * along


## The growth roll that gives, under the published retention, the growth this
## slope would: `roll * retention(slope) / retention(1)`, rounded, positive
## rolls only (retention applies to positive growth only).
func retained_roll(roll: int, payout_policy_percent: int) -> int:
	if not changes_retention() or roll <= 0:
		return roll
	var gap: float = float(DividendRules.NEUTRAL_POLICY_PERCENT - payout_policy_percent) / 100.0
	var wanted: float = 1.0 + retention_slope * gap
	return roundi(float(roll) * wanted / DividendRules.retention_factor(payout_policy_percent))


func changes_anything() -> bool:
	if changes_regimes() or not premium.is_empty() or not squeeze:
		return true
	if changes_retention() or flow_limit >= 0.0 or flow_limit_at_99 >= 0.0 or flag_at >= 0.0:
		return true
	if changes_whispers():
		return true
	return squeeze_chance >= 0 or squeeze_size >= 0 or short_target != &"highpe"


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
		parts.append("squeeze %d%% a point" % squeeze_size)
	if short_target != &"highpe":
		parts.append("SHORT target %s" % short_target)
	if retention_slope >= 0.0:
		parts.append("retention slope %.2f" % retention_slope)
	if flow_limit >= 0.0:
		parts.append("flow clamp %.3f" % flow_limit)
	if flow_limit_at_99 >= 0.0:
		parts.append("flow clamp %.3f at 99 years" % flow_limit_at_99)
	if flag_at >= 0.0:
		parts.append("flag at %.1f%%" % flag_at)
	if whisper_count >= 0:
		parts.append("%d whispers a round" % whisper_count)
	if not whisper_odds.is_empty():
		parts.append("whisper odds %s" % [whisper_odds])
	if not squeeze_whispers:
		parts.append("no squeeze whispers")
	if not whisper_sources.is_empty():
		parts.append("whisper sources %s" % [whisper_sources])
	return ", ".join(parts)


static func _bigger_remainder_first(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	return a[1] < b[1]
