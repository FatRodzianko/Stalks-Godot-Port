extends GutTest
## The scrolling name label.
##
## The stalk names are the funniest thing in the game, so the board shows them in
## full and scrolls the ones that do not fit rather than abbreviating them.

const LONG: String = "My Pillow, Your Pillow, We're All Pillows!"
const SHORT: String = "PG&Enron"

var _label: MarqueeLabel


func before_each() -> void:
	_label = MarqueeLabel.new()
	# The real theme, so the label measures against Terminus's 6px cell rather
	# than Godot's default font. Without it "characters that fit" means something
	# quite different and these tests measure nothing useful.
	_label.theme = load("res://assets/themes/stalks_theme.tres")
	# 72px is a twelve-character column at that cell.
	_label.custom_minimum_size = Vector2(72, 12)
	_label.size = Vector2(72, 12)
	add_child_autofree(_label)
	await get_tree().process_frame


func test_it_shows_the_whole_name_by_default() -> void:
	_label.set_full_text(LONG)
	assert_eq(_label.text, LONG, "the text is stored whole, not pre-truncated")
	assert_eq(_label.full_text(), LONG)


func test_the_full_name_is_always_available_on_hover() -> void:
	_label.set_full_text(LONG)
	assert_eq(_label.tooltip_text, LONG)


func test_a_long_name_is_reported_as_overflowing() -> void:
	_label.set_full_text(LONG)
	assert_true(_label.overflows(), "42 characters cannot fit a 12-character column")


func test_a_short_name_does_not_overflow() -> void:
	_label.set_full_text(SHORT)
	assert_false(_label.overflows())


func test_a_short_name_never_scrolls() -> void:
	# Most rows should sit still; only the long ones move.
	_label.set_full_text(SHORT)
	_label.start_scrolling()
	assert_false(_label.is_scrolling(), "a name that fits has nothing to scroll to")


func test_a_long_name_scrolls_when_asked() -> void:
	_label.set_full_text(LONG)
	_label.start_scrolling()
	assert_true(_label.is_scrolling())


func test_scrolling_advances_the_text_one_character_at_a_time() -> void:
	_label.set_full_text(LONG)
	_label.start_scrolling()

	# The first few steps are the deliberate pause on the start of the name.
	for i: int in MarqueeLabel.HOLD_STEPS:
		_label._step()
	assert_eq(_label.text, LONG, "it should hold on the start first")

	_label._step()
	assert_eq(_label.text, LONG.substr(1), "then advance one character")
	_label._step()
	assert_eq(_label.text, LONG.substr(2))


func test_scrolling_returns_to_the_start_after_reaching_the_end() -> void:
	_label.set_full_text(LONG)
	_label.start_scrolling()
	for i: int in 200:
		_label._step()
	assert_true(_label.text.length() > 0, "it should never scroll into emptiness")
	assert_true(LONG.ends_with(_label.text) or _label.text == LONG,
		"whatever is shown is always a tail of the real name, got: %s" % _label.text)


func test_stopping_restores_the_start_of_the_name() -> void:
	_label.set_full_text(LONG)
	_label.start_scrolling()
	for i: int in 12:
		_label._step()
	assert_ne(_label.text, LONG, "it should have moved")

	_label.stop_scrolling()
	assert_false(_label.is_scrolling())
	assert_eq(_label.text, LONG, "and reset so the row reads normally again")


func test_changing_the_name_resets_any_scroll() -> void:
	_label.set_full_text(LONG)
	_label.start_scrolling()
	for i: int in 12:
		_label._step()

	_label.set_full_text(SHORT)
	assert_eq(_label.text, SHORT)
	assert_false(_label.is_pinned())


func test_clicking_pins_the_scroll_and_clicking_again_releases_it() -> void:
	_label.set_full_text(LONG)

	_label._on_gui_input(_click())
	assert_true(_label.is_pinned(), "a click should pin it so the mouse can move away")
	assert_true(_label.is_scrolling())

	_label._on_gui_input(_click())
	assert_false(_label.is_pinned())
	assert_false(_label.is_scrolling())


func test_clicking_a_name_that_fits_does_nothing() -> void:
	_label.set_full_text(SHORT)
	_label._on_gui_input(_click())
	assert_false(_label.is_pinned())


func test_a_pinned_name_keeps_scrolling_when_the_mouse_leaves() -> void:
	_label.set_full_text(LONG)
	_label._on_gui_input(_click())
	_label._on_mouse_exited()
	assert_true(_label.is_scrolling(), "pinning is what lets you read it hands-free")


func test_hovering_scrolls_and_leaving_stops() -> void:
	_label.set_full_text(LONG)

	_label._on_mouse_entered()
	assert_true(_label.is_scrolling())

	_label._on_mouse_exited()
	assert_false(_label.is_scrolling())
	assert_eq(_label.text, LONG)


func _click() -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event
