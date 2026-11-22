extends SceneTree
## Measures what a match costs on the wire, in bytes, for both game modes: the
## per-trade snapshot, the year packet, and the welcome a rejoining player is
## sent. Written for StalkleHeads phase S6, to replace the estimates in
## docs/stalkleheads-design.md §9.2 with measurements (decisions.md D178).
##
##     <godot> --headless --script res://tools/wire_report.gd
##
## **How it measures.** Every figure is `var_to_bytes(...).size()` of exactly
## what the host passes to the RPC - `StateSync.encode_state`, `encode_year_
## result` and `encode_history`, the same calls `HostSession` makes. That is
## Godot's own Variant encoding, the one an RPC's arguments go through, so the
## figures are the payload; the RPC adds a few bytes of header of its own, which
## are not counted.
##
## **The matches.** Seeded, played by `WireMatch`'s scripted players (tests/
## fixtures/wire_match.gd), with every player also carrying a loan every year
## they can, because loans are the largest per-player part of a year record.
## Ten players, the maximum, is the heavy case.
##
## **The dictionary column** is what the design's estimate assumed StalkleHeads
## would cost if it were sent the way the base game sends a year: every row
## change, every company's fundamentals and readouts, the ledgers and the desk
## as dictionaries keyed by name. It is built here and measured, not guessed,
## so the saving the packed format claims is a measured one too.


const SEED: int = 4242


func _init() -> void:
	var lines: PackedStringArray = []
	lines.append("Wire payloads, bytes (var_to_bytes of what the host sends). Seed %d." % SEED)
	lines.append("")
	for players: int in [1, 4, 10]:
		lines.append_array(_report(players))
		lines.append("")
	print("\n".join(lines))
	quit()


func _report(players: int) -> PackedStringArray:
	var out: PackedStringArray = ["== %d player%s" % [players, "" if players == 1 else "s"]]
	var base: MatchAuthority = _authority(GameMode.Value.BASE, players)
	var earnings: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS, players)

	var rows: Array[Array] = []
	var base_year: int = 0
	var earnings_year: int = 0
	var naive_year: int = 0
	for year: int in 99:
		var base_result: YearResult = _play_year(base)
		var earnings_result: YearResult = _play_year(earnings)
		base_year = maxi(base_year, _size(StateSync.encode_year_result(base_result, base.state)))
		earnings_year = maxi(
			earnings_year, _size(StateSync.encode_year_result(earnings_result, earnings.state))
		)
		naive_year = maxi(naive_year, _size(_naive_year(earnings_result, earnings.state)))
		if year + 1 in [1, 10, 99]:
			rows.append([year + 1, base, earnings])
			rows.back().append_array([
				_size(StateSync.encode_state(base.state, 0)),
				_size(StateSync.encode_state(earnings.state, 0)),
				_size(_naive_snapshot(earnings.state)),
				_size(StateSync.encode_history(base.state)),
				_size(StateSync.encode_history(earnings.state)),
				_size(_naive_history(earnings.state)),
				_size(StateSync.encode_state(earnings.state, 0)["market"]),
				_size(StateSync.encode_state(earnings.state, 0)["market"]["desk"]),
			])

	out.append("%-6s | %-23s | %-31s | %s" % ["", "snapshot (every trade)", "welcome history", "StalkleHeads snapshot parts"])
	out.append("%-6s | %7s %7s %7s | %9s %10s %10s | %7s %7s" % [
		"year", "base", "S.Heads", "dicts", "base", "S.Heads", "dicts", "market", "desk",
	])
	for row: Array in rows:
		out.append("%-6d | %7d %7d %7d | %9d %10d %10d | %7d %7d" % [
			row[0], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10],
		])
	out.append("largest year packet: base %d, StalkleHeads %d, dicts %d" % [
		base_year, earnings_year, naive_year,
	])

	var history: Array = StateSync.encode_history(earnings.state)
	var inputs_bytes: int = 0
	for entry: Dictionary in history:
		inputs_bytes += _size(entry["inputs"])
	out.append("StalkleHeads history at %d years: market inputs %d (%d a year), the rest (players, event, keys) %d" % [
		history.size(), inputs_bytes, inputs_bytes / maxi(history.size(), 1),
		_size(history) - inputs_bytes,
	])
	var desk: Variant = StateSync.encode_state(earnings.state, 0)["market"]["desk"]
	out.append("desk block at year %d is %s" % [earnings.state.year, type_string(typeof(desk))])
	var started: int = Time.get_ticks_usec()
	var replica: GameState = GameState.new(GameSettings.new())
	StateSync.apply_state(replica, StateSync.encode_state(earnings.state, 0), ContentLibrary.load_from())
	StateSync.apply_history(replica, history, MatchSetup.load_library(GameMode.Value.STALKLEHEADS))
	out.append("welcome replay of %d years on a client: %.0f ms" % [
		history.size(), float(Time.get_ticks_usec() - started) / 1000.0,
	])
	return out


