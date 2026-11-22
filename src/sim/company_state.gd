class_name CompanyState
extends RefCounted
## The live fundamentals of one company during a StalkleHeads match: its
## accounts, its regime, its valuation and the three terms of its price.
##
## Pairs with an immutable `CompanyProfile`. Pure data and rules - no nodes, no
## signals, no autoloads; every draw comes from the RNG passed in.
##
## **Phase S1 delivers the pieces, not the year.** A year is three calls, in this
## order, and S3's `EarningsYearResolver` is what will make them (§4 steps 2, 3,
## 5 and 9 of docs/stalkleheads-design.md):
##
## 1. `advance_earnings` - the regime rolls, revenue and margin move. Two draws.
## 2. `reprice` - the multiple, fair value, event carry, flow and the price.
## 3. `split_if_above` - halves the price and doubles shares above 300.
##
## Take a `copy()` before step 1 and `PriceLedger.between(copy, self)` after step
## 2 says why the price moved, to the coin.


var profile: CompanyProfile

# ------------------------------------------------------------- the accounts
# Floats, like every ratio in this mode: they are accounting figures that are
# never paid to anybody, and keeping them float is what keeps the mode to its
# two truncations (decisions.md D130).

var revenue: float = 0.0

## Profit as a percentage of revenue.
var margin_percent: float = 0.0

var profit: float = 0.0

## Profit before the latest earnings season: what `profit` was when
## `move_accounts` last ran. Equal to `profit` at year 0. What the GROWTH
## traders read growth from (`profit_growth_percent`). Profit does not change
## on a split, so its growth is the split-adjusted growth of earnings per share
## (decisions.md D146).
var profit_before_season: float = 0.0

var shares_outstanding: int = 0

## This year's total revenue growth, in percent: the regime's own (damped, then
## retained) plus the industry's share. A readout for the Company tab.
var revenue_growth_percent: float = 0.0

## The growth roll the latest earnings season was drawn with, a whole percent
## from the regime's band. 0 before the first season. **An input, not a
## readout**: it is what the year record sends so a client can replay the
## season (decisions.md D176).
var growth_roll: int = 0

# ---------------------------------------------------------------- the regime

var regime: EarningsRegime.Value = EarningsRegime.Value.STEADY

## Consecutive years spent in `regime` beyond the year it was entered. 0 in a
## regime's first year. Drives ageing and recovery (RegimeRules, D131).
var years_in_regime: int = 0

# ------------------------------------------------------------- the valuation
# The three inputs are kept as well as the result, because the ledger needs
# last year's value of each to say what moved.

## Last year's market move, as used this year, already clamped to +/-20.
var sentiment: float = 0.0

## Its industry's standing this year, in turns of multiple.
var industry_standing: float = 0.0

## Its regime's premium this year, in turns of multiple.
var regime_premium: float = 0.0

var multiple: float = ValuationRules.BASE_MULTIPLE

var fair_value: float = 0.0

## True when this year's multiple or fair value hit its clamp. The ledger reports
## the clamp as its own line only then (D133).
var valuation_clamped: bool = false

# ----------------------------------------------------------------- the price

## The undecayed remainder of announced events.
var event_carry: float = 0.0

## This year's event delta alone, as added to `event_carry` by `reprice`.
var event_delta: int = 0

## What traders did last year, persistent and clamped.
var flow: float = 0.0

var price: int = 0

## Set by `split_if_above` in the year a split happened.
var did_split: bool = false


var id: StringName:
	get:
		return profile.id if profile != null else &""


## Year-0 state from a profile: STEADY, at the base multiple, no events, no flow,
## so the opening price is `EPS x 12.5` (D129).
func _init(company_profile: CompanyProfile) -> void:
	profile = company_profile
	if profile == null:
		return
	shares_outstanding = profile.shares_outstanding
	margin_percent = profile.starting_margin_percent
	profit = profile.starting_earnings_per_share * float(shares_outstanding)
	if margin_percent != 0.0:
		revenue = profit * 100.0 / margin_percent
	profit_before_season = profit
	multiple = ValuationRules.BASE_MULTIPLE
	fair_value = ValuationRules.fair_value(profile.starting_earnings_per_share, multiple)
	price = PriceIdentity.price_of(fair_value, event_carry, flow)


## Earnings per share. Derived, never stored, so a split cannot leave it stale.
func earnings_per_share() -> float:
	if shares_outstanding <= 0:
		return 0.0
	return profit / float(shares_outstanding)


