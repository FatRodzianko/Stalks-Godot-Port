extends GutTest
## StalkleHeads phase S5: choosing the game mode, and everything the choice
## decides at match start (docs/stalkleheads-design.md §9.4, §10.2, §11;
## decisions.md D171).
##
## The base game must be the default everywhere, and must build exactly the
## match it always did. The golden-history test is what proves the base game's
## year is untouched; this file proves the right year is picked.


const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")
const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")
const RowScene: PackedScene = preload("res://src/ui/widgets/steam_lobby_row.tscn")

## Any company on the shipped roster. Found, not assumed, so a roster change
## does not break this file.
var _company_id: StringName = &""


func _settings(mode: GameMode.Value, seed_value: int = 4242) -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	settings.mode = mode
	settings.rng_seed = seed_value
	settings.loans_enabled = true
	return settings


func _authority(mode: GameMode.Value, seed_value: int = 4242) -> MatchAuthority:
	var library: ContentLibrary = MatchSetup.load_library(mode)
	assert_true(library.is_valid(), "the shipped content is valid for this mode")
	return LocalSession.build_authority(
		_settings(mode, seed_value), library, ["You"] as Array[String]
	)


## Advances a solo match past year 0, where trading is closed.
func _into_year_one(authority: MatchAuthority) -> void:
	authority.set_ready(&"p0", true)
	authority.advance_year()
	authority.set_ready(&"p0", false)


func before_all() -> void:
	var library: ContentLibrary = MatchSetup.load_library(GameMode.Value.STALKLEHEADS)
	_company_id = library.companies[0].id


# ------------------------------------------------------------------ the default

func test_the_base_game_is_the_default() -> void:
	assert_eq(GameSettings.new().mode, GameMode.Value.BASE)


func test_every_mode_has_a_name() -> void:
	for mode: GameMode.Value in GameMode.ALL:
		assert_false(GameMode.label(mode).is_empty())
		assert_false(GameMode.lobby_value(mode).is_empty())


func test_a_number_that_is_not_a_mode_is_the_base_game() -> void:
	assert_eq(GameMode.from_int(99), GameMode.Value.BASE)
	assert_eq(GameMode.from_int(-1), GameMode.Value.BASE)
	assert_eq(GameMode.from_int(int(GameMode.Value.STALKLEHEADS)), GameMode.Value.STALKLEHEADS)


# ------------------------------------------------------- what the mode decides

func test_the_base_game_gets_the_base_games_year() -> void:
	var library: ContentLibrary = MatchSetup.load_library(GameMode.Value.BASE)
	var pipeline: YearPipeline = MatchSetup.new_pipeline(_settings(GameMode.Value.BASE), library)
	assert_true(pipeline is YearResolver)


func test_stalkleheads_gets_the_earnings_year_and_the_squeeze() -> void:
	var library: ContentLibrary = MatchSetup.load_library(GameMode.Value.STALKLEHEADS)
	var pipeline: YearPipeline = MatchSetup.new_pipeline(
		_settings(GameMode.Value.STALKLEHEADS), library
	)
	assert_true(pipeline is EarningsYearResolver)
	assert_not_null(library.short_squeeze)
	assert_eq((pipeline as EarningsYearResolver)._short_squeeze, library.short_squeeze,
		"the squeeze template is passed, so squeezes can fire (D170)")


func test_the_base_game_loads_no_stalkleheads_content() -> void:
	var library: ContentLibrary = MatchSetup.load_library(GameMode.Value.BASE)
	assert_true(library.companies.is_empty(), "a broken company file cannot stop a base match")
	assert_null(library.short_squeeze)


func test_a_base_match_is_the_board_it_always_was() -> void:
	var authority: MatchAuthority = _authority(GameMode.Value.BASE)
	var expected: Array[StalkState] = ContentLibrary.load_from().build_stalk_states()

	assert_null(authority.state.market)
	assert_eq(authority.state.stalks.size(), expected.size())
	for index: int in expected.size():
		assert_eq(authority.state.stalks[index].id, expected[index].id)
		assert_eq(authority.state.stalks[index].price, expected[index].price)


