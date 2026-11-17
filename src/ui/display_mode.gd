class_name DisplayMode
extends RefCounted
## Puts a chosen resolution and fullscreen state onto a real window.
##
## The arithmetic lives in `DisplaySettings`, which knows nothing about
## windows. This is the other half: the only place in the project that touches
## `Window` sizing or `DisplayServer`.
##
## **How a resolution reaches the screen.** Three steps, and it is worth being
## precise because the difference between them is what every scaling argument
## in this project has been about:
##
## 1. The interface lays itself out on the 640x360 grid. That never changes,
##    whatever resolution is picked, so every player sees the same rows and
##    columns (docs/decisions.md D40).
## 2. That layout is **drawn at 640x360**, always. The game is pixel art and
##    this is the size of its pixels.
## 3. `Stage` **enlarges that picture by a whole number** to fill as much of
##    the window as it can, centres it, and leaves black around the rest.
##
## Nothing here does step 3, and nothing here resizes a viewport. Godot's own
## stretch settings are switched off in `project.godot` for exactly that
## reason — a stretch happens after everything is drawn, where neither the CRT
## effect nor anything else can reach it. See decisions.md D96.
##
## **So what does the resolution setting do?** It picks **the size of the
## window**. Every rung of the ladder is a whole multiple of 640x360, so a
## window at any of them is filled exactly, with no bars and nothing resampled.
##
## **In fullscreen it does nothing at all**, because the monitor's own size is
## the window. The settings panel greys the control out there rather than
## letting a player change a number and watch nothing happen. That is a true
## statement about this design rather than a shortcoming of it: a pixel-art
## game drawn at 640x360 has one honest picture size and the only question is
## how many times it is enlarged.


## Applies `resolution` and `fullscreen` to `window`, and returns the
## resolution actually used.
##
## The return matters: `resolution` may be `UserSettings.USE_NATIVE`, or a size
## this monitor cannot show, and the caller needs to know what it really got so
## the settings screen can show the truth rather than the request.
## **Changes nothing under the headless display server**, where there is no
## window to change and the whole test suite runs. It still answers with the
## resolution that would have been used, so a settings screen under test shows
## the same thing it would show a player.
static func apply(window: Window, resolution: Vector2i, fullscreen: bool) -> Vector2i:
	var screen: Vector2i = screen_size(window)
	var chosen: Vector2i = DisplaySettings.resolve(resolution, screen)
	if not has_a_real_window():
		return chosen

	# No `content_scale_*` here any more. Setting a content scale would put a
	# second resize between the game and the window, on top of the one `Stage`
	# does, and the two fought: the old pairing of `content_scale_size` with a
	# matching `content_scale_factor` cancelled out exactly, which is why the
	# resolution setting did nothing for weeks (decisions.md D85, then D96).
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return chosen

	window.mode = Window.MODE_WINDOWED
	window.size = chosen
	centre_on_screen(window)
	return chosen


## False when the game is running without a display — the test suite, a
## dedicated server, any `--headless` run. Nothing here should touch a window
## in that case.
static func has_a_real_window() -> bool:
	return DisplayServer.get_name() != "headless"


## The usable area of the monitor this window is on, in pixels.
##
## Usable rather than total: it excludes the taskbar, so a windowed game at the
## largest offered size still has its title bar reachable.
static func screen_size(window: Window) -> Vector2i:
	if not has_a_real_window():
		return Vector2i.ZERO
	return DisplayServer.screen_get_usable_rect(window.current_screen).size


## Puts the window in the middle of the monitor it is already on.
##
## Needed because the window cannot be dragged to a sensible place by the
## player on the first run — it is not resizable and a game that opens half off
## the edge looks broken.
static func centre_on_screen(window: Window) -> void:
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = usable.position + (usable.size - window.size) / 2
