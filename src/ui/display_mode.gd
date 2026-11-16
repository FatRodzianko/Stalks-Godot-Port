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
## 2. That layout is **drawn into an image of the chosen resolution**. At
##    1920x1080 a letter is drawn with three times as many pixels as at
##    640x360. This is `content_scale_size` with a matching
##    `content_scale_factor`: the first sets how big the image is, the second
##    keeps the layout at 640x360 units inside it.
## 3. The image is **stretched to fill the window**, keeping its shape. A
##    monitor that is not 16:9 gets black bars rather than a distorted
##    picture. This is `CONTENT_SCALE_ASPECT_KEEP`.
##
## Step 3 is a straight stretch of a finished image, so choosing a resolution
## below the monitor's own costs sharpness, exactly as it does in any other
## game. Choosing the monitor's own resolution — what a first run does — makes
## step 3 a one-to-one copy, and nothing is resampled at all.
##
## **Windowed mode makes the window the size of the image**, so step 3 is again
## one-to-one and the picture is exact.


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

	# Set before the window mode changes, so there is never a frame rendered at
	# the old size inside the new window.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = chosen
	window.content_scale_factor = DisplaySettings.scale_for(chosen)

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
