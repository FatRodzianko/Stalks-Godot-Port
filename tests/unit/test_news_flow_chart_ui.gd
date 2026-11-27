extends GutTest
## The News Flow tab's screens (docs/news-flow-chart.md, Phase 2: the chart,
## read-only), driven through GUT's scene tree: given some news items, the
## right boxes and arrows are drawn, choosing a chain shows its members,
## clicking a box fills the details panel, and the Problems strip shows the
## validator's news errors.
##
## The plugin that puts this screen in a tab at the top of the editor exists
## only inside the running editor, so it is tested by hand
## (manual-testing.md, "News Flow Chart"). Shipped books are loaded fresh, not
## as the shared cached copies, and nothing here writes a file under res://.


const CHART_SCENE: String = "res://addons/news_flow_chart/ui/news_chart.tscn"


func _chart() -> NewsChart:
	var chart: NewsChart = (load(CHART_SCENE) as PackedScene).instantiate() as NewsChart
	add_child_autofree(chart)
	return chart


## A general industry headline with this id, requiring `requires`.
func _item(id: String, requires: Array[StringName] = []) -> IndustryReport:
	var line: IndustryReport = IndustryReport.new()
	line.id = StringName(id)
	line.text = "Words of %s" % id
	line.requires = requires
	return line


## A leads to B and C, B leads to D and E; a second chain F to G; H on its own;
## and E also requires something that is not an item.
func _example() -> Array[Resource]:
	var lines: Array[Resource] = [
		_item("a"),
		_item("b", [&"a"]),
		_item("c", [&"a"]),
		_item("d", [&"b"]),
		_item("e", [&"b", &"no_such_item"]),
		_item("f"),
		_item("g", [&"f"]),
		_item("h"),
	]
	return lines


func _no_problems() -> Array[String]:
	return [] as Array[String]


func _box_ids(chart: NewsChart) -> PackedStringArray:
	var ids: PackedStringArray = []
	for box: NewsItemBox in chart.boxes():
		ids.append(String(box.item_id))
	ids.sort()
	return ids


func _shipped_lines() -> Array[Resource]:
	var books: Array[NewsBook] = []
	for file_name: String in DirAccess.get_files_at(ContentLibrary.NEWS_DIR):
		if file_name.ends_with(".tres"):
			var path: String = "%s/%s" % [ContentLibrary.NEWS_DIR, file_name]
			books.append(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as NewsBook)
	return NewsContent.build(books, []).all_lines()


# ------------------------------------------------------------ chains and boxes


func test_each_chain_is_listed_by_its_root_and_the_first_is_shown() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	assert_eq(chart.chain_labels(), PackedStringArray(["a", "f"]), "an item on its own is not a chain")
	assert_eq(_box_ids(chart), PackedStringArray(["a", "b", "c", "d", "e"]))


func test_one_arrow_for_each_requires_inside_the_chain() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	var expected: Array[PackedStringArray] = [
		PackedStringArray(["a", "b"]),
		PackedStringArray(["a", "c"]),
		PackedStringArray(["b", "d"]),
		PackedStringArray(["b", "e"]),
	]
	assert_eq(chart.arrows(), expected, "the id that is not an item draws nothing")


func test_choosing_a_chain_in_the_list_shows_its_members() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	var chain_list: ItemList = chart.get_node("%ChainList")
	chain_list.item_selected.emit(1)
	assert_eq(_box_ids(chart), PackedStringArray(["f", "g"]))
	assert_eq(chart.arrows(), [PackedStringArray(["f", "g"])] as Array[PackedStringArray])


func test_a_named_chain_shows_its_name_and_a_lost_name_is_a_problem() -> void:
	var names: NewsChainNames = NewsChainNames.new()
	names.names[&"a"] = "Oil crisis"
	names.names[&"h"] = "Lonely"
	var chart: NewsChart = _chart()
	chart.show_content(_example(), names, _no_problems())
	assert_eq(chart.chain_labels(), PackedStringArray(["Oil crisis", "f"]))
	assert_string_contains(chart.problems_text(), "\"Lonely\"")


