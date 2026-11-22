class_name MarketSync
extends RefCounted
## The StalkleHeads half of the wire: a match's market in the snapshot, and a
## year as its inputs. `StateSync` calls this; nothing else does. A base-game
## match has no market, so nothing here is ever reached and the base game's
## wire is exactly what it was (docs/stalkleheads-design.md §9, decisions.md
## D176-D178).
##
## All static, all pure, built-in types only, for the reasons at the top of
## `state_sync.gd`.
##
## **Inputs travel, readouts are derived (design §9.1).** The two halves apply
## that rule differently, because they are answering different questions.
##
## - **The snapshot** carries the market's *state*: every number the next year
##   or the desk reads that cannot be worked out from the others - revenue,
##   margin, shares, regime, event carry, flow, every NPC trader's book, the
##   flow input, the event bags. It does not carry profit, the multiple, fair
##   value or anything else `CompanyState.derive_readouts` rebuilds. It must be
##   enough on its own for a client to take the match over (D105).
## - **The year record** carries only the year's *draws* - the industry rolls,
##   each company's regime and growth roll, the net shares its price read, the
##   squeeze and the event - plus what the desk did. A client replays the year
##   from the market before it (`EarningsYearResolver.replay_year`), and every
##   price change, ledger, index move, mood and dividend comes out of that.
##
## **Packed rows, not dictionaries (design §9.2).** A dictionary pays for its
## key strings every time it is sent. Here each block is a packed array in a
## fixed field order, and position says what a number is: the third company is
## the third in `EarningsMarket.companies`, the fifth board row is the fifth in
## the snapshot's `stalks`. That only works if both ends hold the same content
## in the same order, so every snapshot carries `content_key` and a client
## whose own key differs refuses it, as `apply_state` refuses an unknown stalk.
##
## Integers go as `PackedInt32Array`, 4 bytes each, unless one of them does not
## fit, in which case that one block goes as `PackedInt64Array` (`_pack`).
## Ratios go as `PackedFloat64Array`: they are `float` in `sim` (decisions.md
## D130), and 64 bits is the only width that arrives as the same number.


## What the market block holds, per company, as reals and as integers. **The
## order is the wire format**: change it and old and new builds disagree about
## what every number means. `test_wire.gd` pins both widths.
const COMPANY_REALS: int = 6   # revenue, margin_percent, profit_before_season, revenue_growth_percent, event_carry, flow
const COMPANY_INTS: int = 7    # shares_outstanding, regime, years_in_regime, growth_roll, event_delta, price, did_split
const MARKET_REALS: int = 3    # sentiment, sentiment_used, index_level

## A year record's integers per company: regime, growth roll, net shares priced.
const YEAR_COMPANY_INTS: int = 3

## A year record's integers per NPC trader: appetite, target row, action.
const YEAR_TRADER_INTS: int = 3

## A refused snapshot says this, in the same words whatever was wrong with it.
const MISMATCH: String = "The host's StalkleHeads content is not this build's — host is running different content."
const MALFORMED: String = "Malformed StalkleHeads market."


# ------------------------------------------------------------- the snapshot

## The market block of a snapshot. `state.market` must be set.
static func encode_market(state: GameState) -> Dictionary:
	var market: EarningsMarket = state.market
	var reals: PackedFloat64Array = [market.sentiment, market.sentiment_used, market.index_level]
	var company_ints: Array[int] = []
	for company: CompanyState in market.companies:
		reals.append_array([
			company.revenue, company.margin_percent, company.profit_before_season,
			company.revenue_growth_percent, company.event_carry, company.flow,
		])
		company_ints.append_array([
			company.shares_outstanding, int(company.regime), company.years_in_regime,
			company.growth_roll, company.event_delta, company.price, int(company.did_split),
		])
	var industry_rolls: Array[int] = []
	for industry: IndustryState in market.industries:
		reals.append(industry.performance)
		industry_rolls.append(industry.roll)

	var flow: Array[int] = []
	for row: StalkState in state.stalks:
		flow.append(market.net_shares_traded.get(row.id, 0))

	return {
		"content": market.content_key,
		"mood": int(market.last_mood),
		"reals": reals,
		"companies": _pack(company_ints),
		"industries": _pack(industry_rolls),
		"flow": _pack(flow),
		"bags": _encode_bags(market.event_bags),
		"desk": _pack(_encode_desk(market.desk, state)),
	}


