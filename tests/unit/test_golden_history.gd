extends GutTest
## The golden history: proof that the base game is bit-for-bit unchanged.
##
## This is property P5 of docs/stalkleheads-design.md (§1, §12.1), written in
## build phase S0, BEFORE any StalkleHeads code exists. It plays one seeded
## 99-year base-game match on the shipped content, with three scripted players,
## writes down everything the year pipeline decided in every year as one block
## of plain text, hashes that text, and compares the hash with the one below.
##
## **Why it exists.** Phase S3 moves the back half of `YearResolver` (loans, net
## worth, standings, the game-end check) into a shared `YearSettlement`. That is
## meant to be a pure move. A test written after the move could only prove the
## base game matches itself as it then is; this one was recorded first, so it
## proves the move changed nothing.
##
## **What the record covers**, every year: the mood, the event drawn, and per
## stalk the price before and after, base and event deltas, split and
## bankruptcy; per player the dividend, the loan assessment (penalty, interest,
## misses, default), cash, holdings, loan state and net worth; the standings;
## whether the game ended and who won. The scripted players' actions, and
## whether each was allowed, are recorded too. See docs/decisions.md D127.
##
## **The hash is meant to break only when a base-game rule deliberately
## changes** - a price range, an event, a dividend, the loan arithmetic, the
## order of the year. Shipped content (src/data/stalks/) is part of the record,
## so editing a stalk's numbers or an event's price change breaks it as well;
## flavour text and display names are not recorded and do not.
##
## **If it fails:**
##   1. Do not just paste in the new hash. First find out what changed.
##      The failure message names a file holding the full record of this run.
##      Check out the last commit where the test passed, run it there, and diff
##      the two record files - the first differing line is the first year and
##      the first thing that moved.
##   2. If the change was NOT intended, it is a bug. Fix the code, not the hash.
##   3. If it WAS intended (a rule was deliberately changed), update
##      `GOLDEN_HASH` below and add an entry to docs/decisions.md saying which
##      rule changed and why the base game's history was allowed to move.
##
## Players and their scripts:
##   p0 "the trader"   - every fourth year sells everything and puts half its
##                       cash into one stalk, cycling through the board.
##   p1 "the defaulter" - takes the largest loan allowed in year 2, buys
##                       strYker!!! with it, and never pays. Three misses bankrupt
##                       it (10% penalty, then 15%, then seizure).
##   p2 "the payer"    - buys bonds and mutuals in year 1, borrows half its limit
##                       in year 3, pays the minimum every year except year 6
##                       (one penalty), and in year 10 pays more than it owes,
##                       which the loan rules clamp to the balance.


## sha256 of the canonical record. Change only by the procedure above.
const GOLDEN_HASH: String = "e581d9ed88cd8ca2d23d6f4b62258fac3ddef0188ecdf5c815f88832c06dbb8a"

const SEED: int = 20261121
const MAX_YEARS: int = 99
const RECORD_PATH: String = "user://golden_history_record.txt"


func test_the_base_game_history_is_unchanged() -> void:
	var state: GameState = _build_state()
	var library: ContentLibrary = ContentLibrary.load_from()
	assert_true(library.is_valid(), "the shipped content must load clean")
	var resolver: YearResolver = YearResolver.new(
		RandomRangePriceModel.new(), library.build_event_pool()
	)
	var rng: RandomNumberGenerator = StalksFixture.rng(SEED)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("seed=%d max_years=%d" % [SEED, MAX_YEARS])

	var advances: int = 0
	while not state.is_over and advances < MAX_YEARS + 5:
		if state.is_trading_open():
			_act(state, lines)
		var year_result: YearResult = resolver.advance_year(state, rng)
		_record_year(state, year_result, lines)
		advances += 1

	var record: String = "\n".join(lines)
	var hash_value: String = record.sha256_text()
	_write_record(record)

	assert_true(state.is_over, "the match should end")
	assert_eq(state.year, MAX_YEARS + 1, "a 99-year match settles into year 100")
	_assert_the_match_exercised_everything(state)

	assert_eq(hash_value, GOLDEN_HASH,
		"The base game's history changed. Full record of this run: %s. Read the header of this file before touching GOLDEN_HASH."
		% ProjectSettings.globalize_path(RECORD_PATH))


# ------------------------------------------------------------------ the match

func _build_state() -> GameState:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = MAX_YEARS
	settings.player_count = 3
	settings.starting_cash = 10000
	settings.loans_enabled = true
	settings.rng_seed = SEED

	var state: GameState = GameState.new(settings)
	state.stalks = ContentLibrary.load_from().build_stalk_states()
	for index: int in 3:
		state.players.append(
			PlayerState.new(StringName("p%d" % index), "Player %d" % index, settings.starting_cash)
		)
	return state