func _authority(mode: GameMode.Value, players: int) -> MatchAuthority:
	var settings: GameSettings = GameSettings.new()
	settings.mode = mode
	settings.rng_seed = SEED
	settings.max_years = 99
	settings.loans_enabled = true
	var names: Array[String] = []
	for index: int in players:
		names.append("Player %d" % index)
	return LocalSession.build_authority(settings, MatchSetup.load_library(mode), names)


## A year of the scripted trading, every player borrowing when they can.
func _play_year(on: MatchAuthority) -> YearResult:
	WireMatch.trade(on)
	for player: PlayerState in on.state.players:
		if player.loan == null or player.loan.is_paid_off:
			on.take_loan(player.id, 1000)
		on.set_ready(player.id, true)
	var result: YearResult = on.advance_year()
	for player: PlayerState in on.state.players:
		on.set_ready(player.id, false)
	return result


func _size(value: Variant) -> int:
	return var_to_bytes(value).size()


# ------------------------------------------- the dictionary encoding, built

func _naive_snapshot(state: GameState) -> Dictionary:
	var data: Dictionary = StateSync.encode_state(state, 0)
	data.erase("market")
	var companies: Array[Dictionary] = []
	for company: CompanyState in state.market.companies:
		companies.append(_company(company))
	var industries: Dictionary = {}
	for industry: IndustryState in state.market.industries:
		industries[String(industry.id)] = {"performance": industry.performance, "roll": industry.roll}
	var desk: Array[Dictionary] = []
	for trader: NpcTraderState in state.market.desk.traders:
		var holdings: Dictionary = {}
		for stalk_id: StringName in trader.holdings:
			holdings[String(stalk_id)] = trader.holdings[stalk_id]
		var shorts: Dictionary = {}
		for stalk_id: StringName in trader.shorts:
			shorts[String(stalk_id)] = trader.shorts[stalk_id]
		desk.append({"id": String(trader.id), "cash": trader.cash, "holdings": holdings, "shorts": shorts})
	data["market"] = {
		"sentiment": state.market.sentiment,
		"index_level": state.market.index_level,
		"last_mood": int(state.market.last_mood),
		"companies": companies,
		"industries": industries,
		"desk": desk,
	}
	return data


func _naive_history(state: GameState) -> Array:
	var years: Array = []
	for result: YearResult in state.history:
		years.append(_naive_year(result, state))
	return years


func _naive_year(result: YearResult, _state: GameState) -> Dictionary:
	var data: Dictionary = StateSync.encode_year_result(result)
	var earnings: EarningsYearResult = result
	var ledgers: Dictionary = {}
	for company_id: StringName in earnings.ledgers:
		var ledger: PriceLedger = earnings.ledgers[company_id]
		ledgers[String(company_id)] = {
			"earnings": ledger.earnings, "sentiment": ledger.sentiment,
			"industry_standing": ledger.industry_standing, "regime_premium": ledger.regime_premium,
			"valuation_limits": ledger.valuation_limits, "this_years_event": ledger.this_years_event,
			"last_years_event_faded": ledger.last_years_event_faded, "flow": ledger.flow,
		}
	var industries: Dictionary = {}
	for industry_id: StringName in earnings.industry_performance:
		industries[String(industry_id)] = earnings.industry_performance[industry_id]
	var per_share: Dictionary = {}
	for stalk_id: StringName in earnings.dividend_per_share:
		per_share[String(stalk_id)] = earnings.dividend_per_share[stalk_id]
	var desk: Dictionary = {}
	if earnings.desk != null:
		for trader_id: StringName in earnings.desk.trader_ids:
			desk[String(trader_id)] = {
				"appetite": earnings.desk.appetites[trader_id],
				"target": String(earnings.desk.targets[trader_id]),
				"action": int(earnings.desk.actions[trader_id]),
			}
	data["ledgers"] = ledgers
	data["industry_performance"] = industries
	data["dividend_per_share"] = per_share
	data["desk"] = desk
	data["index_move_percent"] = earnings.index_move_percent
	return data


## A company as the design's estimate pictured it: inputs and readouts alike.
func _company(company: CompanyState) -> Dictionary:
	return {
		"id": String(company.id), "revenue": company.revenue, "margin": company.margin_percent,
		"profit": company.profit, "shares": company.shares_outstanding,
		"regime": int(company.regime), "years_in_regime": company.years_in_regime,
		"eps": company.earnings_per_share(), "multiple": company.multiple,
		"fair_value": company.fair_value, "event_carry": company.event_carry,
		"flow": company.flow, "price": company.price,
	}
