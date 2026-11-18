class_name StalkPanel
extends Control
## What a company is, and who is in it.
##
## Opened by clicking a row on the board. Shows the stalk's name, the paragraph
## about it from its own resource file, and the list of players holding it.
## See docs/decisions.md D103.
##
## **Names, not amounts.** A player can see *that* a rival has bought into a
## company and not how much they hold. The host sends the membership and keeps
## the sizes back (`StateSync.encode_player`), so this panel could not show the
## amounts even if it wanted to.
##
## **It knows nothing about the market.** It is handed a name, a description
## and a list of names; working out who those are belongs to the screen.


## The player has closed it.
signal dismissed


## Shown in place of the list when nobody holds any.
const NOBODY: String = "Nobody owns any yet."

## Shown in place of the description when a stalk has none written.
const NO_DESCRIPTION: String = "No description."


@onready var _name_label: Label = %StalkName
@onready var _description: Label = %Description
@onready var _investors: Label = %Investors
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	hide()


## Puts a company's details up.
##
## `investors` is the display names of the players holding it, in board order.
func show_stalk(display_name: String, description: String, investors: PackedStringArray) -> void:
	_name_label.text = display_name
	_description.text = description if not description.is_empty() else NO_DESCRIPTION
	_investors.text = NOBODY if investors.is_empty() else "\n".join(investors)

	show()
	_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	dismissed.emit()


func is_open() -> bool:
	return visible


## For tests.
func investors_text() -> String:
	return _investors.text


## For tests.
func description_text() -> String:
	return _description.text


## Clicking anywhere closes it, as the news panel does, so the gesture is the
## same wherever a panel appears.
func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	accept_event()
	close()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
		return
	accept_event()
	close()
