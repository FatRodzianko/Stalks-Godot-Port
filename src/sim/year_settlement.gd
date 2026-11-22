class_name YearSettlement
extends RefCounted
## The back half of every year, shared by both year pipelines: loans, net worth
## and standings, and the game-end check. Then the year is closed: ready flags
## cleared and the result appended to the history.
##
## **Why this is its own class.** The base game's `YearResolver` and
## StalkleHeads' `EarningsYearResolver` set prices in different orders, but once
## prices, splits and dividends have settled they finish the year identically.
## So the shared half lives here, once, and each pipeline calls it as its last
## step. Neither pipeline asks which mode it is in. See
## docs/stalkleheads-design.md §10.2 and decisions.md D152.
##
## **This was a pure move.** The statements below were steps 8-10 of
## `YearResolver.advance_year`, moved in the same order with nothing added and
## no draw from any RNG. `tests/unit/test_golden_history.gd` hashes a seeded
## 99-year base match and proved the hash identical before and after the move.
##
## No state, no randomness. Every function is static.


## Runs §4 steps 11, 12 and 15 of the year (game-rules.md §4.1 steps 8-10) on a
## year whose prices, splits and dividends are already final, then closes it.
static func settle(state: GameState, result: YearResult) -> void:
	# Loans: missed-payment penalties, then interest. Must run before net worth,
	# since an outstanding balance is subtracted from it.
	process_loans(state, result)

	# Net worth and standings.
	for player: PlayerState in state.players:
		player.net_worth = TradeRules.net_worth(player, state)
		result.net_worths[player.id] = player.net_worth
	result.rankings = TradeRules.rank(state.players)

	# Game end. The original's condition is `currentYear > maxNumberOfYears`, so
	# a 10-year match plays years 1..10 and then settles once more into year 11,
	# which ends it. See docs/game-rules.md §12.
	if state.has_passed_final_year():
		state.is_over = true
		result.is_final_year = true
		result.winners = TradeRules.winners(state.players)

	state.clear_ready_flags()
	state.history.append(result)


## Runs the year-end loan assessment for every player who owes money.
##
## Skipped entirely when loans are disabled for the match, matching the original,
## which wrapped its whole loan pass in that check. Note that a player can be
## bankrupted here, which is why this runs before net worth is recomputed.
static func process_loans(state: GameState, result: YearResult) -> void:
	if state.settings == null or not state.settings.loans_enabled:
		return

	for player: PlayerState in state.players:
		var change: LoanYearChange = LoanRules.process_year_end(player)
		if change != null:
			result.loan_changes.append(change)
