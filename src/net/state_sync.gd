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
## ten stalks; a full redacted snapshot is well under a kilobyte and arrives a
## handful of times per year. Delta encoding would buy nothing and could drift out
## of sync. See docs/decisions.md D42.
##
## **Definitions are not sent.** Both sides load the same `.tres` content, so only
## ids travel and the receiver looks the definition up locally. A client that
## cannot resolve an id is running different content from the host, which is worth
## failing loudly over rather than papering over.


# ---------------------------------------------------------------------- the view
#
# What one player is allowed to see. See docs/architecture.md §5.3.

## Fields every player may see about every other player.
##
## Net worth is public because the rankings board shows it — that is the whole
## point of the board. Cash and holdings are not, because knowing exactly what a
## rival holds would change how the game is played.
const PUBLIC_PLAYER_FIELDS: PackedStringArray = [
	"id", "display_name", "net_worth", "is_bankrupt", "is_ready", "has_loan",
]


## Encodes the whole match as `for_player_id` is allowed to see it.
##
## Pass an empty id to encode nothing privately — useful for tests asserting that
## redaction happens at all.
static func encode_state(state: GameState, for_player_id: StringName) -> Dictionary:
	var players: Array[Dictionary] = []
	for player: PlayerState in state.players:
		players.append(encode_player(player, player.id == for_player_id))

	var stalks: Array[Dictionary] = []
	for stalk: StalkState in state.stalks:
		stalks.append(encode_stalk(stalk))

	return {
		"year": state.year,
		"is_over": state.is_over,
		# Public: everybody's button depends on it.
		"yeehaw_requested_by": String(state.yeehaw_requested_by),
		"stalks": stalks,
		"players": players,
		"settings": encode_settings(state.settings),
	}


## The private half of a player's state is included only when `is_own` is true.
## Everything else gets the public fields and nothing more.
static func encode_player(player: PlayerState, is_own: bool) -> Dictionary:
	var data: Dictionary = {
		"id": String(player.id),
		"display_name": player.display_name,
		"net_worth": player.net_worth,
		"is_bankrupt": player.is_bankrupt,
		"is_ready": player.is_ready,
		# Whether somebody has a loan at all is public — net worth already shows
		# its effect, and the original's rankings row showed a loan marker. The
		# balance and payment schedule are not.
		"has_loan": player.loan != null,
	}
	if not is_own:
		return data

	var holdings: Dictionary = {}
	for stalk_id: StringName in player.holdings:
		holdings[String(stalk_id)] = player.holdings[stalk_id]

	data["cash"] = player.cash
	data["holdings"] = holdings
	data["loan"] = encode_loan(player.loan)
	return data


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
		"starting_cash": settings.starting_cash,
		"max_years": settings.max_years,
		"loans_enabled": settings.loans_enabled,
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
	apply_settings(state, data.get("settings", {}))

	var stalk_data: Array = data["stalks"]
	for entry: Dictionary in stalk_data:
		var stalk_id: StringName = StringName(entry.get("id", ""))
		var stalk: StalkState = state.stalk_by_id(stalk_id)
		if stalk == null:
			# The host knows about a stalk this build does not. Mismatched
			# content, and silently rendering a short board would be worse than
			# saying so.
			var definition: StalkDefinition = library.stalk_by_id(stalk_id)
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

	return ""


static func apply_settings(state: GameState, data: Dictionary) -> void:
	if data.is_empty():
		return
	if state.settings == null:
		state.settings = GameSettings.new()
	state.settings.game_name = String(data.get("game_name", state.settings.game_name))
	state.settings.starting_cash = int(data.get("starting_cash", state.settings.starting_cash))
	state.settings.max_years = int(data.get("max_years", state.settings.max_years))
	state.settings.loans_enabled = bool(data.get("loans_enabled", state.settings.loans_enabled))
	state.settings.rng_seed = int(data.get("rng_seed", state.settings.rng_seed))


static func apply_stalk(stalk: StalkState, data: Dictionary) -> void:
	stalk.price = int(data.get("price", stalk.price))
	stalk.last_yearly_change = int(data.get("last_yearly_change", 0))
	stalk.is_bankrupt = bool(data.get("is_bankrupt", false))
	stalk.did_split = bool(data.get("did_split", false))


## Applies one player entry. A redacted entry carries no `cash` key, and the
## replica's own fields are left untouched rather than zeroed — a client holds
## real values only for itself, and zeroing would make a rival look broke.
static func apply_player(player: PlayerState, data: Dictionary) -> void:
	player.id = StringName(data.get("id", ""))
	player.display_name = String(data.get("display_name", ""))
	player.net_worth = int(data.get("net_worth", 0))
	player.is_bankrupt = bool(data.get("is_bankrupt", false))
	player.is_ready = bool(data.get("is_ready", false))

	if not data.has("cash"):
		return

	player.cash = int(data["cash"])
	player.holdings.clear()
	var holdings: Dictionary = data.get("holdings", {})
	for key: Variant in holdings:
		player.set_shares(StringName(key), int(holdings[key]))
	player.loan = decode_loan(data.get("loan"))


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

static func encode_year_result(result: YearResult) -> Dictionary:
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

	return {
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


static func decode_year_result(data: Dictionary, library: ContentLibrary) -> YearResult:
	var result: YearResult = YearResult.new()
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
	return result


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
