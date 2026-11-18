class_name SettingsPanel
extends VBoxContainer
## Sound, resolution, fullscreen, the CRT effect and whether the year's news
## panel appears, in one widget used in two places.
##
## The title screen's Settings tab and the in-match pause menu show the same
## controls, exactly as the original did — its pause menu reused the title
## screen's settings panel rather than having a second one. A second copy of
## this would be a second place for the volume preview rules to drift.
##
## **It owns applying and saving.** Nothing above it has to know that volume
## goes to a bus and resolution goes to a window; a host just puts this on
## screen.
##
## **The revert prompt is added to the viewport, not to this panel.** It is a
## modal question about the whole screen, and a confirmation laid out inside a
## settings panel would be drawn at the size of the settings panel. See
## `_ask_about_keeping`, which also says why the viewport rather than the
## window.


const ConfirmPanelScene: PackedScene = preload("res://src/ui/widgets/confirm_panel.tscn")


## Whether moving the volume slider plays a clip so the level can be heard.
##
## On by default, as the original did it. The pause menu turns it off: a
## bull-market sound arriving mid-match, in a year that might be a bear one,
## and heard by one player only, is a worse answer than silence.
@export var preview_volume: bool = true


## True between grabbing the volume slider and letting it go, so the preview
## clip can wait for the release instead of firing on every step of a drag.
var _dragging_volume: bool = false

## The resolutions in the dropdown, in the same order as its items.
var _offered: Array[Vector2i] = []

## What the display was before the change now being confirmed.
var _previous_resolution: Vector2i = UserSettings.USE_NATIVE
var _previous_fullscreen: bool = UserSettings.DEFAULT_FULLSCREEN

var _revert_prompt: ConfirmPanel

@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _fullscreen_check: CheckBox = %FullscreenCheck
@onready var _crt_check: CheckBox = %CrtCheck
@onready var _news_check: CheckBox = %NewsCheck


func _ready() -> void:
	_volume_slider.value_changed.connect(_on_volume_changed)
	_volume_slider.drag_started.connect(_on_volume_drag_started)
	_volume_slider.drag_ended.connect(_on_volume_drag_ended)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_crt_check.toggled.connect(_on_crt_toggled)
	_news_check.toggled.connect(_on_news_toggled)
	refresh()


## Puts every control where the setting actually is, rather than where the
## scene file happens to have left it.
##
## Called whenever the panel comes back on screen, because the other copy of
## it may have changed something in between.
func refresh() -> void:
	_show_current_volume()
	_show_current_display()
	_show_current_crt()
	_show_current_news()


## The revert overlay, or null if no display setting has been touched. For
## tests.
func revert_prompt() -> ConfirmPanel:
	return _revert_prompt


# -------------------------------------------------------------------- volume

func _show_current_volume() -> void:
	_volume_slider.set_value_no_signal(Audio.volume_percent())
	_volume_value.text = "%d%%" % int(_volume_slider.value)


## Applies and saves at once, so the number on screen is never a promise about
## a volume that has not been set yet.
##
## **The clip is not played while a drag is in progress.** Playing on every
## step was the first attempt and it was wrong: the clip is longer than the
## gap between steps, so a drag stacked previews into an echo and the only
## part at the volume you had chosen was the tail. A change made without a
## drag — the arrow keys, Home, End — has no release to wait for, so it
## previews immediately.
func _on_volume_changed(value: float) -> void:
	Audio.set_volume_percent(int(value))
	_volume_value.text = "%d%%" % int(value)
	if _dragging_volume or not preview_volume:
		return
	Audio.play_volume_preview()


## Silences a preview left over from the last adjustment, so a drag is quiet
## whether or not one was still sounding when it began. Without this, a clip
## from a previous release rides the volume up and down as you drag.
func _on_volume_drag_started() -> void:
	_dragging_volume = true
	Audio.stop_volume_preview()


## `changed` is false when the slider was grabbed and released on the same
## value, where a preview would be a sound in answer to nothing.
func _on_volume_drag_ended(changed: bool) -> void:
	_dragging_volume = false
	if changed and preview_volume:
		Audio.play_volume_preview()


# ------------------------------------------------------------------- display

func _show_current_display() -> void:
	var stored: UserSettings = UserSettings.load_from()
	var screen: Vector2i = DisplayMode.screen_size(get_window())
	var current: Vector2i = DisplaySettings.resolve(stored.resolution, screen)

	_offered = DisplaySettings.choices_for(screen)
	_resolution_option.clear()
	for index: int in _offered.size():
		_resolution_option.add_item(DisplaySettings.describe(_offered[index]), index)
	_resolution_option.select(_offered.find(current))
	_fullscreen_check.set_pressed_no_signal(stored.fullscreen)
	_show_whether_resolution_applies(stored.fullscreen)


