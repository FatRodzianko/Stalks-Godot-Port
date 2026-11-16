class_name PauseMenu
extends Control
## The overlay Escape puts over a match.
##
## **It pauses nothing**, and neither did the original's. A year only advances
## when every player presses Ready, so there is no clock to stop — and in a
## multiplayer game stopping one would be a way to stall everybody else. What
## this is for is the three things a player mid-match otherwise cannot do:
## change a setting, leave to the title screen, and close the game.
##
## **Why it has to exist at all.** In fullscreen there is no window to close.
## Without this, and without the title screen's quit button, the only way out
## of a running match is Alt+F4.
##
## **Settings is a button, not a row of controls.** The original's pause menu
## had a Settings button that swapped in the same panel as the title screen,
## and this does the same with the same `SettingsPanel` widget — sound,
## resolution and fullscreen. A volume slider sitting on the pause menu by
## itself was the first attempt and it answered only a third of the question.
##
## It decides nothing. Each button says what was asked for and the screen host
## does it — including the leave confirmation, which lives there because the
## session this would abandon lives there too.


## Close this and carry on playing.
signal resume_requested

## Go back to the title screen. The host asks before acting: leaving a match
## cannot be undone.
signal leave_requested

## Close the game.
signal quit_requested


@onready var _buttons_page: VBoxContainer = %ButtonsPage
@onready var _settings_page: VBoxContainer = %SettingsPage
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _leave_button: Button = %LeaveButton
@onready var _quit_button: Button = %QuitButton
@onready var _back_button: Button = %BackButton
@onready var _settings: SettingsPanel = %Settings


func _ready() -> void:
	_resume_button.pressed.connect(_on_resume_pressed)
	_settings_button.pressed.connect(show_settings)
	_leave_button.pressed.connect(_on_leave_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_back_button.pressed.connect(show_buttons)
	close()


## Shows the menu, always on its first page.
##
## Reopening on whatever page it was left on would mean Escape sometimes
## produced a settings panel and sometimes a menu, for no reason the player
## could see.
func open() -> void:
	show_buttons()
	visible = true
	# The harmless button takes focus, so Enter or Space on a keyboard cannot
	# land on the one that ends the match.
	_resume_button.grab_focus()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## True when the settings page is the one on display.
func is_showing_settings() -> bool:
	return _settings_page.visible


func show_buttons() -> void:
	_buttons_page.visible = true
	_settings_page.visible = false


## Swaps in the shared settings panel.
##
## Refreshed on the way in because the title screen shows the same controls and
## may have changed something since this was last opened.
func show_settings() -> void:
	_settings.refresh()
	_buttons_page.visible = false
	_settings_page.visible = true
	_back_button.grab_focus()


## The settings panel. For tests.
func settings_panel() -> SettingsPanel:
	return _settings


func _on_resume_pressed() -> void:
	close()
	resume_requested.emit()


func _on_leave_pressed() -> void:
	close()
	leave_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


## Escape backs out one step: from settings to the buttons, from the buttons to
## the game. The key that opens the menu is the key that gets rid of it.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
		return
	accept_event()
	if is_showing_settings():
		show_buttons()
		return
	_on_resume_pressed()
