extends GutTest
## The rebuilt title screen: four things across the top, one panel size, and
## the development overlay that took the direct-connection form off it.
##
## Asked for after play on 2026-11-16. The panel used to change size with every
## tab, so the title, the tab bar and the quit button all moved as you clicked
## between them.


const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")
const PauseScene: PackedScene = preload("res://src/ui/widgets/pause_menu.tscn")
const DevScene: PackedScene = preload("res://src/ui/widgets/dev_overlay.tscn")
const BrowserScene: PackedScene = preload("res://src/ui/widgets/lobby_browser.tscn")


func _menu() -> MainMenu:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	return menu


# ------------------------------------------------------------ one panel size

## The fault: every tab sized the card to its own contents, so the heading and
## the quit button jumped as you moved between them.
func test_the_panel_is_the_same_size_on_every_tab() -> void:
	var menu: MainMenu = _menu()
	var card: Control = menu.get_node("Centre/Shell/Card")

	var sizes: Array[Vector2] = []
	for mode: int in [
		MainMenu.Mode.SINGLE, MainMenu.Mode.HOST, MainMenu.Mode.JOIN, MainMenu.Mode.SETTINGS
	]:
		menu.show_mode(mode)
		await wait_process_frames(2)
		sizes.append(card.size)

	for size: Vector2 in sizes:
		assert_eq(size, sizes[0], "every tab draws into the same card")


func test_the_title_and_the_quit_button_do_not_move() -> void:
	var menu: MainMenu = _menu()
	var title: Control = menu.get_node("Centre/Shell/Title")
	var quit: Control = menu.get_node("%QuitButton")

	menu.show_mode(MainMenu.Mode.SINGLE)
	await wait_process_frames(2)
	var title_at: Vector2 = title.global_position
	var quit_at: Vector2 = quit.global_position

	menu.show_mode(MainMenu.Mode.JOIN)
	await wait_process_frames(2)

	assert_eq(title.global_position, title_at)
	assert_eq(quit.global_position, quit_at)


## Reported while reviewing the rebuilt screen: a full-width START sat directly
## above a full-width QUIT TO DESKTOP, which is an accidental click waiting to
## happen.
func test_the_start_button_is_not_as_wide_as_the_panel() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.SINGLE)
	await wait_process_frames(2)

	var card: Control = menu.get_node("Centre/Shell/Card")
	var start: Control = menu.get_node("%StartButton")

	assert_lt(start.size.x, card.size.x * 0.6, "narrow, not the width of the panel")
	assert_gt(
		start.global_position.x, card.global_position.x + card.size.x * 0.4,
		"and over to the right",
	)


func test_the_quit_button_is_clear_of_the_panel() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.SINGLE)
	await wait_process_frames(2)

	var card: Control = menu.get_node("Centre/Shell/Card")
	var quit: Control = menu.get_node("%QuitButton")

	assert_gt(
		quit.global_position.y, card.global_position.y + card.size.y + 6.0,
		"a real gap below the panel, not a button tucked under it",
	)
	assert_lt(quit.size.x, card.size.x * 0.6, "and narrower than the panel")


## The revert prompt is parented to the window rather than to the settings
## panel, which put it outside the themed tree: it came up in Godot's default
## font and styling. Reported from play.
func test_a_confirmation_carries_the_games_theme_wherever_it_is_parented() -> void:
	var panel: ConfirmPanel = preload(
		"res://src/ui/widgets/confirm_panel.tscn"
	).instantiate()
	add_child_autofree(panel)

	assert_not_null(panel.theme, "it cannot rely on inheriting one")


# --------------------------------------------------------------- the dev tool

## Direct host and join by address is a development tool. It is meaningless to
## somebody who bought the game on Steam, and it used to take up a third of
## the Join panel.
func test_the_title_screen_has_no_address_form_on_it() -> void:
	var menu: MainMenu = _menu()
	for mode: int in [
		MainMenu.Mode.SINGLE, MainMenu.Mode.HOST, MainMenu.Mode.JOIN, MainMenu.Mode.SETTINGS
	]:
		menu.show_mode(mode)
		assert_null(menu.find_child("DevAddressField", true, false), "not on the title screen")


## The first version was unusable: an ordinary child of `Main`, which is a
## `MarginContainer`, so it was stretched to fill the screen rather than sitting
## in the corner, and every screen swap added the new screen after it, so the
## screen drew on top and took the clicks. Reported from play.
func test_the_overlay_is_above_the_game_and_not_laid_out_by_it() -> void:
	var main: Main = preload("res://src/ui/screens/main/main.tscn").instantiate()
	add_child_autofree(main)
	if main.dev_overlay() == null:
		pass_test("release build: there is no overlay to place")
		return

	var layer: CanvasLayer = main.dev_overlay().get_parent() as CanvasLayer
	assert_not_null(layer, "it needs a canvas layer of its own, not a container")
	if layer == null:
		return
	assert_gt(layer.layer, 1, "and that layer must draw above the game")


