extends GutTest
## Escape during a match, and the two ways out of the game.
##
## These exist because of a fault found in play on 2026-11-16: in fullscreen
## there is no window to close, and the game had no quit button anywhere, so
## Alt+F4 was the only way out. A test that the buttons are present and wired
## is cheap; discovering it again is not.


const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")
const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")
const PauseScene: PackedScene = preload("res://src/ui/widgets/pause_menu.tscn")


func _pause() -> PauseMenu:
	var menu: PauseMenu = PauseScene.instantiate()
	add_child_autofree(menu)
	return menu


func _press(node: Node, name: String) -> void:
	(node.get_node("%" + name) as Button).pressed.emit()


func test_a_pause_menu_starts_closed() -> void:
	assert_false(_pause().is_open())


func test_opening_shows_it_and_closing_hides_it() -> void:
	var menu: PauseMenu = _pause()
	menu.open()
	assert_true(menu.is_open())

	menu.close()
	assert_false(menu.is_open())


func test_back_to_the_game_closes_it_and_says_so() -> void:
	var menu: PauseMenu = _pause()
	menu.open()
	watch_signals(menu)

	_press(menu, "ResumeButton")

	assert_signal_emitted(menu, "resume_requested")
	assert_false(menu.is_open())


func test_leaving_asks_the_host_rather_than_acting() -> void:
	# The menu owns no session and must not pretend to. Leaving a match cannot
	# be undone, and the confirmation lives with the thing being abandoned.
	var menu: PauseMenu = _pause()
	menu.open()
	watch_signals(menu)

	_press(menu, "LeaveButton")

	assert_signal_emitted(menu, "leave_requested")


func test_quitting_stays_open_until_the_host_acts() -> void:
	# Closing first would flash the board for a frame on the way out.
	var menu: PauseMenu = _pause()
	menu.open()
	watch_signals(menu)

	_press(menu, "QuitButton")

	assert_signal_emitted(menu, "quit_requested")
	assert_true(menu.is_open())


func test_the_volume_slider_applies_without_a_preview_clip() -> void:
	# The title screen plays a clip so you can hear the level. In a match that
	# would be a bull-market sound in a year that might be a bear one.
	var menu: PauseMenu = _pause()
	menu.open()
	var slider: HSlider = menu.settings_panel().get_node("%VolumeSlider")

	slider.value = 35

	assert_eq(Audio.volume_percent(), 35)
	assert_null(Audio.preview_voice().stream, "no clip was loaded")
	Audio.set_volume_percent(100)


func test_escape_during_a_match_opens_the_pause_menu() -> void:
	# It used to go straight to "leave the game?", which made the one key that
	# does anything mid-match a key that offers to end your game.
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())

	host.show_pause_menu()

	assert_not_null(host.pause_menu())
	assert_true(host.pause_menu().is_open())


func test_leaving_from_the_pause_menu_still_asks_first() -> void:
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())
	host.show_pause_menu()

	_press(host.pause_menu(), "LeaveButton")

	assert_not_null(host.leave_prompt(), "the confirmation was raised")
	assert_true(host.leave_prompt().is_open())


func test_the_pause_menu_does_not_survive_a_screen_change() -> void:
	# Left open across a swap it would sit over the title screen, where none
	# of its buttons mean anything.
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())
	host.show_pause_menu()

	host.show_menu()

	assert_false(host.pause_menu().is_open())


func test_the_title_screen_has_a_way_out_of_the_game() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	watch_signals(menu)

	_press(menu, "QuitButton")

	assert_signal_emitted(menu, "quit_requested")