## Applies a market block onto `state`, whose board (`state.stalks`) the same
## snapshot has already set. Builds the market from `library` if the replica
## has none. Returns a reason if it could not be applied, or an empty string.
static func apply_market(state: GameState, data: Dictionary, library: ContentLibrary) -> String:
	if state.market == null:
		state.market = EarningsMarket.from_library(library)
	var market: EarningsMarket = state.market
	if int(data.get("content", 0)) != market.content_key:
		return MISMATCH

	var reals: PackedFloat64Array = _reals(data.get("reals"))
	var company_ints: PackedInt64Array = _ints(data.get("companies"))
	var industry_rolls: PackedInt64Array = _ints(data.get("industries"))
	var flow: PackedInt64Array = _ints(data.get("flow"))
	var companies: int = market.companies.size()
	var industries: int = market.industries.size()
	var sizes_match: bool = reals.size() == MARKET_REALS + companies * COMPANY_REALS + industries
	sizes_match = sizes_match and company_ints.size() == companies * COMPANY_INTS
	sizes_match = sizes_match and industry_rolls.size() == industries
	sizes_match = sizes_match and flow.size() == state.stalks.size()
	if not sizes_match:
		return MALFORMED

	market.sentiment = reals[0]
	market.sentiment_used = reals[1]
	market.index_level = reals[2]
	market.last_mood = MarketMood.Value.BEAR
	if int(data.get("mood", 0)) == int(MarketMood.Value.BULL):
		market.last_mood = MarketMood.Value.BULL

	for index: int in industries:
		var industry: IndustryState = market.industries[index]
		industry.performance = reals[MARKET_REALS + companies * COMPANY_REALS + index]
		industry.roll = int(industry_rolls[index])

	for index: int in companies:
		if state.year == 0:
			# A company that has had no earnings season is its profile's, as
			# the host built it; nothing about it is derived (see below).
			market.companies[index] = CompanyState.new(market.companies[index].profile)
		var company: CompanyState = market.companies[index]
		var at: int = MARKET_REALS + index * COMPANY_REALS
		company.revenue = reals[at]
		company.margin_percent = reals[at + 1]
		company.profit_before_season = reals[at + 2]
		company.revenue_growth_percent = reals[at + 3]
		company.event_carry = reals[at + 4]
		company.flow = reals[at + 5]
		at = index * COMPANY_INTS
		company.shares_outstanding = int(company_ints[at])
		company.regime = EarningsRegime.Value.STEADY
		var regime: int = int(company_ints[at + 1])
		if regime >= 0 and regime < EarningsRegime.ALL.size():
			company.regime = EarningsRegime.ALL[regime]
		company.years_in_regime = int(company_ints[at + 2])
		company.growth_roll = int(company_ints[at + 3])
		company.event_delta = int(company_ints[at + 4])
		company.price = int(company_ints[at + 5])
		company.did_split = company_ints[at + 6] != 0
		if state.year > 0:
			var row: StalkState = state.stalk_by_id(company.id)
			company.derive_readouts(
				market.sentiment_used,
				market.performance_of(company),
				row == null or row.is_bankrupt,
			)

	market.net_shares_traded = {}
	for index: int in state.stalks.size():
		if flow[index] != 0:
			market.net_shares_traded[state.stalks[index].id] = int(flow[index])

	var bags: Variant = _decode_bags(_ints(data.get("bags")))
	if bags == null:
		return MALFORMED
	market.event_bags = bags
	if not _apply_desk(market.desk, _ints(data.get("desk")), state):
		return MALFORMED
	return ""


