class_name DisplaySettings
extends RefCounted
## Which resolutions the game offers, and what each one means to the renderer.
##
## **Pure logic.** It touches no window and no `DisplayServer`; a caller hands
## it the monitor's size and it answers with numbers. `DisplayMode` is the part
## that acts on a window. That split is what lets the whole list be tested
## headless, on a machine whose real monitor is nothing like the one in the
## test.
##
## **What a "resolution" is here.** The game lays its interface out on a fixed
## 640x360 grid of character cells (docs/decisions.md D40). The resolution a
## player picks is **the size of the image that grid is drawn into**, and that
## image is then stretched to fill the screen. Picking a bigger one means more
## pixels per letter; picking a smaller one means fewer, and a softer picture
## when it is stretched up. Nothing about the layout changes — every resolution
## shows the same rows and the same columns.
##
## **Why only 16:9.** The grid is 16:9. Offering a 16:10 or 21:9 image would
## mean either distorting it or inventing content to fill the sides, and the
## owner's standing requirement is that every player sees the same thing. A
## monitor that is not 16:9 gets the nearest 16:9 image with black bars in the
## leftover space.


## The interface's own coordinate space, in character cells' worth of pixels.
## Everything below is a multiple of it or of half of it. See D40.
const BASE: Vector2i = Vector2i(640, 360)


## Every 16:9 size the game will ever offer, smallest first.
##
## These are exact 16:9 — width divided by 16 equals height divided by 9 for
## all of them, so none is the 854x480 approximation that usually shows up in
## resolution lists. A monitor only sees the ones that fit on it.
##
## **Every rung is a whole multiple of `BASE`**, and that is now a rule rather
## than a coincidence. The game draws itself at 640x360 and is shown at the
## largest whole multiple that fits (decisions.md D96), so a window of 960x540
## would display a 640x360 picture with a quarter of the window left black.
## 960x540 and 1600x900 were on this ladder until 2026-11-17 and were dropped
## for exactly that reason: 1.5x and 2.5x are the two sizes the new display
## path cannot fill.
const LADDER: Array[Vector2i] = [
	Vector2i(640, 360),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]


## The sizes worth offering on a monitor of `screen` pixels: everything on the
## ladder that fits inside it.
##
## **Never returns an empty list.** A screen smaller than 640x360 is not a
## thing anybody will plug in, but returning nothing would leave the dropdown
## blank and the game unable to start, so the smallest rung is always offered.
static func choices_for(screen: Vector2i) -> Array[Vector2i]:
	var fitting: Array[Vector2i] = []
	for size: Vector2i in LADDER:
		if size.x <= screen.x and size.y <= screen.y:
			fitting.append(size)
	if fitting.is_empty():
		fitting.append(LADDER[0])
	return fitting


## The resolution a player who has never opened the settings should get: the
## largest 16:9 image this monitor can show without being scaled down.
##
## On a 1920x1080 monitor that is 1920x1080, and the image is then displayed
## one pixel to one pixel with no scaling at all. On a 1920x1200 monitor it is
## also 1920x1080, displayed with a bar above and below.
static func native_choice(screen: Vector2i) -> Vector2i:
	var choices: Array[Vector2i] = choices_for(screen)
	return choices[choices.size() - 1]


## `resolution` if the monitor can show it, otherwise the best one it can.
##
## Guards the settings file against a monitor that has been unplugged and
## replaced by a smaller one, which would otherwise leave the game rendering
## an image too big to display.
static func nearest_supported(resolution: Vector2i, screen: Vector2i) -> Vector2i:
	var choices: Array[Vector2i] = choices_for(screen)
	if choices.has(resolution):
		return resolution
	return choices[choices.size() - 1]


## The resolution to actually use, given what the settings file asked for.
##
## A zero or negative request means "whatever this monitor is", which is what
## a first run stores. Anything else is honoured if the monitor can show it and
## quietly reduced if it cannot, so a settings file carried to a smaller screen
## still starts.
static func resolve(requested: Vector2i, screen: Vector2i) -> Vector2i:
	if requested.x <= 0 or requested.y <= 0:
		return native_choice(screen)
	return nearest_supported(requested, screen)


## How many times the 640x360 picture can be enlarged and still fit in a
## window of `window` pixels, as a whole number.
##
## **Whole numbers only, and that is the point.** Enlarging a 640x360 picture
## by 2.5 means some source pixels become three screen pixels wide and some
## become two, so a letter's strokes come out uneven and the pattern crawls as
## anything moves. At a whole multiple every source pixel is the same size
## square. See decisions.md D96.
##
## Never less than one, so a window smaller than the picture still shows
## something rather than nothing.
static func integer_scale_for(window: Vector2i) -> int:
	if window.x <= 0 or window.y <= 0:
		return 1
	return maxi(1, mini(window.x / BASE.x, window.y / BASE.y))


## The size the picture is actually drawn at inside a window of `window`
## pixels. Whatever is left over is black bars.
static func image_size_for(window: Vector2i) -> Vector2i:
	return BASE * integer_scale_for(window)


## `"1920 x 1080"`, for the dropdown.
##
## Spaced rather than written `1920x1080` because the interface is monospaced
## and the spaces make a column of them line up on the digits.
static func describe(resolution: Vector2i) -> String:
	return "%d x %d" % [resolution.x, resolution.y]
