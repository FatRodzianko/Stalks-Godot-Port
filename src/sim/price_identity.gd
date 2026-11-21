class_name PriceIdentity
extends RefCounted
## The StalkleHeads price, which is an identity rather than a roll:
##
## ```
## event_carry = previous_event_carry * 0.50 + this_year_event_delta
## flow        = previous_flow * 0.70 + net_shares_traded / shares_outstanding * 100 * 0.55
## flow        = clamp(flow, -5% of fair value, +5% of fair value)
## price       = int(fair_value + event_carry + flow)
## ```
##
## See docs/stalkleheads-design.md §3.5 and §3.10. There is no convergence term
## and no hidden noise term, and §2.2 is why: either one is an arbitrage. Pure
## rules, no state, no randomness.


## Share of last year's event carry still in the price this year.
const EVENT_DECAY: float = 0.50

## Share of last year's flow still pushing this year.
const FLOW_PERSISTENCE: float = 0.70

## Price points per percent of shares outstanding traded, net.
const FLOW_GAIN: float = 0.55

## Flow is clamped to this fraction of fair value, either way. **Asserted as a
## constant in a test**: §2.4 measured that at 0.18 the leading strategy wins
## 61.3% of matches, against 23.2% here.
const FLOW_LIMIT_FRACTION: float = 0.05

## A company splits when its price is above this. The mode's own threshold,
## not the base game's 150 (§3.6).
const SPLIT_ABOVE: int = 300


static func carry_after(previous_event_carry: float, event_delta: int) -> float:
	return previous_event_carry * EVENT_DECAY + float(event_delta)


## The flow clamp for a fair value. Taken from its magnitude, so the bound is
## never inverted for a company whose fair value has gone negative (D132).
static func flow_limit(fair_value: float) -> float:
	return absf(fair_value) * FLOW_LIMIT_FRACTION


## This year's flow from last year's and the net shares traded last year. NPC and
## player shares count identically: the caller sums them before passing them in.
static func flow_after(
	previous_flow: float,
	net_shares_traded: int,
	shares_outstanding: int,
	fair_value: float,
) -> float:
	var pushed: float = previous_flow * FLOW_PERSISTENCE
	if shares_outstanding > 0:
		pushed += float(net_shares_traded) / float(shares_outstanding) * 100.0 * FLOW_GAIN
	var limit: float = flow_limit(fair_value)
	return clampf(pushed, -limit, limit)


## The posted price.
##
## **This is one of the mode's two truncations** (§3.7), where a ratio becomes
## money: `int()` toward zero, matching GDScript's `int / int` everywhere else.
static func price_of(fair_value: float, event_carry: float, flow: float) -> int:
	return int(fair_value + event_carry + flow)


## The price after a split: halved, rounding **up**, as the base game rounds
## (decisions.md D22). Only the threshold is this mode's own.
static func split_price(price: int) -> int:
	return price / 2 + price % 2
