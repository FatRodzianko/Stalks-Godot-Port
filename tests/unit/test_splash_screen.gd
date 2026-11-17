extends GutTest
## The studio logo shown as the game starts.
##
## Nothing here looks at it — Godot renders nothing headless. What these cover
## is the part that can go wrong without being seen: that it ends, that it ends
## only once, that anything a player presses gets rid of it, and above all that
## it does not appear in front of somebody who launched the game into
## something.


const SplashScene: PackedScene = preload("res://src/ui/screens/splash/splash_screen.tscn")
const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")


func _splash() -> SplashScreen:
	var splash: SplashScreen = SplashScene.instantiate()
	add_child_autofree(splash)
	return splash


## A click well outside anything, including the test runner's own panels.
##
## **The position matters and it is not about the splash.** A click goes
## through the interface before it becomes unhandled input, and in the test
## runner GUT's own panels sit in front of whatever a test builds — so a click
## at the origin lands on GUT and the splash never hears it. In the game there
## is nothing to land on: every node in the splash scene is
## `MOUSE_FILTER_IGNORE`, so a click anywhere falls through to the handler.
##
## This test used the origin for weeks and passed by luck. It started failing
## the moment the root viewport changed size, which is a fair warning about
## tests that quietly depend on where somebody else's interface happens to be.
func _click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(-4000, -4000)
	click.global_position = click.position
	return click


func _press(key: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.pressed = true
	return event


func test_it_says_when_it_is_over() -> void:
	var splash: SplashScreen = _splash()
	watch_signals(splash)

	splash.skip()

	assert_signal_emitted(splash, "finished")


## The fade ends by calling `skip`, and a key can land in the same frame. A
## second `finished` would open the menu twice, over the top of itself.
func test_it_is_only_ever_over_once() -> void:
	var splash: SplashScreen = _splash()
	watch_signals(splash)

	splash.skip()
	splash.skip()
	splash.skip()

	assert_signal_emit_count(splash, "finished", 1)


## Pushes an event the way a real one arrives.
##
## Mouse events have to be aimed somewhere no interface is, which `_click`
## explains.
func _skip_with(event: InputEvent) -> void:
	get_tree().root.push_input(event)


func test_a_keypress_gets_rid_of_it() -> void:
	# A splash that cannot be skipped is a tax on everybody who launches the
	# game more than once.
	var splash: SplashScreen = _splash()
	watch_signals(splash)

	_skip_with(_press(KEY_SPACE))
	await wait_process_frames(1)

	assert_signal_emitted(splash, "finished")


func test_a_mouse_click_gets_rid_of_it_too() -> void:
	# Somebody who has just launched the game may have no hand on the keyboard.
	var splash: SplashScreen = _splash()
	watch_signals(splash)

	_skip_with(_click())
	await wait_process_frames(1)

	assert_signal_emitted(splash, "finished")


func test_letting_go_of_a_key_does_not_count() -> void:
	# Otherwise the release of whatever launched the game could skip it before
	# a single frame of it had been seen.
	var splash: SplashScreen = _splash()
	watch_signals(splash)

	var release: InputEventKey = InputEventKey.new()
	release.keycode = KEY_SPACE
	release.pressed = false
	_skip_with(release)
	await wait_process_frames(1)

	assert_signal_not_emitted(splash, "finished")


func test_it_ends_on_its_own_if_nobody_touches_it() -> void:
	var splash: SplashScreen = _splash()
	watch_signals(splash)

	await wait_seconds(
		SplashScreen.FADE_IN_SECONDS
		+ SplashScreen.HOLD_SECONDS
		+ SplashScreen.FADE_OUT_SECONDS
		+ 0.4
	)

	assert_signal_emitted(splash, "finished")


## The whole suite runs headless, so this is also the assertion that no test
## anywhere has to sit through a logo.
func test_a_headless_run_never_shows_it() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	assert_false(main.current_screen() is SplashScreen)


func test_it_hands_over_to_the_menu() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	main.show_splash()
	assert_true(main.current_screen() is SplashScreen)

	(main.current_screen() as SplashScreen).skip()

	assert_true(main.current_screen() is MainMenu)


## Pins the fade to its stated length.
##
## Added after the timing was changed and the splash looked unchanged on the
## next run: the constants are the only statement of how long it takes, and
## nothing was checking that the tween actually used them.
func test_the_fade_in_takes_the_time_it_says() -> void:
	var splash: SplashScreen = _splash()
	var logo: TextureRect = splash.get_node("%Logo")

	await wait_seconds(SplashScreen.FADE_IN_SECONDS * 0.5)
	var halfway: float = logo.modulate.a

	assert_lt(halfway, 0.85, "still fading in at the halfway mark")
	assert_gt(halfway, 0.15, "and not still at nothing")

	await wait_seconds(SplashScreen.FADE_IN_SECONDS * 0.6)
	assert_almost_eq(logo.modulate.a, 1.0, 0.05, "fully in once the fade is up")


func test_it_is_still_on_screen_well_past_the_old_running_time() -> void:
	# The whole splash used to be over in 2.5 seconds. If it ends at 2.5 now,
	# the constants are not reaching the tween.
	var splash: SplashScreen = _splash()
	watch_signals(splash)

	await wait_seconds(2.6)

	assert_signal_not_emitted(splash, "finished")
