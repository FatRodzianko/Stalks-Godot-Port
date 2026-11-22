class_name MarqueeLabel
extends Label
## A label that scrolls its text sideways when it is too long to fit.
##
## The stalk names are the funniest thing in the game — "My Pillow, Your Pillow,
## We're All Pillows!" — so the board shows them in full rather than abbreviating
## them. They do not fit a twelve-character column, so hovering a name scrolls
## it.
##
## **Hovering only. Clicks pass straight through**, because on the board a
## click on a row opens that company's details (decisions.md D103) and the name
## is the most obvious part of the row to click. Clicking used to pin the
## scroll so a long name could be read without holding the mouse still; the
## details panel shows the whole name anyway, so pinning was solving a problem
## that no longer exists and was swallowing the click that solves it better.
##
## Scrolling is by whole characters, which is both authentic to a ticker display
## and exact on a monospace grid: there is no sub-pixel movement to blur.
##
## A name that already fits never scrolls, so most rows stay still.


## Seconds between character steps. Slow enough to read, quick enough to get
## through a long name before interest runs out.
const STEP_SECONDS: float = 0.2

## Steps to pause on the start of the name before it moves (one second).
const HOLD_STEPS: int = 5

## Steps to pause on the end of the name before going back to the start (two
## seconds). Longer than the start, because the end is what the player has
## just scrolled to read. Reported from play on 2026-11-22: there used to be no
## pause here at all - the last characters showed for one step and it jumped
## straight back.
const END_HOLD_STEPS: int = 10


var _full_text: String = ""
var _offset: int = 0
var _hold: int = 0
var _timer: Timer


func _ready() -> void:
	# PASS, not STOP: this still wants `mouse_entered` and `mouse_exited` for
	# the hover, but a click must carry on to the row underneath.
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_text = true

	_timer = Timer.new()
	_timer.wait_time = STEP_SECONDS
	_timer.timeout.connect(_step)
	add_child(_timer)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## Sets the text this label represents. Always store the whole string here, not
## a pre-truncated one, or there is nothing to scroll to.
func set_full_text(value: String) -> void:
	if value == _full_text:
		return
	_full_text = value
	tooltip_text = value
	_reset()
	# A name that fits has nothing to scroll, so the timer stops rather than
	# running until its next tick notices. Matters when a row is reused for a
	# different stalk while the mouse is still over it.
	if not overflows():
		stop_scrolling()


func full_text() -> String:
	return _full_text


## Whether the text is too long for the current width, and therefore scrollable.
func overflows() -> bool:
	return _full_text.length() > _visible_characters()


func is_scrolling() -> bool:
	return _timer != null and not _timer.is_stopped()


## Starts scrolling if there is anything hidden. Public so a test, or a future
## "selected row" behaviour, can drive it without faking a mouse.
func start_scrolling() -> void:
	if not overflows():
		return
	_hold = HOLD_STEPS
	if _timer != null:
		_timer.start()


func stop_scrolling() -> void:
	if _timer != null:
		_timer.stop()
	_reset()


func _reset() -> void:
	_offset = 0
	_hold = 0
	text = _full_text


## How many characters fit at the current width. Exact on a monospace font,
## which is what the UI uses; for a proportional one this is an approximation
## that errs toward scrolling slightly early, which is harmless.
func _visible_characters() -> int:
	var font: Font = get_theme_font("font")
	var font_size: int = get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return _full_text.length()
	var cell: float = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if cell <= 0.0:
		return _full_text.length()
	return int(size.x / cell)


func _step() -> void:
	if _hold > 0:
		_hold -= 1
		return

	var furthest: int = maxi(0, _full_text.length() - _visible_characters())
	if furthest == 0:
		stop_scrolling()
		return

	if _offset >= furthest:
		# The end has been read: back to the start, and pause there.
		_offset = 0
		_hold = HOLD_STEPS
	else:
		_offset += 1
		if _offset == furthest:
			# Just reached the end: hold it so it can be read.
			_hold = END_HOLD_STEPS
	text = _full_text.substr(_offset)


func _on_mouse_entered() -> void:
	start_scrolling()


func _on_mouse_exited() -> void:
	stop_scrolling()
