extends GutTest
## Which resolutions the game offers, and what each one means.
##
## All of this is arithmetic over a monitor size handed in as a number, so
## every case below runs on a machine whose real monitor is nothing like the
## one being tested — including monitors nobody here owns. That is the point
## of keeping it out of `DisplayMode`.


const HD: Vector2i = Vector2i(1920, 1080)
const SIXTEEN_TEN: Vector2i = Vector2i(1920, 1200)
const LAPTOP: Vector2i = Vector2i(1366, 768)
const FOUR_K: Vector2i = Vector2i(3840, 2160)


func test_every_offer_is_exactly_sixteen_by_nine() -> void:
	# Not 854x480, which is the usual approximation and is 16:9.0075. A list
	# with one near-miss in it produces one resolution whose bars are a
	# different size from everybody else's.
	for size: Vector2i in DisplaySettings.LADDER:
		assert_eq(size.x * 9, size.y * 16, DisplaySettings.describe(size))


func test_a_monitor_is_offered_only_what_it_can_show() -> void:
	var choices: Array[Vector2i] = DisplaySettings.choices_for(HD)

	assert_true(choices.has(HD), "its own size")
	assert_false(choices.has(Vector2i(2560, 1440)), "larger than the monitor")


func test_a_bigger_monitor_is_offered_more() -> void:
	assert_gt(
		DisplaySettings.choices_for(FOUR_K).size(),
		DisplaySettings.choices_for(HD).size(),
	)


func test_an_absurdly_small_screen_still_gets_one_choice() -> void:
	# A blank dropdown would be a game that cannot be configured at all, which
	# is a worse answer than one option that does not fit.
	var choices: Array[Vector2i] = DisplaySettings.choices_for(Vector2i(320, 200))

	assert_eq(choices.size(), 1)
	assert_eq(choices[0], DisplaySettings.LADDER[0])


func test_the_native_choice_is_the_largest_that_fits() -> void:
	assert_eq(DisplaySettings.native_choice(HD), HD)


func test_a_sixteen_ten_monitor_gets_the_tallest_sixteen_by_nine() -> void:
	# 1920x1200 cannot show a 16:9 image at its full height. It gets 1920x1080
	# and a bar above and below, rather than a stretched picture.
	assert_eq(DisplaySettings.native_choice(SIXTEEN_TEN), HD)


func test_an_odd_laptop_panel_gets_the_largest_that_fits_inside_it() -> void:
	# 1366x768 is not 16:9 and is between two rungs. 1280x720 fits; 1600x900
	# does not.
	assert_eq(DisplaySettings.native_choice(LAPTOP), Vector2i(1280, 720))


func test_a_first_run_resolves_to_the_monitors_own_size() -> void:
	assert_eq(DisplaySettings.resolve(UserSettings.USE_NATIVE, HD), HD)


func test_a_saved_size_is_honoured() -> void:
	assert_eq(DisplaySettings.resolve(Vector2i(1280, 720), HD), Vector2i(1280, 720))


func test_a_saved_size_too_big_for_the_monitor_is_reduced() -> void:
	# The settings file moved to a smaller screen, or the monitor was
	# replaced. Rendering an image the display cannot show would strand the
	# player with no way back to the settings.
	assert_eq(DisplaySettings.resolve(FOUR_K, HD), HD)


func test_a_saved_size_that_is_not_on_the_ladder_is_replaced() -> void:
	# A hand-edited file, or a list from an older version.
	assert_eq(DisplaySettings.resolve(Vector2i(1366, 768), HD), HD)


func test_the_scale_is_how_many_times_the_picture_is_enlarged() -> void:
	# Whole numbers. The picture is 640x360 and is shown at a whole multiple of
	# that, so nothing is ever resampled. See decisions.md D96.
	assert_eq(DisplaySettings.integer_scale_for(Vector2i(640, 360)), 1)
	assert_eq(DisplaySettings.integer_scale_for(Vector2i(1280, 720)), 2)
	assert_eq(DisplaySettings.integer_scale_for(Vector2i(1920, 1080)), 3)
	assert_eq(DisplaySettings.integer_scale_for(Vector2i(2560, 1440)), 4)


func test_a_window_that_does_not_divide_evenly_is_rounded_down() -> void:
	# 1366x768 is 2.13 times the picture. Enlarging by 2.13 would make some
	# source pixels three screen pixels wide and others two; enlarging by 2
	# leaves a border instead, which is the trade this design makes.
	assert_eq(DisplaySettings.integer_scale_for(Vector2i(1366, 768)), 2)
	assert_eq(DisplaySettings.image_size_for(Vector2i(1366, 768)), Vector2i(1280, 720))


func test_the_shorter_side_decides() -> void:
	# A very wide window still only fits what its height allows.
	assert_eq(DisplaySettings.integer_scale_for(Vector2i(5120, 1440)), 4)


func test_a_window_smaller_than_the_picture_still_gets_a_whole_one() -> void:
	# Never zero, which would be a blank screen.
	assert_eq(DisplaySettings.integer_scale_for(Vector2i(320, 180)), 1)
	assert_eq(DisplaySettings.integer_scale_for(Vector2i.ZERO), 1)


func test_every_rung_of_the_ladder_is_a_whole_multiple() -> void:
	# The rule that got 960x540 and 1600x900 dropped. If a rung ever fails
	# this, a player choosing it would get a window the game cannot fill.
	for rung: Vector2i in DisplaySettings.LADDER:
		assert_eq(
			DisplaySettings.image_size_for(rung), rung,
			"%s should be fillable exactly" % DisplaySettings.describe(rung)
		)


func test_a_resolution_reads_as_a_resolution() -> void:
	assert_eq(DisplaySettings.describe(HD), "1920 x 1080")
