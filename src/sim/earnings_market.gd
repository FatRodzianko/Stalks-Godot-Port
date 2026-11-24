class_name EarningsMarket
extends RefCounted
## Everything a StalkleHeads match knows about its market beyond the board: the
## companies' fundamentals, the industries, last year's sentiment and mood, the
## index level, and the net shares traded that feed next year's flow.
##
## Hangs off `GameState.market`, and is null in a base-game match. The board
## itself is still `GameState.stalks`, one `StalkState` per row, so trading, net
## worth, standings and loans read prices exactly as they do in the base game.
## `EarningsYearResolver` copies each company's price onto its row every time it
## changes. See docs/stalkleheads-design.md §3, §4 and decisions.md D160.
##
## Pure data with lookup helpers and two factories. No nodes, no RNG of its own.


## The two board rows that are not companies. Read from content by id, as the
## base game's resolver reads them, never by display name.
const BOND_ID: StringName = &"berry_bonds"
const INDEX_ID: StringName = &"mutuals"


## Every company, sorted by id, bankrupt or not. A bankrupt company keeps its
## last fundamentals and is never advanced again; its row says BANKRUPT.
var companies: Array[CompanyState] = []

## Every industry, sorted by id.
var industries: Array[IndustryState] = []

## Last year's index move in percent, clamped to +/-20 (§3.1). 0 before year 1.
## This is what this year's multiples and industry rolls lean on.
var sentiment: float = 0.0

## The sentiment the latest year's prices were valued on: what `sentiment` was
## when that year began. 0 before year 1. A readout's input: a client rebuilding
## each company's valuation from the wire needs it, because `sentiment` has
## already moved on to next year's (`CompanyState.derive_readouts`, D176).
var sentiment_used: float = 0.0

## Last year's reported mood. BULL before year 1, so the first year's event is
## drawn from the bull bag (§14 q14).
var last_mood: MarketMood.Value = MarketMood.Value.BULL

## What is left in each mood's event bag, as positions in that mood's pool
## (`EventPool.bag_state`), keyed by mood. Empty until the first event is drawn.
##
## **The bags are the pipeline's, and they are kept here as well** so that they
## travel with the match: a host that takes the match over builds a fresh
## pipeline, and without this it would deal its events from freshly shuffled
## bags - an event the old host had already dealt could come round again, and
## the match would not be the one being played. `EarningsYearResolver` restores
## the pool from this at the start of each year and writes it back after the
## draw (decisions.md D177).
var event_bags: Dictionary[int, PackedInt32Array] = {}

## A fingerprint of the content this market was built from: the companies,
## industries and traders, and every event the pool can deal, in order. Two
## machines build the same market from the same content, so a client compares
## the host's with its own before applying a snapshot that names things only by
## position (`StateSync`, decisions.md D176).
var content_key: int = 0

## My Mutuals and Me Inc.'s level, unrounded. The posted price is `int()` of it
## (decisions.md D157). Starts at the index row's authored starting price.
var index_level: float = 0.0

## **The flow input**, per stalk id: net shares bought (positive) or sold
## (negative) since the last price was set, NPC and player alike (§3.10). The
## next year advance reads the companies' entries into flow, then clears it.
##
## Filled in two places, both through `record_trade`: the NPC desk at the end of
## each year advance (§4 step 13), and players' trades during the trading phase
## that follows, which `MatchAuthority` passes on through
## `EarningsYearResolver.record_trade` (decisions.md D163, D171). The balance
## tool records its players' trades the same way.
var net_shares_traded: Dictionary[StringName, int] = {}

## The NPC desk (§5). Never null; empty if the content has no traders.
var desk: NpcDesk = NpcDesk.new()

## Every news line the match can show (`ContentLibrary.news`), for
## `NewsSelector`. Content, not state: it never changes during a match and is
## not sent - each peer has its own copy from disk (decisions.md D200).
var news: NewsContent = NewsContent.new()

## Next year's earnings draws, made a year early (`KeptDraws`, design §8.4,
## decisions.md D205). Null before the match is opened, after the last year,
## and in a market that is only replaying years. **State**: it travels in the
## snapshot.
var next_draws: KeptDraws = null

