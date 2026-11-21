class_name ValuationRules
extends RefCounted
## What the market pays for a company's earnings in StalkleHeads mode: the
## multiple, and fair value. See docs/stalkleheads-design.md §3.4 and §3.5.
##
## ```
## multiple   = clamp(12.5 + sentiment * 0.02 + industry_standing + regime_premium, 4, 30)
## fair_value = clamp(earnings_per_share * multiple, -40, 1200)
## ```
##
## Pure rules, no state, no randomness. Only `+ - * /` and clamps, as §3.7 asks
## of the price path.


## The base multiple. BERRY BONDS yields 3%; 12.5x is an earnings yield of 8%,
## five points of compensation for owning a company instead of the bond (§3.4).
const BASE_MULTIPLE: float = 12.5

## Turns of multiple per point of sentiment (last year's market move).
const SENTIMENT_GAIN: float = 0.02

## Sentiment is last year's index move, clamped to this either way, in percent.
const SENTIMENT_LIMIT: float = 20.0

const MIN_MULTIPLE: float = 4.0
const MAX_MULTIPLE: float = 30.0

const MIN_FAIR_VALUE: float = -40.0
const MAX_FAIR_VALUE: float = 1200.0


static func clamp_sentiment(sentiment: float) -> float:
	return clampf(sentiment, -SENTIMENT_LIMIT, SENTIMENT_LIMIT)


## The multiple before its clamp. Sentiment is clamped first, as §3.4 states it.
static func unclamped_multiple(
	sentiment: float,
	industry_standing: float,
	regime: EarningsRegime.Value,
) -> float:
	return (
		BASE_MULTIPLE
		+ clamp_sentiment(sentiment) * SENTIMENT_GAIN
		+ industry_standing
		+ RegimeRules.PREMIUM[regime]
	)


static func multiple(
	sentiment: float,
	industry_standing: float,
	regime: EarningsRegime.Value,
) -> float:
	return clampf(
		unclamped_multiple(sentiment, industry_standing, regime), MIN_MULTIPLE, MAX_MULTIPLE
	)


static func unclamped_fair_value(earnings_per_share: float, valuation_multiple: float) -> float:
	return earnings_per_share * valuation_multiple


static func fair_value(earnings_per_share: float, valuation_multiple: float) -> float:
	return clampf(
		unclamped_fair_value(earnings_per_share, valuation_multiple),
		MIN_FAIR_VALUE,
		MAX_FAIR_VALUE,
	)
