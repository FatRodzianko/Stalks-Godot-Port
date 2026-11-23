class_name DrawnChart
extends Control
## A chart drawn with lines and rectangles rather than written as text: a line
## chart, a candlestick chart or a bar chart, by year (decisions.md D188).
##
## **Why drawn.** Text charts (`TextChart`, D181) are eighth-block characters on
## the grid, which suit bars but cannot draw a line between two points or a
## candle's body between two prices. Godot draws those directly in `_draw()`
## (`draw_line`, `draw_rect`), with no art and no plugin, so the owner's line
## and candlestick charts cost a widget rather than a graphics library.
## Everything still comes from the shared Theme (the `DrawnChart` type), and
## the lines are whole pixels so the CRT effect treats them like text.
##
## Where things go is `ChartGeometry`'s arithmetic, tested on its own; this
## widget only draws what that decides. Every figure arrives already derived
## (`MarketReadouts`), with the year captions and a tooltip for each year;
## resting the mouse over a year shows its tooltip.
##
## A series may contain NAN for a year with no figure - a P/E with no earnings.
## A line breaks there rather than dropping to zero.


enum Kind { NONE, LINES, CANDLES, BARS }

## The type in the Theme that holds the chart's colours and font.
const THEME_TYPE: StringName = &"DrawnChart"

## Each series' colour, by its index, as the Theme names them.
const SERIES_COLOURS: Array[StringName] = [&"series_1", &"series_2"]

## A point on a line is drawn as a square this many pixels across.
const POINT_SIZE: int = 3


var _kind: Kind = Kind.NONE
var _series: Array[PackedFloat32Array] = []
var _names: PackedStringArray = []
var _captions: PackedStringArray = []
var _tips: PackedStringArray = []
var _message: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


## One line per series (oldest year first), each in its own colour, with a
## legend naming them when there is more than one.
func show_lines(
	series: Array[PackedFloat32Array],
	names: PackedStringArray,
	captions: PackedStringArray,
	tips: PackedStringArray,
) -> void:
	_show(Kind.LINES, series, names, captions, tips)


## A candle per year from its opening price to its closing one: green when it
## closed higher, red when lower. There are no wicks - the match has one price
## a year, so a year has no high or low of its own (decisions.md D188).
func show_candles(
	opens: PackedFloat32Array,
	closes: PackedFloat32Array,
	captions: PackedStringArray,
	tips: PackedStringArray,
) -> void:
	var series: Array[PackedFloat32Array] = [opens, closes]
	_show(Kind.CANDLES, series, PackedStringArray(), captions, tips)


## Bars from zero, one per series side by side in each year, with a legend
## when there is more than one series.
func show_bars(
	series: Array[PackedFloat32Array],
	names: PackedStringArray,
	captions: PackedStringArray,
	tips: PackedStringArray,
) -> void:
	_show(Kind.BARS, series, names, captions, tips)


## No chart, and a line saying why: no years played yet, say.
func show_message(text: String) -> void:
	_show(Kind.NONE, [], PackedStringArray(), PackedStringArray(), PackedStringArray())
	_message = text
	queue_redraw()


func kind() -> Kind:
	return _kind


func series() -> Array[PackedFloat32Array]:
	return _series


func captions() -> PackedStringArray:
	return _captions


func message() -> String:
	return _message


## What the chart shows, as text: its kind and every figure. Two players
## looking at the same year see the same summary, so a test can compare them.
func summary() -> String:
	var parts: PackedStringArray = [Kind.keys()[_kind], _message]
	for values: PackedFloat32Array in _series:
		var shown: PackedStringArray = []
		for value: float in values:
			shown.append(ChartGeometry.label(value))
		parts.append(" ".join(shown))
	parts.append(" ".join(_captions))
	return "\n".join(parts)


## The plot's rectangle, where the slots are. For tests.
func plot_rect() -> Rect2i:
	return ChartGeometry.plot_rect(size, _has_legend())


func _get_tooltip(at_position: Vector2) -> String:
	var index: int = ChartGeometry.slot_at(at_position.x, _captions.size(), plot_rect())
	if index < 0 or index >= _tips.size():
		return ""
	return TermTips.fit(_tips[index])


func _draw() -> void:
	var font: Font = get_theme_font(&"font", THEME_TYPE)
	var font_size: int = get_theme_font_size(&"font_size", THEME_TYPE)
	var label_colour: Color = get_theme_color(&"label", THEME_TYPE)
	if _kind == Kind.NONE:
		if not _message.is_empty():
			draw_string(font, Vector2(0, ChartGeometry.LINE_HEIGHT), _message,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_colour)
		return

	var plot: Rect2i = plot_rect()
	var scale: Vector2 = ChartGeometry.value_range(_series, _kind == Kind.BARS)
	_draw_axes(plot, scale, font, font_size)
	match _kind:
		Kind.LINES:
			_draw_lines(plot, scale)
		Kind.CANDLES:
			_draw_candles(plot, scale)
		Kind.BARS:
			_draw_bars(plot, scale)
	_draw_captions(plot, font, font_size, label_colour)
	if _has_legend():
		_draw_legend(font, font_size, label_colour)


func _show(
	chart_kind: Kind,
	series: Array[PackedFloat32Array],
	names: PackedStringArray,
	captions: PackedStringArray,
	tips: PackedStringArray,
) -> void:
	_kind = chart_kind
	_series = series
	_names = names
	_captions = captions
	_tips = tips
	_message = ""
	queue_redraw()


func _has_legend() -> bool:
	return _names.size() > 1


