class_name EarningsYearResolver
extends YearPipeline
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
##   4. The event           the market news, drawn from **last year's** mood and
##                          index move (D209), and a short squeeze when one fires
##                          (D213); a squeeze that ran its course comes off
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
##  14. Next year drawn  next year's industry swings and every living company's
##                       regime and growth roll, kept on the market
##
## **Steps 1 and 2 do not draw (decisions.md D205).** Their draws were made a
## year early, at step 14 of the year before (or by `open_match` for year 1),
## and kept in `EarningsMarket.next_draws`, so that a whisper can foreshadow
## them (design §8.4). Nothing a player does reaches them, and nothing draws
## between the end of one year and the start of the next, so drawing them early
## takes the same place in the stream: a seed plays the same match as before.
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
## sentiment; the market news is chosen by last year's mood and move. If a future change wants this
## year's mood before prices exist, the design is broken, not the code.
##
## This is a separate pipeline rather than hooks in `YearResolver`, so neither
## asks which mode it is in (§10.2, decisions.md D152).
##
## **Two halves, so a client can replay a year (decisions.md D176).** Every draw
## a year makes before the desk is made first and written into the result: the
## industry rolls, each company's regime and growth roll, the squeeze rolls and
## lift, and the market news. Everything after that is arithmetic on those inputs, in
## `_settle_prices`. `advance_year` is the host's way in: draw, then settle.
## `replay_year` is the client's: take the draws the host sent, then settle with
## the same code. That is how "inputs travel, readouts are derived" (design
## §9.1) is kept honest - there is one implementation of the year, not two that
## are supposed to agree.


## The short-squeeze template (`ContentLibrary.short_squeeze`): its words, for
## the year's news. Null for no squeezes at all. The squeeze rolls are drawn
## either way.
var _short_squeeze: SpecialEventDefinition


func _init(short_squeeze: SpecialEventDefinition = null) -> void:
	_short_squeeze = short_squeeze


## Advances `state` by one year and returns what happened. `state.market` must
## be set (see `EarningsMarket.new_game_state`). All randomness comes from
## `rng`, in a fixed order: the squeeze roll, the hold roll, one draw for the
## market news when any can be drawn, two draws per NPC trader in id order,
## then next year's draws (`draw_ahead`) unless this was the last year. This
## year's industry and earnings draws were made the year before; a market
## nobody opened draws them first.
func advance_year(state: GameState, rng: RandomNumberGenerator) -> EarningsYearResult:
	var market: EarningsMarket = state.market
	var result: EarningsYearResult = EarningsYearResult.new()
	# What news has been shown before this year, for market news that requires
	# some (D210). Read before the year opens, while `next_draws` still holds
	# this year's draws for the last whisper round.
	var shown: Dictionary[StringName, bool] = {}
	if MarketNewsRules.any_requires(market.news):
		shown = NewsSelector.shown_through(state, state.year)
	if market.next_draws == null:
		# A market `open_match` never saw: a test, or the balance tool.
		market.next_draws = draw_ahead(state, rng)
	var draws: KeptDraws = market.next_draws
	market.next_draws = null
	var year: YearInProgress = _open_year(state, result)

	# 1. Industry year, from the swing kept last year, leaning on last year's
	#    sentiment.
	for industry: IndustryState in market.industries:
		industry.replay(draws.industry_rolls.get(industry.id, 0), market.sentiment)
	_record_industries(market, result)

	# 2. Earnings season, from the regimes and growth rolls kept last year.
	for company: CompanyState in year.alive:
		company.replay_earnings(
			draws.regimes.get(company.id, company.regime),
			draws.growth_rolls.get(company.id, 0),
			market.performance_of(company),
			state.settings.max_years,
		)
		result.regimes[company.id] = company.regime
		result.growth_rolls[company.id] = company.growth_roll

	# 4. The events, so they are inputs to the price rather than corrections to
	#    it. A short squeeze when a company's short interest is flagged and the
	#    roll comes up (§5.3, D213); its two rolls are drawn every year, flagged
	#    or not. Then, squeeze or no squeeze, the market news (D209).
	result.squeeze_roll = rng.randi_range(1, 100)
	result.squeeze_hold_roll = rng.randi_range(ShortInterestRules.HOLD_YEARS_MIN, ShortInterestRules.HOLD_YEARS_MAX)
	result.short_interest_flagged = market.desk.flagged_companies(state)
	var any_flagged: bool = not result.short_interest_flagged.is_empty()
	if _short_squeeze != null and result.squeeze_roll <= squeeze_chance_percent(any_flagged):
		result.squeezed = true
		var squeezed_id: StringName = result.short_interest_flagged[0]
		var squeezed: CompanyState = market.company_by_id(squeezed_id)
		var percent: float = ShortInterestRules.percent_of(
			market.desk.short_interest(squeezed_id), squeezed.shares_outstanding
		)
		result.squeeze_spike = squeeze_spike(squeezed.price, percent)
	result.market_news = MarketNewsRules.draw(state, shown, rng)

	# Last year's net buying, as this year's price reads it: the last input.
	for company: CompanyState in year.alive:
		result.net_shares_priced[company.id] = market.net_shares_traded.get(company.id, 0)

	_settle_prices(state, result, year)

	YearSettlement.settle(state, result)

	# 13. The NPC desk, on the settled state. Its net trading is next year's flow.
	result.desk = market.desk.act(state, rng)
	for stalk_id: StringName in result.desk.net_shares:
		market.record_trade(stalk_id, result.desk.net_shares[stalk_id])

	# 14. Next year's earnings, drawn now and kept, so a whisper can know them.
	#     The final year too: a match of N years settles once more into year
	#     N + 1, which moves every price, so its whispers are worth hearing
	#     (D219). The same place in the stream as drawing them at its start.
	if state.year <= state.settings.max_years:
		market.next_draws = draw_ahead(state, rng)
	return result


