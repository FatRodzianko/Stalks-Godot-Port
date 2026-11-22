class_name StateSync
extends RefCounted
## Turns match state into plain dictionaries for the wire, and back again.
##
## All static, all pure — no nodes and no peer. That means every rule about what a
## client is allowed to know is testable without a network, which is the point:
## a privacy leak is invisible in play and obvious in a test.
##
## **Why hand-written encoding.** Godot will not serialize script objects over RPC
## unless object decoding is enabled, and enabling it lets a peer instantiate
## arbitrary classes in this process. So nothing but built-in types crosses the
## wire, and every field is listed by hand. See docs/decisions.md D41.
##
## **Why whole snapshots.** This is a turn-based game with at most ten players and
## ten stalks; a complete snapshot is a couple of kilobytes and arrives a
## handful of times per year. Delta encoding would buy nothing and could drift out
## of sync. See docs/decisions.md D42.
##
## **Definitions are not sent.** Both sides load the same `.tres` content, so only
## ids travel and the receiver looks the definition up locally. A client that
## cannot resolve an id is running different content from the host, which is worth
## failing loudly over rather than papering over.


# ---------------------------------------------------------------------- the view
#
# What a client is told. See docs/architecture.md §5.3.
#
# **Everything, as of 2026-11-18.** Every client holds a complete copy of the
# match - everybody's cash, holdings and loan, not only its own. Two reasons,
# and the second is the one that decided it.
#
# The first is that there was never much worth protecting. This is a game of
# bets on a random number generator, and nobody plays it differently for
# knowing a rival's cash balance. The board already publishes net worth, which
# is the figure players actually watch.
#
# The second is **host migration**. When the host walks out, one of the
# remaining players has to carry the match on, and the only thing they can
# carry it on from is a copy they already hold. A redacted copy is missing
# every other player's position, so a new host would have to ask the remaining
# players what they own and believe the answers - trusting precisely the people
# a host exists not to have to trust. With a complete copy it promotes its own
# and asks nobody anything. See docs/decisions.md D105.
#
# **This is about visibility, not authority.** The host still owns every rule.
# A client sends requests - "buy 5 of X" - and the host validates them against
# its own state and applies them (`host_session.gd`); no client writes anybody's
# position, its own included. Being able to see a number and being able to
# change it are different powers, and only the first one was given away.


## Encodes the whole match, in full, for everybody.
##
## `rng_state` is how far the match's random stream has run. It rides along so
## that a client forced to take over as host can carry that stream on from
## where it stood, instead of rewinding to the start of the match and dealing
## year one's rolls out a second time. A client that never becomes host ignores
## it.
static func encode_state(state: GameState, rng_state: int = 0) -> Dictionary:
	var players: Array[Dictionary] = []
	for player: PlayerState in state.players:
		players.append(encode_player(player))

	var stalks: Array[Dictionary] = []
	for stalk: StalkState in state.stalks:
		stalks.append(encode_stalk(stalk))

	var data: Dictionary = {
		"year": state.year,
		"is_over": state.is_over,
		"rng_state": rng_state,
		# Public: every board draws a host marker from it, and after a
		# migration it is the only way to know the marker has moved.
		"hosted_by": String(state.hosted_by),
		# Public: everybody's button depends on it.
		"yeehaw_requested_by": String(state.yeehaw_requested_by),
		"stalks": stalks,
		"players": players,
		"settings": encode_settings(state.settings),
	}
	# A StalkleHeads match's market: the companies, industries, desk and the
	# rest. A base-game match has none, so its snapshot has no such key and is
	# byte for byte what it always was (decisions.md D176).
	if state.market != null:
		data["market"] = MarketSync.encode_market(state)
	return data


