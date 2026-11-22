class_name TextChart
extends RefCounted
## Charts drawn as text, on the 6 x 12 character grid (docs/ui-reference.md).
##
## **Why text.** Design §7.6 measured it rather than assumed it: the game's font,
## Terminus, carries the whole eighth-block ramp (U+2581 to U+2588), so a bar
## gets eight steps of height per character cell and a seven-row chart resolves
## 56 levels. A chart that is a string needs no art and no drawing code, sits on
## the grid, takes the shared Theme and the CRT effect like any other label, and
## is tested by comparing strings. See decisions.md D181 and design §15 N.
##
## Only presentation lives here. The numbers come from `MarketReadouts`; this
## turns a list of them into lines of characters and decides nothing about them.
##
## Pure: static functions, no nodes.


## Empty, then one to eight eighths of a cell, bottom up.
const RAMP: Array[String] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

const FULL: String = "█"

## The top half of a cell: the finest step a bar hanging *down* from an axis
## can take, because the eighth ramp only fills from the bottom.
const TOP_HALF: String = "▀"

## The horizontal bar of a share: the lower half block, as design §7.4 draws it.
const SHARE_CELL: String = "▄"

const AXIS_V: String = "|"
const AXIS_H: String = "-"
const AXIS_CORNER: String = "+"

## Each bar is this many cells wide, with this many blank between bars.
const BAR_WIDTH: int = 2
const BAR_GAP: int = 1

## How wide the value labels left of the axis are, in characters.
const LABEL_WIDTH: int = 5


## How many bars fit across `width` cells of plot.
static func bars_that_fit(width: int) -> int:
	@warning_ignore("integer_division")
	return maxi(0, (width + BAR_GAP) / (BAR_WIDTH + BAR_GAP))


## A bar chart of `values` (oldest first), `height` rows tall and at most
## `width` cells of plot wide, with the scale labelled at the top and bottom of
## the axis and `captions` (one per value, same order) under the bars. When
## more values are given than fit, the latest are drawn.
##
## The scale runs from the smallest value to the largest, so a series that
## barely moved still shows its shape; the labels say what the ends are.
static func bars(
	values: Array[float],
	captions: PackedStringArray,
	width: int,
	height: int,
) -> String:
	var shown: Array[float] = _latest(values, bars_that_fit(width))
	var shown_captions: PackedStringArray = _latest_strings(captions, shown.size())
	var low: float = 0.0
	var high: float = 0.0
	if not shown.is_empty():
		low = shown.min()
		high = shown.max()
	if high <= low:
		high = low + 1.0

	var lines: PackedStringArray = []
	for row: int in range(height - 1, -1, -1):
		var line: String = _label_for(row, height, low, high) + AXIS_V
		for value: float in shown:
			var eighths: int = _eighths(value, low, high, height)
			var cell: String = RAMP[clampi(eighths - row * 8, 0, 8)]
			line += cell.repeat(BAR_WIDTH) + " ".repeat(BAR_GAP)
		lines.append(line.rstrip(" "))
	lines.append(" ".repeat(LABEL_WIDTH) + AXIS_CORNER + AXIS_H.repeat(_plot_width(shown.size())))
	lines.append(" ".repeat(LABEL_WIDTH + 1) + _caption_line(shown_captions))
	return "\n".join(lines)


## A chart of signed values (a percentage move each year): positive bars rise
## from a zero axis drawn across the middle, negative ones hang below it. The
## scale is symmetric, the larger of the two extremes either way.
##
## `height` is rows above the axis and the same number below it. A bar above
## the axis has eighth-cell steps; one below it has half-cell steps, because
## the font's ramp only fills from the bottom (see `TOP_HALF`).
static func signed_bars(
	values: Array[float],
	captions: PackedStringArray,
	width: int,
	height: int,
) -> String:
	var shown: Array[float] = _latest(values, bars_that_fit(width))
	var shown_captions: PackedStringArray = _latest_strings(captions, shown.size())
	var reach: float = 1.0
	for value: float in shown:
		reach = maxf(reach, absf(value))

	var lines: PackedStringArray = []
	for row: int in range(height - 1, -1, -1):
		var label: String = " ".repeat(LABEL_WIDTH)
		if row == height - 1:
			label = _number(reach).lpad(LABEL_WIDTH)
		var line: String = label + AXIS_V
		for value: float in shown:
			var cell: String = " "
			if value > 0.0:
				var eighths: int = roundi(value / reach * float(height * 8))
				cell = RAMP[clampi(eighths - row * 8, 0, 8)]
			line += cell.repeat(BAR_WIDTH) + " ".repeat(BAR_GAP)
		lines.append(line.rstrip(" "))

	lines.append("0".lpad(LABEL_WIDTH) + AXIS_CORNER + AXIS_H.repeat(_plot_width(shown.size())))

	for row: int in height:
		var label: String = " ".repeat(LABEL_WIDTH)
		if row == height - 1:
			label = _number(-reach).lpad(LABEL_WIDTH)
		var line: String = label + AXIS_V
		for value: float in shown:
			var cell: String = " "
			if value < 0.0:
				var halves: int = roundi(-value / reach * float(height * 2))
				var filled: int = halves - row * 2
				if filled >= 2:
					cell = FULL
				elif filled == 1:
					cell = TOP_HALF
			line += cell.repeat(BAR_WIDTH) + " ".repeat(BAR_GAP)
		lines.append(line.rstrip(" "))
	lines.append(" ".repeat(LABEL_WIDTH + 1) + _caption_line(shown_captions))
	return "\n".join(lines)


## A horizontal bar for a share out of 100, at most `cells` long: design
## §7.4's revenue-share column. Rounded to the nearest cell; anything above
## zero shows at least one, so a small share is not drawn as none.
static func share_bar(percent: float, cells: int) -> String:
	if is_nan(percent) or percent <= 0.0:
		return ""
	var length: int = clampi(roundi(percent / 100.0 * float(cells)), 1, cells)
	return SHARE_CELL.repeat(length)


# ------------------------------------------------------------------ helpers

static func _eighths(value: float, low: float, high: float, height: int) -> int:
	# The lowest value still gets one eighth, so every year has a visible bar
	# and a gap in the chart always means a year that has not happened.
	var span: int = height * 8 - 1
	return 1 + roundi((value - low) / (high - low) * float(span))


static func _label_for(row: int, height: int, low: float, high: float) -> String:
	if row == height - 1:
		return _number(high).lpad(LABEL_WIDTH)
	if row == 0:
		return _number(low).lpad(LABEL_WIDTH)
	return " ".repeat(LABEL_WIDTH)


static func _number(value: float) -> String:
	return str(roundi(value))


static func _plot_width(bar_count: int) -> int:
	return maxi(0, bar_count * (BAR_WIDTH + BAR_GAP) - BAR_GAP)


## Each caption centred-left under its bar, cut to the bar's width.
static func _caption_line(captions: PackedStringArray) -> String:
	var line: String = ""
	for caption: String in captions:
		line += caption.left(BAR_WIDTH).rpad(BAR_WIDTH) + " ".repeat(BAR_GAP)
	return line.rstrip(" ")


static func _latest(values: Array[float], count: int) -> Array[float]:
	if values.size() <= count:
		return values.duplicate()
	return values.slice(values.size() - count)


static func _latest_strings(values: PackedStringArray, count: int) -> PackedStringArray:
	if values.size() <= count:
		return values
	return values.slice(values.size() - count)
