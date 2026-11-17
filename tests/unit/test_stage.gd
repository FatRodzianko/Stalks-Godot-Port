extends GutTest
## The root scene: the window, and the game shown inside it.
##
## `Stage` draws the game into a `SubViewport` of exactly 640x360 and enlarges
## it by a whole number to fill the window, centred, with black around the
## rest. See decisions.md D96.
##
## **None of this can be seen headless**, so what these cover is the
## arithmetic and the wiring: that the picture keeps its size, that the
## enlargement is a whole number, that it is centred on whole pixels, and that
## the two properties the whole design leans on are actually set. The last of
## those matters most — both were established by running Godot rather than by
## reading about it (`tools/subviewport_spike.gd`, `tools/popup_spike.gd`), and
## a silent change to either would be found by a player, not by a test.


const StageScene: PackedScene = preload("res://src/ui/stage.tscn")

## What was in the real settings file before these tests ran.
var _saved: UserSettings


## Every test here builds a `Stage`, and a `Stage` switches the CRT effect to
## whatever the settings file says. Without this they inherit whatever the last
## run on this machine left — and since the effect changes how the picture is
## sampled, a test asserting the sampling fails or passes depending on how
## somebody last played the game. That is the second time this exact shape of
## bug has bitten in this suite; see `test_crt_overlay.gd` for the first.
func before_each() -> void:
	_saved = UserSettings.load_from()

	var known: UserSettings = UserSettings.load_from()
	known.crt_effect = false
	known.save_to()


func after_each() -> void:
	_saved.save_to()


func _stage() -> Stage:
	var stage: Stage = StageScene.instantiate()
	add_child_autofree(stage)
	return stage


## Lays the stage out for a window of `size` without there being one.
##
## **It does not resize the root viewport**, which was the first version and
## was a bug: the root is shared with every other test in the suite, so
## leaving it at 1920x1201 broke the next test that pushed input at it. The
## splash screen stopped hearing keypresses and the failure pointed at the
## splash, which had nothing to do with it.
func _laid_out_for(stage: Stage, size: Vector2i) -> void:
	stage.fit_to(size)


func test_the_game_is_drawn_at_the_layout_grid_and_nothing_else() -> void:
	# The whole point. Every screen in the game is built for 640x360 and no
	# window size is allowed to change that.
	assert_eq(_stage().picture_size(), Vector2i(640, 360))


func test_the_screen_host_lives_inside_that_viewport() -> void:
	var stage: Stage = _stage()

	assert_eq(stage.game().get_viewport(), stage.game_viewport())


func test_a_window_of_exactly_the_right_size_is_filled_completely() -> void:
	var stage: Stage = _stage()

	_laid_out_for(stage, Vector2i(1280, 720))

	assert_eq(stage.picture_scale(), 2)
	assert_eq(stage.screen_control().size, Vector2(1280, 720), "no bars")
	assert_eq(stage.screen_control().position, Vector2.ZERO)


func test_every_rung_of_the_ladder_fills_its_window_exactly() -> void:
	# This is why 960x540 and 1600x900 were dropped: they are the only 16:9
	# sizes on the old ladder that cannot be filled by a whole multiple.
	var stage: Stage = _stage()

	for rung: Vector2i in DisplaySettings.LADDER:
		_laid_out_for(stage, rung)
		assert_eq(
			stage.screen_control().size, Vector2(rung),
			"%s should be filled edge to edge" % DisplaySettings.describe(rung)
		)


func test_a_taller_window_gets_bars_above_and_below_only() -> void:
	# 16:10, which is every Steam Deck and a good many laptops. The width is a
	# whole multiple, so only the height is left over.
	var stage: Stage = _stage()

	_laid_out_for(stage, Vector2i(1280, 800))

	assert_eq(stage.picture_scale(), 2)
	assert_eq(stage.screen_control().size, Vector2(1280, 720))
	assert_eq(stage.screen_control().position, Vector2(0, 40), "centred")


func test_a_window_that_is_not_a_whole_multiple_is_letterboxed() -> void:
	# The cost of the design, stated as a test rather than left to be
	# discovered: 1366x768 shows a 1280x720 picture with a border all round.
	var stage: Stage = _stage()

	_laid_out_for(stage, Vector2i(1366, 768))

	assert_eq(stage.picture_scale(), 2)
	assert_eq(stage.screen_control().size, Vector2(1280, 720))
	assert_eq(stage.screen_control().position, Vector2(43, 24))


func test_the_picture_never_lands_on_half_a_pixel() -> void:
	# Half a pixel of offset resamples the whole picture and throws away the
	# reason for enlarging by a whole number at all.
	var stage: Stage = _stage()

	for size: Vector2i in [
		Vector2i(1281, 721), Vector2i(1367, 769), Vector2i(1920, 1201)
	]:
		_laid_out_for(stage, size)
		var at: Vector2 = stage.screen_control().position
		assert_eq(at, at.floor(), "whole pixels at %s" % size)


func test_a_window_smaller_than_the_picture_still_shows_it() -> void:
	# Never zero. A window this small is not a thing anybody will use, but
	# scaling by nothing would leave a blank screen rather than a cramped one.
	var stage: Stage = _stage()

	_laid_out_for(stage, Vector2i(320, 180))

	assert_eq(stage.picture_scale(), 1)


func test_the_effect_is_told_how_far_the_picture_is_enlarged() -> void:
	# The shader cannot work it out for itself: `fwidth` returns zero under the
	# Compatibility renderer, and without this number its edge reconstruction
	# collapses to nearest-neighbour in silence. See decisions.md D96.
	var stage: Stage = _stage()

	_laid_out_for(stage, Vector2i(2560, 1440))

	assert_eq(stage.crt_overlay().enlargement, 4)


func test_the_picture_is_sampled_as_whole_pixels() -> void:
	# The game is pixel art. Filtering the enlargement would soften every
	# letter in it, and at a whole multiple there is nothing to interpolate.
	# With the effect off, which is how a fresh stage comes up.
	assert_eq(
		_stage().screen_control().texture_filter,
		CanvasItem.TEXTURE_FILTER_NEAREST
	)


## Dropdowns and tooltips are `Window`s, not `Control`s, and are placed in
## their own space. Without this they are drawn in the window around the game
## instead of in the picture: still beside their own button, but at the
## monitor's resolution and outside any effect. Measured in
## `tools/popup_spike.gd`.
func test_dropdowns_are_kept_inside_the_picture() -> void:
	assert_true(_stage().game_viewport().gui_embed_subwindows)


## A `SubViewportContainer` transforms mouse coordinates into its viewport
## itself, but only when it is the thing doing the stretching. Measured in
## `tools/subviewport_spike.gd`.
func test_the_container_owns_the_stretch_so_input_is_transformed() -> void:
	assert_true(_stage().screen_control().stretch)
