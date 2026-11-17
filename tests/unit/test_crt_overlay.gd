extends GutTest
## The optional CRT effect.
##
## **What a test can and cannot reach here.** How it looks is not checkable:
## the suite runs headless, nothing is rendered, and the shader is never even
## compiled. Judging the picture is a manual step and is written up as one in
## docs/manual-testing.md.
##
## What these cover is everything around the shader, which is where the faults
## that would matter live. Two in particular:
##
##   * **A full-screen rectangle in front of the whole game must not take a
##     click.** Get that wrong and every press in the game is swallowed,
##     including the one that would turn the effect off again. There is no way
##     out of that except a hand-edited settings file.
##   * **A screen change must not switch it off.** The development overlay is
##     deliberately hidden away from the title screen by `Main._swap`, and this
##     sits on a layer beside it; the obvious mistake is to treat the two the
##     same.


const OverlayScene: PackedScene = preload("res://src/ui/widgets/crt_overlay.tscn")
const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")
const PanelScene: PackedScene = preload("res://src/ui/widgets/settings_panel.tscn")

## What was in the real settings file before a test that has to write to it.
## Restored afterwards, so running the suite does not change how the game
## looks next time it is started by hand.
var _saved: UserSettings


## Keeps what was there, then puts the setting in a known state.
##
## **The known state is the point, and leaving it out was a real bug.** These
## tests share one real settings file with the game, so without this they
## inherit whatever the last run on this machine happened to leave. That is
## invisible until it bites: if the effect is already on, the settings panel
## opens with its box already ticked, and
## `test_the_settings_tick_box_turns_it_on_and_remembers` then ticks a ticked
## box - which changes nothing, emits no signal, and fails an assertion that
## has nothing wrong with it. It passed for a day and failed the moment a
## developer tool left the effect switched on.
func before_each() -> void:
	_saved = UserSettings.load_from()

	var known: UserSettings = UserSettings.load_from()
	known.crt_effect = false
	known.save_to()


func after_each() -> void:
	_saved.save_to()


func _overlay() -> CrtOverlay:
	var overlay: CrtOverlay = OverlayScene.instantiate()
	add_child_autofree(overlay)
	return overlay


func _glass(overlay: CrtOverlay) -> ColorRect:
	return overlay.get_node("Glass") as ColorRect


func test_an_overlay_starts_switched_off() -> void:
	assert_false(_overlay().is_enabled())


func test_it_can_be_switched_on_and_off() -> void:
	var overlay: CrtOverlay = _overlay()

	overlay.enable(true)
	assert_true(overlay.is_enabled())

	overlay.enable(false)
	assert_false(overlay.is_enabled())


func test_the_group_reaches_it_without_knowing_where_it_is() -> void:
	var overlay: CrtOverlay = _overlay()

	CrtOverlay.apply(get_tree(), true)
	assert_true(overlay.is_enabled(), "switched on through the group")

	CrtOverlay.apply(get_tree(), false)
	assert_false(overlay.is_enabled())


func test_applying_with_no_overlay_in_the_tree_is_harmless() -> void:
	# A widget built on its own in a test has no overlay above it, and the
	# settings panel is one of those.
	CrtOverlay.apply(get_tree(), true)
	pass_test("nothing to switch, and nothing broke")


## The fault that would make the game unplayable.
func test_the_glass_never_takes_a_click() -> void:
	var glass: ColorRect = _glass(_overlay())

	assert_eq(glass.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_the_glass_covers_the_whole_screen() -> void:
	# Anything less and the effect would stop partway across the picture.
	var glass: ColorRect = _glass(_overlay())

	assert_eq(glass.anchor_right, 1.0)
	assert_eq(glass.anchor_bottom, 1.0)


func test_the_glass_carries_the_shader() -> void:
	var glass: ColorRect = _glass(_overlay())
	var material: ShaderMaterial = glass.material as ShaderMaterial

	assert_not_null(material, "a shader material")
	assert_not_null(material.shader, "with a shader in it")


## Above the game, below the development overlay.
##
## Debugging text read through a barrel warp and a scanline comb is worse
## debugging text, and the overlay is not part of what a player sees anyway.
func test_it_draws_over_the_game_but_under_the_development_overlay() -> void:
	var overlay: CrtOverlay = _overlay()

	assert_gt(overlay.layer, 0, "over everything the game draws")
	assert_lt(overlay.layer, Main.DEV_OVERLAY_LAYER, "under the dev overlay")


func test_the_game_builds_one() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	assert_not_null(main.crt_overlay())


func test_the_game_switches_it_to_whatever_was_saved() -> void:
	var asked_for: UserSettings = UserSettings.load_from()
	asked_for.crt_effect = true
	asked_for.save_to()

	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	assert_true(main.crt_overlay().is_enabled())


func test_a_screen_change_does_not_switch_it_off() -> void:
	var asked_for: UserSettings = UserSettings.load_from()
	asked_for.crt_effect = true
	asked_for.save_to()

	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.show_menu()

	assert_true(main.crt_overlay().is_enabled(), "still on after a swap")


func test_the_settings_tick_box_turns_it_on_and_remembers() -> void:
	var overlay: CrtOverlay = _overlay()
	var panel: SettingsPanel = PanelScene.instantiate()
	add_child_autofree(panel)

	var box: CheckBox = panel.get_node("%CrtCheck")
	box.button_pressed = true

	assert_true(overlay.is_enabled(), "on at once, not at the next launch")
	assert_true(UserSettings.load_from().crt_effect, "and written down")


func test_the_settings_tick_box_turns_it_off_again() -> void:
	var overlay: CrtOverlay = _overlay()
	overlay.enable(true)
	var panel: SettingsPanel = PanelScene.instantiate()
	add_child_autofree(panel)

	var box: CheckBox = panel.get_node("%CrtCheck")
	box.button_pressed = true
	box.button_pressed = false

	assert_false(overlay.is_enabled())
	assert_false(UserSettings.load_from().crt_effect)


## The panel is shown in two places and the other copy may have been used in
## between, so it reads the setting again every time it comes back on screen.
func test_the_tick_box_shows_the_saved_state_when_the_panel_reopens() -> void:
	var panel: SettingsPanel = PanelScene.instantiate()
	add_child_autofree(panel)
	var box: CheckBox = panel.get_node("%CrtCheck")

	var asked_for: UserSettings = UserSettings.load_from()
	asked_for.crt_effect = true
	asked_for.save_to()
	panel.refresh()

	assert_true(box.button_pressed)
