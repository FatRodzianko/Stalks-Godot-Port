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


@onready var _message: Label = %Message
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm)
	_cancel_button.pressed.connect(_on_cancel)
	hide_panel()


## Shows the question. `confirm_text` labels the yes button, so it can say what
## will happen ("End the year anyway") rather than a bare "OK" — a player
## reading only the buttons should still understand the choice.
func ask(question: String, confirm_text: String, cancel_text: String) -> void:
	_message.text = question
	_confirm_button.text = confirm_text
	_cancel_button.text = cancel_text
	visible = true
	# The safe option takes focus, so a stray Enter does not commit to the
	# irreversible one.
	_cancel_button.grab_focus()


func hide_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _on_confirm() -> void:
	hide_panel()
	confirmed.emit()


func _on_cancel() -> void:
	hide_panel()
	cancelled.emit()


## Escape dismisses, which is the same as saying no.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		accept_event()
		_on_cancel()
