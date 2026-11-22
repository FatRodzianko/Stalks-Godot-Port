class_name MatchSetup
extends RefCounted
## **The one place the game mode is read.** Everything that differs between the
## base game and StalkleHeads at the start of a match is decided here, once:
##
## | Question | Base game | StalkleHeads |
## |---|---|---|
## | Which content | the stalks | the stalks, plus companies, industries, traders and the squeeze (`load_fundamentals`) |
## | Which board | `ContentLibrary.build_stalk_states` | `EarningsMarket.new_game_state`, with the market beside it |
## | Which year | `YearResolver` | `EarningsYearResolver`, with the squeeze template |
## | Which settings it forces | none | `multiple_loans_enabled` on (decisions.md D159) |
##
## After this, nothing asks. `MatchAuthority` holds a `YearPipeline` and calls
## it; the board is `GameState.stalks` in both modes. If a later change needs
## `if settings.mode ==` anywhere else, that is the sign the modes have stopped
## being additive (docs/stalkleheads-design.md §10.2 and §13.3, decisions.md
## D171).
##
## Pure: static functions, no nodes, no RNG of its own.


## The authored content a match in `mode` needs, loaded and validated. Check
## `is_valid()` before using it. The base game loads only what it always has,
## so a broken StalkleHeads file can never stop a base-game match.
static func load_library(mode: GameMode.Value) -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.load_from()
	prepare_library(library, mode)
	return library


## Adds what `mode` needs to a library that was loaded for the base game, once.
## A client joining an online game does not know the mode until the host's
## first snapshot arrives, so its library is topped up then
## (`StateSync.apply_state`).
static func prepare_library(library: ContentLibrary, mode: GameMode.Value) -> void:
	if mode == GameMode.Value.STALKLEHEADS and library.companies.is_empty():
		library.load_fundamentals()


## The definition behind the board row `stalk_id`, from a library prepared for
## the match's mode: a shipped stalk, or a StalkleHeads company the base game
## does not ship, built from its profile as the host built it
## (`EarningsMarket.definition_for`). Null if neither knows the id.
static func board_definition(library: ContentLibrary, stalk_id: StringName) -> StalkDefinition:
	var definition: StalkDefinition = library.stalk_by_id(stalk_id)
	if definition != null:
		return definition
	var profile: CompanyProfile = library.company_by_id(stalk_id)
	if profile != null:
		return EarningsMarket.definition_for(profile)
	return null


## Writes the mode's own rules into `settings`, before the match is built, so
## they travel to clients with the rest of the settings. The base game's are
## left exactly as they were chosen.
static func apply_mode_rules(settings: GameSettings) -> void:
	if settings.mode == GameMode.Value.STALKLEHEADS:
		# Borrow again once a loan is settled (§14 q2).
		settings.multiple_loans_enabled = true


## A match at year 0 with no players seated: the board, and in StalkleHeads
## the market beside it. `library` must come from `load_library` for the same
## mode.
static func new_game_state(settings: GameSettings, library: ContentLibrary) -> GameState:
	if settings.mode == GameMode.Value.STALKLEHEADS:
		return EarningsMarket.new_game_state(library, settings)
	var state: GameState = GameState.new(settings)
	state.stalks = library.build_stalk_states()
	return state


## The year pipeline for `settings.mode`. Also what a promoted host builds when
## it takes a match over, so the year after a migration is the same game.
static func new_pipeline(settings: GameSettings, library: ContentLibrary) -> YearPipeline:
	if settings.mode == GameMode.Value.STALKLEHEADS:
		return EarningsYearResolver.new(
			EarningsMarket.build_event_pool(library), library.short_squeeze
		)
	return YearResolver.new(RandomRangePriceModel.new(), library.build_event_pool())


## Why `state` cannot be continued by a new host, or an empty string if it can.
##
## A StalkleHeads match's market (fundamentals, industries, the desk, the event
## bags) travels in every snapshot (decisions.md D176), so a client's copy can
## be carried on. One without a market - a snapshot from a build older than
## that - has nothing to advance the year from, and refusing is better than
## carrying on with a market made up afresh.
static func why_not_take_over(state: GameState) -> String:
	if state.settings != null and state.settings.mode == GameMode.Value.STALKLEHEADS:
		if state.market == null:
			return "This copy of the StalkleHeads match has no market to carry on from."
	return ""