## One player, with nothing held back.
##
## **Deliberately complete** - the note at the top of this file says why, and
## `apply_player` is its mirror. Cash, share counts and the loan schedule all
## travel, which is what makes any client able to take the match over.
static func encode_player(player: PlayerState) -> Dictionary:
	var holdings: Dictionary = {}
	for stalk_id: StringName in player.holdings:
		holdings[String(stalk_id)] = player.holdings[stalk_id]

	return {
		"id": String(player.id),
		"display_name": player.display_name,
		"steam_id": player.steam_id,
		"net_worth": player.net_worth,
		"is_bankrupt": player.is_bankrupt,
		"is_ready": player.is_ready,
		# Public: every board marks who is not here, and the year gate skips
		# them, so a client that could not see it would be waiting on somebody
		# the host is not waiting on. See docs/decisions.md D110.
		"is_away": player.is_away,
		"cash": player.cash,
		"holdings": holdings,
		"loan": encode_loan(player.loan),
	}


static func encode_loan(loan: LoanState) -> Variant:
	if loan == null:
		return null
	return {
		"balance": loan.balance,
		"min_payment": loan.min_payment,
		"years_remaining": loan.years_remaining,
		"missed_payments": loan.missed_payments,
		"paid_this_year": loan.paid_this_year,
		"is_paid_off": loan.is_paid_off,
		"is_defaulted": loan.is_defaulted,
	}


static func encode_stalk(stalk: StalkState) -> Dictionary:
	return {
		"id": String(stalk.id),
		"price": stalk.price,
		"last_yearly_change": stalk.last_yearly_change,
		"is_bankrupt": stalk.is_bankrupt,
		"did_split": stalk.did_split,
	}


static func encode_settings(settings: GameSettings) -> Dictionary:
	if settings == null:
		return {}
	return {
		"game_name": settings.game_name,
		"mode": int(settings.mode),
		"invite_only": settings.invite_only,
		"starting_cash": settings.starting_cash,
		"max_years": settings.max_years,
		"loans_enabled": settings.loans_enabled,
		"multiple_loans_enabled": settings.multiple_loans_enabled,
		"rng_seed": settings.rng_seed,
	}


# ------------------------------------------------------------------- applying it

## Overwrites `state` in place from a snapshot, resolving stalk and event
## definitions through `library`.
##
## In place, rather than returning a fresh GameState, because the UI holds
## references to the state and its players; replacing the object would strand
## every one of them.
##
## Returns a reason if the snapshot could not be applied, or an empty string.
static func apply_state(
	state: GameState,
	data: Dictionary,
	library: ContentLibrary,
) -> String:
	if not data.has("stalks") or not data.has("players"):
		return "Malformed state snapshot."

	state.year = int(data.get("year", 0))
	state.is_over = bool(data.get("is_over", false))
	state.yeehaw_requested_by = StringName(data.get("yeehaw_requested_by", ""))
	state.hosted_by = StringName(data.get("hosted_by", ""))
	apply_settings(state, data.get("settings", {}))
	# A StalkleHeads board has companies the base game does not ship. The mode
	# arrives in the settings, so this is the first moment a joining client can
	# know to load them (decisions.md D171).
	MatchSetup.prepare_library(library, state.settings.mode)

	var stalk_data: Array = data["stalks"]
	for entry: Dictionary in stalk_data:
		var stalk_id: StringName = StringName(entry.get("id", ""))
		var stalk: StalkState = state.stalk_by_id(stalk_id)
		if stalk == null:
			# The host knows about a stalk this build does not. Mismatched
			# content, and silently rendering a short board would be worse than
			# saying so.
			var definition: StalkDefinition = MatchSetup.board_definition(library, stalk_id)
			if definition == null:
				return "Unknown stalk '%s' — host is running different content." % stalk_id
			stalk = StalkState.new(definition)
			state.stalks.append(stalk)
		apply_stalk(stalk, entry)

	var player_data: Array = data["players"]
	# Players arrive in the host's order, which is the order the rankings and
	# lobby use, so the replica adopts it rather than preserving its own.
	var rebuilt: Array[PlayerState] = []
	for entry: Dictionary in player_data:
		var player_id: StringName = StringName(entry.get("id", ""))
		var player: PlayerState = state.player_by_id(player_id)
		if player == null:
			player = PlayerState.new(player_id, String(entry.get("display_name", "")), 0)
		apply_player(player, entry)
		rebuilt.append(player)
	state.players = rebuilt

	# After the board, because the market's packed rows are read against it.
	# No market block means a base-game match, and a replica holding a market
	# from an earlier StalkleHeads match must not keep it.
	if data.get("market") is Dictionary:
		return MarketSync.apply_market(state, data["market"], library)
	state.market = null
	return ""


