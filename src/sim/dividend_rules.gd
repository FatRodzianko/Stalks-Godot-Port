class_name DividendRules
extends RefCounted
## Dividends in StalkleHeads mode: paid out of earnings, by each company's own
## policy, scaled by its regime - and the cost of paying, which is slower growth.
## See docs/stalkleheads-design.md §3.10a.
##
## Pure rules, no state, no randomness.


## The neutral policy. A company paying this has a retention factor of exactly 1.
const NEUTRAL_POLICY_PERCENT: int = 35


## The share of earnings paid out this year: policy, scaled by regime.
static func payout_ratio(payout_policy_percent: int, regime: EarningsRegime.Value) -> float:
	return float(payout_policy_percent) / 100.0 * RegimeRules.PAYOUT_SCALE[regime]


## The dividend per share, as money.
##
## **This is one of the mode's two truncations** (§3.7), where a ratio becomes
## money: `int()` toward zero, so a fraction of a coin is never paid. Negative
## earnings pay nothing rather than charging the holder.
static func dividend_per_share(
	earnings_per_share: float,
	payout_policy_percent: int,
	regime: EarningsRegime.Value,
) -> int:
	var amount: int = int(earnings_per_share * payout_ratio(payout_policy_percent, regime))
	return maxi(0, amount)


## How much of its regime's revenue growth a company keeps, given what it pays
## out: `1 + (35 - policy) / 100`. Policy 0 keeps x1.35, 35 keeps x1.00, 80
## keeps x0.55.
static func retention_factor(payout_policy_percent: int) -> float:
	return 1.0 + float(NEUTRAL_POLICY_PERCENT - payout_policy_percent) / 100.0


## Applies the retention factor to a growth figure, **positive growth only**: a
## high payer in DECLINE does not shrink more slowly for having paid out.
static func retained_growth(growth_percent: float, payout_policy_percent: int) -> float:
	if growth_percent <= 0.0:
		return growth_percent
	return growth_percent * retention_factor(payout_policy_percent)
