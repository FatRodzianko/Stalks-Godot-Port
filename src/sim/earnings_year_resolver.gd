class_name EarningsYearResolver
extends RefCounted
## Runs one StalkleHeads year advance: prices from earnings, industries and the
## market's own momentum, then the same back half as the base game.
##
## The base game's `YearResolver` rolls a mood first and moves prices from it.
## This mode reverses that: prices come from the price identity of
## docs/stalkleheads-design.md §3.5, and the mood is *derived* afterwards from
## what the market did. The order is §4's, steps 1-10:
##
##   1. Industry year       each industry rolls, leaning on last year's sentiment
##   2. Earnings season     each living company's regime, revenue and margin move
##   3. Valuation           inside `CompanyState.reprice`, from last year's sentiment
##   4. The event           drawn from **last year's** mood bag (bull in year 1)
##   5. Prices              the identity, once, with the event and last year's flow
##   6. The index           My Mutuals and Me Inc., from pre-split moves
##   7. The mood            reported from the index move; next year's sentiment set
##   8. Bankruptcy          one pass, not the base game's two
##   9. Splits              above 300, exactly once, after the event
##  10. Dividends           from earnings, on post-split share counts
##
## then `YearSettlement` runs loans, net worth, standings and game end, exactly
## as the base game does (§4 steps 11, 12, 15), and then:
##
##  13. The NPC desk     trades on the settled, published state; its net shares
##                       are recorded as next year's flow input (§5)
##
## Step 13 comes after the settlement, so the desk can never move the year it
## traded in, only the next, and what a player sees of the desk's positions is
## a record of decisions made on information the player also has (§4).
##
## Steps 3 and 5 are one call because `reprice` does both. That is still §4's
## order: valuation draws nothing, so drawing the event before the call is the
## same as drawing it between the two halves.
##
## **Two orderings must hold, the same two the base game holds:** splits are
## checked once, after the event; dividends are paid after splits.
##
## **One circularity must never come back (§4).** Nothing before step 7 may read
## this year's mood or this year's index move. Multiples read last year's
## sentiment; the event bag is last year's mood. If a future change wants this
## year's mood before prices exist, the design is broken, not the code.
##
## This is a separate pipeline rather than hooks in `YearResolver`, so neither
## asks which mode it is in (§10.2, decisions.md D152).


var _event_pool: EventPool

## The short-squeeze template (`ContentLibrary.short_squeeze`), or null for no
## squeezes at all. The squeeze roll is drawn either way.
var _short_squeeze: SpecialEventDefinition


func _init(event_pool: EventPool, short_squeeze: SpecialEventDefinition = null) -> void:
	_event_pool = event_pool
	_short_squeeze = short_squeeze