## The whispers worked out so far, by the year they were heard at the end of
## (from 1). A cache for `NewsSelector.whispers_for`, never
## sent: every peer works them out for itself from the history and
## `next_draws`.
var whisper_rounds: Dictionary[int, WhisperRound] = {}

var _industry_by_id: Dictionary[StringName, IndustryState] = {}


## The market for a fresh match: every company at year 0 (STEADY, the base
## multiple, no events, no flow), every industry at 0, the index at its row's
## starting price. Needs `library.load_fundamentals()` to have run.
static func from_library(library: ContentLibrary) -> EarningsMarket:
	var market: EarningsMarket = EarningsMarket.new()
	for definition: IndustryDefinition in library.industries:
		var industry: IndustryState = IndustryState.new(definition)
		market.industries.append(industry)
		market._industry_by_id[definition.id] = industry
	for profile: CompanyProfile in library.companies:
		market.companies.append(CompanyState.new(profile))
	market.desk = NpcDesk.from_definitions(library.traders)
	market.news = library.news
	var index_definition: StalkDefinition = library.stalk_by_id(INDEX_ID)
	if index_definition != null:
		market.index_level = float(index_definition.starting_price)
	market.content_key = content_key_of(market, build_event_pool(library))
	return market


## The fingerprint `content_key` holds: every id, in the order the wire uses,
## hashed. Order matters as much as membership, because a packed row means
## "the third company" and both ends must agree on which that is.
static func content_key_of(market: EarningsMarket, pool: EventPool) -> int:
	var parts: PackedStringArray = []
	for company: CompanyState in market.companies:
		parts.append(String(company.id))
	parts.append("|")
	for industry: IndustryState in market.industries:
		parts.append(String(industry.id))
	parts.append("|")
	for trader: NpcTraderState in market.desk.traders:
		parts.append(String(trader.id))
	parts.append("|")
	parts.append_array(pool.event_ids())
	return ",".join(parts).hash()


## A players-less match holding a detached copy of `state`'s board and market,
## for replaying a year on (`EarningsYearResolver.replay_year`). Nothing done to
## the copy reaches `state`. The desk is the same traders at their starting
## books: a replay never runs the desk, it only needs to know who is on it.
static func replay_state(state: GameState) -> GameState:
	var copy: GameState = GameState.new(state.settings)
	copy.year = state.year
	for row: StalkState in state.stalks:
		var twin: StalkState = StalkState.new(row.definition)
		twin.price = row.price
		twin.last_yearly_change = row.last_yearly_change
		twin.is_bankrupt = row.is_bankrupt
		twin.did_split = row.did_split
		copy.stalks.append(twin)
	copy.market = state.market.copy_for_replay()
	return copy


## A detached copy of everything but the traders' books: the desk is the same
## traders, fresh.
func copy_for_replay() -> EarningsMarket:
	var twin: EarningsMarket = EarningsMarket.new()
	var roster: Array[NpcTraderDefinition] = []
	for trader: NpcTraderState in desk.traders:
		roster.append(trader.definition)
	twin.desk = NpcDesk.from_definitions(roster)
	for company: CompanyState in companies:
		twin.companies.append(company.copy())
	for industry: IndustryState in industries:
		var copied: IndustryState = IndustryState.new(industry.definition)
		copied.performance = industry.performance
		copied.roll = industry.roll
		twin.industries.append(copied)
	twin.sentiment = sentiment
	twin.sentiment_used = sentiment_used
	twin.last_mood = last_mood
	twin.index_level = index_level
	twin.net_shares_traded = net_shares_traded.duplicate()
	twin.event_bags = event_bags.duplicate(true)
	twin.content_key = content_key
	twin.news = news
	if next_draws != null:
		twin.next_draws = next_draws.copy()
	return twin