static func apply_settings(state: GameState, data: Dictionary) -> void:
	if data.is_empty():
		return
	if state.settings == null:
		state.settings = GameSettings.new()
	state.settings.game_name = String(data.get("game_name", state.settings.game_name))
	state.settings.mode = GameMode.from_int(int(data.get("mode", int(state.settings.mode))))
	state.settings.invite_only = bool(data.get("invite_only", state.settings.invite_only))
	state.settings.starting_cash = int(data.get("starting_cash", state.settings.starting_cash))
	state.settings.max_years = int(data.get("max_years", state.settings.max_years))
	state.settings.loans_enabled = bool(data.get("loans_enabled", state.settings.loans_enabled))
	state.settings.multiple_loans_enabled = bool(
		data.get("multiple_loans_enabled", state.settings.multiple_loans_enabled)
	)
	state.settings.rng_seed = int(data.get("rng_seed", state.settings.rng_seed))


static func apply_stalk(stalk: StalkState, data: Dictionary) -> void:
	stalk.price = int(data.get("price", stalk.price))
	stalk.last_yearly_change = int(data.get("last_yearly_change", 0))
	stalk.is_bankrupt = bool(data.get("is_bankrupt", false))
	stalk.did_split = bool(data.get("did_split", false))


## Applies one player entry, in full. The mirror of `encode_player`, field for
## field; a snapshot carries every player's whole position, so nothing here has
## to decide whether a field was withheld.
static func apply_player(player: PlayerState, data: Dictionary) -> void:
	player.id = StringName(data.get("id", ""))
	player.display_name = String(data.get("display_name", ""))
	player.steam_id = int(data.get("steam_id", 0))
	player.net_worth = int(data.get("net_worth", 0))
	player.is_bankrupt = bool(data.get("is_bankrupt", false))
	player.is_ready = bool(data.get("is_ready", false))
	player.is_away = bool(data.get("is_away", false))
	player.cash = int(data.get("cash", 0))

	player.holdings.clear()
	var holdings: Dictionary = data.get("holdings", {})
	for key: Variant in holdings:
		player.set_shares(StringName(key), int(holdings[key]))

	player.loan = decode_loan(data.get("loan"))


## How far the random stream had run when this snapshot was taken.
##
## Kept out of `apply_state`, which writes into a GameState and has nowhere to
## put this: the random generator belongs to the authority, and only a client
## that is becoming one has any use for the number.
static func rng_state_of(data: Dictionary) -> int:
	return int(data.get("rng_state", 0))


static func decode_loan(data: Variant) -> LoanState:
	if data == null or not data is Dictionary:
		return null
	var entry: Dictionary = data
	var loan: LoanState = LoanState.new()
	loan.balance = int(entry.get("balance", 0))
	loan.min_payment = int(entry.get("min_payment", 0))
	loan.years_remaining = int(entry.get("years_remaining", 0))
	loan.missed_payments = int(entry.get("missed_payments", 0))
	loan.paid_this_year = bool(entry.get("paid_this_year", false))
	loan.is_paid_off = bool(entry.get("is_paid_off", false))
	loan.is_defaulted = bool(entry.get("is_defaulted", false))
	return loan


# ------------------------------------------------------------------- year result
#
# Broadcast alongside the snapshot after a year advance. The snapshot says where
# things stand; this says what happened, which is what the UI animates from.

