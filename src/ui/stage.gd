class_name Stage
extends Control
## The root scene: the window, and the game shown inside it.
##
## Everything the player sees is drawn into a `SubViewport` of exactly 640x360
## and then enlarged by a **whole number** to fill as much of the window as it
## can, centred, with black around whatever is left. `Main` lives inside that
## viewport and neither it nor any screen knows about any of this.
##
## **Why the picture is enlarged by a whole number.** Enlarging 640x360 by 2.5
## makes some source pixels three screen pixels wide and others two, so a
## letter's strokes come out uneven and the pattern crawls whenever anything
## moves. At a whole multiple every source pixel is the same square. The
## resolution list was trimmed to match: 960x540 and 1600x900 were the only two
## rungs that are not whole multiples and they were dropped. See
## docs/decisions.md D96.
##
## **Why a `SubViewport` at all**, when Godot's own stretch setting did this
## before: because a stretch happens after everything is drawn, where nothing
## can reach it. With the picture in a viewport it is an ordinary texture, so
## the CRT effect can be a material on the control that shows it, running at
## the monitor's resolution instead of the game's.
##
## **Input needs no help.** A `SubViewportContainer` transforms mouse
## coordinates into its viewport itself - measured, in
## `tools/subviewport_spike.gd` - and the game has no code anywhere that reads
## the pointer directly. `gui_embed_subwindows` on the viewport is what keeps
## dropdowns and tooltips inside the picture rather than in the window around
## it; `tools/popup_spike.gd` is why that one line is there.


@onready var _screen: SubViewportContainer = %Screen
@onready var _game: SubViewport = %GameViewport
@onready var _main: Main = %Main

var _crt: CrtOverlay


func _ready() -> void:
	# Fullscreen, a resolution change and a drag of the window edge all arrive
	# as this one signal.
	get_tree().root.size_changed.connect(fit_to_window)
	_build_the_crt_effect()
	fit_to_window()


## Sizes and centres the picture for the window it is in.
func fit_to_window() -> void:
	fit_to(Vector2i(get_viewport_rect().size))


## The same, for a window of a stated size.
##
## **Separate so it can be tested without a window.** The obvious way to test
## the layout is to resize the root viewport and look, and that is exactly
## wrong: the root viewport is shared with every other test in the suite, so a
## test that resizes it and does not put it back breaks whichever test runs
## next. That happened, and what it broke was the splash screen's input
## reaching it at all.
func fit_to(window: Vector2i) -> void:
	var picture: Vector2i = DisplaySettings.image_size_for(window)
	var enlargement: int = DisplaySettings.integer_scale_for(window)

	_screen.stretch_shrink = enlargement
	if _crt != null:
		_crt.enlargement = enlargement
		_crt.enable(_crt.is_enabled())
	_screen.size = Vector2(picture)
	# Whole pixels. Half a pixel of offset would resample the whole picture and
	# undo the reason for enlarging by a whole number in the first place.
	_screen.position = ((Vector2(window) - Vector2(picture)) * 0.5).floor()


## The size the game is being drawn at, before it is enlarged. Always 640x360
## unless something has gone wrong, which is why a test asks.
func picture_size() -> Vector2i:
	return _game.size


## How many times the picture is enlarged to fill this window.
func picture_scale() -> int:
	return _screen.stretch_shrink


## The control the picture is drawn on, and so the thing the effect hangs from.
func screen_control() -> SubViewportContainer:
	return _screen


## The viewport the whole game lives in.
func game_viewport() -> SubViewport:
	return _game


## The screen host inside it. For tests; nothing in the game reaches down here.
func game() -> Main:
	return _main


## The CRT effect. For tests.
func crt_overlay() -> CrtOverlay:
	return _crt


## Built whether or not the effect is wanted, because the settings panel
## toggles it live and needs something already there to toggle.
func _build_the_crt_effect() -> void:
	_crt = CrtOverlay.new()
	_crt.target = _screen
	_crt.source = _game.get_texture()
	add_child(_crt)
	_crt.enable(UserSettings.load_from().crt_effect)
