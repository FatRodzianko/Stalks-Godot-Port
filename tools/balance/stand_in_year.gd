extends RefCounted
## STAND-IN, for the balance tool only. **Phase S3 replaces this file.**
##
## A minimal StalkleHeads market and its year, strung together from the real S1
## pieces in `src/sim/` in the order of docs/stalkleheads-design.md §4:
##
## 1. industry year          `IndustryState.advance_all`
## 2. earnings season        `CompanyState.advance_earnings`
## 3. valuation              inside `CompanyState.reprice`
## 4. the event              drawn here (see below)
## 5. prices                 `CompanyState.reprice`
## 6. index move, and the derived mood and next year's sentiment
## 7. bankruptcy             price at or below 0
## 8. splits                 `CompanyState.split_if_above`
## 9. dividends              `CompanyState.dividend_per_share`
##
## Steps 3 and 5 are one call because `reprice` does both. That is still §4's
## order: valuation draws nothing, so drawing the event before the call is the
## same as drawing it between the two halves.
##
## **What is stand-in here, and what S3 must do properly instead:**
##
## - **The event** is the balance probe's shape, not `EventPool`: one a year, on a
##   living company picked uniformly, `+5..+20` after a bull year (and in year 1)
##   or `-5..-25` after a bear one. No bags, no industry or market effects.
## - **The index** is this file's arithmetic (§3.9): the mean of every living
##   company's pre-split percentage move, a bankrupt one counting -100. There is
##   no Mutuals instrument to hold.
## - **Bankruptcy** is a flag in this file. `CompanyState` has none yet.
##
## This file computes no rule of its own beyond those three. Everything that
## moves a price is a call into `src/sim/`. It lives in `tools/` and not in
## `src/` on purpose (decisions.md D144): nothing in the game may call it.


## Balance overrides for a sweep; see levers.gd.
const Levers := preload("res://tools/balance/levers.gd")

## The stand-in event's magnitudes (Appendix A's probe).
const BULL_EVENT: Vector2i = Vector2i(5, 20)
const BEAR_EVENT: Vector2i = Vector2i(5, 25)


## What one year did, for the caller to apply to its players' books and count.
class Outcome:
	extends RefCounted
	var split_ids: Array[StringName] = []
	var bankrupt_ids: Array[StringName] = []
	## |price after splits - price before|, one per company alive at the year's
	## start. Counts a split's halving as movement, as the probe's figure does.
	var abs_moves: Array[int] = []
	var index_move_percent: float = 0.0
	var mood: MarketMood.Value = MarketMood.Value.BULL


var match_years: int = 10

## Every company, sorted by id, living or not.
var companies: Array[CompanyState] = []

var industries: Array[IndustryState] = []

var bankrupt: Dictionary[StringName, bool] = {}

## This year's price move before splits, in coins: the board's Yearly Change.
var last_delta: Dictionary[StringName, int] = {}

## Each company's profit before the latest earnings season. Absent until the
## first season has run, so "growth" has no value in year 1.
var previous_profit: Dictionary[StringName, float] = {}

## The dividend per share paid in the latest year. 0 before year 1.
var dividend: Dictionary[StringName, int] = {}

## Last year's index move, clamped to +/-20. 0 before year 1.
var sentiment: float = 0.0

## Last year's derived mood. BULL before year 1, so year 1 draws from the bull
## bag (§10.2).
var mood: MarketMood.Value = MarketMood.Value.BULL

## Overrides for a sweep (levers.gd). All at the published values by default.
var levers: Levers

var _industry_by_id: Dictionary[StringName, IndustryState] = {}


func _init(library: ContentLibrary, years: int, overrides: Levers = null) -> void:
	match_years = years
	levers = overrides
	if levers == null:
		levers = Levers.new()
	for definition: IndustryDefinition in library.industries:
		var industry: IndustryState = IndustryState.new(definition)
		industries.append(industry)
		_industry_by_id[definition.id] = industry
	for profile: CompanyProfile in library.companies:
		var company: CompanyState = CompanyState.new(profile)
		companies.append(company)
		bankrupt[company.id] = false
		last_delta[company.id] = 0
		dividend[company.id] = 0


## Companies not bankrupt, in id order.
func living() -> Array[CompanyState]:
	var alive: Array[CompanyState] = []
	for company: CompanyState in companies:
		if not bankrupt[company.id]:
			alive.append(company)
	return alive