## A new resolution, applied at once and then asked about.
##
## **Applied before it is confirmed, on purpose.** The question is whether the
## monitor can show it, and the only way to answer that is to try it. The
## countdown is what makes that safe.
func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _offered.size():
		return
	_change_display(_offered[index], _fullscreen_check.button_pressed)


func _on_fullscreen_toggled(on: bool) -> void:
	_show_whether_resolution_applies(on)
	_change_display(_chosen_resolution(), on)


## Greys the resolution out in fullscreen, where it does nothing.
##
## **This is honesty, not polish.** The chosen resolution only reaches the
## screen in a window; fullscreen draws at the desktop's own size whatever the
## dropdown says (decisions.md D85). Leaving the control live meant a player
## could pick a size, watch nothing happen, and reasonably conclude the game
## was broken. Reported from play on 2026-11-16.
##
## It greys out the moment the box is ticked, before the change is confirmed,
## because the display has already changed by then — the confirmation asks
## whether to keep it, not whether to make it.
##
## **Remove this when the resolution works in fullscreen**, not before: the
## greying is a true statement about what the setting currently does, so it
## stops being true the day that is fixed.
func _show_whether_resolution_applies(fullscreen: bool) -> void:
	_resolution_option.disabled = fullscreen


func _chosen_resolution() -> Vector2i:
	var index: int = _resolution_option.selected
	if index < 0 or index >= _offered.size():
		return UserSettings.USE_NATIVE
	return _offered[index]


func _change_display(resolution: Vector2i, fullscreen: bool) -> void:
	var stored: UserSettings = UserSettings.load_from()
	_previous_resolution = stored.resolution
	_previous_fullscreen = stored.fullscreen

	DisplayMode.apply(get_window(), resolution, fullscreen)
	_ask_about_keeping()


## Puts the question over the whole screen.
##
## **Added to the window rather than to this panel.** A `Control` inside a
## container is laid out by that container, so a confirmation parented here
## would be drawn at the width of the settings panel and the dim behind it
## would cover only the settings panel. The question is about the display, so
## it belongs over the display.
func _ask_about_keeping() -> void:
	if _revert_prompt == null:
		_revert_prompt = ConfirmPanelScene.instantiate()
		_revert_prompt.confirmed.connect(_on_display_kept)
		_revert_prompt.cancelled.connect(_on_display_reverted)
		# The viewport, not the window. Those are the same thing when this panel
		# is built on its own in a test, and different in the game: the game is
		# drawn inside a `SubViewport` and the window around it is the monitor
		# (decisions.md D96). Parenting to the window would lay this out at the
		# monitor's size, so its text would come out a few pixels tall beside a
		# picture drawn at 640x360.
		get_viewport().add_child(_revert_prompt)
	_revert_prompt.ask_with_countdown(
		"Keep this display setting?",
		"Keep it",
		"Go back",
	)


## Kept: write it to the settings file, where it was not until now.
func _on_display_kept() -> void:
	var stored: UserSettings = UserSettings.load_from()
	stored.resolution = _chosen_resolution()
	stored.fullscreen = _fullscreen_check.button_pressed
	stored.save_to()


## Refused, or not answered in time. Puts back whatever was saved and moves
## the controls to match, so the dropdown never claims a size that is not on
## screen.
func _on_display_reverted() -> void:
	DisplayMode.apply(get_window(), _previous_resolution, _previous_fullscreen)
	_show_current_display()


# ----------------------------------------------------------------- crt effect

func _show_current_crt() -> void:
	var stored: UserSettings = UserSettings.load_from()
	_crt_check.set_pressed_no_signal(stored.crt_effect)


## Applied and saved at once, like the volume and unlike the resolution.
##
## **No revert countdown, on purpose.** The countdown exists because a
## resolution a monitor cannot show leaves a player looking at a black screen
## with no way back. This cannot do that: the effect is drawn over a picture
## that is still there underneath, the tick box is still on screen and still
## readable through it, and turning it off is the same click again. A
## confirmation here would be a question about something the player can
## already see the answer to.
func _on_crt_toggled(on: bool) -> void:
	CrtOverlay.apply(get_tree(), on)
	var stored: UserSettings = UserSettings.load_from()
	stored.crt_effect = on
	stored.save_to()


# ---------------------------------------------------------------- the news

func _show_current_news() -> void:
	_news_check.set_pressed_no_signal(UserSettings.load_from().show_news)


## **The only way back.** The panel itself offers "Don't show again", and
## without this that would be a one-way door: a player who ticked it by
## accident could never see the year's news again without hand-editing
## `user://settings.cfg`. See decisions.md D102.
func _on_news_toggled(on: bool) -> void:
	var stored: UserSettings = UserSettings.load_from()
	stored.show_news = on
	stored.save_to()


## The prompt is parented to the window, so it does not go away with this
## panel unless it is told to.
func _exit_tree() -> void:
	if _revert_prompt == null:
		return
	_revert_prompt.queue_free()
	_revert_prompt = null