func test_a_base_match_keeps_one_loan_per_match() -> void:
	assert_false(_authority(GameMode.Value.BASE).state.settings.multiple_loans_enabled)


func test_a_stalkleheads_match_has_a_market_beside_the_board() -> void:
	var authority: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS)
	var library: ContentLibrary = MatchSetup.load_library(GameMode.Value.STALKLEHEADS)

	assert_not_null(authority.state.market)
	assert_eq(authority.state.stalks.size(), library.companies.size() + 2,
		"every company, then the bond and the index")
	assert_eq(authority.state.players.size(), 1)


func test_a_stalkleheads_match_lets_a_player_borrow_again() -> void:
	assert_true(_authority(GameMode.Value.STALKLEHEADS).state.settings.multiple_loans_enabled,
		"D159: on for StalkleHeads")


func test_a_stalkleheads_year_advances() -> void:
	var authority: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS)
	var result: YearResult = authority.advance_year()

	assert_true(result is EarningsYearResult)
	assert_eq(authority.state.year, 1)


# ------------------------------------------------------- players' trades in flow

func test_a_players_purchase_is_recorded_as_flow() -> void:
	var authority: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS)
	_into_year_one(authority)
	var before: int = authority.state.market.net_shares_traded.get(_company_id, 0)

	assert_eq(authority.buy(&"p0", _company_id, 10), "")

	assert_eq(authority.state.market.net_shares_traded.get(_company_id, 0), before + 10)


func test_a_players_sale_is_recorded_as_negative_flow() -> void:
	var authority: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS)
	_into_year_one(authority)
	assert_eq(authority.buy(&"p0", _company_id, 10), "")
	var after_buy: int = authority.state.market.net_shares_traded.get(_company_id, 0)

	assert_eq(authority.sell(&"p0", _company_id, 4), "")

	assert_eq(authority.state.market.net_shares_traded.get(_company_id, 0), after_buy - 4)


func test_a_refused_trade_records_nothing() -> void:
	var authority: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS)
	_into_year_one(authority)
	var before: Dictionary = authority.state.market.net_shares_traded.duplicate()

	assert_ne(authority.buy(&"p0", _company_id, 999999), "", "unaffordable")
	assert_ne(authority.sell(&"p0", _company_id, 1), "", "nothing to sell")

	assert_eq(authority.state.market.net_shares_traded, before)


## The point of recording it: a player's buying is an input to next year's
## price, as an NPC's is. Same seed, same everything, one buys and one does not.
func test_a_players_buying_moves_next_years_price() -> void:
	var bought: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS, 77)
	var idle: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS, 77)
	_into_year_one(bought)
	_into_year_one(idle)
	var shares: int = TradeRules.max_affordable(
		bought.state.players[0], bought.state.stalk_by_id(_company_id)
	)
	assert_gt(shares, 0)
	assert_eq(bought.buy(&"p0", _company_id, shares), "")

	bought.advance_year()
	idle.advance_year()

	assert_gt(bought.state.market.company_by_id(_company_id).flow,
		idle.state.market.company_by_id(_company_id).flow, "the purchase became flow")
	assert_ne(bought.state.stalk_by_id(_company_id).price, idle.state.stalk_by_id(_company_id).price)


func test_a_base_game_trade_touches_no_market() -> void:
	var authority: MatchAuthority = _authority(GameMode.Value.BASE)
	_into_year_one(authority)
	var stalk_id: StringName = authority.state.stalks[0].id

	assert_eq(authority.buy(&"p0", stalk_id, 1), "")
	assert_null(authority.state.market)


# ------------------------------------------------------------------ the wire

func test_the_mode_travels_with_the_settings() -> void:
	var settings: GameSettings = _settings(GameMode.Value.STALKLEHEADS)
	var state: GameState = GameState.new(GameSettings.new())

	StateSync.apply_settings(state, StateSync.encode_settings(settings))

	assert_eq(state.settings.mode, GameMode.Value.STALKLEHEADS)


