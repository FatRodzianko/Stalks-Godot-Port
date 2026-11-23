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


## The characters a bar is drawn with, which are the only ones coloured.
const BAR_CHARACTERS: String = "▁▂▃▄▅▆▇█▀"


## What the chart says, without its colours.
var _plain: String = ""

@onready var _title: Label = %Title
@onready var _chart: RichTextLabel = %Chart


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


## The plot plus the axis labels and the axis itself.
func _reserve(width_cells: int) -> void:
	_chart.custom_minimum_size.x = (width_cells + TextChart.LABEL_WIDTH + 1) * CellRow.CELL_WIDTH