## The latest season's profit growth in percent, or NAN when there is no
## positive base to measure it from (a company that was already losing money).
func profit_growth_percent() -> float:
	if profit_before_season <= 0.0:
		return NAN
	return (profit - profit_before_season) * 100.0 / profit_before_season


## §4 step 2, earnings season. The regime rolls, then revenue moves by the new
## regime's band and its industry, and margin moves a third of the way to the
## new regime's target. **Exactly two draws**, always: the regime roll, then the
## growth roll.
##
## `industry_performance` is this year's figure for its industry, in percent.
## `match_years` is the match length, for the long-match damping ladder.
func advance_earnings(
	industry_performance: float,
	match_years: int,
	rng: RandomNumberGenerator,
) -> void:
	var next: EarningsRegime.Value = RegimeRules.roll_next(
		regime, profile.quality, years_in_regime, rng
	)
	var band: Vector2i = RegimeRules.GROWTH_BAND[next]
	replay_earnings(next, rng.randi_range(band.x, band.y), industry_performance, match_years)


## Earnings season from its two draws already made: the regime it lands in and
## the growth roll. Draws nothing. `advance_earnings` is this plus the draws,
## and a client replaying a year it was sent calls this with the host's draws
## (`EarningsYearResolver.replay_year`, decisions.md D176), so both sides run
## the same arithmetic.
func replay_earnings(
	next_regime: EarningsRegime.Value,
	roll: int,
	industry_performance: float,
	match_years: int,
) -> void:
	enter_regime(next_regime)
	move_accounts(roll, industry_performance, match_years)


## Moves to `next_regime`, ageing the regime instead if it is the same one.
func enter_regime(next_regime: EarningsRegime.Value) -> void:
	if next_regime == regime:
		years_in_regime += 1
	else:
		years_in_regime = 0
	regime = next_regime


## The accounts half of earnings season, for a growth roll already drawn from
## the current regime's band. Draws nothing; split out so the arithmetic can be
## tested without steering the RNG.
##
## The regime's own growth is damped for long matches, then the retention factor
## applies if it is positive, then the industry's share is added:
## `own = roll * damping; own *= retention if own > 0; growth = own + performance * beta / 100`.
func move_accounts(roll: int, industry_performance: float, match_years: int) -> void:
	growth_roll = roll
	profit_before_season = profit
	var own: float = float(roll) * RegimeRules.growth_damping(match_years)
	own = DividendRules.retained_growth(own, profile.payout_policy_percent)
	var from_industry: float = industry_performance * float(profile.industry_beta_percent) / 100.0
	revenue_growth_percent = own + from_industry

	revenue = revenue * (100.0 + revenue_growth_percent) / 100.0
	margin_percent += (RegimeRules.MARGIN_TARGET[regime] - margin_percent) / RegimeRules.MARGIN_DIVISOR
	profit = revenue * margin_percent / 100.0


## §4 steps 3 and 5: valuation, then the price identity. Draws nothing.
##
## - `market_sentiment`: last year's index move, in percent (clamped here).
## - `industry_performance`: this year's figure for its industry.
## - `this_year_event_delta`: the event aimed at this company this year, or 0.
## - `net_shares_traded`: last year's net buying, NPC and player alike.
func reprice(
	market_sentiment: float,
	industry_performance: float,
	this_year_event_delta: int,
	net_shares_traded: int,
) -> void:
	sentiment = ValuationRules.clamp_sentiment(market_sentiment)
	industry_standing = IndustryState.standing_for(industry_performance)
	regime_premium = RegimeRules.PREMIUM[regime]

	var raw_multiple: float = ValuationRules.unclamped_multiple(sentiment, industry_standing, regime)
	multiple = ValuationRules.multiple(sentiment, industry_standing, regime)
	var eps: float = earnings_per_share()
	var raw_fair: float = ValuationRules.unclamped_fair_value(eps, multiple)
	fair_value = ValuationRules.fair_value(eps, multiple)
	valuation_clamped = raw_multiple != multiple or raw_fair != fair_value

	event_delta = this_year_event_delta
	event_carry = PriceIdentity.carry_after(event_carry, this_year_event_delta)
	flow = PriceIdentity.flow_after(flow, net_shares_traded, shares_outstanding, fair_value)
	price = PriceIdentity.price_of(fair_value, event_carry, flow)
	did_split = false