## A fresh match: year 1's draws, made before anybody sees year 0, so a match
## holds next year's draws from its first snapshot on, as it does every later
## year (`YearPipeline.open_match`). They take the same place in the stream as
## drawing them at year 1's start would. No whisper reads them: there is none
## in year 0 (D207).
func open_match(state: GameState, rng: RandomNumberGenerator) -> void:
	if state.market != null and state.market.next_draws == null:
		state.market.next_draws = draw_ahead(state, rng)


## Next year's industry and earnings draws, from the market as it stands now:
## one swing per industry in id order, then two draws per living company in
## the market's order (`draw_company_earnings`). Draws exactly that; changes
## nothing.
func draw_ahead(state: GameState, rng: RandomNumberGenerator) -> KeptDraws:
	var market: EarningsMarket = state.market
	var draws: KeptDraws = KeptDraws.new()
	var ordered: Array[IndustryState] = market.industries.duplicate()
	ordered.sort_custom(_industry_by_id)
	for industry: IndustryState in ordered:
		draws.industry_rolls[industry.id] = rng.randi_range(-IndustryState.SWING, IndustryState.SWING)
	for company: CompanyState in _living(state):
		var drawn: Vector2i = draw_company_earnings(market, company, state.settings.max_years, rng)
		draws.regimes[company.id] = EarningsRegime.ALL[drawn.x]
		draws.growth_rolls[company.id] = drawn.y
	return draws


## A year the host already resolved, rebuilt from the inputs it sent, on a copy
## of the market as it stood before that year (decisions.md D176).
##
## `result` arrives holding the year's draws - `industry_rolls`, `regimes`,
## `growth_rolls`, `net_shares_priced`, the `event`, the squeeze fields - and
## the desk's record; this fills in everything they determine: every row's
## change, the ledgers, the industry figures, the index move, the mood, the
## dividends per share. `state` is moved to the end of the year exactly as
## `advance_year` moved the host's, through the same `_settle_prices`.
##
## **Draws nothing and runs neither the settlement nor the desk.** Players'
## cash, loans and standings arrive with the year as the host settled them, and
## the desk's trades arrive as its record; neither is the market's to rebuild.
## `state` is normally a copy with no players (`EarningsMarket.replay_state`).
func replay_year(state: GameState, result: EarningsYearResult) -> void:
	var market: EarningsMarket = state.market
	var year: YearInProgress = _open_year(state, result)

	for industry: IndustryState in market.industries:
		industry.replay(result.industry_rolls.get(industry.id, 0), market.sentiment)
	_record_industries(market, result)

	for company: CompanyState in year.alive:
		company.replay_earnings(
			result.regimes.get(company.id, company.regime),
			result.growth_rolls.get(company.id, 0),
			market.performance_of(company),
			state.settings.max_years,
		)

	_settle_prices(state, result, year)


## What a year carries from its opening to its prices: every row's change
## record, the companies alive at the start, and a copy of each as it was.
class YearInProgress:
	extends RefCounted
	var changes: Dictionary[StringName, StalkYearChange] = {}
	var alive: Array[CompanyState] = []
	var before: Dictionary[StringName, CompanyState] = {}


## The start of a year, the same on both paths: the year number, last year's
## sentiment and bag on the record, the rows' yearly flags cleared, a change
## record per row and a copy of every living company.
func _open_year(state: GameState, result: EarningsYearResult) -> YearInProgress:
	var market: EarningsMarket = state.market
	state.year += 1
	result.year = state.year
	result.sentiment_used = market.sentiment
	result.event_bag = market.last_mood
	# What this year's prices are valued on, kept for a client that has to
	# rebuild the valuation from the inputs (`CompanyState.derive_readouts`).
	market.sentiment_used = market.sentiment

	for row: StalkState in state.stalks:
		row.did_split = false
		row.last_yearly_change = 0

	var year: YearInProgress = YearInProgress.new()
	for row: StalkState in state.stalks:
		var change: StalkYearChange = StalkYearChange.new()
		change.stalk_id = row.id
		change.price_before = row.price
		change.price_after = row.price
		year.changes[row.id] = change
		result.stalk_changes.append(change)

	year.alive = _living(state)
	for company: CompanyState in year.alive:
		year.before[company.id] = company.copy()
	return year


