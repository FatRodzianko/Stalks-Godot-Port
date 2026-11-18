class_name NewsPanel
extends Control
## The year's special event, put in front of the player when the year turns.
##
## **Why this exists.** The event description lives in a strip along the top of
## the board, where it is easy to miss entirely - and it is the one thing each
## year that changes the market under you. Reported from play on 2026-11-17.
## Showing it in the middle of the screen once a year makes it news rather than
## furniture. See docs/decisions.md D101.
##
## **This is new, not a port.** The original game had nothing like it; the event
## only ever appeared in its top strip. Recorded in original-game-audit.md §18
## with the rest of the things this port added.
##
## **It appears every year**, which in practice means every year: there is one
## event a year and the pool refills, so a year with none needs all nine
## targetable stalks bankrupt at once. That case still gets a panel saying so,
## rather than being silently skipped - in the one game where everything has
## already gone wrong, a missing panel would read as a second thing broken.
##
## Built as a widget rather than Godot's `AcceptDialog` for the same reason
## `ConfirmPanel` is: that opens a real operating-system window, which escapes
## the 640x360 viewport and breaks the pixel grid (decisions.md D40).


## The player has read it and closed it.
signal dismissed


## What the game calls a year with nothing in it. The same sentence the top
## strip uses, so the two never disagree.
const NOTHING_HAPPENED: String = "No special event this year."


@onready var _description: Label = %Description
@onready var _effect: Label = %Effect
@onready var _close_button: Button = %CloseButton
@onready var _dont_show_again: CheckBox = %DontShowAgain


func _ready() -> void:
	_close_button.pressed.connect(close)
	_dont_show_again.toggled.connect(_on_dont_show_again_toggled)
	hide()


## Whether a player has asked not to see this again.
##
## Read from the settings file rather than remembered in the panel, because the
## answer outlives the match: "the rest of the game, and future games".
static func is_wanted() -> bool:
	return UserSettings.load_from().show_news


## Saves the choice the moment it is made, not on closing.
##
## A player who ticks the box and then shuts the game down another way - Alt+F4
## on a fullscreen window, say - still gets what they asked for next time.
func _on_dont_show_again_toggled(dont: bool) -> void:
	var stored: UserSettings = UserSettings.load_from()
	stored.show_news = not dont
	stored.save_to()


## Puts the year's news up.
##
## `description` is the event's own text and `effect` is what it did to which
## stalk. Both empty means a quiet year, and the panel says so.
func show_news(description: String, effect: String) -> void:
	var quiet: bool = description.strip_edges().is_empty()
	_description.text = NOTHING_HAPPENED if quiet else description
	_effect.text = effect
	_effect.visible = not effect.strip_edges().is_empty()

	# Always unticked when it opens. The box is a statement about the future,
	# not a thing that stays pressed - and seeing it already ticked on a panel
	# that is nevertheless showing would read as broken.
	_dont_show_again.set_pressed_no_signal(false)

	show()
	# The close button takes focus, so Enter or Space gets rid of it without
	# the player having to find the mouse. Not the tick box, which Space would
	# then toggle by accident.
	_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	dismissed.emit()


func is_open() -> bool:
	return visible


## The text on display. For tests.
func description_text() -> String:
	return _description.text


## **Clicking anywhere closes it, not only the button.**
##
## The button is there to be obvious the first time. After that this is read
## once a year, every year, and hunting for a small target each time would be a
## toll. The whole panel takes mouse input, so a click that lands on the dim,
## on the text, or on the heading all do the same thing.
func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	accept_event()
	close()


## The tick box. For tests.
func dont_show_again_box() -> CheckBox:
	return _dont_show_again


## Escape closes it too, matching every other panel in the game.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
		return
	accept_event()
	close()
