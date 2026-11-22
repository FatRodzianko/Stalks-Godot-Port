class_name ChartWidget
extends VBoxContainer
## A titled text chart (docs/stalkleheads-design.md §7.6): a heading, then the
## chart itself as one label of block characters built by `TextChart`.
##
## Sized in whole character cells, so it sits on the grid: the index chart is 38
## cells wide and 7 tall, the industry chart 22 by 5 (§7.6). The label's width
## is reserved from that size rather than from whatever it currently says, so a
## chart with three years in it takes the same room as one with thirty.


@onready var _title: Label = %Title
@onready var _chart: Label = %Chart


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
	_chart.text = TextChart.bars(values, captions, width_cells, height_cells)


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
	_chart.text = TextChart.signed_bars(values, captions, width_cells, height_cells)


func chart_text() -> String:
	return _chart.text


func title_text() -> String:
	return _title.text


## The plot plus the axis labels and the axis itself.
func _reserve(width_cells: int) -> void:
	_chart.custom_minimum_size.x = (width_cells + TextChart.LABEL_WIDTH + 1) * CellRow.CELL_WIDTH