func _series_colour(index: int) -> Color:
	return get_theme_color(SERIES_COLOURS[index % SERIES_COLOURS.size()], THEME_TYPE)


## The axis down the left, a line along zero (or the bottom), and the scale's
## top and bottom values written beside it.
func _draw_axes(plot: Rect2i, scale: Vector2, font: Font, font_size: int) -> void:
	var axis: Color = get_theme_color(&"axis", THEME_TYPE)
	var label_colour: Color = get_theme_color(&"label", THEME_TYPE)
	var left: float = plot.position.x - 1.5
	var bottom: int = plot.position.y + plot.size.y
	draw_line(Vector2(left, plot.position.y), Vector2(left, bottom), axis)
	var base: int = bottom
	if scale.x < 0.0 and scale.y > 0.0:
		base = ChartGeometry.y_for(0.0, scale, plot)
	draw_line(Vector2(left, base + 0.5), Vector2(plot.end.x, base + 0.5), axis)

	var label_width: int = ChartGeometry.LABEL_CHARS * ChartGeometry.CELL_WIDTH
	var ascent: float = font.get_ascent(font_size)
	var half: float = ascent / 2.0
	draw_string(font, Vector2(0, plot.position.y + half), ChartGeometry.label(scale.y),
		HORIZONTAL_ALIGNMENT_RIGHT, label_width, font_size, label_colour)
	draw_string(font, Vector2(0, bottom + half), ChartGeometry.label(scale.x),
		HORIZONTAL_ALIGNMENT_RIGHT, label_width, font_size, label_colour)


func _draw_lines(plot: Rect2i, scale: Vector2) -> void:
	var count: int = _captions.size()
	for which: int in _series.size():
		var colour: Color = _series_colour(which)
		var run: PackedVector2Array = []
		for index: int in _series[which].size():
			var value: float = _series[which][index]
			if is_nan(value):
				_draw_run(run, colour)
				run = PackedVector2Array()
				continue
			var point: Vector2 = Vector2(
				ChartGeometry.slot_centre(index, count, plot),
				ChartGeometry.y_for(value, scale, plot),
			)
			run.append(point)
			@warning_ignore("integer_division")
			var corner: Vector2 = point - Vector2(POINT_SIZE / 2, POINT_SIZE / 2)
			draw_rect(Rect2(corner, Vector2(POINT_SIZE, POINT_SIZE)), colour)
		_draw_run(run, colour)


## One unbroken stretch of a line. Offset half a pixel so a one-pixel line
## covers whole pixels.
func _draw_run(run: PackedVector2Array, colour: Color) -> void:
	if run.size() < 2:
		return
	var shifted: PackedVector2Array = []
	for point: Vector2 in run:
		shifted.append(point + Vector2(0.5, 0.5))
	draw_polyline(shifted, colour)


func _draw_candles(plot: Rect2i, scale: Vector2) -> void:
	var count: int = _captions.size()
	var opens: PackedFloat32Array = _series[0]
	var closes: PackedFloat32Array = _series[1]
	for index: int in mini(opens.size(), closes.size()):
		var rect: Rect2i = ChartGeometry.candle_rect(index, count, opens[index], closes[index], scale, plot)
		var colour: Color = get_theme_color(&"label", THEME_TYPE)
		if closes[index] > opens[index]:
			colour = get_theme_color(&"gain", THEME_TYPE)
		elif closes[index] < opens[index]:
			colour = get_theme_color(&"loss", THEME_TYPE)
		draw_rect(Rect2(rect), colour)


func _draw_bars(plot: Rect2i, scale: Vector2) -> void:
	var count: int = _captions.size()
	for which: int in _series.size():
		var colour: Color = _series_colour(which)
		for index: int in _series[which].size():
			var value: float = _series[which][index]
			if is_nan(value):
				continue
			var rect: Rect2i = ChartGeometry.bar_rect(index, count, which, _series.size(), value, scale, plot)
			draw_rect(Rect2(rect), colour)


## The year captions under the plot, as many as fit without touching; the
## latest year is always written.
func _draw_captions(plot: Rect2i, font: Font, font_size: int, colour: Color) -> void:
	var count: int = _captions.size()
	var longest: int = 1
	for caption: String in _captions:
		longest = maxi(longest, caption.length())
	var step: int = ChartGeometry.caption_step(count, longest, plot)
	var width: int = (longest + 1) * ChartGeometry.CELL_WIDTH
	var baseline: float = plot.end.y + ChartGeometry.CAPTION_GAP + font.get_ascent(font_size)
	for index: int in count:
		var from_end: int = count - 1 - index
		if from_end % step != 0:
			continue
		@warning_ignore("integer_division")
		var left: int = ChartGeometry.slot_centre(index, count, plot) - width / 2
		draw_string(font, Vector2(left, baseline), _captions[index],
			HORIZONTAL_ALIGNMENT_CENTER, width, font_size, colour)


## The series' names along the top, each after a square of its colour.
func _draw_legend(font: Font, font_size: int, colour: Color) -> void:
	var x: float = ChartGeometry.LABEL_CHARS * ChartGeometry.CELL_WIDTH + ChartGeometry.AXIS_GAP
	var baseline: float = font.get_ascent(font_size)
	for which: int in _names.size():
		draw_rect(Rect2(x, 3, ChartGeometry.CELL_WIDTH, ChartGeometry.CELL_WIDTH), _series_colour(which))
		x += ChartGeometry.CELL_WIDTH * 2
		draw_string(font, Vector2(x, baseline), _names[which], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
		x += (_names[which].length() + 2) * ChartGeometry.CELL_WIDTH