func test_a_snapshot_without_a_mode_is_the_base_game() -> void:
	var data: Dictionary = StateSync.encode_settings(_settings(GameMode.Value.BASE))
	data.erase("mode")
	var state: GameState = GameState.new(GameSettings.new())

	StateSync.apply_settings(state, data)

	assert_eq(state.settings.mode, GameMode.Value.BASE)


## A joining client loads only the base content, because it does not know the
## mode until the host's settings arrive. Ten of the board's companies are not
## base-game stalks, and must still resolve.
func test_a_client_with_base_content_can_show_a_stalkleheads_board() -> void:
	var host: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS)
	var client_library: ContentLibrary = ContentLibrary.load_from()
	var replica: GameState = GameState.new(GameSettings.new())

	var problem: String = StateSync.apply_state(
		replica, StateSync.encode_state(host.state), client_library
	)

	assert_eq(problem, "")
	assert_eq(replica.settings.mode, GameMode.Value.STALKLEHEADS)
	assert_eq(replica.stalks.size(), host.state.stalks.size())
	for index: int in host.state.stalks.size():
		assert_eq(replica.stalks[index].id, host.state.stalks[index].id)
		assert_eq(replica.stalks[index].price, host.state.stalks[index].price)


## A copy of a StalkleHeads match with no market - a snapshot from a build
## older than S6, which did not send one - has nothing to carry on from, so a
## new host must refuse rather than invent one. S6's own snapshots carry the
## market and can change hosts (test_wire.gd).
func test_a_stalkleheads_match_without_its_market_cannot_change_hosts() -> void:
	var host: MatchAuthority = _authority(GameMode.Value.STALKLEHEADS)
	var replica: GameState = GameState.new(GameSettings.new())
	var old_build: Dictionary = StateSync.encode_state(host.state)
	old_build.erase("market")
	StateSync.apply_state(replica, old_build, ContentLibrary.load_from())

	var opened: Dictionary = HostSession.take_over(
		StubTransport.new(), replica, MatchSetup.load_library(GameMode.Value.STALKLEHEADS),
		&"p0", 0
	)

	assert_ne(String(opened["error"]), "")
	assert_null(opened["session"])


func test_a_base_match_can_still_change_hosts() -> void:
	assert_eq(MatchSetup.why_not_take_over(_authority(GameMode.Value.BASE).state), "")


# ---------------------------------------------------------------- the lobby row

func _detail(lobby: Dictionary) -> String:
	var row: SteamLobbyRow = RowScene.instantiate()
	add_child_autofree(row)
	row.display(lobby)
	return (row.get_node("%Detail") as Label).text


func _lobby(mode: String) -> Dictionary:
	return {"id": 7, "name": "Friday", "players": 1, "capacity": 4, "years": 10, "mode": mode}


func test_a_stalkleheads_lobby_says_so() -> void:
	var detail: String = _detail(_lobby(GameMode.LOBBY_STALKLEHEADS))
	assert_string_contains(detail, GameMode.label(GameMode.Value.STALKLEHEADS))
	assert_true(detail.begins_with(GameMode.label(GameMode.Value.STALKLEHEADS)), "first")


func test_a_base_lobby_says_so() -> void:
	assert_string_contains(_detail(_lobby(GameMode.LOBBY_BASE)),
		GameMode.label(GameMode.Value.BASE))


## §9.4: a lobby that did not publish its mode is not labelled as the base game.
func test_a_lobby_that_published_no_mode_shows_none() -> void:
	var detail: String = _detail(_lobby(""))
	for mode: GameMode.Value in GameMode.ALL:
		assert_false(detail.contains(GameMode.label(mode)))
	assert_string_contains(detail, "10 years", "the rest of the row is still there")


