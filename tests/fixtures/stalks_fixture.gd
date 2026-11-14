class_name StalksFixture
extends RefCounted
## Shared test content: the ten real stalks, a synthetic event set, and helpers
## for building a GameState.
##
## Lives outside tests/unit so GUT does not scan it for tests.


## The ten shipped stalks, with the exact stat blocks from docs/game-rules.md §3.
## Columns: id, display name, bear range, bull range, bear div, bull div, static.
const STALK_ROWS: Array = [
	[&"berry_bonds", "BERRY BONDS FROM DIE HARD", Vector2i(0, 0), Vector2i(0, 0), 3, 3, true],
	[&"mutuals", "My Mutuals and Me Inc.", Vector2i(0, 10), Vector2i(0, 5), 2, 3, false],
	[&"springfield", "Springfield Nuclear Power", Vector2i(10, 20), Vector2i(0, 15), 0, 5, false],
	[&"pillows", "My Pillow, Your Pillow, We're All Pillows!", Vector2i(5, 25), Vector2i(0, 15), 1, 1, false],
	[&"mafia", "Mafia HUD Scam", Vector2i(5, 25), Vector2i(5, 15), 1, 3, false],
	[&"submissives", "Unionized Submissives LLC", Vector2i(0, 25), Vector2i(5, 20), 0, 2, false],
	[&"monorail", "North Haverbrook MONORAIL", Vector2i(5, 30), Vector2i(0, 20), 1, 4, false],
	[&"pgenron", "PG&Enron", Vector2i(10, 35), Vector2i(5, 15), 0, 4, false],
	[&"teamsters", "Teamsters Pension Fund", Vector2i(15, 40), Vector2i(0, 15), 0, 8, false],
	[&"stryker", "strYker!!!", Vector2i(15, 50), Vector2i(13, 42), 0, 0, false],
]


static func build_stalks() -> Array[StalkDefinition]:
	var defs: Array[StalkDefinition] = []
	for row: Array in STALK_ROWS:
		var d: StalkDefinition = StalkDefinition.new()
		d.id = row[0]
		d.display_name = row[1]
		d.starting_price = 100
		d.bear_change = row[2]
		d.bull_change = row[3]
		d.bear_dividend = row[4]
		d.bull_dividend = row[5]
		d.is_price_static = row[6]
		defs.append(d)
	return defs


static func one_stalk(stalk_id: StringName) -> StalkDefinition:
	for d: StalkDefinition in build_stalks():
		if d.id == stalk_id:
			return d
	return null


## Five bull and five bear events per non-static stalk, matching the shipped
## pool sizes of 45 and 45.
static func build_events(defs: Array[StalkDefinition]) -> Array[SpecialEventDefinition]:
	var events: Array[SpecialEventDefinition] = []
	for d: StalkDefinition in defs:
		if d.is_price_static:
			continue
		for i: int in 5:
			events.append(make_event(
				StringName("%s_bull_%d" % [d.id, i]),
				d.id,
				MarketMood.Value.BULL,
				5 + i * 5,
			))
			events.append(make_event(
				StringName("%s_bear_%d" % [d.id, i]),
				d.id,
				MarketMood.Value.BEAR,
				-(5 + i * 5),
			))
	return events


static func make_event(
	event_id: StringName,
	target: StringName,
	mood: MarketMood.Value,
	price_change: int,
) -> SpecialEventDefinition:
	var e: SpecialEventDefinition = SpecialEventDefinition.new()
	e.id = event_id
	e.target_stalk_id = target
	e.mood = mood
	e.price_change = price_change
	e.flavour_text = "Something happens to %s." % target
	return e


static func make_settings(max_years: int = 10) -> GameSettings:
	var s: GameSettings = GameSettings.new()
	s.max_years = max_years
	s.starting_cash = 10000
	return s


## A state holding every stalk and `player_count` players, each with starting cash.
static func make_state(
	max_years: int = 10,
	player_count: int = 1,
	defs: Array[StalkDefinition] = [],
) -> GameState:
	var definitions: Array[StalkDefinition] = defs if not defs.is_empty() else build_stalks()
	var settings: GameSettings = make_settings(max_years)
	settings.player_count = player_count

	var state: GameState = GameState.new(settings)
	for d: StalkDefinition in definitions:
		state.stalks.append(StalkState.new(d))
	for i: int in player_count:
		state.players.append(
			PlayerState.new(StringName("p%d" % i), "Player %d" % i, settings.starting_cash)
		)
	return state


static func rng(seed_value: int) -> RandomNumberGenerator:
	var generator: RandomNumberGenerator = RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


## A resolver whose prices never move, so a test can set a price by hand and see
## only the behaviour it cares about.
static func frozen_resolver() -> YearResolver:
	return YearResolver.new(FixedPriceModelStub.new(0), EventPool.new([]))


static func resolver_with_delta(delta: int) -> YearResolver:
	return YearResolver.new(FixedPriceModelStub.new(delta), EventPool.new([]))


static func real_resolver(defs: Array[StalkDefinition]) -> YearResolver:
	return YearResolver.new(
		RandomRangePriceModel.new(), EventPool.new(build_events(defs))
	)
