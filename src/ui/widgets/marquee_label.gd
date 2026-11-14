class_name MarqueeLabel
extends Label
## A label that scrolls its text sideways when it is too long to fit.
##
## The stalk names are the funniest thing in the game — "My Pillow, Your Pillow,
## We're All Pillows!" — so the board shows them in full rather than abbreviating
## them. They do not fit a twelve-character column, so hovering a name scrolls it
## and clicking pins the scroll until clicked again.
##
## Scrolling is by whole characters, which is both authentic to a ticker display
## and exact on a monospace grid: there is no sub-pixel movement to blur.
##
## A name that already fits never scrolls, so most rows stay still.


## Seconds between character steps. Slow enough to read, quick enough to get
## through a long name before interest runs out.
const STEP_SECONDS: float = 0.2

## Steps to pause at each end, so the start and finish are readable.
const HOLD_STEPS: int = 5


var _full_text: String = ""
var _offset: int = 0
var _hold: int = 0
var _pinned: bool = false
var _timer: Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_text = true

	_timer = Timer.new()
	_timer.wait_time = STEP_SECONDS
	_timer.timeout.connect(_step)
	add_child(_timer)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


## Sets the text this label represents. Always store the whole string here, not
## a pre-truncated one, or there is nothing to scroll to.
func set_full_text(value: String) -> void:
	if value == _full_text:
		return
	_full_text = value
	tooltip_text = value
	_reset()


func full_text() -> String:
	return _full_text


## Whether the text is too long for the current width, and therefore scrollable.
func overflows() -> bool:
	return _full_text.length() > _visible_characters()


func is_scrolling() -> bool:
	return _timer != null and not _timer.is_stopped()


func is_pinned() -> bool:
	return _pinned


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

	_offset += 1
	if _offset > furthest:
		# Reached the end: pause on it, then start over.
		_offset = 0
		_hold = HOLD_STEPS
	text = _full_text.substr(_offset)


func _on_mouse_entered() -> void:
	if not _pinned:
		start_scrolling()


func _on_mouse_exited() -> void:
	if not _pinned:
		stop_scrolling()


## Clicking pins the scroll so a long name can be read without holding the mouse
## still, and clicking again releases it.
func _on_gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not overflows():
		return

	_pinned = not _pinned
	if _pinned:
		start_scrolling()
	else:
		stop_scrolling()
	accept_event()