## The scripted actions for the current trading year. Every action goes through
## the sim-layer validation first and is applied only if allowed; the record
## notes which it was, so a change in what is legal also changes the hash.
func _act(state: GameState, lines: PackedStringArray) -> void:
	var year: int = state.year
	var trader: PlayerState = state.player_by_id(&"p0")
	var defaulter: PlayerState = state.player_by_id(&"p1")
	var payer: PlayerState = state.player_by_id(&"p2")

	# p0, the trader.
	if year % 4 == 1:
		for stalk_id: String in _sorted_holdings(trader):
			var held: int = trader.shares_of(StringName(stalk_id))
			_sell(state, trader, StringName(stalk_id), held, lines)
		var choices: Array[StalkState] = _tradeable_stalks(state)
		if not choices.is_empty():
			var target: StalkState = choices[(year * 3) % choices.size()]
			@warning_ignore("integer_division")
			var shares: int = TradeRules.max_affordable(trader, target) / 2
			_buy(state, trader, target.id, shares, lines)

	# p1, the defaulter.
	if year == 2:
		_take_loan(state, defaulter, LoanRules.max_loan_for(defaulter), lines)
		var stryker: StalkState = state.stalk_by_id(&"stryker")
		_buy(state, defaulter, &"stryker", TradeRules.max_affordable(defaulter, stryker), lines)

	# p2, the payer.
	if year == 1:
		_buy(state, payer, &"berry_bonds", 20, lines)
		_buy(state, payer, &"mutuals", 30, lines)
	if year == 3:
		@warning_ignore("integer_division")
		_take_loan(state, payer, LoanRules.max_loan_for(payer) / 2, lines)
	if year >= 4 and year != 6 and payer.has_outstanding_loan():
		var amount: int = payer.loan.min_payment
		if year == 10:
			# Deliberately more than is owed: apply_payment clamps it.
			amount = payer.loan.balance + 100
		_pay(payer, amount, lines)
	if year % 10 == 0:
		@warning_ignore("integer_division")
		var half: int = payer.shares_of(&"mutuals") / 2
		_sell(state, payer, &"mutuals", half, lines)


func _buy(
	state: GameState,
	player: PlayerState,
	stalk_id: StringName,
	shares: int,
	lines: PackedStringArray,
) -> void:
	var stalk: StalkState = state.stalk_by_id(stalk_id)
	var allowed: bool = TradeRules.validate_buy(player, stalk, shares, state) == ""
	if allowed:
		TradeRules.apply_buy(player, stalk, shares)
	lines.append("  T %s buy %s %d %s" % [player.id, stalk_id, shares, _verdict(allowed)])


func _sell(
	state: GameState,
	player: PlayerState,
	stalk_id: StringName,
	shares: int,
	lines: PackedStringArray,
) -> void:
	var stalk: StalkState = state.stalk_by_id(stalk_id)
	var allowed: bool = TradeRules.validate_sell(player, stalk, shares, state) == ""
	if allowed:
		TradeRules.apply_sell(player, stalk, shares)
	lines.append("  T %s sell %s %d %s" % [player.id, stalk_id, shares, _verdict(allowed)])


func _take_loan(
	state: GameState,
	player: PlayerState,
	amount: int,
	lines: PackedStringArray,
) -> void:
	var allowed: bool = LoanRules.validate_take_loan(player, amount, state) == ""
	if allowed:
		LoanRules.take_loan(player, amount)
	lines.append("  T %s loan %d %s" % [player.id, amount, _verdict(allowed)])


func _pay(player: PlayerState, amount: int, lines: PackedStringArray) -> void:
	var allowed: bool = LoanRules.validate_payment(player, amount) == ""
	var paid: int = 0
	if allowed:
		paid = LoanRules.apply_payment(player, amount)
	lines.append("  T %s pay %d paid=%d %s" % [player.id, amount, paid, _verdict(allowed)])


## Non-static, non-bankrupt stalks, sorted by id.
func _tradeable_stalks(state: GameState) -> Array[StalkState]:
	var by_id: Dictionary[String, StalkState] = {}
	var ids: Array[String] = []
	for stalk: StalkState in state.stalks:
		if stalk.is_bankrupt or stalk.is_price_static():
			continue
		by_id[String(stalk.id)] = stalk
		ids.append(String(stalk.id))
	ids.sort()
	var result: Array[StalkState] = []
	for stalk_id: String in ids:
		result.append(by_id[stalk_id])
	return result


# ----------------------------------------------------------------- the record

