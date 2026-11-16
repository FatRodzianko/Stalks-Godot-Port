class_name ConfirmPanel
extends Control
## A modal yes/no question over the screen that owns it.
##
## Built as a widget rather than Godot's `ConfirmationDialog` because that opens
## a real OS-level popup window, which would escape the 640x360 viewport and
## break the pixel grid (docs/decisions.md D40). This is an ordinary `Control`
## inside the game's own resolution, styled by the shared theme like everything
## else.
##
## It knows nothing about loans or about what it is asking. The screen supplies
## the question and decides what a yes means.


## The player said yes. Carries nothing: the caller knows what it asked.
signal confirmed

## The player said no, or dismissed it.
signal cancelled


## How long a change that could make the game unreadable gets to be confirmed
## before it is undone. Fifteen seconds is the convention every other game
## uses for a resolution change, and it is long enough to find the mouse on a
## display that has just gone black.
const REVERT_SECONDS: int = 15


## Seconds left before this answers "no" by itself, or 0 when nothing is
## counting down.
var _remaining: int = 0

## The question without the countdown line, so the line can be rewritten each
## second without the question being lost.
var _question: String = ""

var _countdown: Timer

@onready var _message: Label = %Message
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm)
	_cancel_button.pressed.connect(_on_cancel)

	# Built here rather than in the scene because it is machinery, not layout,
	# and a reader looking for why this panel can answer itself should find it
	# next to the code that does it.
	_countdown = Timer.new()
	_countdown.wait_time = 1.0
	add_child(_countdown)
	_countdown.timeout.connect(_on_countdown_tick)

	hide_panel()


## Shows the question. `confirm_text` labels the yes button, so it can say what
## will happen ("End the year anyway") rather than a bare "OK" — a player
## reading only the buttons should still understand the choice.
func ask(question: String, confirm_text: String, cancel_text: String) -> void:
	_stop_countdown()
	_question = question
	_message.text = question
	_confirm_button.text = confirm_text
	_cancel_button.text = cancel_text
	visible = true
	# The safe option takes focus, so a stray Enter does not commit to the
	# irreversible one.
	_cancel_button.grab_focus()


## Asks, and answers "no" itself if nobody replies within `seconds`.
##
## For a change the player might not be able to undo by hand — a resolution
## their monitor cannot display, where the settings screen they would need is
## the thing that has just become unreadable. Waiting it out is the safe move,
## so waiting is what doing nothing does.
func ask_with_countdown(
	question: String, confirm_text: String, cancel_text: String, seconds: int = REVERT_SECONDS
) -> void:
	ask(question, confirm_text, cancel_text)
	_remaining = maxi(seconds, 1)
	_show_remaining()
	_countdown.start()


func hide_panel() -> void:
	_stop_countdown()
	visible = false


func is_open() -> bool:
	return visible


## Seconds left on the countdown, or 0 if nothing is counting down.
func seconds_remaining() -> int:
	return _remaining


func _on_confirm() -> void:
	hide_panel()
	confirmed.emit()


func _on_cancel() -> void:
	hide_panel()
	cancelled.emit()


## One second gone. At zero this says no on the player's behalf.
func _on_countdown_tick() -> void:
	_remaining -= 1
	if _remaining <= 0:
		_on_cancel()
		return
	_show_remaining()


func _show_remaining() -> void:
	_message.text = "%s\n\nGoing back in %d..." % [_question, _remaining]


func _stop_countdown() -> void:
	_remaining = 0
	if _countdown != null:
		_countdown.stop()


## Escape dismisses, which is the same as saying no.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		accept_event()
		_on_cancel()
