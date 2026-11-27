class_name ChartWidget
extends VBoxContainer
## A titled text chart (docs/stalkleheads-design.md §7.6): a heading, then the
## chart itself as one label of block characters built by `TextChart`.
##
## **A signed chart is coloured**: bars above the zero line in the gain colour,
## bars below it in the loss colour, as the board colours a move (decisions.md
## D187). That is why the chart is a `RichTextLabel` - a `Label` has one colour.
## Only the bar characters are coloured; the scale and the axis are not.
## `TextChart` still returns plain text, and `chart_text()` returns that.
##
## Sized in whole character cells, so it sits on the grid: the index chart is 38
## cells wide and 7 tall, the industry chart 22 by 5 (§7.6). The label's width
## is reserved from that size rather than from whatever it currently says, so a
## chart with three years in it takes the same room as one with thirty.
##
## **Or it fills its width** (`show_signed_bars_to_fit`, D218): the Industries
## tab's BY YEAR chart. Every bar is the same width whatever the year, so year 1
## is one bar at the left and the chart grows to the right; once the bars reach
## the right edge, the oldest year is dropped for each new one. It redraws when
## its width changes, and a tooltip names the year under the mouse.


## The characters a bar is drawn with, which are the only ones coloured.
const BAR_CHARACTERS: String = "▁▂▃▄▅▆▇█▀"


## What the chart says, without its colours.
var _plain: String = ""

## What `show_signed_bars_to_fit` was given, kept to redraw at a new width.
var _fit_values: Array[float] = []
var _fit_captions: PackedStringArray = []
var _fit_tips: PackedStringArray = []
var _fit_height: int = 0
var _fits_width: bool = false
## The plot width the chart was last drawn at, in cells.
var _fit_cells: int = -1

@onready var _title: Label = %Title
@onready var _chart: RichTextLabel = %Chart


func _ready() -> void:
	resized.connect(_on_resized)


## Bars of a series that is always positive, such as the index level.
func show_bars(
	title: String,
	values: Array[float],
	captions: PackedStringArray,
	width_cells: int,
	height_cells: int,
) -> void:
	_title.text = title
	_reserve(width_cells)
	_plain = TextChart.bars(values, captions, width_cells, height_cells)
	_chart.text = _plain


## Bars either side of zero, such as a year's percentage move.
func show_signed_bars(
	title: String,
	values: Array[float],
	captions: PackedStringArray,
	width_cells: int,
	height_cells: int,
) -> void:
	_title.text = title
	_reserve(width_cells)
	_plain = TextChart.signed_bars(values, captions, width_cells, height_cells)
	_chart.text = coloured_signed(_plain, height_cells)


## Bars either side of zero, each as wide as ever, as many of the latest as fit
## across the chart's width (D218). `tips` is one tooltip per value.
func show_signed_bars_to_fit(
	title: String,
	values: Array[float],
	captions: PackedStringArray,
	tips: PackedStringArray,
	height_cells: int,
) -> void:
	_title.text = title
	_fits_width = true
	_fit_values = values
	_fit_captions = captions
	_fit_tips = tips
	_fit_height = height_cells
	# Room for the scale and one bar; the rest of the width is whatever the
	# layout gives. The label is not sized to its text, so it can shrink again.
	_chart.fit_content = false
	_chart.custom_minimum_size.x = (TextChart.LABEL_WIDTH + 1 + TextChart.BAR_WIDTH) * CellRow.CELL_WIDTH
	_chart.custom_minimum_size.y = (height_cells * 2 + 2) * ChartGeometry.LINE_HEIGHT
	_draw_to_fit()


## How many cells of plot fit across `width` pixels, after the scale and axis.
static func plot_cells_for(width: float) -> int:
	@warning_ignore("integer_division")
	return maxi(TextChart.BAR_WIDTH, int(width) / CellRow.CELL_WIDTH - TextChart.LABEL_WIDTH - 1)


## How many years a fitted chart is showing.
func years_shown() -> int:
	if not _fits_width:
		return 0
	return mini(_fit_values.size(), TextChart.bars_that_fit(_fit_cells))


## The captions of the years shown, oldest first.
func captions_shown() -> PackedStringArray:
	var count: int = years_shown()
	return _fit_captions.slice(_fit_captions.size() - count)


func chart_text() -> String:
	return _plain


## The chart as BBCode, which is what the label shows.
func shown_bbcode() -> String:
	return _chart.text


## `signed_bars` text with its bars coloured: the `height` lines above the axis
## in the gain colour, the lines below it in the loss colour.
static func coloured_signed(plain: String, height: int) -> String:
	var lines: PackedStringArray = plain.split("
")
	for index: int in lines.size():
		if index < height:
			lines[index] = _colour_bars(lines[index], Palette.BULL)
		elif index > height and index <= height * 2:
			lines[index] = _colour_bars(lines[index], Palette.BEAR)
	return "
".join(lines)


## Wraps each run of bar characters in `line` in a colour tag.
static func _colour_bars(line: String, colour: Color) -> String:
	var open: String = "[color=#%s]" % colour.to_html(false)
	var result: String = ""
	var in_bar: bool = false
	for character: String in line:
		var is_bar: bool = BAR_CHARACTERS.contains(character)
		if is_bar and not in_bar:
			result += open
		elif in_bar and not is_bar:
			result += "[/color]"
		in_bar = is_bar
		result += character
	if in_bar:
		result += "[/color]"
	return result


func title_text() -> String:
	return _title.text


func _draw_to_fit() -> void:
	_fit_cells = plot_cells_for(size.x)
	_plain = TextChart.signed_bars(_fit_values, _fit_captions, _fit_cells, _fit_height)
	_chart.text = coloured_signed(_plain, _fit_height)


## The tooltip of the year under the mouse, when the chart fits its width.
func _get_tooltip(at_position: Vector2) -> String:
	if not _fits_width:
		return ""
	var x: float = at_position.x - _chart.position.x
	@warning_ignore("integer_division")
	var column: int = int(x) / CellRow.CELL_WIDTH - TextChart.LABEL_WIDTH - 1
	if column < 0 or at_position.y < _chart.position.y:
		return ""
	@warning_ignore("integer_division")
	var slot: int = column / (TextChart.BAR_WIDTH + TextChart.BAR_GAP)
	var shown: int = years_shown()
	if slot >= shown:
		return ""
	var index: int = _fit_tips.size() - shown + slot
	if index < 0 or index >= _fit_tips.size():
		return ""
	return TermTips.fit(_fit_tips[index])


func _on_resized() -> void:
	if _fits_width and plot_cells_for(size.x) != _fit_cells:
		_draw_to_fit()


## The plot plus the axis labels and the axis itself.
func _reserve(width_cells: int) -> void:
	_chart.custom_minimum_size.x = (width_cells + TextChart.LABEL_WIDTH + 1) * CellRow.CELL_WIDTH
