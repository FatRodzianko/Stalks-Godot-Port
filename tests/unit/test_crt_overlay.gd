extends GutTest
## The optional CRT effect.
##
## **What a test can and cannot reach here.** How it looks is not checkable:
## the suite runs headless, nothing is rendered, and the shader is never even
## compiled. Judging the picture is a manual step and is written up as one in
## docs/manual-testing.md; `tools/crt_shot.gd` and `tools/crt_compare.gd` are
## how it is measured.
##
## What these cover is everything around the shader. The effect is a material
## on the control that shows the game (decisions.md D96), so the question is
## whether that material goes on and comes off at the right times — and above
## all whether a screen change switches it off, which is the mistake the
## development overlay's deliberate hiding invites.


const StageScene: PackedScene = preload("res://src/ui/stage.tscn")
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
## box — which changes nothing, emits no signal, and fails an assertion that
## has nothing wrong with it. It passed for a day and failed the moment a
## developer tool left the effect switched on.
func before_each() -> void:
	_saved = UserSettings.load_from()

	var known: UserSettings = UserSettings.load_from()
	known.crt_effect = false
	known.save_to()


func after_each() -> void:
	_saved.save_to()


func _overlay_on(target: CanvasItem) -> CrtOverlay:
	var overlay: CrtOverlay = CrtOverlay.new()
	overlay.target = target
	add_child_autofree(overlay)
	return overlay


func _something_to_draw_on() -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	add_child_autofree(rect)
	return rect


func _stage() -> Stage:
	var stage: Stage = StageScene.instantiate()
	add_child_autofree(stage)
	return stage


func test_an_overlay_starts_switched_off() -> void:
	assert_false(_overlay_on(_something_to_draw_on()).is_enabled())


func test_switching_it_on_puts_the_shader_on_its_target() -> void:
	var rect: ColorRect = _something_to_draw_on()
	var overlay: CrtOverlay = _overlay_on(rect)

	overlay.enable(true)

	assert_true(overlay.is_enabled())
	assert_eq(rect.material, CrtOverlay.MATERIAL, "the effect is the material")


func test_switching_it_off_takes_the_shader_away_again() -> void:
	# Not merely hidden. A material left on would keep costing a full-screen
	# pass every frame for a player who turned the effect off.
	var rect: ColorRect = _something_to_draw_on()
	var overlay: CrtOverlay = _overlay_on(rect)

	overlay.enable(true)
	overlay.enable(false)

	assert_null(rect.material)


## The fault this catches is invisible and shipped twice.
##
## A `CanvasItem`'s `texture_filter` overrides the `filter_linear` hint on the
## shader's own sampler. Left on nearest, the shader samples nearest whatever
## it asks for, and its edge reconstruction — which works by nudging where it
## reads from — does nothing at all. The picture still looks like a reasonable
## pixel-art upscale, just with a stair-step in every line the tube bends, so
## nothing announces that half the shader is inert.
func test_the_effect_switches_the_target_to_linear_sampling() -> void:
	var rect: ColorRect = _something_to_draw_on()
	var overlay: CrtOverlay = _overlay_on(rect)

	overlay.enable(true)

	assert_eq(rect.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR)


func test_turning_it_off_puts_nearest_sampling_back() -> void:
	# With no effect the target draws the picture itself at a whole multiple,
	# where there is nothing to interpolate and linear would only soften it.
	var rect: ColorRect = _something_to_draw_on()
	var overlay: CrtOverlay = _overlay_on(rect)

	overlay.enable(true)
	overlay.enable(false)

	assert_eq(rect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_an_overlay_with_nothing_to_draw_on_is_harmless() -> void:
	var overlay: CrtOverlay = CrtOverlay.new()
	add_child_autofree(overlay)

	overlay.enable(true)

	assert_true(overlay.is_enabled(), "it still remembers what was asked for")


func test_the_group_reaches_it_without_knowing_where_it_is() -> void:
	var rect: ColorRect = _something_to_draw_on()
	var overlay: CrtOverlay = _overlay_on(rect)

	CrtOverlay.apply(get_tree(), true)
	assert_true(overlay.is_enabled(), "switched on through the group")

	CrtOverlay.apply(get_tree(), false)
	assert_false(overlay.is_enabled())


func test_applying_with_no_overlay_in_the_tree_is_harmless() -> void:
	# A widget built on its own in a test has no overlay above it, and the
	# settings panel is one of those.
	CrtOverlay.apply(get_tree(), true)
	pass_test("nothing to switch, and nothing broke")


func test_the_game_builds_one() -> void:
	assert_not_null(_stage().crt_overlay())


func test_it_hangs_from_the_control_that_shows_the_picture() -> void:
	# Not from a rectangle in front of the game, which is what it used to be.
	var stage: Stage = _stage()

	assert_eq(stage.crt_overlay().target, stage.screen_control())


func test_the_game_switches_it_to_whatever_was_saved() -> void:
	var asked_for: UserSettings = UserSettings.load_from()
	asked_for.crt_effect = true
	asked_for.save_to()

	assert_true(_stage().crt_overlay().is_enabled())


func test_a_screen_change_does_not_switch_it_off() -> void:
	var asked_for: UserSettings = UserSettings.load_from()
	asked_for.crt_effect = true
	asked_for.save_to()

	var stage: Stage = _stage()
	stage.game().show_menu()

	assert_true(stage.crt_overlay().is_enabled(), "still on after a swap")


func test_the_settings_tick_box_turns_it_on_and_remembers() -> void:
	var rect: ColorRect = _something_to_draw_on()
	var overlay: CrtOverlay = _overlay_on(rect)
	var panel: SettingsPanel = PanelScene.instantiate()
	add_child_autofree(panel)

	var box: CheckBox = panel.get_node("%CrtCheck")
	box.button_pressed = true

	assert_true(overlay.is_enabled(), "on at once, not at the next launch")
	assert_true(UserSettings.load_from().crt_effect, "and written down")


func test_the_settings_tick_box_turns_it_off_again() -> void:
	var rect: ColorRect = _something_to_draw_on()
	var overlay: CrtOverlay = _overlay_on(rect)
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