## One year's lines. Every collection is written in sorted-id order and every
## number is an int, so the text is identical on every machine and every run.
func _record_year(state: GameState, result: YearResult, lines: PackedStringArray) -> void:
	var event_id: String = "-"
	if result.event != null:
		event_id = "%s@%s%+d" % [
			result.event.id, result.event.target_stalk_id, result.event.price_change,
		]
	# The mood as a fixed word, not MarketMood.label(): the label is display
	# text, and rewording it is not a rule change.
	var mood: String = "BEAR" if result.mood == MarketMood.Value.BEAR else "BULL"
	lines.append("Y%d mood=%s event=%s" % [result.year, mood, event_id])

	var changes: Dictionary[String, StalkYearChange] = {}
	for change: StalkYearChange in result.stalk_changes:
		changes[String(change.stalk_id)] = change
	var stalk_ids: Array[String] = []
	stalk_ids.assign(changes.keys())
	stalk_ids.sort()
	for stalk_id: String in stalk_ids:
		var change: StalkYearChange = changes[stalk_id]
		lines.append("  S %s %d>%d base=%d event=%d split=%d bankrupt=%d" % [
			stalk_id, change.price_before, change.price_after, change.base_delta,
			change.event_delta, int(change.did_split), int(change.went_bankrupt),
		])

	for player_id: String in _sorted_player_ids(state):
		var player: PlayerState = state.player_by_id(StringName(player_id))
		lines.append("  D %s %d" % [player_id, result.dividends.get(StringName(player_id), -1)])

		var loan_change: LoanYearChange = result.loan_change_for(StringName(player_id))
		if loan_change != null:
			lines.append("  L %s %d>%d paid=%d missed=%d penalty=%d interest=%d min=%d defaulted=%d" % [
				player_id, loan_change.balance_before, loan_change.balance_after,
				int(loan_change.paid_during_year), loan_change.missed_payments,
				loan_change.penalty_added, loan_change.interest_added,
				loan_change.min_payment_after, int(loan_change.defaulted),
			])

		lines.append("  P %s cash=%d nw=%d reported=%d bankrupt=%d loan=%s holdings=%s" % [
			player_id, player.cash, player.net_worth,
			result.net_worths.get(StringName(player_id), -1), int(player.is_bankrupt),
			_loan_text(player.loan), _holdings_text(player),
		])

	var ranking: PackedStringArray = PackedStringArray()
	for player_id: StringName in result.rankings:
		ranking.append(String(player_id))
	lines.append("  R %s" % ",".join(ranking))

	var winners: PackedStringArray = PackedStringArray()
	for player_id: StringName in result.winners:
		winners.append(String(player_id))
	lines.append("  E over=%d final=%d winners=%s" % [
		int(state.is_over), int(result.is_final_year), ",".join(winners),
	])


func _loan_text(loan: LoanState) -> String:
	if loan == null:
		return "-"
	return "%d/%d/%d/%d/%d/%d/%d" % [
		loan.balance, loan.min_payment, loan.years_remaining, loan.missed_payments,
		int(loan.paid_this_year), int(loan.is_paid_off), int(loan.is_defaulted),
	]


func _holdings_text(player: PlayerState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for stalk_id: String in _sorted_holdings(player):
		parts.append("%s:%d" % [stalk_id, player.shares_of(StringName(stalk_id))])
	return ",".join(parts) if not parts.is_empty() else "-"


func _sorted_holdings(player: PlayerState) -> Array[String]:
	var ids: Array[String] = []
	for stalk_id: StringName in player.held_stalk_ids():
		ids.append(String(stalk_id))
	ids.sort()
	return ids


func _sorted_player_ids(state: GameState) -> Array[String]:
	var ids: Array[String] = []
	for player: PlayerState in state.players:
		ids.append(String(player.id))
	ids.sort()
	return ids


func _verdict(allowed: bool) -> String:
	return "ok" if allowed else "refused"


func _write_record(record: String) -> void:
	var file: FileAccess = FileAccess.open(RECORD_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(record)
	file.close()


# ------------------------------------------------- the match did what it claims

## A hash only guards what the match actually reaches. These assertions keep the
## script honest: if a later edit to the script stops a loan defaulting, say, the
## test says so rather than quietly guarding less.
func _assert_the_match_exercised_everything(state: GameState) -> void:
	var splits: int = 0
	var bankruptcies: int = 0
	var events: int = 0
	var bears: int = 0
	var penalties: int = 0
	var defaults: int = 0
	for result: YearResult in state.history:
		splits += result.split_ids().size()
		bankruptcies += result.bankrupt_ids().size()
		if result.event != null:
			events += 1
		if result.mood == MarketMood.Value.BEAR:
			bears += 1
		defaults += result.defaulted_player_ids().size()
		for change: LoanYearChange in result.loan_changes:
			if change.penalty_added > 0:
				penalties += 1

	assert_gt(splits, 0, "the match should include a split")
	assert_gt(bankruptcies, 0, "the match should include a stalk bankruptcy")
	assert_gt(events, 0, "the match should draw events")
	assert_gt(bears, 0, "the match should include bear years")
	assert_gt(penalties, 1, "the match should include missed-payment penalties")
	assert_eq(defaults, 1, "the defaulter should default exactly once")
	assert_true(state.player_by_id(&"p1").is_bankrupt, "p1 should be wiped out by the default")
	assert_true(state.player_by_id(&"p2").loan.is_paid_off, "p2 should clear its loan")
	assert_false(state.latest_result().winners.is_empty(), "the final year names a winner")