## Like the Unity overlay it follows: a session can only be started from the
## title screen, and in a match it would be sitting over the board.
func test_the_overlay_is_only_on_the_title_screen() -> void:
	var main: Main = preload("res://src/ui/screens/main/main.tscn").instantiate()
	add_child_autofree(main)
	if main.dev_overlay() == null:
		pass_test("release build: there is no overlay to hide")
		return

	var layer: CanvasLayer = main.dev_overlay().get_parent() as CanvasLayer
	main.show_menu()
	assert_true(layer.visible, "on the title screen")

	main.start_match(GameSettings.new())
	assert_false(layer.visible, "and gone once a match starts")


## It sits over the top-left of the title screen, which is where the heading
## is, so judging the layout with it on display is harder than it should be.
func test_f1_hides_the_overlay() -> void:
	var overlay: DevOverlay = DevScene.instantiate()
	add_child_autofree(overlay)
	assert_true(overlay.visible)

	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F1
	event.pressed = true
	get_tree().root.push_input(event)
	await wait_process_frames(1)

	assert_false(overlay.visible)


## No name field: `HostSession.sanitised_name` names an unnamed arrival after
## its seat, so two windows on one machine come out as distinct players with
## nothing typed.
func test_the_overlay_hosts_on_the_typed_port() -> void:
	var overlay: DevOverlay = DevScene.instantiate()
	add_child_autofree(overlay)
	(overlay.get_node("%DevPortSpin") as SpinBox).value = 43100

	var seen: Array = []
	overlay.host_requested.connect(
		func(port: int, player_name: String) -> void: seen.append([port, player_name])
	)
	(overlay.get_node("%DevHostButton") as Button).pressed.emit()

	assert_eq(seen, [[43100, ""]])
	assert_null(overlay.find_child("DevNameField", true, false), "no name field")


func test_the_overlay_joins_this_machine_by_default() -> void:
	# Two windows on one computer is what it is for nearly every time, so it
	# should need no typing at all.
	var overlay: DevOverlay = DevScene.instantiate()
	add_child_autofree(overlay)

	var seen: Array = []
	overlay.join_requested.connect(
		func(address: String, port: int, player_name: String) -> void:
			seen.append([address, port, player_name])
	)
	(overlay.get_node("%DevJoinButton") as Button).pressed.emit()

	assert_eq(seen, [["127.0.0.1", DevOverlay.DEFAULT_PORT, ""]])


# ------------------------------------------------------------ the lobby list

func _browser() -> LobbyBrowser:
	var browser: LobbyBrowser = BrowserScene.instantiate()
	add_child_autofree(browser)
	return browser


func _lobbies() -> Array[Dictionary]:
	return [
		{"id": 1, "name": "Friday night", "members": 2, "limit": 4},
		{"id": 2, "name": "FRIDAY REMATCH", "members": 1, "limit": 4},
		{"id": 3, "name": "Sunday roast", "members": 3, "limit": 10},
	] as Array[Dictionary]


func test_the_list_can_be_searched_by_name() -> void:
	# The original had a Search button beside the box. Filtering as you type is
	# the same feature without a button that re-asks a question you have
	# already answered.
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list(_lobbies())

	(browser.get_node("%SearchField") as LineEdit).text = "friday"
	browser._on_search_changed("friday")

	assert_eq(browser.lobby_rows().size(), 2, "case does not matter")


func test_clearing_the_search_puts_every_game_back() -> void:
	# The original's "did the player search" flag was cleared only on a path
	# the normal flow never reached, so once you had searched the filter went
	# on applying to every later refresh (audit 3.3).
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list(_lobbies())
	(browser.get_node("%SearchField") as LineEdit).text = "sunday"
	browser._on_search_changed("sunday")
	assert_eq(browser.lobby_rows().size(), 1)

	(browser.get_node("%SearchField") as LineEdit).text = ""
	browser._on_search_changed("")

	assert_eq(browser.lobby_rows().size(), 3)


func test_a_search_that_matches_nothing_says_so() -> void:
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list(_lobbies())
	(browser.get_node("%SearchField") as LineEdit).text = "zzz"
	browser._on_search_changed("zzz")

	assert_eq(browser.lobby_rows().size(), 0)
	assert_string_contains((browser.get_node("%Status") as Label).text, "zzz")


func test_a_refresh_keeps_whatever_is_in_the_search_box() -> void:
	var browser: LobbyBrowser = _browser()
	(browser.get_node("%SearchField") as LineEdit).text = "sunday"
	browser._on_lobby_list(_lobbies())

	assert_eq(browser.lobby_rows().size(), 1, "the box is read on every list")


