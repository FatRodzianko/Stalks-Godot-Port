class_name PriceLedger
extends RefCounted
## Why a company's price moved this year, in whole coins, summing exactly to the
## move. See docs/stalkleheads-design.md §3.5 ("the ledger") and property P1.
##
## Because the price is an identity, `fair_value + event_carry + flow`, its
## change splits into named parts:
##
## | Line | Float term |
## |---|---|
## | `earnings` | change in EPS, at last year's multiple: `(eps1 - eps0) * m0` |
## | `sentiment` | `eps1 * (s1 - s0) * 0.02` |
## | `industry_standing` | `eps1 * (standing1 - standing0)` |
## | `regime_premium` | `eps1 * (premium1 - premium0)` |
## | `valuation_limits` | what the 4-30 multiple clamp or the fair-value clamp took off; 0 unless one was hit |
## | `this_years_event` | this year's event delta |
## | `last_years_event_faded` | the half of last year's carry that decayed away |
## | `flow` | change in flow |
##
## **How the lines become whole coins (D133).** Each line is the change in
## `int(running total)` as the float terms are added one at a time, starting from
## last year's posted price and ending at this year's. That telescopes: the lines
## sum to `price_after - price_before` exactly, by construction, with no rounding
## step of its own and no remainder parked anywhere. A split between the two
## years is already in `price_before`, so it needs no line.
##
## This is a readout. It derives from two `CompanyState` snapshots and changes
## nothing.


var price_before: int = 0
var price_after: int = 0

var earnings: int = 0
var sentiment: int = 0
var industry_standing: int = 0
var regime_premium: int = 0
var valuation_limits: int = 0
var this_years_event: int = 0
var last_years_event_faded: int = 0
var flow: int = 0


## The ledger between `before` (a `copy()` taken before the year's earnings
## season) and `after` (the same company once `reprice` has run).
static func between(before: CompanyState, after: CompanyState) -> PriceLedger:
	var ledger: PriceLedger = PriceLedger.new()
	ledger.price_before = before.price
	ledger.price_after = after.price

	var eps_before: float = before.earnings_per_share()
	var eps_after: float = after.earnings_per_share()

	var earnings_term: float = (eps_after - eps_before) * before.multiple
	var sentiment_term: float = (
		eps_after * (after.sentiment - before.sentiment) * ValuationRules.SENTIMENT_GAIN
	)
	var standing_term: float = eps_after * (after.industry_standing - before.industry_standing)
	var premium_term: float = eps_after * (after.regime_premium - before.regime_premium)

	# Only a clamp makes the four terms above disagree with the change in fair
	# value by more than float noise; reporting the noise would print a stray 1.
	var limits_term: float = 0.0
	if before.valuation_clamped or after.valuation_clamped:
		limits_term = (after.fair_value - before.fair_value) - (
			earnings_term + sentiment_term + standing_term + premium_term
		)

	var event_term: float = float(after.event_delta)
	var faded_term: float = after.event_carry - before.event_carry - event_term
	var flow_term: float = after.flow - before.flow

	var terms: Array[float] = [
		earnings_term, sentiment_term, standing_term, premium_term,
		limits_term, event_term, faded_term, flow_term,
	]
	var lines: Array[int] = []
	var running: float = before.fair_value + before.event_carry + before.flow
	var posted: int = before.price
	for index: int in terms.size():
		var reached: int = after.price
		if index < terms.size() - 1:
			running += terms[index]
			reached = int(running)
		lines.append(reached - posted)
		posted = reached

	ledger.earnings = lines[0]
	ledger.sentiment = lines[1]
	ledger.industry_standing = lines[2]
	ledger.regime_premium = lines[3]
	ledger.valuation_limits = lines[4]
	ledger.this_years_event = lines[5]
	ledger.last_years_event_faded = lines[6]
	ledger.flow = lines[7]
	return ledger


func total() -> int:
	return (
		earnings + sentiment + industry_standing + regime_premium
		+ valuation_limits + this_years_event + last_years_event_faded + flow
	)


## What the change in the multiple itself was worth, apart from the industry:
## the sentiment, regime-premium and valuation-limit lines together. The
## Company tab prints the ledger in the design's six lines (§7.5), and this is
## its "multiple" line; the industry's standing is a line of its own.
func multiple_total() -> int:
	return sentiment + regime_premium + valuation_limits


## P1: the lines account for the whole move.
func is_balanced() -> bool:
	return total() == price_after - price_before


func _to_string() -> String:
	return "PriceLedger(%d -> %d: earnings %+d, sentiment %+d, standing %+d, regime %+d, limits %+d, event %+d, faded %+d, flow %+d)" % [
		price_before, price_after, earnings, sentiment, industry_standing, regime_premium,
		valuation_limits, this_years_event, last_years_event_faded, flow,
	]