## Every trader's book: `[cash, holdings, (row, shares) x holdings, shorts,
## (company, shares) x shorts]`, traders in the desk's sorted order. Sparse,
## because a trader holds one thing at a time and almost nothing is short: a
## dense row per board stalk would be twenty numbers to say one.
static func _encode_desk(desk: NpcDesk, state: GameState) -> Array[int]:
	var out: Array[int] = []
	var row_of: Dictionary[StringName, int] = _row_positions(state)
	var company_of: Dictionary[StringName, int] = _company_positions(state.market)
	for trader: NpcTraderState in desk.traders:
		out.append(trader.cash)
		var held: Array[StringName] = trader.held_ids()
		out.append(held.size())
		for stalk_id: StringName in held:
			out.append_array([row_of.get(stalk_id, -1), trader.shares_of(stalk_id)])
		var shorted: Array[StringName] = trader.shorted_ids()
		out.append(shorted.size())
		for company_id: StringName in shorted:
			out.append_array([company_of.get(company_id, -1), trader.short_of(company_id)])
	return out


static func _apply_desk(desk: NpcDesk, data: PackedInt64Array, state: GameState) -> bool:
	var reader: IntReader = IntReader.new(data)
	var companies: Array[CompanyState] = state.market.companies
	for trader: NpcTraderState in desk.traders:
		trader.cash = reader.next()
		trader.holdings.clear()
		for _held: int in reader.count(state.stalks.size()):
			var row: int = reader.position(state.stalks.size())
			var shares: int = reader.next()
			if reader.ok:
				trader.set_shares(state.stalks[row].id, shares)
		trader.shorts.clear()
		for _shorted: int in reader.count(companies.size()):
			var company: int = reader.position(companies.size())
			var shares: int = reader.next()
			if reader.ok:
				trader.set_short(companies[company].id, shares)
	return reader.ok and reader.is_done()


## `[bull count, bull positions..., bear count, bear positions...]`, or nothing
## before the first event has been drawn.
static func _encode_bags(bags: Dictionary[int, PackedInt32Array]) -> PackedInt32Array:
	var out: PackedInt32Array = []
	if bags.is_empty():
		return out
	for mood: int in [MarketMood.Value.BULL, MarketMood.Value.BEAR]:
		var positions: PackedInt32Array = bags.get(mood, PackedInt32Array())
		out.append(positions.size())
		out.append_array(positions)
	return out


## The bags back as a dictionary, or null if the block is malformed. Positions
## are not checked against the pool here; `EventPool.restore_bags` drops any
## that are out of range, and `content_key` has already said the pool matches.
static func _decode_bags(data: PackedInt64Array) -> Variant:
	var bags: Dictionary[int, PackedInt32Array] = {}
	if data.is_empty():
		return bags
	var reader: IntReader = IntReader.new(data)
	for mood: int in [MarketMood.Value.BULL, MarketMood.Value.BEAR]:
		var positions: PackedInt32Array = []
		for _entry: int in reader.count(data.size()):
			positions.append(reader.next())
		bags[mood] = positions
	if not reader.ok or not reader.is_done():
		return null
	return bags


# ------------------------------------------------------------ the year record