# --------------------------------------------------- settings in two places

## The original's pause menu reused the title screen's settings panel rather
## than having a second one. A volume slider sitting on the pause menu by
## itself answered a third of the question.
func test_the_pause_menu_shows_the_same_settings_as_the_title_screen() -> void:
	var pause: PauseMenu = PauseScene.instantiate()
	add_child_autofree(pause)
	pause.open()

	assert_false(pause.is_showing_settings(), "buttons first")
	(pause.get_node("%SettingsButton") as Button).pressed.emit()

	assert_true(pause.is_showing_settings())
	for control: String in ["%VolumeSlider", "%ResolutionOption", "%FullscreenCheck"]:
		assert_not_null(pause.settings_panel().get_node(control), control)


func test_escape_backs_out_of_the_settings_page_before_the_menu() -> void:
	var pause: PauseMenu = PauseScene.instantiate()
	add_child_autofree(pause)
	pause.open()
	pause.show_settings()

	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	get_tree().root.push_input(event)
	await wait_process_frames(1)

	assert_false(pause.is_showing_settings(), "back to the buttons")
	assert_true(pause.is_open(), "and not out of the menu altogether")


func test_the_pause_menu_always_opens_on_its_buttons() -> void:
	# Reopening on whichever page it was left on would mean Escape sometimes
	# produced a settings panel and sometimes a menu.
	var pause: PauseMenu = PauseScene.instantiate()
	add_child_autofree(pause)
	pause.open()
	pause.show_settings()
	pause.close()

	pause.open()

	assert_false(pause.is_showing_settings())


# ------------------------------------------------- resolution and fullscreen

func _settings() -> SettingsPanel:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.SETTINGS)
	return menu.settings_panel()


## Reported from play: the dropdown does nothing in fullscreen, so a player
## could pick a size, watch nothing happen, and reasonably conclude the game
## was broken. Greying it out is a true statement about what the setting
## currently does. See decisions.md D85.
func test_the_resolution_is_greyed_out_in_fullscreen() -> void:
	var panel: SettingsPanel = _settings()
	var dropdown: OptionButton = panel.get_node("%ResolutionOption")
	var fullscreen: CheckBox = panel.get_node("%FullscreenCheck")

	fullscreen.button_pressed = true
	assert_true(dropdown.disabled, "it does nothing in fullscreen")


func test_the_resolution_comes_back_in_a_window() -> void:
	var panel: SettingsPanel = _settings()
	var dropdown: OptionButton = panel.get_node("%ResolutionOption")
	var fullscreen: CheckBox = panel.get_node("%FullscreenCheck")

	fullscreen.button_pressed = true
	fullscreen.button_pressed = false

	assert_false(dropdown.disabled, "a window is the case where it applies")


# ------------------------------------------------- the settings column lines up

## Found in play on 2026-11-22 (manual-testing.md C1): the label column was as
## wide as its widest *visible* label, so the settings started further left on
## HOST ONLINE than on SINGLE PLAYER. The owner asked for both to start where the
## SINGLE PLAYER and HOST ONLINE tabs meet. See decisions.md D173.
func _field_column_x(menu: MainMenu) -> float:
	return (menu.get_node("%YearsSpin") as Control).global_position.x


func _tab_seam_x(menu: MainMenu) -> float:
	var single: Control = menu.get_node("%SinglePlayerTab")
	var host: Control = menu.get_node("%HostOnlineTab")
	return (single.global_position.x + single.size.x + host.global_position.x) / 2.0


func test_the_settings_start_at_the_same_place_on_both_tabs() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.SINGLE)
	await wait_process_frames(2)
	var single_x: float = _field_column_x(menu)

	menu.show_mode(MainMenu.Mode.HOST)
	await wait_process_frames(2)

	assert_eq(_field_column_x(menu), single_x)


func test_the_settings_start_where_the_first_two_tabs_meet() -> void:
	var menu: MainMenu = _menu()
	for tab: MainMenu.Mode in [MainMenu.Mode.SINGLE, MainMenu.Mode.HOST]:
		menu.show_mode(tab)
		await wait_process_frames(2)
		assert_almost_eq(_field_column_x(menu), _tab_seam_x(menu), 3.0,
			"the field column starts at the seam between the first two tabs")


## The column is held open by one label's minimum width, so a label wider than
## it would push the column out again on whichever tab shows it.
func test_no_label_is_wider_than_the_column() -> void:
	var menu: MainMenu = _menu()
	var column: float = (menu.get_node("%YearsLabel") as Control).custom_minimum_size.x
	for child: Node in menu.get_node("%YearsLabel").get_parent().get_children():
		var label: Label = child as Label
		if label != null:
			assert_true(label.get_minimum_size().x <= column,
				"%s fits the column" % label.name)