## Advances `state` by one year and returns what happened. `state.market` must
## be set (see `EarningsMarket.new_game_state`). All randomness comes from
## `rng`, in a fixed order: six industry rolls in id order, two draws per
## living company in id order, the squeeze roll, the event pool's draws (when no
## squeeze fired), then two draws per NPC trader in id order.
func advance_year(state: GameState, rng: RandomNumberGenerator) -> EarningsYearResult:
	var market: EarningsMarket = state.market
	var result: EarningsYearResult = EarningsYearResult.new()

	state.year += 1
	result.year = state.year
	result.sentiment_used = market.sentiment
	result.event_bag = market.last_mood

	for row: StalkState in state.stalks:
		row.did_split = false
		row.last_yearly_change = 0

	var changes: Dictionary[StringName, StalkYearChange] = {}
	for row: StalkState in state.stalks:
		var change: StalkYearChange = StalkYearChange.new()
		change.stalk_id = row.id
		change.price_before = row.price
		change.price_after = row.price
		changes[row.id] = change
		result.stalk_changes.append(change)

	var alive: Array[CompanyState] = _living(state)
	var before: Dictionary[StringName, CompanyState] = {}
	for company: CompanyState in alive:
		before[company.id] = company.copy()

	# 1. Industry year, leaning on last year's sentiment.
	IndustryState.advance_all(market.industries, market.sentiment, rng)
	for industry: IndustryState in market.industries:
		result.industry_performance[industry.id] = industry.performance

	# 2. Earnings season.
	for company: CompanyState in alive:
		advance_company_earnings(market, company, state.settings.max_years, rng)

	# 4. The event, so it is an input to the price rather than a correction to
	#    it. A short squeeze when a company's short interest is flagged and the
	#    roll comes up (§5.3); otherwise from last year's mood bag, where a target
	#    already bankrupt is skipped and left in the bag (EventPool, D24). The
	#    squeeze roll is drawn every year, flagged or not.
	result.squeeze_roll = rng.randi_range(1, 100)
	result.short_interest_flagged = market.desk.flagged_companies(state)
	var any_flagged: bool = not result.short_interest_flagged.is_empty()
	if _short_squeeze != null and result.squeeze_roll <= squeeze_chance_percent(any_flagged):
		var squeezed_id: StringName = result.short_interest_flagged[0]
		result.event = ShortInterestRules.squeeze_event(
			_short_squeeze, squeezed_id, state.stalk_by_id(squeezed_id).definition.display_name
		)
		result.squeezed = true
	else:
		result.event = _event_pool.draw(market.last_mood, state, rng)
	var event_target: StringName = &""
	if result.event != null:
		event_target = result.event.target_stalk_id

	# 3 and 5. Valuation, then the price identity, once.
	for company: CompanyState in alive:
		var event_delta: int = 0
		if company.id == event_target:
			event_delta = result.event.price_change
		var traded: int = market.net_shares_traded.get(company.id, 0)
		company.reprice(market.sentiment, valuation_performance(market, company), event_delta, traded)

		var ledger: PriceLedger = PriceLedger.between(before[company.id], company)
		result.ledgers[company.id] = ledger
		var row: StalkState = state.stalk_by_id(company.id)
		var moved: int = company.price - before[company.id].price
		# Yearly Change includes the event in this mode (§14 q7); the ledger is
		# what breaks it down.
		row.last_yearly_change = moved
		row.price = company.price
		changes[company.id].event_delta = ledger.this_years_event
		changes[company.id].base_delta = moved - ledger.this_years_event
		changes[company.id].price_after = company.price
	market.net_shares_traded = {}

	# 6. The index, from pre-split moves.
	result.index_move_percent = index_move_percent(before, alive)
	_move_index(state, result.index_move_percent, changes)

	# 7. The mood is what the index did. Next year's sentiment is set here, and
	#    nothing above this line may read either (§4).
	result.mood = mood_for(result.index_move_percent)
	market.last_mood = result.mood
	market.sentiment = ValuationRules.clamp_sentiment(result.index_move_percent)

	# 8. Bankruptcy, one pass.
	_apply_bankruptcies(state, alive, changes)

	# 9. Splits, after the event, exactly once.
	_apply_splits(state, alive, changes)

	# 10. Dividends, on post-split share counts.
	_pay_dividends(state, result)

	YearSettlement.settle(state, result)

	# 13. The NPC desk, on the settled state. Its net trading is next year's flow.
	result.desk = market.desk.act(state, rng)
	for stalk_id: StringName in result.desk.net_shares:
		market.record_trade(stalk_id, result.desk.net_shares[stalk_id])
	return result


## §4 step 2 for one company. **A seam for the balance tool only**, which
## overrides it to sweep the transition matrix (tools/balance/levers.gd,
## decisions.md D150); nothing in the game overrides it. Two draws.
func advance_company_earnings(
	market: EarningsMarket,
	company: CompanyState,
	match_years: int,
	rng: RandomNumberGenerator,
) -> void:
	company.advance_earnings(market.performance_of(company), match_years, rng)


## §5.3: the chance, in percent, of a squeeze this year. **A seam for the
## balance tool only**, which overrides it to sweep the chance (decisions.md
## D166); nothing in the game overrides it.
func squeeze_chance_percent(any_flagged: bool) -> int:
	return ShortInterestRules.squeeze_chance_percent(any_flagged)


## The industry performance a company is valued on at step 3: its industry's.
## **A seam for the balance tool only**, which overrides it to sweep the regime
## premium; nothing in the game overrides it.
func valuation_performance(market: EarningsMarket, company: CompanyState) -> float:
	return market.performance_of(company)


## §3.9: the mean percentage move of the companies alive at the start of the
## year, measured before splits. One that went bankrupt this year counts -100;
## one that was already bankrupt is not a constituent any more. 0 when there
## are none. `before` holds each company's state at the start of the year.
static func index_move_percent(
	before: Dictionary[StringName, CompanyState],
	alive: Array[CompanyState],
) -> float:
	var total: float = 0.0
	var counted: int = 0
	for company: CompanyState in alive:
		var was: int = before[company.id].price
		if was <= 0:
			continue
		counted += 1
		if company.price <= TradeRules.BANKRUPT_AT_OR_BELOW:
			total -= 100.0
		else:
			total += float(company.price - was) * 100.0 / float(was)
	if counted == 0:
		return 0.0
	return total / float(counted)


## §3.1: BULL exactly when the index rose. A flat year is BEAR.
static func mood_for(index_move: float) -> MarketMood.Value:
	if index_move > 0.0:
		return MarketMood.Value.BULL
	return MarketMood.Value.BEAR


