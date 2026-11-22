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


func ledger_for(company_id: StringName) -> PriceLedger:
	return ledgers.get(company_id, null)
