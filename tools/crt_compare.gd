extends SceneTree
## Compares two renders of the same screen and prints how they differ.
##
## **Why this exists.** The CRT effect cannot be judged by looking at a
## screenshot. Its scanline period is two or three pixels and its colour bleed
## is a fraction of one, so a capture viewed at anything other than 1:1 shows
## neither. Worse, an effect that is doing *nothing at all* looks exactly like
## a tastefully subtle one on a dark screen - that mistake was made here once
## already (decisions.md D94).
##
## So: render the same screen twice with `tools/crt_shot.gd`, once with
## `EFFECT_ON` true and once false, then run this at the two folders.
##
##     <godot> --headless --script res://tools/crt_compare.gd -- <on.png> <off.png>
##
## It reports mean difference, how much of the frame changed, the brightness
## the effect costs or adds, the same figure for the middle of the screen only
## (which excludes the vignette), and a column of pixels through the picture so
## the scanline comb can be seen as numbers.
##
## This is a developer tool, not part of the game: `tools/` is excluded from
## the export (see `export_presets.cfg`) so none of it ships.


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: crt_compare.gd -- <on.png> <off.png>")
		quit(1)
		return

	var on: Image = Image.load_from_file(args[0])
	var off: Image = Image.load_from_file(args[1])
	if on == null or off == null:
		print("could not read one of the images")
		quit(1)
		return
	if on.get_size() != off.get_size():
		print("different sizes: %s and %s" % [on.get_size(), off.get_size()])
		quit(1)
		return

	_report(on, off)
	if args.size() >= 3:
		_write_zooms(on, off, args[2])
	quit()


## Numbers say whether the effect is working; they do not say whether it looks
## right. This writes a matching crop of each image, scaled up with nearest
## neighbour so every pixel is a visible block, which is the only way to see a
## three-pixel scanline period at all.
func _write_zooms(on: Image, off: Image, into: String) -> void:
	# The upper middle of the screen, which on most of this game's screens is
	# where the headings and the densest text are.
	var region := Rect2i(
		on.get_width() / 4, on.get_height() / 16,
		on.get_width() / 4, on.get_height() / 4
	)
	for pair: Array in [["on", on], ["off", off]]:
		var crop: Image = (pair[1] as Image).get_region(region)
		crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
		var path: String = "%s/zoom_%s.png" % [into, pair[0]]
		crop.save_png(path)
		print("wrote %s" % path)