## §4 step 9. Above 300 the price halves (rounding up), shares outstanding
## double - which halves earnings per share and so fair value - and event carry
## and flow halve with it. Value-neutral: nothing a holder owns changes worth,
## once the caller doubles their shares too (S3).
##
## Rounding up means the posted price can sit one coin above
## `int(fair_value + event_carry + flow)` until the next `reprice` (D134).
func split_if_above() -> bool:
	if price <= PriceIdentity.SPLIT_ABOVE:
		return false
	price = PriceIdentity.split_price(price)
	shares_outstanding *= 2
	fair_value /= 2.0
	event_carry /= 2.0
	flow /= 2.0
	did_split = true
	return true


## This year's dividend per share, from earnings, policy and regime.
func dividend_per_share() -> int:
	return DividendRules.dividend_per_share(
		earnings_per_share(), profile.payout_policy_percent, regime
	)


## §4 step 8 for this company: it failed. Its price is 0 and it has no
## valuation any more, so the six valuation readouts are cleared. Its accounts,
## regime and price terms are kept as they were, as the record of what it was.
##
## **Why cleared rather than left.** Nothing reads a failed company's valuation,
## but a client rebuilding readouts from the inputs it was sent
## (`derive_readouts`) would value it on this year's market rather than on the
## one it failed in. Clearing it on both sides is what lets a client's copy equal
## the host's field for field (decisions.md D176).
func fail() -> void:
	price = 0
	sentiment = 0.0
	industry_standing = 0.0
	regime_premium = 0.0
	multiple = 0.0
	fair_value = 0.0
	valuation_clamped = false


## Rebuilds every readout of a company from the inputs the wire carries, as the
## host computed them in the latest year (docs/stalkleheads-design.md §9.1,
## decisions.md D176). **The mirror of `reprice`, `split_if_above` and `fail`**,
## and it must stay one: a change to any of them is a change here, and
## `test_wire.gd` compares the two field by field over whole matches.
##
## - Profit is `revenue x margin / 100`, the expression `move_accounts` ends on.
## - The valuation is `reprice`'s, from the sentiment the year was valued on
##   (`EarningsMarket.sentiment_used`) and this year's industry performance.
## - A company that split this year was valued on half its shares, and its fair
##   value was then halved.
## - A failed company has no valuation (`fail`).
##
## Only for a company that has had an earnings season. At year 0 a company is
## its profile's, exactly as `_init` builds it, and is never derived.
func derive_readouts(sentiment_valued_on: float, industry_performance: float, has_failed: bool) -> void:
	profit = revenue * margin_percent / 100.0
	if has_failed:
		fail()
		return
	sentiment = ValuationRules.clamp_sentiment(sentiment_valued_on)
	industry_standing = IndustryState.standing_for(industry_performance)
	regime_premium = RegimeRules.PREMIUM[regime]

	var raw_multiple: float = ValuationRules.unclamped_multiple(sentiment, industry_standing, regime)
	multiple = ValuationRules.multiple(sentiment, industry_standing, regime)
	var valued_on_shares: int = shares_outstanding
	if did_split:
		@warning_ignore("integer_division")
		valued_on_shares = shares_outstanding / 2
	var eps: float = 0.0
	if valued_on_shares > 0:
		eps = profit / float(valued_on_shares)
	var raw_fair: float = ValuationRules.unclamped_fair_value(eps, multiple)
	fair_value = ValuationRules.fair_value(eps, multiple)
	valuation_clamped = raw_multiple != multiple or raw_fair != fair_value
	if did_split:
		fair_value /= 2.0


## A detached copy, for the ledger's "before" and for tests. Shares the profile,
## which is immutable content.
func copy() -> CompanyState:
	var twin: CompanyState = CompanyState.new(null)
	twin.profile = profile
	twin.revenue = revenue
	twin.margin_percent = margin_percent
	twin.profit = profit
	twin.profit_before_season = profit_before_season
	twin.shares_outstanding = shares_outstanding
	twin.revenue_growth_percent = revenue_growth_percent
	twin.growth_roll = growth_roll
	twin.regime = regime
	twin.years_in_regime = years_in_regime
	twin.sentiment = sentiment
	twin.industry_standing = industry_standing
	twin.regime_premium = regime_premium
	twin.multiple = multiple
	twin.fair_value = fair_value
	twin.valuation_clamped = valuation_clamped
	twin.event_carry = event_carry
	twin.event_delta = event_delta
	twin.flow = flow
	twin.price = price
	twin.did_split = did_split
	return twin


func _to_string() -> String:
	return "CompanyState(%s @ %d, %s)" % [id, price, EarningsRegime.name_of(regime)]