func test_choosing_an_item_in_the_list_shows_its_chain_and_selects_its_box() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	var item_list: ItemList = chart.get_node("%NewsItemList")
	var index: int = Array(chart.news_item_labels()).find("g")
	item_list.item_selected.emit(index)
	assert_eq(_box_ids(chart), PackedStringArray(["f", "g"]))
	assert_true(chart.box_for(&"g").selected)
	item_list.item_selected.emit(Array(chart.news_item_labels()).find("h"))
	assert_eq(_box_ids(chart), PackedStringArray(["h"]), "an item with no arrows is shown on its own")


func test_a_box_shows_kind_id_conditions_and_the_first_words() -> void:
	var market: MarketNews = MarketNews.new()
	market.id = &"mkt_bear_crash_9"
	market.mood = NewsBands.Mood.BEAR
	market.move = NewsBands.Move.CRASH
	market.headline = "one two three four five six seven eight nine ten"
	market.target_company = &"stryker"
	market.amount = -5
	var industry: IndustryReport = _item("ind_any_down_9")
	industry.move = NewsBands.Move.DOWN
	var chart: NewsChart = _chart()
	chart.show_content([market, industry] as Array[Resource], NewsChainNames.new(), _no_problems())

	chart.choose_item(&"mkt_bear_crash_9")
	var box: NewsItemBox = chart.box_for(&"mkt_bear_crash_9")
	assert_eq(box.title, "Market news")
	assert_eq(box.id_text(), "mkt_bear_crash_9")
	assert_eq(box.conditions_text(), "Mood: Bear  ·  Move: Crash  ·  Target: stryker  ·  Amount: -5")
	assert_eq(box.words_text(), "one two three four five six seven eight …", "the headline's own words, cut short")

	chart.choose_item(&"ind_any_down_9")
	box = chart.box_for(&"ind_any_down_9")
	assert_eq(box.title, "Industry headline")
	assert_eq(box.conditions_text(), "Industry: (any)  ·  Mood: Any  ·  Move: Down")
	assert_eq(box.words_text(), "Words of ind_any_down_9", "no headline, so the text")


func test_every_shipped_news_item_is_listed_and_none_is_in_a_chain_yet() -> void:
	var lines: Array[Resource] = _shipped_lines()
	var chart: NewsChart = _chart()
	chart.show_content(lines, NewsChainNames.new(), _no_problems())
	assert_eq(chart.news_item_labels().size(), lines.size())
	assert_eq(chart.chain_labels(), PackedStringArray(), "no shipped item uses requires (news-flow-chart.md §1.1)")
	assert_eq(chart.boxes().size(), 0)


func test_the_search_box_narrows_the_list_by_id_or_words() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	chart.search("Words of G")
	assert_eq(chart.news_item_labels(), PackedStringArray(["g"]))
	chart.search("")
	assert_eq(chart.news_item_labels().size(), 8)


func test_arrange_lays_each_follower_out_to_the_right_of_what_it_requires() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	await wait_process_frames(2)
	chart.arrange()
	for arrow: PackedStringArray in chart.arrows():
		var from_x: float = chart.box_for(StringName(arrow[0])).position_offset.x
		var to_x: float = chart.box_for(StringName(arrow[1])).position_offset.x
		assert_gt(to_x, from_x, "%s is right of %s" % [arrow[1], arrow[0]])


# ------------------------------------------------------------------ details


func test_clicking_a_box_shows_every_field_in_the_details_panel() -> void:
	var whisper: Whisper = Whisper.new()
	whisper.id = &"whisp_company_worse_9"
	whisper.about = NewsBands.Subject.COMPANY
	whisper.subject = &"stryker"
	whisper.outcome = NewsBands.Surprise.WORSE
	whisper.text = "Some words"
	whisper.requires = [&"a"]
	var lines: Array[Resource] = [_item("a"), whisper]
	var chart: NewsChart = _chart()
	chart.show_content(lines, NewsChainNames.new(), _no_problems())
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	assert_eq(details.shown_fields(), {} as Dictionary[String, String], "nothing until a box is clicked")

	chart.box_for(&"whisp_company_worse_9").selected = true
	assert_eq(details.title_text(), "Whisper")
	var expected: Dictionary[String, String] = {
		"Id": "whisp_company_worse_9",
		"About": "Company",
		"Subject": "stryker",
		"Outcome": "Worse",
		"Text": "Some words",
		"Requires": "a",
	}
	assert_eq(details.shown_fields(), expected)


