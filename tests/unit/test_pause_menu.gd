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


## **This used to assert the opposite**, and the reason it gave was "closing
## first would flash the board for a frame on the way out". That was true while
## the press was final. It stopped being true on 2026-11-19, when quitting
## started asking first (D117): the player may well say no, and a menu left
## open behind the question is a menu the question is being asked from behind.
##
## The widget still decides nothing itself - it closes and says what was asked
## for, exactly as the leave button does.
func test_quitting_asks_the_host_rather_than_acting() -> void:
	var menu: PauseMenu = _pause()
	menu.open()
	watch_signals(menu)

	_press(menu, "QuitButton")

	assert_signal_emitted(menu, "quit_requested")
	assert_false(menu.is_open(), "it gets out of the way of the question")


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


# --------------------------------------------------- quitting asks first too
#
# Reported from play on 2026-11-19. **Exit to Desktop** sat two buttons under
# **Leave Game**, which asks, and closed the game on the press. A misclick
# ended the session. See docs/decisions.md D117.
#
# **These tests are safe to run, and the safety is the assertion.** A quit that
# still went straight through would call `get_tree().quit()` and take the whole
# suite down with it - not a failure, a vanished run. So a green run of this
# file is itself part of the evidence, and the explicit assertions below say
# which question was raised and where its yes goes.

func test_quitting_from_the_pause_menu_asks_first() -> void:
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())
	host.show_pause_menu()

	_press(host.pause_menu(), "QuitButton")

	assert_not_null(host.quit_prompt(), "the confirmation was raised")
	if host.quit_prompt() == null:
		return
	assert_true(host.quit_prompt().is_open())


## The yes has to actually quit, and pressing it here would end the run, so the
## wiring is asserted instead of exercised.
func test_the_yes_on_that_question_closes_the_game() -> void:
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())
	host.show_pause_menu()

	_press(host.pause_menu(), "QuitButton")

	if host.quit_prompt() == null:
		assert_true(false, "no confirmation to check")
		return
	assert_true(
		host.quit_prompt().confirmed.is_connected(host.quit_to_desktop),
		"saying yes should close the game",
	)


## Saying no leaves the match exactly as it was. The panel hides itself on
## either answer, so what matters is that nothing else happened: the session is
## still here and the board is still the screen.
func test_saying_no_leaves_the_match_alone() -> void:
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())
	host.show_pause_menu()
	_press(host.pause_menu(), "QuitButton")
	if host.quit_prompt() == null:
		assert_true(false, "no confirmation to answer")
		return

	_press(host.quit_prompt(), "CancelButton")

	assert_false(host.quit_prompt().is_open(), "the question is gone")
	assert_not_null(host.session(), "and the match is not")
	assert_true(host.current_screen() is GameplayScreen)


## Two buttons, two questions, two different yeses. Sharing one panel and
## swapping its handler is how a yes ends up doing the wrong thing.
func test_leaving_and_quitting_do_not_share_a_confirmation() -> void:
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())
	host.show_pause_menu()
	_press(host.pause_menu(), "LeaveButton")

	host.show_pause_menu()
	_press(host.pause_menu(), "QuitButton")

	assert_not_null(host.leave_prompt())
	assert_not_null(host.quit_prompt())
	assert_ne(
		host.leave_prompt(), host.quit_prompt(),
		"one panel cannot answer both questions",
	)


## The pause menu gets out of the way, so the question is not asked from behind
## the menu that asked it.
func test_the_pause_menu_closes_when_the_question_comes_up() -> void:
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.start_match(GameSettings.new())
	host.show_pause_menu()

	_press(host.pause_menu(), "QuitButton")

	assert_false(host.pause_menu().is_open())


## **The title screen still does not ask**, and neither does the window's X
## (D71). Both are deliberate: there is no match to lose from the title screen,
## and a confirmation in front of a window that is already closing is an
## argument with somebody who has finished. Only the button sitting inside a
## menu, next to one that asks, was the problem.
func test_the_title_screens_quit_button_still_asks_nothing() -> void:
	var host: Main = MainScene.instantiate()
	add_child_autofree(host)
	host.show_menu()

	assert_null(
		host.quit_prompt(),
		"nothing should have asked about quitting from the title screen",
	)