## Adds a StalkleHeads year's inputs to `data`, the year as `StateSync` encoded
## it, and removes what the inputs determine: every row's change and the mood.
## What stays is what the market cannot rebuild - the event's id and the
## players' part (dividends, loans, net worths, standings), as the base game
## sends them.
##
## The inputs, one packed block in this order (D178):
##
## | Block | Integers |
## |---|---|
## | industries | count, then each industry's roll |
## | companies | count, then per company: regime, growth roll, net shares priced (`YEAR_COMPANY_INTS`); zeros for a company already bankrupt |
## | squeeze | the roll, 1 if it fired, the flagged count, each flagged company's position |
## | desk | trader count, then per trader: appetite, target row (-1 for none), action (`YEAR_TRADER_INTS`) |
## | desk flow | count, then (row, net shares) for each row the desk traded |
static func encode_year_into(data: Dictionary, result: EarningsYearResult, state: GameState) -> void:
	data.erase("stalk_changes")
	data.erase("mood")
	var market: EarningsMarket = state.market
	var row_of: Dictionary[StringName, int] = _row_positions(state)
	var company_of: Dictionary[StringName, int] = _company_positions(market)
	var out: Array[int] = []

	out.append(market.industries.size())
	for industry: IndustryState in market.industries:
		out.append(result.industry_rolls.get(industry.id, 0))

	out.append(market.companies.size())
	for company: CompanyState in market.companies:
		out.append_array([
			int(result.regimes.get(company.id, 0)),
			result.growth_rolls.get(company.id, 0),
			result.net_shares_priced.get(company.id, 0),
		])

	out.append_array([result.squeeze_roll, int(result.squeezed), result.short_interest_flagged.size()])
	for company_id: StringName in result.short_interest_flagged:
		out.append(company_of.get(company_id, -1))

	var desk: NpcDeskYear = result.desk
	if desk == null:
		desk = NpcDeskYear.new()
	out.append(desk.trader_ids.size())
	for trader_id: StringName in desk.trader_ids:
		var target: StringName = desk.targets.get(trader_id, &"")
		out.append_array([
			desk.appetites.get(trader_id, 0),
			row_of.get(target, -1),
			int(desk.actions.get(trader_id, NpcTraderDefinition.Situation.HELD)),
		])
	var traded: Array[StringName] = []
	for stalk_id: StringName in desk.net_shares:
		traded.append(stalk_id)
	traded.sort_custom(_by_row.bind(row_of))
	out.append(traded.size())
	for stalk_id: StringName in traded:
		out.append_array([row_of.get(stalk_id, -1), desk.net_shares[stalk_id]])

	data["inputs"] = _pack(out)


## A StalkleHeads year back from its record, replayed on `replay`: a match
## standing where the host's stood before the year (`EarningsMarket.
## replay_state`, or a fresh year-0 match for the first year of a welcome).
## `replay` is moved on to the end of the year, so a caller rebuilding a whole
## history passes the same one for every year in turn.
##
## `result` already holds the players' part, decoded by `StateSync`. Returns a
## reason if the record could not be used, or an empty string.
static func decode_year_into(
	result: EarningsYearResult,
	data: Dictionary,
	library: ContentLibrary,
	replay: GameState,
) -> String:
	var market: EarningsMarket = replay.market
	var reader: IntReader = IntReader.new(_ints(data.get("inputs")))

	if reader.next() != market.industries.size():
		return MISMATCH
	for industry: IndustryState in market.industries:
		result.industry_rolls[industry.id] = reader.next()

	if reader.next() != market.companies.size():
		return MISMATCH
	for company: CompanyState in market.companies:
		var regime: int = reader.next()
		var roll: int = reader.next()
		var priced: int = reader.next()
		var row: StalkState = replay.stalk_by_id(company.id)
		if row == null or row.is_bankrupt:
			continue
		if regime < 0 or regime >= EarningsRegime.ALL.size():
			return MALFORMED
		result.regimes[company.id] = EarningsRegime.ALL[regime]
		result.growth_rolls[company.id] = roll
		result.net_shares_priced[company.id] = priced

	result.squeeze_roll = reader.next()
	result.squeezed = reader.next() != 0
	for _flagged: int in reader.count(market.companies.size()):
		var position: int = reader.position(market.companies.size())
		if reader.ok:
			result.short_interest_flagged.append(market.companies[position].id)

	var desk: NpcDeskYear = NpcDeskYear.new()
	var trader_ids: Array[StringName] = []
	for trader: NpcTraderState in market.desk.traders:
		trader_ids.append(trader.id)
	if reader.next() != trader_ids.size():
		return MISMATCH
	for trader_id: StringName in trader_ids:
		desk.trader_ids.append(trader_id)
		desk.appetites[trader_id] = reader.next()
		var target: int = reader.next()
		desk.targets[trader_id] = &""
		if target >= 0 and target < replay.stalks.size():
			desk.targets[trader_id] = replay.stalks[target].id
		desk.actions[trader_id] = _situation(reader.next())
	for _traded: int in reader.count(replay.stalks.size()):
		var row: int = reader.position(replay.stalks.size())
		var shares: int = reader.next()
		if reader.ok:
			desk.net_shares[replay.stalks[row].id] = shares
	result.desk = desk

	if not reader.ok or not reader.is_done():
		return MALFORMED

	# The event: the host's squeeze is rebuilt from the template, as the host
	# built it, because it was never authored content to look up.
	var event_id: StringName = StringName(data.get("event_id", ""))
	if result.squeezed and not result.short_interest_flagged.is_empty() and library.short_squeeze != null:
		var squeezed_id: StringName = result.short_interest_flagged[0]
		result.event = ShortInterestRules.squeeze_event(
			library.short_squeeze, squeezed_id, replay.stalk_by_id(squeezed_id).definition.display_name
		)
	elif not event_id.is_empty():
		result.event = library.event_by_id(event_id)

	EarningsYearResolver.new(null).replay_year(replay, result)
	return ""