func _record_industries(market: EarningsMarket, result: EarningsYearResult) -> void:
	for industry: IndustryState in market.industries:
		result.industry_performance[industry.id] = industry.performance
		result.industry_rolls[industry.id] = industry.roll


## §4 steps 3 and 5 to 10, from the year's inputs, which are all in `result` by
## now. Draws nothing. Both `advance_year` and `replay_year` end here.
func _settle_prices(state: GameState, result: EarningsYearResult, year: YearInProgress) -> void:
	var market: EarningsMarket = state.market
	var changes: Dictionary[StringName, StalkYearChange] = year.changes
	var alive: Array[CompanyState] = year.alive
	var before: Dictionary[StringName, CompanyState] = year.before
	var hits: Dictionary[StringName, int] = MarketNewsRules.hits(state, result.market_news)
	var squeezed_id: StringName = result.squeeze_target()

	# A squeeze that has run its course comes off now, before the price is
	# set; one still running counts down a year (D213).
	for company: CompanyState in alive:
		if not company.in_squeeze():
			continue
		if company.squeeze_years_left <= 0:
			result.squeeze_moves[company.id] = -company.squeeze_premium
			company.squeeze_premium = 0
			company.squeeze_years_left = 0
		else:
			company.squeeze_years_left -= 1

	# 3 and 5. Valuation, then the price identity, once.
	for company: CompanyState in alive:
		var traded: int = result.net_shares_priced.get(company.id, 0)
		company.reprice(market.sentiment, valuation_performance(market, company), hits.get(company.id, 0), traded)
		if company.id == squeezed_id:
			# The lift, plus whatever the rest of the year would have taken off:
			# a squeezed price never falls in the year it is squeezed.
			var lift: int = result.squeeze_spike + maxi(0, before[company.id].price - company.price)
			company.squeeze_premium = lift
			company.squeeze_years_left = result.squeeze_hold_roll - 1
			company.price += lift
			result.squeeze_moves[company.id] = lift

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

	# The year's record of every company, for the screens (decisions.md D179).
	# Here, at the end of the half both paths share, so a client's is the host's.
	for company: CompanyState in market.companies:
		result.companies_after[company.id] = company.copy()
	result.index_level_after = market.index_level


## A player's accepted trade, added to next year's flow exactly as an NPC's is
## (§3.10). `MatchAuthority` calls this for every buy and sell (decisions.md
## D163, D171). A trade in the bond or the index is recorded too, and never
## read: only companies' entries feed a price.
func record_trade(state: GameState, stalk_id: StringName, shares: int) -> void:
	state.market.record_trade(stalk_id, shares)


## §4 step 2's draws for one company, a year early: the regime it will enter
## and the growth roll from that regime's band, as `Vector2i(regime, roll)`.
## Changes nothing. **A seam for the balance tool only**, which overrides it to
## sweep the transition matrix (tools/balance/levers.gd, decisions.md D150);
## nothing in the game overrides it. Two draws, as `CompanyState.advance_earnings`.
func draw_company_earnings(
	_market: EarningsMarket,
	company: CompanyState,
	_match_years: int,
	rng: RandomNumberGenerator,
) -> Vector2i:
	var next: EarningsRegime.Value = RegimeRules.roll_next(
		company.regime, company.profile.quality, company.years_in_regime, rng
	)
	var band: Vector2i = RegimeRules.GROWTH_BAND[next]
	return Vector2i(int(next), rng.randi_range(band.x, band.y))


## §5.3: the chance, in percent, of a squeeze this year. **A seam for the
## balance tool only**, which overrides it to sweep the chance (decisions.md
## D166); nothing in the game overrides it.
func squeeze_chance_percent(any_flagged: bool) -> int:
	return ShortInterestRules.squeeze_chance_percent(any_flagged)


## The squeeze's lift for a company priced at `price` with `short_percent`
## of its shares sold short (`ShortInterestRules.spike_for`). **A seam for the
## balance tool only**, which overrides it to sweep the size; nothing in the
## game overrides it.
func squeeze_spike(price: int, short_percent: float) -> int:
	return ShortInterestRules.spike_for(price, short_percent)


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
static func _industry_by_id(a: IndustryState, b: IndustryState) -> bool:
	return String(a.id) < String(b.id)


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
			company.fail()
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