func test_the_details_panel_is_read_only() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	chart.box_for(&"b").selected = true
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	var editable: Array[Node] = details.find_children("*", "LineEdit", true, false)
	editable.append_array(details.find_children("*", "TextEdit", true, false))
	editable.append_array(details.find_children("*", "OptionButton", true, false))
	assert_eq(editable.size(), 0, "Phase 2 shows fields; editing them is Phase 3")


# ----------------------------------------------------------------- problems


func test_the_problems_strip_shows_what_it_is_given_or_none() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	assert_eq(chart.problems_text(), "Problems: none")
	var problems: Array[String] = ["News e requires no_such_item, which is not a news line."]
	chart.show_content(_example(), NewsChainNames.new(), problems)
	assert_eq(chart.problems_text(), "Problems (1):\n%s" % problems[0])


func test_only_the_validators_news_errors_are_problems() -> void:
	var errors: Array[String] = [
		"News e requires no_such_item, which is not a news line.",
		"Duplicate news id: a",
		"res://src/data/news/x.tres is not a NewsBook",
		"Stalk spud has a bear_change out of range.",
	]
	assert_eq(NewsProblems.of(errors), errors.slice(0, 3))


func test_the_problems_file_reads_back_what_was_written() -> void:
	var path: String = "user://news_flow_chart_ui_test.json"
	var problems: Array[String] = ["one", "two"]
	assert_eq(NewsProblems.write_result(problems, path), OK)
	assert_eq(NewsProblems.read_result(path), problems)
	DirAccess.remove_absolute(path)


func test_the_check_runs_the_real_validator_in_its_own_process() -> void:
	# The check the tab runs: a headless Godot process on the books as saved.
	# The shipped news is valid, so it finds nothing - and "did not run" would
	# show up here as a problem.
	assert_eq(NewsProblems.run_check(), [] as Array[String])



func test_a_box_is_no_taller_than_its_contents() -> void:
	# Found by hand on 2026-11-27: a Whisper box with three short lines stood
	# about 1,800 pixels tall, empty below its words.
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	await wait_process_frames(2)
	for box: NewsItemBox in chart.boxes():
		assert_almost_eq(box.size.y, box.get_combined_minimum_size().y, 1.0, String(box.item_id))


func test_godots_own_arrange_button_is_hidden() -> void:
	# It arranges only the selected boxes, so with one selected it does
	# nothing visible. The tab's Arrange button arranges them all.
	var chart: NewsChart = _chart()
	var canvas: GraphEdit = chart.get_node("%Chart")
	assert_false(canvas.show_arrange_button)


func test_arrange_moves_every_box_even_with_one_selected() -> void:
	var chart: NewsChart = _chart()
	chart.show_content(_example(), NewsChainNames.new(), _no_problems())
	await wait_process_frames(2)
	var moved: NewsItemBox = chart.box_for(&"d")
	moved.position_offset = Vector2(-2000, -2000)
	moved.selected = true
	chart.arrange()
	assert_gt(moved.position_offset.x, chart.box_for(&"b").position_offset.x, "d is back right of b")
	assert_true(moved.selected, "and still selected")


func test_every_arrow_has_a_head_at_the_end_that_requires() -> void:
	var canvas: NewsChartCanvas = NewsChartCanvas.new()
	add_child_autofree(canvas)
	var from_position: Vector2 = Vector2(0, 0)
	var to_position: Vector2 = Vector2(200, 50)
	var points: PackedVector2Array = canvas._get_connection_line(from_position, to_position)
	assert_eq(points[0], from_position, "starts at the required item")
	var size: int = points.size()
	assert_eq(points[size - 2], to_position, "the head's point is on the item that requires")
	assert_eq(points[size - 4], to_position, "the line itself ends there too")
	assert_lt(points[size - 3].x, to_position.x, "one barb behind the point")
	assert_lt(points[size - 1].x, to_position.x, "and the other")
	assert_ne(points[size - 3].y, points[size - 1].y, "on either side of the line")
