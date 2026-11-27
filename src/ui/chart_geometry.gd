class_name ChartGeometry
extends RefCounted
## Where things go on a drawn chart (`DrawnChart`): the arithmetic, kept apart
## from the drawing so it is tested by comparing numbers.
##
## **The layout.** A chart's area is split into a label column on the left (the
## scale's top and bottom values), a plot, and a caption row under it (the year
## numbers). The plot is divided into equal **slots**, one per year; a line's
## point, a candle and a pair of bars all sit in their year's slot, so every kind
## of chart lines up the same way. Positions are whole pixels, so one-pixel lines
## stay sharp on the 640 x 360 picture (docs/ui-reference.md).
##
## Only presentation lives here. The numbers come from `MarketReadouts`; this
## decides where they are drawn and nothing about what they mean.
##
## Pure: static functions, no nodes.


## The scale labels left of the plot, in characters of the 6 x 12 grid.
const LABEL_CHARS: int = 5

## One character cell, in pixels (`CellRow.CELL_WIDTH` and the font's height).
const CELL_WIDTH: int = 6
const LINE_HEIGHT: int = 12

## Space kept above the plot so the top value's label is not cut off, and
## between the plot and the captions.
const TOP_PAD: int = 6
const CAPTION_GAP: int = 2

## Between the labels and the plot's left edge, where the axis is drawn.
const AXIS_GAP: int = 3


## The plot's rectangle inside a chart of `size`, leaving room for the labels
## on the left, the captions underneath and, with `has_legend`, a line of
## series names along the top.
static func plot_rect(size: Vector2, has_legend: bool) -> Rect2i:
	var left: int = LABEL_CHARS * CELL_WIDTH + AXIS_GAP
	var top: int = TOP_PAD
	if has_legend:
		top += LINE_HEIGHT
	var width: int = maxi(1, int(size.x) - left - 1)
	var height: int = maxi(1, int(size.y) - top - LINE_HEIGHT - CAPTION_GAP)
	return Rect2i(left, top, width, height)


## The scale: the smallest and largest of every value given, NAN left out.
## With `include_zero` the scale always reaches zero, for bars, which grow from
## it. A scale with no spread is widened by one either way so it can be drawn.
static func value_range(series: Array[PackedFloat32Array], include_zero: bool) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for values: PackedFloat32Array in series:
		for value: float in values:
			if is_nan(value):
				continue
			low = minf(low, value)
			high = maxf(high, value)
	if low == INF:
		low = 0.0
		high = 1.0
	if include_zero:
		low = minf(low, 0.0)
		high = maxf(high, 0.0)
	if high <= low:
		low -= 1.0
		high += 1.0
	return Vector2(low, high)


## The pixel row for `value` on a scale of `low` to `high` drawn in `plot`:
## `high` at the top edge, `low` at the bottom one.
static func y_for(value: float, scale: Vector2, plot: Rect2i) -> int:
	var fraction: float = (value - scale.x) / (scale.y - scale.x)
	return plot.position.y + plot.size.y - roundi(fraction * float(plot.size.y))


## How wide each year's slot is, in whole pixels.
static func slot_width(count: int, plot: Rect2i) -> int:
	if count <= 0:
		return plot.size.x
	@warning_ignore("integer_division")
	return maxi(1, plot.size.x / count)


## The middle of slot `index` of `count`, in pixels.
static func slot_centre(index: int, count: int, plot: Rect2i) -> int:
	var width: int = slot_width(count, plot)
	@warning_ignore("integer_division")
	return plot.position.x + index * width + width / 2


## Which slot an x position falls in, or -1 outside the plot. For tooltips.
static func slot_at(x: float, count: int, plot: Rect2i) -> int:
	if count <= 0 or x < plot.position.x:
		return -1
	@warning_ignore("integer_division")
	var index: int = int(x - plot.position.x) / slot_width(count, plot)
	if index >= count:
		return -1
	return index


## A candle's body from `open` to `close` in slot `index`: two thirds of the
## slot wide, at least one pixel tall so a year that did not move still shows.
static func candle_rect(index: int, count: int, open: float, close: float, scale: Vector2, plot: Rect2i) -> Rect2i:
	var width: int = slot_width(count, plot)
	@warning_ignore("integer_division")
	var body: int = clampi(width * 2 / 3, 1, width)
	@warning_ignore("integer_division")
	var left: int = slot_centre(index, count, plot) - body / 2
	var top: int = mini(y_for(open, scale, plot), y_for(close, scale, plot))
	var bottom: int = maxi(y_for(open, scale, plot), y_for(close, scale, plot))
	return Rect2i(left, top, body, maxi(1, bottom - top))


## Bar `which` of `of_count` side by side in slot `index`, from zero to
## `value`. Together the bars take two thirds of the slot.
static func bar_rect(index: int, count: int, which: int, of_count: int, value: float, scale: Vector2, plot: Rect2i) -> Rect2i:
	var width: int = slot_width(count, plot)
	@warning_ignore("integer_division")
	var group: int = clampi(width * 2 / 3, of_count, width)
	@warning_ignore("integer_division")
	var bar: int = maxi(1, group / of_count)
	@warning_ignore("integer_division")
	var left: int = slot_centre(index, count, plot) - group / 2 + which * bar
	var zero: int = y_for(0.0, scale, plot)
	var end: int = y_for(value, scale, plot)
	return Rect2i(left, mini(zero, end), bar, maxi(1, absi(end - zero)))


## How many slots fit in `plot` with a caption of `caption_chars` under every
## one, at least 1.
static func slots_that_fit(caption_chars: int, plot: Rect2i) -> int:
	@warning_ignore("integer_division")
	return maxi(1, plot.size.x / ((caption_chars + 1) * CELL_WIDTH))


## Every how many years a caption is written, so captions `caption_chars`
## long never touch: 1 when they all fit, 2 for every other year, and so on.
static func caption_step(count: int, caption_chars: int, plot: Rect2i) -> int:
	var needed: int = (caption_chars + 1) * CELL_WIDTH
	var width: int = slot_width(count, plot)
	@warning_ignore("integer_division")
	return maxi(1, (needed + width - 1) / width)


## A scale label in at most `LABEL_CHARS` characters: whole numbers from 100
## up, thousands as "12k", one decimal from 10, two below - and a value that is
## already whole, a price of 8, written as one.
static func label(value: float) -> String:
	var size: float = absf(value)
	if value == roundf(value) and size < 10000.0:
		return str(roundi(value))
	if size >= 10000.0:
		return "%dk" % roundi(value / 1000.0)
	if size >= 100.0:
		return str(roundi(value))
	if size >= 10.0:
		return "%.1f" % value
	return "%.2f" % value