# ------------------------------------------------------------- the whole record
#
# The year-by-year history, sent once when a player is welcomed.
#
# **Not part of a snapshot, deliberately.** A snapshot goes out on every trade;
# the history only changes when a year resolves and only matters to somebody
# who was not there for it. Putting it in `encode_state` would send the whole
# match's past every time anybody bought a share.
#
# A client otherwise builds its history from the year broadcasts it was present
# for, which is fine for a player who was there from the start and wrong for
# everybody else: a rejoining player, and - less obviously - every client that
# reconnects after a host migration. Both are welcomed, so both are fixed by
# the same thing. See docs/decisions.md D118.

## Every year so far, in order.
static func encode_history(state: GameState) -> Array:
	var years: Array = []
	for result: YearResult in state.history:
		years.append(encode_year_result(result, state))
	return years


## Replaces a replica's history with the host's, wholesale. Returns a reason if
## the record could not be used, or an empty string.
##
## Wholesale rather than appended, because the receiver may hold years it was
## present for and the host's record is the one that is right.
##
## **A StalkleHeads record is replayed, year by year, from year 0.** Each year
## arrives as its inputs (`MarketSync`), and what it did is rebuilt on a fresh
## year-0 match moved through every year in turn - so the replica's history is
## the host's, ledgers and all, from a payload a fraction of the size. Call this
## after `apply_state`, which sets the settings the fresh match is built from.
static func apply_history(state: GameState, data: Array, library: ContentLibrary) -> String:
	state.history.clear()
	var replay: GameState = null
	for entry: Variant in data:
		if not entry is Dictionary:
			continue
		var year_data: Dictionary = entry
		if not year_data.has("inputs"):
			state.history.append(decode_year_result(year_data, library))
			continue
		if replay == null:
			replay = MatchSetup.new_game_state(state.settings, library)
		var result: YearResult = decode_year(year_data, library, replay)
		if result == null:
			state.history.clear()
			return MarketSync.MALFORMED
		state.history.append(result)
	return ""


## A year as a client receives it live, decoded **before** its snapshot is
## applied: a StalkleHeads year is replayed from the market as the replica
## holds it before the year, and that is gone once the snapshot lands. A base
## year does not care. Null if a StalkleHeads record could not be used.
static func decode_live_year(
	state: GameState,
	data: Dictionary,
	library: ContentLibrary,
) -> YearResult:
	if not data.has("inputs"):
		return decode_year_result(data, library)
	if state.market == null:
		return null
	return decode_year(data, library, EarningsMarket.replay_state(state))


## A StalkleHeads year from its record, replayed on `replay` (see
## `MarketSync.decode_year_into`). Null if the record could not be used.
static func decode_year(data: Dictionary, library: ContentLibrary, replay: GameState) -> YearResult:
	if replay == null or replay.market == null:
		return null
	var result: EarningsYearResult = EarningsYearResult.new()
	_decode_into(result, data, library)
	if not MarketSync.decode_year_into(result, data, library, replay).is_empty():
		return null
	return result


## One year for the wire. `state` is the match the year belongs to; a
## StalkleHeads year needs it, to know the order its packed rows are in, and a
## base-game year ignores it and is encoded exactly as it always was.
static func encode_year_result(result: YearResult, state: GameState = null) -> Dictionary:
	var stalk_changes: Array[Dictionary] = []
	for change: StalkYearChange in result.stalk_changes:
		stalk_changes.append({
			"stalk_id": String(change.stalk_id),
			"price_before": change.price_before,
			"base_delta": change.base_delta,
			"event_delta": change.event_delta,
			"did_split": change.did_split,
			"went_bankrupt": change.went_bankrupt,
			"price_after": change.price_after,
		})

	var loan_changes: Array[Dictionary] = []
	for change: LoanYearChange in result.loan_changes:
		loan_changes.append({
			"player_id": String(change.player_id),
			"balance_before": change.balance_before,
			"paid_during_year": change.paid_during_year,
			"missed_payments": change.missed_payments,
			"penalty_added": change.penalty_added,
			"interest_added": change.interest_added,
			"balance_after": change.balance_after,
			"min_payment_after": change.min_payment_after,
			"defaulted": change.defaulted,
		})

	var data: Dictionary = {
		"year": result.year,
		"mood": int(result.mood),
		# Only the id: the client loads the same event content and takes the
		# flavour text from its own copy.
		"event_id": String(result.event.id) if result.event != null else "",
		"stalk_changes": stalk_changes,
		"dividends": _ids_to_ints(result.dividends),
		"loan_changes": loan_changes,
		"net_worths": _ids_to_ints(result.net_worths),
		"rankings": _ids_to_strings(result.rankings),
		"winners": _ids_to_strings(result.winners),
		"is_final_year": result.is_final_year,
	}
	# A StalkleHeads year goes as its inputs instead of its outcome (D178).
	if result is EarningsYearResult and state != null and state.market != null:
		MarketSync.encode_year_into(data, result as EarningsYearResult, state)
	return data


