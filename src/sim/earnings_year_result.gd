class_name EarningsYearResult
extends YearResult
## Everything one StalkleHeads year advance did: the base game's `YearResult`,
## plus what only this mode has - why each price moved, what the market and its
## industries did, and what every row paid.
##
## A subclass rather than new fields on `YearResult`, so the base game's record
## is unchanged. Everything that reads a `YearResult` - the history, the
## settlement, the standings - reads this one the same way. See
## docs/stalkleheads-design.md §3.5 and §4.
##
## **`mood` here is a report, not a cause.** It is set at step 7, from the index
## move, after every price is already final (§3.1).


## Why each company's price moved, keyed by company id: the ledger of §3.5. Only
## companies alive at the start of the year have one. Each balances exactly:
## its lines sum to `price_after_event - price_before` (P1).
var ledgers: Dictionary[StringName, PriceLedger] = {}

## The index move, in percent: the mean pre-split move of the companies alive at
## the start of the year, a company that went bankrupt this year counting -100.
## Positive means BULL. Next year's sentiment is this, clamped to +/-20.
var index_move_percent: float = 0.0

## The sentiment this year's prices were valued on: **last** year's index move,
## clamped. Kept so a reader can see the one-year lag (§3.1).
var sentiment_used: float = 0.0

## The mood whose bag this year's event came from: last year's, BULL in year 1.
var event_bag: MarketMood.Value = MarketMood.Value.BULL

## Each industry's performance this year, in percent, keyed by industry id.
var industry_performance: Dictionary[StringName, float] = {}

## The dividend each row paid per share this year, keyed by stalk id, including
## the bond's coupon and the index's average. 0 for a bankrupt row.
var dividend_per_share: Dictionary[StringName, int] = {}

## **Every company as this year left it**, keyed by id: a `copy()` taken once
## splits and dividends are done, failed companies included. What the screens
## draw a company's history from - the Company tab's five years of earnings,
## the digest's "margin 12% -> 8%" (decisions.md D179).
##
## A readout, not an input: it is recorded at the end of the shared second half
## of the year, so a client replaying the year it was sent records exactly the
## host's, and nothing extra travels.
var companies_after: Dictionary[StringName, CompanyState] = {}

## My Mutuals and Me Inc.'s unrounded level as this year left it, after any
## split. What the Market tab's index chart is drawn from. A readout, like
## `companies_after`.
var index_level_after: float = 0.0


## What the NPC desk did after the year settled (§4 step 13). Its net shares are
## next year's flow input. Null only if the year never reached step 13.
var desk: NpcDeskYear = null

## The companies whose short interest was flagged when this year's event was
## chosen, most shorted first (§5.3). Read from the desk as last year left it.
var short_interest_flagged: Array[StringName] = []

## This year's squeeze roll, 1-100, drawn every year whether or not anything was
## flagged. A squeeze fires when it is at most the squeeze chance.
var squeeze_roll: int = 0

## True when a short squeeze fired this year, on the first flagged company.
## Since D213 it comes **as well as** the year's market news, not instead.
var squeezed: bool = false

## The squeeze's hold roll, 1-3, drawn every year after the squeeze roll: how
## many years the lift stays in the price if a squeeze fired (D213).
var squeeze_hold_roll: int = 0

## The squeeze's lift before the no-loss top-up, in coins: a share of the
## company's price that grows with its short interest
## (`ShortInterestRules.spike_for`). 0 when no squeeze fired. Sent, because a
## client's replay has no desk to read the short interest from.
var squeeze_spike: int = 0

## The year's market news (D209), or null when none was drawn. The base game's
## `event` is always null in this mode.
var market_news: MarketNews = null

## A readout: every company squeezed this year with its whole lift, and every
## company whose lift came off, with the coins it lost (negative).
var squeeze_moves: Dictionary[StringName, int] = {}

# ----------------------------------------------------------------- the inputs
# What the year drew, kept so the year can be sent as its inputs and replayed
# on a client (`EarningsYearResolver.replay_year`, decisions.md D176). The
# market news, the squeeze roll, hold roll and spike and the flagged list above
# are inputs too. Everything
# else in this result is derived from these and the market before the year.

## Each industry's swing this year, keyed by industry id.
var industry_rolls: Dictionary[StringName, int] = {}

## The regime each company alive at the start of the year landed in, by id.
var regimes: Dictionary[StringName, EarningsRegime.Value] = {}

## The growth roll each of those companies' earnings season was drawn with.
var growth_rolls: Dictionary[StringName, int] = {}

## The net shares traded since the last price was set, NPC and player alike,
## that this year's flow term read, by company id (§3.10).
var net_shares_priced: Dictionary[StringName, int] = {}


## **The year's news, once a screen has asked for it** (`NewsSelector.news_for`,
## decisions.md D200). A readout kept here so it is worked out once; null until
## then. Never sent: every peer works it out from the history it holds.
var news: YearNews = null


## The squeezed company, or empty when no squeeze fired.
func squeeze_target() -> StringName:
	if not squeezed or short_interest_flagged.is_empty():
		return &""
	return short_interest_flagged[0]


func ledger_for(company_id: StringName) -> PriceLedger:
	return ledgers.get(company_id, null)