func test_a_mode_this_build_does_not_know_shows_none() -> void:
	var detail: String = _detail(_lobby("some_future_mode"))
	for mode: GameMode.Value in GameMode.ALL:
		assert_false(detail.contains(GameMode.label(mode)))


# ------------------------------------------------------------ the title screen

func _menu() -> MainMenu:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	return menu


func test_the_title_screen_offers_every_mode() -> void:
	var option: OptionButton = _menu().get_node("%GameModeOption")
	assert_eq(option.item_count, GameMode.ALL.size())
	for index: int in GameMode.ALL.size():
		assert_eq(option.get_item_text(index), GameMode.label(GameMode.ALL[index]))


func test_the_title_screen_starts_on_the_base_game() -> void:
	assert_eq(_menu().chosen_settings().mode, GameMode.Value.BASE)


func test_choosing_stalkleheads_is_in_the_settings_on_either_tab() -> void:
	var menu: MainMenu = _menu()
	menu.choose_game_mode(GameMode.Value.STALKLEHEADS)
	for tab: MainMenu.Mode in [MainMenu.Mode.SINGLE, MainMenu.Mode.HOST]:
		menu.show_mode(tab)
		assert_eq(menu.chosen_settings().mode, GameMode.Value.STALKLEHEADS)


## D86 and D125: the card is one fixed size, decided up front. The new row
## must fit inside it on the tab with the most rows, not grow it.
func test_the_mode_row_does_not_grow_the_panel() -> void:
	var menu: MainMenu = _menu()
	var card: Control = menu.get_node("Centre/Shell/Card")
	menu.show_mode(MainMenu.Mode.HOST)
	await wait_process_frames(2)

	assert_eq(card.size, card.custom_minimum_size, "the host tab fits the card as authored")


func test_a_stalkleheads_match_starts_from_the_screen_host() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	var settings: GameSettings = _settings(GameMode.Value.STALKLEHEADS)
	settings.player_count = 1

	main.start_match(settings)

	assert_not_null(main.session())
	assert_not_null(main.session().state().market)
	assert_false(main.current_screen() is MainMenu)


func test_a_base_match_from_the_screen_host_has_no_market() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	var settings: GameSettings = _settings(GameMode.Value.BASE)
	settings.player_count = 1

	main.start_match(settings)

	assert_null(main.session().state().market)


## Not playable on screen until S7, but it must not fall over: the existing
## playing screen shows the twenty-row board and survives a year.
func test_a_stalkleheads_year_runs_on_the_playing_screen() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	var settings: GameSettings = _settings(GameMode.Value.STALKLEHEADS)
	settings.player_count = 1
	main.start_match(settings)
	var session: LocalSession = main.session()

	session.set_ready(session.local_player_id(), true)
	await wait_process_frames(2)

	assert_eq(session.state().year, 1)
	assert_false(main.current_screen() is MainMenu)


## D171: the mode is read in one place. Any other file comparing a game mode is
## the `if mode ==` that design §13.3 names as the modes becoming entangled.
## `MainMenu` compares its own tab enum, also called `Mode`, so the pattern is
## the game mode's values and its setting, not the word.
func test_only_match_setup_branches_on_the_game_mode() -> void:
	var allowed: Array[String] = [
		"res://src/sim/match_setup.gd",
		"res://src/data/game_mode.gd",
	]
	var pattern: RegEx = RegEx.create_from_string(
		"(settings\\.mode|GameMode\\.Value\\.[A-Z]+)\\s*[!=]=|[!=]=\\s*GameMode\\.Value"
	)
	var offenders: Array[String] = []
	for path: String in _scripts_under("res://src"):
		if path in allowed:
			continue
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for index: int in lines.size():
			if pattern.search(lines[index]) != null:
				offenders.append("%s:%d" % [path, index + 1])
	assert_eq(offenders, [] as Array[String], "only MatchSetup may ask which mode it is")


func _scripts_under(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir_path):
		found.append_array(_scripts_under(dir_path.path_join(sub)))
	return found
