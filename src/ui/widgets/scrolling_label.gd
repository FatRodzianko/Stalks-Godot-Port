class_name ScrollingLabel
extends Label
## A label that creeps through its text a line at a time when there is more of
## it than fits.
##
## The sideways cousin of this is `MarqueeLabel`, which scrolls a stalk's name
## through a narrow column by whole characters. This one scrolls *lines* of
## wrapped text through a panel of fixed height, which is what a paragraph
## needs. Hovering starts it and clicking pins it, exactly as the names behave,
## so a player meets the same gesture twice rather than two different ones.
##
## **Why this exists.** Three of the game's ninety special event descriptions
## run past the three lines the top bar reserves for them, and were being cut
## off mid-sentence. Shrinking the font was tried first and does not work: see
## decisions.md D100 for the measurements, but in short Terminus has no
## designed shape below size 12 and the smaller sizes come out mangled.
##
## **Most descriptions never move.** `overflows()` is false for eighty-seven of
## the ninety, and a label that does not overflow never starts its timer.


## Seconds between line steps. Much slower than the name marquee's 0.2, because
## a line of prose takes longer to read than a few more characters of a name.
const STEP_SECONDS: float = 1.6

## Steps to wait at the top and bottom, so the first and last lines can be read
## rather than glimpsed.
const HOLD_STEPS: int = 2


var _pinned: bool = false
var _hold: int = 0
var _timer: Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	_timer = Timer.new()
	_timer.wait_time = STEP_SECONDS
	_timer.timeout.connect(_step)
	add_child(_timer)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


## Sets the text and returns to the top.
##
## Always use this rather than assigning `text`, or a new description inherits
## the scroll position of the one before it and opens halfway down.
func set_full_text(value: String) -> void:
	text = value
	_reset()
	# The whole thing is in the tooltip as well, for a player who would rather
	# read it at once than wait for it.
	tooltip_text = value if overflows() else ""


## Whether there is more text than the reserved lines can show.
func overflows() -> bool:
	return max_lines_visible > 0 and get_line_count() > max_lines_visible


func is_scrolling() -> bool:
	return _timer != null and not _timer.is_stopped()


func is_pinned() -> bool:
	return _pinned


## The furthest down it will go: the last line, sitting at the bottom.
func furthest_line() -> int:
	return maxi(0, get_line_count() - max_lines_visible)


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


## Moves on one line. Public so a test does not have to wait out the timer.
func step() -> void:
	_step()


func _reset() -> void:
	lines_skipped = 0
	_hold = 0


func _step() -> void:
	if _hold > 0:
		_hold -= 1
		return

	var furthest: int = furthest_line()
	if furthest == 0:
		stop_scrolling()
		return

	lines_skipped += 1
	if lines_skipped > furthest:
		# Back to the top, and pause there before setting off again.
		lines_skipped = 0
		_hold = HOLD_STEPS


func _on_mouse_entered() -> void:
	if not _pinned:
		start_scrolling()


func _on_mouse_exited() -> void:
	if not _pinned:
		stop_scrolling()


## Clicking pins it, so a long description can be read without holding the
## mouse still, and clicking again lets it go back to the top.
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