## One year, §4 steps 1-9. `net_shares` is last year's net buying per company
## id, NPC and player alike (empty without a desk, so flow stays 0).
func resolve_year(net_shares: Dictionary[StringName, int], rng: RandomNumberGenerator) -> Outcome:
	var outcome: Outcome = Outcome.new()
	var alive: Array[CompanyState] = living()

	# 1. Industry year, leaning on last year's sentiment.
	IndustryState.advance_all(industries, sentiment, rng)

	# 2. Earnings season.
	for company: CompanyState in alive:
		previous_profit[company.id] = company.profit
		if levers.changes_regimes():
			_advance_earnings_with_levers(company, rng)
		else:
			company.advance_earnings(_performance_of(company), match_years, rng)

	# 4. The event (stand-in shape), drawn before prices so it is a cause.
	var target_id: StringName = &""
	var event_delta: int = 0
	if not alive.is_empty():
		target_id = alive[rng.randi_range(0, alive.size() - 1)].id
		if mood == MarketMood.Value.BULL:
			event_delta = rng.randi_range(BULL_EVENT.x, BULL_EVENT.y)
		else:
			event_delta = -rng.randi_range(BEAR_EVENT.x, BEAR_EVENT.y)

	# 3 and 5. Valuation, then the price identity.
	var before: Dictionary[StringName, int] = {}
	for company: CompanyState in alive:
		before[company.id] = company.price
		var delta: int = 0
		if company.id == target_id:
			delta = event_delta
		var traded: int = net_shares.get(company.id, 0)
		var valued_at: float = levers.valuation_performance(company.regime, _performance_of(company))
		company.reprice(sentiment, valued_at, delta, traded)
		last_delta[company.id] = company.price - before[company.id]

	# 6. The index from pre-split moves; the mood is what it did. Nothing above
	# this line may read this year's mood (§4).
	var total: float = 0.0
	var counted: int = 0
	for company: CompanyState in alive:
		var was: int = before[company.id]
		if was <= 0:
			continue
		counted += 1
		if company.price <= 0:
			total -= 100.0
		else:
			total += float(company.price - was) * 100.0 / float(was)
	if counted > 0:
		outcome.index_move_percent = total / float(counted)
	if outcome.index_move_percent > 0.0:
		mood = MarketMood.Value.BULL
	else:
		mood = MarketMood.Value.BEAR
	outcome.mood = mood
	sentiment = ValuationRules.clamp_sentiment(outcome.index_move_percent)

	# 7. Bankruptcy, one pass.
	for company: CompanyState in alive:
		if company.price <= 0:
			bankrupt[company.id] = true
			company.price = 0
			outcome.bankrupt_ids.append(company.id)

	# 8. Splits, after the event, exactly once.
	for company: CompanyState in alive:
		if bankrupt[company.id]:
			continue
		if company.split_if_above():
			outcome.split_ids.append(company.id)

	# 9. Dividends, on post-split share counts.
	for company: CompanyState in companies:
		if bankrupt[company.id]:
			dividend[company.id] = 0
		else:
			dividend[company.id] = company.dividend_per_share()

	for company: CompanyState in alive:
		outcome.abs_moves.append(absi(company.price - before[company.id]))
	return outcome


func company_by_id(company_id: StringName) -> CompanyState:
	for company: CompanyState in companies:
		if company.id == company_id:
			return company
	return null


func _performance_of(company: CompanyState) -> float:
	return _industry_by_id[company.profile.industry].performance


## `CompanyState.advance_earnings` with the regime roll taken from `levers`.
## Same draws in the same order: the regime roll, then the growth roll. The
## accounts move by the real `move_accounts`.
func _advance_earnings_with_levers(company: CompanyState, rng: RandomNumberGenerator) -> void:
	var was: EarningsRegime.Value = company.regime
	var roll: int = rng.randi_range(1, 100)
	company.regime = levers.regime_for_roll(was, roll, company.profile.quality, company.years_in_regime)
	if company.regime == was:
		company.years_in_regime += 1
	else:
		company.years_in_regime = 0
	var band: Vector2i = RegimeRules.GROWTH_BAND[company.regime]
	company.move_accounts(rng.randi_range(band.x, band.y), _performance_of(company), match_years)