## Companies whose row is not bankrupt, in id order.
func _living(state: GameState) -> Array[CompanyState]:
	var alive: Array[CompanyState] = []
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row != null and not row.is_bankrupt:
			alive.append(company)
	return alive


## `index_level *= (100 + move) / 100`, and the row posts `int()` of it.
func _move_index(
	state: GameState,
	move: float,
	changes: Dictionary[StringName, StalkYearChange],
) -> void:
	var row: StalkState = state.stalk_by_id(EarningsMarket.INDEX_ID)
	if row == null or row.is_bankrupt:
		return
	var market: EarningsMarket = state.market
	market.index_level = market.index_level * (100.0 + move) / 100.0
	var was: int = row.price
	row.price = int(market.index_level)
	row.last_yearly_change = row.price - was
	changes[row.id].base_delta = row.last_yearly_change
	changes[row.id].price_after = row.price


## Any company at or below 0 fails, and so does the index if it reaches 0, which
## it can only do when every constituent has. Every holder's shares are wiped
## out, with no compensation - the base game's rule.
func _apply_bankruptcies(
	state: GameState,
	alive: Array[CompanyState],
	changes: Dictionary[StringName, StalkYearChange],
) -> void:
	var failing: Array[StalkState] = []
	for company: CompanyState in alive:
		if company.price <= TradeRules.BANKRUPT_AT_OR_BELOW:
			company.price = 0
			failing.append(state.stalk_by_id(company.id))
	var index_row: StalkState = state.stalk_by_id(EarningsMarket.INDEX_ID)
	if index_row != null and not index_row.is_bankrupt:
		if index_row.price <= TradeRules.BANKRUPT_AT_OR_BELOW:
			state.market.index_level = 0.0
			failing.append(index_row)

	for row: StalkState in failing:
		row.is_bankrupt = true
		row.price = 0
		changes[row.id].went_bankrupt = true
		changes[row.id].price_after = 0
		for player: PlayerState in state.players:
			player.set_shares(row.id, 0)
		state.market.desk.wipe_out(row.id)


## Above 300 a company halves its price (rounding up), doubles its shares
## outstanding, and halves its fair value, event carry and flow, which is
## value-neutral (§3.6). Every holder's shares double. The index splits the
## same way, halving its level.
func _apply_splits(
	state: GameState,
	alive: Array[CompanyState],
	changes: Dictionary[StringName, StalkYearChange],
) -> void:
	var splitting: Array[StalkState] = []
	for company: CompanyState in alive:
		var row: StalkState = state.stalk_by_id(company.id)
		if row.is_bankrupt:
			continue
		if company.split_if_above():
			row.price = company.price
			splitting.append(row)

	var index_row: StalkState = state.stalk_by_id(EarningsMarket.INDEX_ID)
	if index_row != null and not index_row.is_bankrupt:
		if index_row.price > PriceIdentity.SPLIT_ABOVE:
			index_row.price = PriceIdentity.split_price(index_row.price)
			state.market.index_level /= 2.0
			splitting.append(index_row)

	for row: StalkState in splitting:
		row.did_split = true
		changes[row.id].did_split = true
		changes[row.id].price_after = row.price
		for player: PlayerState in state.players:
			var held: int = player.shares_of(row.id)
			if held > 0:
				player.set_shares(row.id, held * 2)
		state.market.desk.split(row.id)


## Every row's dividend per share, then every player paid on what they hold.
##
## - A company pays `int(earnings_per_share * payout_ratio)` (§3.10a).
## - The bond pays its coupon, the same in every year (§3.8).
## - The index pays the average of its living constituents' dividends, truncated
##   (§14 q4, decisions.md D157).
func _pay_dividends(state: GameState, result: EarningsYearResult) -> void:
	var market: EarningsMarket = state.market
	var company_total: int = 0
	var company_count: int = 0
	for company: CompanyState in market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		var paid: int = 0
		if row.has_value():
			paid = company.dividend_per_share()
			company_total += paid
			company_count += 1
		result.dividend_per_share[company.id] = paid

	for row: StalkState in state.stalks:
		if market.company_by_id(row.id) != null:
			continue
		var paid: int = 0
		if row.has_value() and row.is_price_static():
			paid = EarningsMarket.bond_coupon(row.definition)
		elif row.has_value() and company_count > 0:
			@warning_ignore("integer_division")
			paid = company_total / company_count
		result.dividend_per_share[row.id] = paid

	for player: PlayerState in state.players:
		var paid: int = 0
		for row: StalkState in state.stalks:
			if not row.has_value():
				continue
			var held: int = player.shares_of(row.id)
			if held > 0:
				paid += held * result.dividend_per_share[row.id]
		player.cash += paid
		result.dividends[player.id] = paid
	market.desk.settle_dividends(result.dividend_per_share)
