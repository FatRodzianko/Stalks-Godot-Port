class_name YearResolver
extends RefCounted
## Runs one year advance: the ordered end-of-year sequence that is the heart of
## the game.
##
## The order below is traced from the original's actual call chain, NOT from the
## itch.io write-up, which lists a different and incorrect order. Two consequences
## are deliberate and must be preserved:
##
##   * Splits are checked only ONCE, after the event. A stalk pushed above 150 by
##     its base move and then knocked back under by a negative event does not
##     split.
##   * Dividends are paid AFTER splits, so a stalk that split pays that year's
##     dividend on the doubled share count.
##
## See docs/game-rules.md §4.1.


var _price_model: PriceModel
var _event_pool: EventPool


func _init(price_model: PriceModel, event_pool: EventPool) -> void:
	_price_model = price_model
	_event_pool = event_pool


## Advances `state` by one year and returns an immutable record of what happened.
## All randomness comes from `rng`; nothing here touches global randi().
func advance_year(state: GameState, rng: RandomNumberGenerator) -> YearResult:
	var result: YearResult = YearResult.new()

	state.year += 1
	result.year = state.year

	for stalk: StalkState in state.stalks:
		stalk.did_split = false

	# 1. Decide the year's mood.
	result.mood = MarketMood.pick(
		state.settings.bull_weight,
		state.settings.bear_weight,
		rng,
	)

	# Open a change record per stalk so every later step can annotate it.
	var changes: Dictionary[StringName, StalkYearChange] = {}
	for stalk: StalkState in state.stalks:
		var change: StalkYearChange = StalkYearChange.new()
		change.stalk_id = stalk.id
		change.price_before = stalk.price
		change.price_after = stalk.price
		changes[stalk.id] = change
		result.stalk_changes.append(change)

	# 2. Base price change, per stalk, independently rolled.
	for stalk: StalkState in state.stalks:
		if stalk.is_bankrupt or stalk.is_price_static():
			stalk.last_yearly_change = 0
			continue
		var delta: int = _price_model.next_change(stalk, result.mood, state, rng)
		stalk.last_yearly_change = delta
		stalk.price += delta
		changes[stalk.id].base_delta = delta
		changes[stalk.id].price_after = stalk.price

	# 3. Bankruptcy pass one — the base move alone can kill a stalk.
	_apply_bankruptcies(state, changes)

	# 4. One special event, aimed at a single stalk.
	result.event = _event_pool.draw(result.mood, state, rng)
	if result.event != null:
		var target: StalkState = state.stalk_by_id(result.event.target_stalk_id)
		if target != null and not target.is_bankrupt and not target.is_price_static():
			target.price += result.event.price_change
			changes[target.id].event_delta = result.event.price_change
			changes[target.id].price_after = target.price

	# 5. Bankruptcy pass two — the event can kill a stalk the base move spared.
	_apply_bankruptcies(state, changes)

	# 6. Splits.
	_apply_splits(state, changes)

	# 7. Dividends, on post-split share counts.
	_pay_dividends(state, result)

	# 8. Loans — Phase 2 inserts missed-payment penalties and interest here,
	#    before net worth is computed. See docs/porting-plan.md.

	# 9. Net worth and standings.
	for player: PlayerState in state.players:
		player.net_worth = TradeRules.net_worth(player, state)
		result.net_worths[player.id] = player.net_worth
	result.rankings = TradeRules.rank(state.players)

	# 10. Game end. The original's condition is `currentYear > maxNumberOfYears`,
	#     so a 10-year match plays years 1..10 and then settles once more into
	#     year 11, which ends it. See docs/game-rules.md §12.
	if state.has_passed_final_year():
		state.is_over = true
		result.is_final_year = true
		result.winners = TradeRules.winners(state.players)

	state.clear_ready_flags()
	state.history.append(result)
	return result


## Any stalk at or below the bankruptcy threshold fails: its price is pinned to 0
## and every holder's position in it is wiped out, with no compensation.
func _apply_bankruptcies(
	state: GameState,
	changes: Dictionary[StringName, StalkYearChange],
) -> void:
	for stalk: StalkState in state.stalks:
		if stalk.is_bankrupt or stalk.is_price_static():
			continue
		if stalk.price > TradeRules.BANKRUPT_AT_OR_BELOW:
			continue

		stalk.is_bankrupt = true
		stalk.price = 0
		changes[stalk.id].went_bankrupt = true
		changes[stalk.id].price_after = 0
		for player: PlayerState in state.players:
			player.set_shares(stalk.id, 0)


## A stalk above the split threshold halves its price, ROUNDING UP on an odd
## price, and doubles every holder's shares. 153 becomes 77, not 76 — matching the
## original's live code path. See docs/game-rules.md §6.
func _apply_splits(
	state: GameState,
	changes: Dictionary[StringName, StalkYearChange],
) -> void:
	for stalk: StalkState in state.stalks:
		if stalk.is_bankrupt or stalk.is_price_static():
			continue
		if stalk.price <= TradeRules.SPLIT_ABOVE:
			continue

		var before: int = stalk.price
		@warning_ignore("integer_division")
		var halved: int = before / 2
		if before % 2 != 0:
			halved += 1

		stalk.price = halved
		stalk.did_split = true
		changes[stalk.id].did_split = true
		changes[stalk.id].price_after = halved

		for player: PlayerState in state.players:
			var held: int = player.shares_of(stalk.id)
			if held > 0:
				player.set_shares(stalk.id, held * 2)


## Pays each player a fixed per-share dividend for every stalk they hold that
## still has value, using this year's mood.
func _pay_dividends(state: GameState, result: YearResult) -> void:
	for player: PlayerState in state.players:
		var paid: int = 0
		for stalk: StalkState in state.stalks:
			if not stalk.has_value():
				continue
			var held: int = player.shares_of(stalk.id)
			if held > 0:
				paid += held * stalk.dividend_per_share(result.mood)
		player.cash += paid
		result.dividends[player.id] = paid