static func decode_year_result(data: Dictionary, library: ContentLibrary) -> YearResult:
	var result: YearResult = YearResult.new()
	_decode_into(result, data, library)
	return result


## Everything a year record says about itself and its players, into `result`.
## A StalkleHeads record has no row changes or mood here; its replay adds them.
static func _decode_into(result: YearResult, data: Dictionary, library: ContentLibrary) -> void:
	result.year = int(data.get("year", 0))
	result.mood = int(data.get("mood", MarketMood.Value.BULL)) as MarketMood.Value
	result.is_final_year = bool(data.get("is_final_year", false))

	var event_id: StringName = StringName(data.get("event_id", ""))
	if not event_id.is_empty():
		result.event = library.event_by_id(event_id)

	for entry: Dictionary in data.get("stalk_changes", []) as Array:
		var change: StalkYearChange = StalkYearChange.new()
		change.stalk_id = StringName(entry.get("stalk_id", ""))
		change.price_before = int(entry.get("price_before", 0))
		change.base_delta = int(entry.get("base_delta", 0))
		change.event_delta = int(entry.get("event_delta", 0))
		change.did_split = bool(entry.get("did_split", false))
		change.went_bankrupt = bool(entry.get("went_bankrupt", false))
		change.price_after = int(entry.get("price_after", 0))
		result.stalk_changes.append(change)

	for entry: Dictionary in data.get("loan_changes", []) as Array:
		var change: LoanYearChange = LoanYearChange.new()
		change.player_id = StringName(entry.get("player_id", ""))
		change.balance_before = int(entry.get("balance_before", 0))
		change.paid_during_year = bool(entry.get("paid_during_year", false))
		change.missed_payments = int(entry.get("missed_payments", 0))
		change.penalty_added = int(entry.get("penalty_added", 0))
		change.interest_added = int(entry.get("interest_added", 0))
		change.balance_after = int(entry.get("balance_after", 0))
		change.min_payment_after = int(entry.get("min_payment_after", 0))
		change.defaulted = bool(entry.get("defaulted", false))
		result.loan_changes.append(change)

	result.dividends = _to_id_int_dictionary(data.get("dividends", {}))
	result.net_worths = _to_id_int_dictionary(data.get("net_worths", {}))
	result.rankings = _to_id_array(data.get("rankings", []))
	result.winners = _to_id_array(data.get("winners", []))


# ------------------------------------------------------------------------ helpers
#
# StringName keys and typed arrays do not survive the wire as themselves, so each
# conversion is explicit in both directions.

static func _ids_to_ints(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: StringName in source:
		out[String(key)] = int(source[key])
	return out


static func _ids_to_strings(source: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for id: StringName in source:
		out.append(String(id))
	return out


static func _to_id_int_dictionary(source: Variant) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if source is Dictionary:
		var entries: Dictionary = source
		for key: Variant in entries:
			out[StringName(key)] = int(entries[key])
	return out


static func _to_id_array(source: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if source is Array or source is PackedStringArray:
		for value: Variant in source:
			out.append(StringName(value))
	return out