## A whole StalkleHeads match at year 0, ready for `EarningsYearResolver`: the
## settings, the market, and a board of twenty rows - every company in id
## order, then the bond, then the index.
##
## A company the base game already ships reuses that stalk's definition, so its
## name and description are the shared ones (§3.2.2); one it does not ship gets
## a definition built from its profile, carrying no events. Either way the row
## opens at the company's own price, not the base game's 100.
static func new_game_state(library: ContentLibrary, settings: GameSettings) -> GameState:
	var state: GameState = GameState.new(settings)
	var market: EarningsMarket = from_library(library)
	state.market = market

	for company: CompanyState in market.companies:
		var definition: StalkDefinition = library.stalk_by_id(company.id)
		if definition == null:
			definition = definition_for(company.profile)
		var row: StalkState = StalkState.new(definition)
		row.price = company.price
		state.stalks.append(row)

	for row_id: StringName in [BOND_ID, INDEX_ID]:
		var definition: StalkDefinition = library.stalk_by_id(row_id)
		if definition != null:
			state.stalks.append(StalkState.new(definition))
	var index_row: StalkState = state.stalk_by_id(INDEX_ID)
	if index_row != null:
		index_row.price = int(market.index_level)
	return state


## The board definition of a company the base game does not ship: its name,
## ticker and description, no events, and no base-game price model (its
## `bull_change` and `bear_change` stay zero because nothing in this mode reads
## them). Built in memory at match start, never saved.
static func definition_for(profile: CompanyProfile) -> StalkDefinition:
	var definition: StalkDefinition = StalkDefinition.new()
	definition.id = profile.id
	definition.display_name = profile.display_name
	definition.ticker = profile.ticker
	definition.industry = profile.industry
	definition.description = profile.description
	return definition


## The event pool for a StalkleHeads match: every authored event aimed at a
## company. Events aimed at the index are left out, because the index's price is
## its constituents' and nothing else may move it (§3.9, decisions.md D154).
static func build_event_pool(library: ContentLibrary) -> EventPool:
	var company_ids: Dictionary[StringName, bool] = {}
	for profile: CompanyProfile in library.companies:
		company_ids[profile.id] = true
	var events: Array[SpecialEventDefinition] = []
	for event: SpecialEventDefinition in library.all_events():
		if company_ids.has(event.target_stalk_id):
			events.append(event)
	return EventPool.new(events)


## Adds a trade to the flow input: positive shares bought, negative sold. A
## player's trade and an NPC's count identically (§3.10).
func record_trade(stalk_id: StringName, shares: int) -> void:
	if shares == 0:
		return
	net_shares_traded[stalk_id] = net_shares_traded.get(stalk_id, 0) + shares


func company_by_id(company_id: StringName) -> CompanyState:
	for company: CompanyState in companies:
		if company.id == company_id:
			return company
	return null


func industry_by_id(industry_id: StringName) -> IndustryState:
	if _industry_by_id.is_empty():
		for industry: IndustryState in industries:
			_industry_by_id[industry.id] = industry
	return _industry_by_id.get(industry_id, null)


## This year's performance of a company's industry, in percent.
func performance_of(company: CompanyState) -> float:
	var industry: IndustryState = industry_by_id(company.profile.industry)
	if industry == null:
		return 0.0
	return industry.performance


# ------------------------------------------------------ the bond as yardstick
# BERRY BONDS is mechanically the base game's bond (§3.8). What this mode adds is
# that its yield is the risk-free rate the 12.5x base multiple is measured
# against. These are readouts; nothing in the price path reads them.

## What one bond pays a year. The same in both moods, which is what lets it be
## a yardstick in a mode where the mood is only a report.
static func bond_coupon(bond: StalkDefinition) -> int:
	return bond.bull_dividend


## The bond's yield in percent: coupon over price. 3.0 on the shipped bond.
static func risk_free_yield_percent(bond: StalkDefinition) -> float:
	if bond.starting_price <= 0:
		return 0.0
	return float(bond_coupon(bond)) * 100.0 / float(bond.starting_price)


## What a multiple says a company earns on its price, in percent: `100 / m`.
## 8.0 at the base multiple of 12.5.
static func earnings_yield_percent(valuation_multiple: float) -> float:
	if valuation_multiple <= 0.0:
		return 0.0
	return 100.0 / valuation_multiple


## How many points the base multiple pays over the bond: 8.0 - 3.0 = 5.0 on the
## shipped content. The reason 12.5 is the base and not some other number (§3.4).
static func equity_premium_percent(bond: StalkDefinition) -> float:
	return earnings_yield_percent(ValuationRules.BASE_MULTIPLE) - risk_free_yield_percent(bond)
