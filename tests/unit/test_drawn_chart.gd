extends GutTest
## The drawn charts (decisions.md D188): where `ChartGeometry` puts things, and
## what `DrawnChart` holds and answers. The drawing itself is checked by eye in
## manual-testing.md section K; everything it draws is placed by the
## arithmetic tested here.


const ChartScene: PackedScene = preload("res://src/ui/widgets/drawn_chart.tscn")

const PLOT: Rect2i = Rect2i(40, 10, 100, 50)


func test_the_scale_spans_every_value_and_skips_nan() -> void:
	var series: Array[PackedFloat32Array] = [PackedFloat32Array([3.0, NAN, 9.0]), PackedFloat32Array([5.0])]
	assert_eq(ChartGeometry.value_range(series, false), Vector2(3.0, 9.0))


func test_bars_scale_always_reaches_zero() -> void:
	var series: Array[PackedFloat32Array] = [PackedFloat32Array([3.0, 9.0])]
	assert_eq(ChartGeometry.value_range(series, true), Vector2(0.0, 9.0))
	var negative: Array[PackedFloat32Array] = [PackedFloat32Array([-4.0, -2.0])]
	assert_eq(ChartGeometry.value_range(negative, true), Vector2(-4.0, 0.0))


func test_a_flat_or_empty_scale_is_widened() -> void:
	var flat: Array[PackedFloat32Array] = [PackedFloat32Array([5.0, 5.0])]
	assert_eq(ChartGeometry.value_range(flat, false), Vector2(4.0, 6.0))
	var empty: Array[PackedFloat32Array] = [PackedFloat32Array([NAN])]
	assert_eq(ChartGeometry.value_range(empty, false), Vector2(0.0, 1.0))


func test_the_top_of_the_scale_is_the_top_of_the_plot() -> void:
	var scale: Vector2 = Vector2(0.0, 100.0)
	assert_eq(ChartGeometry.y_for(100.0, scale, PLOT), PLOT.position.y)
	assert_eq(ChartGeometry.y_for(0.0, scale, PLOT), PLOT.end.y)
	assert_eq(ChartGeometry.y_for(50.0, scale, PLOT), PLOT.position.y + 25)


func test_slots_divide_the_plot_and_a_position_finds_its_slot() -> void:
	assert_eq(ChartGeometry.slot_width(4, PLOT), 25)
	for index: int in 4:
		var centre: int = ChartGeometry.slot_centre(index, 4, PLOT)
		assert_eq(ChartGeometry.slot_at(centre, 4, PLOT), index)
	assert_eq(ChartGeometry.slot_at(PLOT.position.x - 1, 4, PLOT), -1, "left of the plot")
	assert_eq(ChartGeometry.slot_at(PLOT.end.x + 5, 4, PLOT), -1, "right of the last slot")


func test_a_candle_spans_open_to_close_and_never_vanishes() -> void:
	var scale: Vector2 = Vector2(0.0, 100.0)
	var rising: Rect2i = ChartGeometry.candle_rect(0, 4, 20.0, 60.0, scale, PLOT)
	assert_eq(rising.position.y, ChartGeometry.y_for(60.0, scale, PLOT))
	assert_eq(rising.end.y, ChartGeometry.y_for(20.0, scale, PLOT))
	var flat: Rect2i = ChartGeometry.candle_rect(1, 4, 40.0, 40.0, scale, PLOT)
	assert_eq(flat.size.y, 1, "a year that did not move still shows")
	assert_lt(rising.size.x, ChartGeometry.slot_width(4, PLOT), "gaps between candles")


func test_bars_side_by_side_grow_from_zero() -> void:
	var scale: Vector2 = Vector2(-10.0, 10.0)
	var first: Rect2i = ChartGeometry.bar_rect(0, 4, 0, 2, 10.0, scale, PLOT)
	var second: Rect2i = ChartGeometry.bar_rect(0, 4, 1, 2, -10.0, scale, PLOT)
	var zero: int = ChartGeometry.y_for(0.0, scale, PLOT)
	assert_eq(first.end.y, zero, "a positive bar stands on zero")
	assert_eq(second.position.y, zero, "a negative bar hangs from it")
	assert_eq(second.position.x, first.end.x, "the second sits beside the first")


func test_captions_thin_out_when_they_would_touch() -> void:
	assert_eq(ChartGeometry.caption_step(4, 1, PLOT), 1, "25 px slots hold a 1-character year")
	assert_gt(ChartGeometry.caption_step(30, 2, PLOT), 1, "3 px slots do not")


func test_scale_labels_fit_their_column() -> void:
	assert_eq(ChartGeometry.label(11356.0), "11k")
	assert_eq(ChartGeometry.label(1021.0), "1021")
	assert_eq(ChartGeometry.label(12.66), "12.7")
	assert_eq(ChartGeometry.label(1.026), "1.03")
	assert_eq(ChartGeometry.label(8.0), "8", "a whole number has no decimals")
	assert_eq(ChartGeometry.label(0.0), "0")
	for value: float in [123456.0, -9999.0, -12.5, 0.5]:
		assert_lte(ChartGeometry.label(value).length(), ChartGeometry.LABEL_CHARS, str(value))


func test_a_legend_moves_the_plot_down() -> void:
	var size: Vector2 = Vector2(300, 108)
	assert_eq(
		ChartGeometry.plot_rect(size, true).position.y,
		ChartGeometry.plot_rect(size, false).position.y + ChartGeometry.LINE_HEIGHT,
	)


func test_resting_on_a_year_shows_its_tooltip() -> void:
	var chart: DrawnChart = ChartScene.instantiate()
	add_child_autofree(chart)
	chart.size = Vector2(300, 108)
	var series: Array[PackedFloat32Array] = [PackedFloat32Array([1.0, 2.0, 3.0])]
	chart.show_lines(series, PackedStringArray(["A"]), PackedStringArray(["0", "1", "2"]),
		PackedStringArray(["Year 0", "Year 1", "Year 2"]))
	var plot: Rect2i = chart.plot_rect()
	var middle: float = ChartGeometry.slot_centre(1, 3, plot)
	assert_eq(chart.get_tooltip(Vector2(middle, plot.get_center().y)), "Year 1")
	assert_eq(chart.get_tooltip(Vector2(2, 2)), "", "nothing over the labels")


func test_a_message_replaces_the_chart() -> void:
	var chart: DrawnChart = ChartScene.instantiate()
	add_child_autofree(chart)
	chart.show_message("Nothing yet.")
	assert_eq(chart.kind(), DrawnChart.Kind.NONE)
	assert_eq(chart.message(), "Nothing yet.")
	assert_true(chart.series().is_empty())


func test_a_split_is_restated_on_todays_shares() -> void:
	assert_almost_eq(MarketReadouts.per_share_adjusted(200.0, 1000, 2000), 100.0, 0.001)
	assert_almost_eq(MarketReadouts.per_share_adjusted(8.0, 1000, 1000), 8.0, 0.001)
	assert_true(is_nan(MarketReadouts.per_share_adjusted(NAN, 1000, 2000)))