func _report(on: Image, off: Image) -> void:
	var width: int = on.get_width()
	var height: int = on.get_height()

	var total: float = 0.0
	var changed: int = 0
	var lit_on: float = 0.0
	var lit_off: float = 0.0
	# The middle half of the screen, where the vignette has no say.
	var middle: Rect2i = Rect2i(width / 4, height / 4, width / 2, height / 2)
	var middle_on: float = 0.0
	var middle_off: float = 0.0

	for y: int in height:
		for x: int in width:
			var a: Color = on.get_pixel(x, y)
			var b: Color = off.get_pixel(x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.004:
				changed += 1
			lit_on += a.get_luminance()
			lit_off += b.get_luminance()
			if middle.has_point(Vector2i(x, y)):
				middle_on += a.get_luminance()
				middle_off += b.get_luminance()

	var pixels: float = float(width * height)
	var middle_pixels: float = float(middle.size.x * middle.size.y)

	print("size              %d x %d" % [width, height])
	print("mean difference   %.4f" % (total / pixels))
	print("pixels changed    %d of %d (%.1f%%)" % [
		changed, int(pixels), 100.0 * float(changed) / pixels
	])
	print("")
	print("mean brightness   effect on %.4f, off %.4f" % [
		lit_on / pixels, lit_off / pixels
	])
	print("                  the effect keeps %.1f%% of the light" % [
		100.0 * (lit_on / maxf(lit_off, 1e-6))
	])
	print("middle half only  on %.4f, off %.4f -> %.1f%%" % [
		middle_on / middle_pixels,
		middle_off / middle_pixels,
		100.0 * (middle_on / maxf(middle_off, 1e-6)),
	])
	_print_detail(on, off)
	_print_rows_with_text(on, off)
	_print_brightest_row(on, off)


## How much stroke definition each row of text keeps, one row at a time.
##
## The whole-frame figure hides the fault this was written for: text that is
## sharp on one row and soft on the row below it. Only rows that carry real
## detail in the effect-off render are listed, which selects the rows with text
## on them without having to be told where they are.
func _print_rows_with_text(on: Image, off: Image) -> void:
	var across_on: PackedFloat32Array = []
	var across_off: PackedFloat32Array = []
	var busiest: float = 0.0
	for y: int in on.get_height():
		var row_on: float = 0.0
		var row_off: float = 0.0
		for x: int in range(1, on.get_width()):
			row_on += absf(
				on.get_pixel(x, y).get_luminance()
				- on.get_pixel(x - 1, y).get_luminance()
			)
			row_off += absf(
				off.get_pixel(x, y).get_luminance()
				- off.get_pixel(x - 1, y).get_luminance()
			)
		across_on.append(row_on)
		across_off.append(row_off)
		busiest = maxf(busiest, row_off)

	print("")
	print("per row, stroke definition kept (rows carrying text)")
	var kept: Array[float] = []
	for y: int in across_off.size():
		if across_off[y] < busiest * 0.25:
			continue
		var ratio: float = 100.0 * across_on[y] / maxf(across_off[y], 1e-6)
		kept.append(ratio)
		print("  y=%3d  off %6.2f  on %6.2f  %5.1f%%   %s" % [
			y, across_off[y], across_on[y], ratio, _bar(ratio)
		])

	if kept.is_empty():
		return
	var lowest: float = kept[0]
	var highest: float = kept[0]
	for ratio: float in kept:
		lowest = minf(lowest, ratio)
		highest = maxf(highest, ratio)
	print("  spread %.1f%% to %.1f%% - %.1f points between the best and worst row" % [
		lowest, highest, highest - lowest
	])


func _bar(percent: float) -> String:
	var width: int = clampi(int((percent - 60.0) / 2.0), 0, 30)
	return "#".repeat(width)


## How much fine detail survives, which is what text legibility actually is.
##
## Mean absolute difference between neighbouring pixels along each axis. A
## stroke one pixel wide is nothing but this, so a horizontal smear or a soft
## filter shows up here even when brightness and block contrast do not move at
## all. Both axes, because the bleed is horizontal and the scanlines are
## vertical, and separating them says which is doing what.
func _print_detail(on: Image, off: Image) -> void:
	var across_on: float = 0.0
	var across_off: float = 0.0
	var down_on: float = 0.0
	var down_off: float = 0.0

	for y: int in on.get_height():
		for x: int in on.get_width():
			var a: float = on.get_pixel(x, y).get_luminance()
			var b: float = off.get_pixel(x, y).get_luminance()
			if x > 0:
				across_on += absf(a - on.get_pixel(x - 1, y).get_luminance())
				across_off += absf(b - off.get_pixel(x - 1, y).get_luminance())
			if y > 0:
				down_on += absf(a - on.get_pixel(x, y - 1).get_luminance())
				down_off += absf(b - off.get_pixel(x, y - 1).get_luminance())

	print("")
	print("detail across     on %.4f, off %.4f -> %.1f%% kept" % [
		across_on, across_off, 100.0 * (across_on / maxf(across_off, 1e-6))
	])
	print("detail down       on %.4f, off %.4f -> %.1f%% (scanlines add here)" % [
		down_on, down_off, 100.0 * (down_on / maxf(down_off, 1e-6))
	])


## The row with the most light in it is a row of text, which is where
## readability is decided. Printing both versions of it shows what the effect
## does to a stroke: how much of its peak survives, and how far it spreads.
func _print_brightest_row(on: Image, off: Image) -> void:
	var best_row: int = 0
	var best: float = -1.0
	for y: int in off.get_height():
		var row: float = 0.0
		for x: int in off.get_width():
			row += off.get_pixel(x, y).get_luminance()
		if row > best:
			best = row
			best_row = y

	var peak_on: float = 0.0
	var peak_off: float = 0.0
	for x: int in off.get_width():
		peak_on = maxf(peak_on, on.get_pixel(x, best_row).get_luminance())
		peak_off = maxf(peak_off, off.get_pixel(x, best_row).get_luminance())

	# Local contrast is what readability actually depends on: how far a stroke
	# stands out from the background right beside it. Overall brightness can be
	# untouched while this falls, which is exactly what a glow does.
	var below_on: float = 0.0
	var below_off: float = 0.0
	var below_rows: int = 0
	for y: int in range(best_row + 2, mini(best_row + 5, on.get_height())):
		for x: int in off.get_width():
			below_on += on.get_pixel(x, y).get_luminance()
			below_off += off.get_pixel(x, y).get_luminance()
		below_rows += 1
	var span: float = float(off.get_width() * maxi(below_rows, 1))
	var contrast_on: float = peak_on - below_on / span
	var contrast_off: float = peak_off - below_off / span

	print("")
	print("brightest row     y=%d" % best_row)
	print("  peak stroke     on %.3f, off %.3f -> %.1f%%" % [
		peak_on, peak_off, 100.0 * (peak_on / maxf(peak_off, 1e-6))
	])
	print("  local contrast  on %.3f, off %.3f -> %.1f%% kept" % [
		contrast_on, contrast_off,
		100.0 * (contrast_on / maxf(contrast_off, 1e-6)),
	])
	print("  rows around it (luminance, on -> off)")
	for y: int in range(maxi(best_row - 4, 0), mini(best_row + 5, on.get_height())):
		var row_on: float = 0.0
		var row_off: float = 0.0
		for x: int in off.get_width():
			row_on += on.get_pixel(x, y).get_luminance()
			row_off += off.get_pixel(x, y).get_luminance()
		var columns: float = float(off.get_width())
		print("    y=%3d  %.4f  %.4f" % [y, row_on / columns, row_off / columns])