# ----------------------------------------------------------------- helpers

## Integers as the narrowest packed array that holds them all exactly.
static func _pack(values: Array[int]) -> Variant:
	var fits: bool = true
	for value: int in values:
		if value < -2147483648 or value > 2147483647:
			fits = false
			break
	if fits:
		return PackedInt32Array(values)
	return PackedInt64Array(values)


## A packed integer block as received, or empty for anything else. Accepts
## either width, since `_pack` may have sent either.
static func _ints(source: Variant) -> PackedInt64Array:
	if source is PackedInt32Array:
		var narrow: PackedInt32Array = source
		var wide: PackedInt64Array = []
		wide.resize(narrow.size())
		for index: int in narrow.size():
			wide[index] = narrow[index]
		return wide
	if source is PackedInt64Array:
		return source
	return PackedInt64Array()


## A packed real block as received, or empty. Only 64-bit: a 32-bit array would
## arrive as different numbers, which is worse than refusing it.
static func _reals(source: Variant) -> PackedFloat64Array:
	if source is PackedFloat64Array:
		return source
	return PackedFloat64Array()


static func _row_positions(state: GameState) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for index: int in state.stalks.size():
		out[state.stalks[index].id] = index
	return out


static func _company_positions(market: EarningsMarket) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for index: int in market.companies.size():
		out[market.companies[index].id] = index
	return out


static func _by_row(a: StringName, b: StringName, row_of: Dictionary[StringName, int]) -> bool:
	return row_of.get(a, -1) < row_of.get(b, -1)


static func _situation(value: int) -> NpcTraderDefinition.Situation:
	for situation: NpcTraderDefinition.Situation in NpcTraderDefinition.Situation.values():
		if int(situation) == value:
			return situation
	return NpcTraderDefinition.Situation.HELD


## Reads a packed block front to back, remembering whether it ever ran short or
## met a number out of range, so a decoder can read the whole layout and check
## once at the end instead of after every field.
class IntReader:
	extends RefCounted

	var ok: bool = true
	var _data: PackedInt64Array
	var _at: int = 0

	func _init(data: PackedInt64Array) -> void:
		_data = data

	## The next integer, or 0 once the block has run out.
	func next() -> int:
		if _at >= _data.size():
			ok = false
			return 0
		var value: int = _data[_at]
		_at += 1
		return value

	## A count of entries to follow, which must be between 0 and `limit`. An
	## impossible count reads as none, and marks the block bad.
	func count(limit: int) -> int:
		var value: int = next()
		if value < 0 or value > limit:
			ok = false
			return 0
		return value

	## A position in a list of `size` things. Out of range marks the block bad.
	func position(size: int) -> int:
		var value: int = next()
		if value < 0 or value >= size:
			ok = false
			return 0
		return value

	func is_done() -> bool:
		return _at == _data.size()
