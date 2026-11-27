extends GutTest
## The News Flow tab's screens (docs/news-flow-chart.md, Phases 2 and 3),
## driven through GUT's scene tree: given some news items, the right boxes and
## arrows are drawn, choosing a chain shows its members, clicking a box fills
## the details panel, and the Problems strip shows the validator's news errors.
## Phase 3: drawing and removing an arrow writes `requires`, a loop is refused,
## each kind is created with the right id in the right book, editing a field
## changes that field and nothing else, a chain can be renamed, and Save writes
## the changed books.
##
## The plugin that puts this screen in a tab at the top of the editor exists
## only inside the running editor, so it is tested by hand
## (manual-testing.md, sections Z and AA). Shipped books are loaded fresh, not
## as the shared cached copies, and every book, name file and retired list is
## kept under `user://`: nothing here writes a file under res://.


const CHART_SCENE: String = "res://addons/news_flow_chart/ui/news_chart.tscn"
const SCRATCH_DIR: String = "user://news_flow_chart_ui_test"

var _checks_run: int = 0


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	_checks_run = 0


func after_each() -> void:
	for file_name: String in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, file_name])


func _chart() -> NewsChart:
	var chart: NewsChart = (load(CHART_SCENE) as PackedScene).instantiate() as NewsChart
	chart.news_dir = SCRATCH_DIR
	chart.chain_names_path = "%s/news_chains.cfg" % SCRATCH_DIR
	chart.retired_ids_path = "%s/news_retired_ids.txt" % SCRATCH_DIR
	chart.check_problems = _count_check
	add_child_autofree(chart)
	return chart


## Stands in for the Problems check, which would otherwise run the real one.
func _count_check() -> Array[String]:
	_checks_run += 1
	return [] as Array[String]


## Shows `lines`, all in one book, `market.tres` in the scratch folder.
func _show(
	chart: NewsChart,
	lines: Array[Resource],
	names: NewsChainNames = NewsChainNames.new(),
	problems: Array[String] = [],
) -> NewsBookEditor:
	var book: NewsBook = NewsBook.new()
	for line: Resource in lines:
		var list: Array = book.get(NewsKind.list_name(NewsKind.of(line)))
		list.append(line)
	var books: Dictionary[String, NewsBook] = {"%s/market.tres" % SCRATCH_DIR: book}
	var editor: NewsBookEditor = NewsBookEditor.new(books)
	chart.show_content(editor, names, problems, NewsFieldChoices.library_from_files())
	return editor


## The shipped books, loaded fresh, keyed by paths in the scratch folder.
func _show_shipped(chart: NewsChart) -> NewsBookEditor:
	var books: Dictionary[String, NewsBook] = {}
	for file_name: String in DirAccess.get_files_at(ContentLibrary.NEWS_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [ContentLibrary.NEWS_DIR, file_name]
		var book: NewsBook = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as NewsBook
		books["%s/%s" % [SCRATCH_DIR, file_name]] = book
	var editor: NewsBookEditor = NewsBookEditor.new(books)
	chart.show_content(editor, NewsChainNames.new(), [] as Array[String], NewsFieldChoices.library_from_files())
	return editor


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
	_show(chart, _example())
	assert_eq(chart.chain_labels(), PackedStringArray(["a", "f"]), "an item on its own is not a chain")
	assert_eq(_box_ids(chart), PackedStringArray(["a", "b", "c", "d", "e"]))


func test_one_arrow_for_each_requires_inside_the_chain() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	var expected: Array[PackedStringArray] = [
		PackedStringArray(["a", "b"]),
		PackedStringArray(["a", "c"]),
		PackedStringArray(["b", "d"]),
		PackedStringArray(["b", "e"]),
	]
	assert_eq(chart.arrows(), expected, "the id that is not an item draws nothing")


func test_choosing_a_chain_in_the_list_shows_its_members() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	var chain_list: ItemList = chart.get_node("%ChainList")
	chain_list.item_selected.emit(1)
	assert_eq(_box_ids(chart), PackedStringArray(["f", "g"]))
	assert_eq(chart.arrows(), [PackedStringArray(["f", "g"])] as Array[PackedStringArray])


func test_a_named_chain_shows_its_name_and_a_lost_name_is_a_problem() -> void:
	var names: NewsChainNames = NewsChainNames.new()
	names.names[&"a"] = "Oil crisis"
	names.names[&"h"] = "Lonely"
	var chart: NewsChart = _chart()
	_show(chart, _example(), names)
	assert_eq(chart.chain_labels(), PackedStringArray(["Oil crisis", "f"]))
	assert_string_contains(chart.problems_text(), "\"Lonely\"")


## A left click on the news item list at item `index`: the press, then the
## release, as the list receives them.
func _click_list(item_list: ItemList, index: int, release: bool = true) -> void:
	var at: Vector2 = item_list.get_item_rect(index).get_center()
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	item_list.gui_input.emit(press)
	if not release:
		return
	var let_go: InputEventMouseButton = press.duplicate()
	let_go.pressed = false
	item_list.gui_input.emit(let_go)


func test_clicking_an_item_in_the_list_shows_its_chain_and_selects_its_box() -> void:
	var chart: NewsChart = _chart()
	chart.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chart.size = Vector2(1200, 800)
	_show(chart, _example())
	await wait_process_frames(2)
	var item_list: ItemList = chart.get_node("%NewsItemList")
	_click_list(item_list, Array(chart.news_item_labels()).find("g"))
	assert_eq(_box_ids(chart), PackedStringArray(["f", "g"]))
	assert_true(chart.box_for(&"g").selected)
	item_list.item_activated.emit(Array(chart.news_item_labels()).find("h"))
	assert_eq(_box_ids(chart), PackedStringArray(["h"]), "an item with no arrows is shown on its own; Enter too")


func test_pressing_on_the_list_changes_nothing_until_the_button_is_let_go() -> void:
	# Found by hand: opening the item on the press swapped the chart out from
	# under a drag that was just starting, so nothing could be dropped onto it.
	var chart: NewsChart = _chart()
	chart.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chart.size = Vector2(1200, 800)
	_show(chart, _example())
	await wait_process_frames(2)
	var item_list: ItemList = chart.get_node("%NewsItemList")
	_click_list(item_list, Array(chart.news_item_labels()).find("h"), false)
	assert_eq(_box_ids(chart), PackedStringArray(["a", "b", "c", "d", "e"]), "the chain shown stays")


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
	_show(chart, [market, industry] as Array[Resource])

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
	_show(chart, lines)
	assert_eq(chart.news_item_labels().size(), lines.size())
	assert_eq(chart.chain_labels(), PackedStringArray(), "no shipped item uses requires (news-flow-chart.md §1.1)")
	assert_eq(chart.boxes().size(), 0)


func test_the_search_box_narrows_the_list_by_id_or_words() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	chart.search("Words of G")
	assert_eq(chart.news_item_labels(), PackedStringArray(["g"]))
	chart.search("")
	assert_eq(chart.news_item_labels().size(), 8)


func test_arrange_lays_each_follower_out_below_what_it_requires() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	await wait_process_frames(2)
	chart.arrange()
	for arrow: PackedStringArray in chart.arrows():
		var above: NewsItemBox = chart.box_for(StringName(arrow[0]))
		var below: NewsItemBox = chart.box_for(StringName(arrow[1]))
		assert_gt(below.position_offset.y, above.position_offset.y + above.size.y, "%s is below %s" % [arrow[1], arrow[0]])


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
	_show(chart, lines)
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	assert_eq(details.shown_fields(), {} as Dictionary[String, String], "nothing until a box is clicked")

	chart.box_for(&"whisp_company_worse_9").selected = true
	assert_eq(details.title_text(), "Whisper")
	var expected: Dictionary[String, String] = {
		"Id": "whisp_company_worse_9",
		"About": "Company",
		"Subject": "strYker!!! (stryker)",
		"Outcome": "Worse",
		"Text": "Some words",
		"Requires": "a",
	}
	assert_eq(details.shown_fields(), expected)


# ----------------------------------------------------------------- problems


func test_the_problems_strip_shows_what_it_is_given_or_none() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	assert_eq(chart.problems_text(), "Problems: none")
	var problems: Array[String] = ["News e requires no_such_item, which is not a news line."]
	_show(chart, _example(), NewsChainNames.new(), problems)
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
	_show(chart, _example())
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
	_show(chart, _example())
	await wait_process_frames(2)
	var moved: NewsItemBox = chart.box_for(&"d")
	moved.position_offset = Vector2(-2000, -2000)
	moved.selected = true
	chart.arrange()
	assert_gt(moved.position_offset.y, chart.box_for(&"b").position_offset.y, "d is back below b")
	assert_true(moved.selected, "and still selected")


func test_an_arrow_runs_from_the_bottom_of_one_box_to_the_top_of_the_next_head_down() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	await wait_process_frames(2)
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	var a: NewsItemBox = chart.box_for(&"a")
	var b: NewsItemBox = chart.box_for(&"b")
	var from_port: Vector2 = (a.position_offset + a.get_output_port_position(0)) * canvas.zoom
	var to_port: Vector2 = (b.position_offset + b.get_input_port_position(0)) * canvas.zoom
	var points: PackedVector2Array = canvas._get_connection_line(from_port, to_port)
	var bottom_of_a: Vector2 = (a.position_offset + Vector2(a.size.x / 2.0, a.size.y)) * canvas.zoom
	var top_of_b: Vector2 = (b.position_offset + Vector2(b.size.x / 2.0, 0.0)) * canvas.zoom
	var size: int = points.size()
	assert_eq(points[0], bottom_of_a, "leaves the bottom middle of the required box")
	assert_eq(points[size - 2], top_of_b, "the head's point is on the top middle of the box that requires")
	assert_lt(points[size - 3].y, top_of_b.y, "both barbs above the point: it points down")
	assert_lt(points[size - 1].y, top_of_b.y)


func test_a_line_being_dragged_still_has_a_head() -> void:
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


# ------------------------------------------------------- Phase 3: arrows


func _requires(editor: NewsBookEditor, id: StringName) -> Array[StringName]:
	return editor.find(id).get("requires")


func test_drawing_an_arrow_adds_the_id_to_requires() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	var canvas: GraphEdit = chart.get_node("%Chart")
	canvas.connection_request.emit(&"c", 0, &"d", 0)
	assert_eq(_requires(editor, &"d"), [&"b", &"c"] as Array[StringName])
	assert_has(chart.arrows(), PackedStringArray(["c", "d"]), "and the arrow is drawn")
	assert_string_contains(chart.status_text(), "Unsaved: market.tres")


func test_removing_an_arrow_removes_only_that_id() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	canvas.arrow_delete_requested.emit(&"b", &"e")
	assert_eq(_requires(editor, &"e"), [&"no_such_item"] as Array[StringName], "every other requirement stays")
	assert_eq(_requires(editor, &"d"), [&"b"] as Array[StringName], "every other arrow stays")
	assert_does_not_have(chart.arrows(), PackedStringArray(["b", "e"]))


func test_an_arrow_that_would_make_a_loop_is_refused_and_says_why() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	var canvas: GraphEdit = chart.get_node("%Chart")
	canvas.connection_request.emit(&"d", 0, &"a", 0)
	assert_eq(_requires(editor, &"a"), [] as Array[StringName], "a still requires nothing")
	assert_string_contains(chart.status_text(), "loop")
	assert_false(chart.has_unsaved_changes())


func test_the_details_panel_adds_and_removes_a_requirement() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	chart.box_for(&"c").selected = true
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	details.requirement_added.emit(&"h")
	assert_eq(_requires(editor, &"c"), [&"a", &"h"] as Array[StringName])
	details.requirement_removed.emit(&"a")
	assert_eq(_requires(editor, &"c"), [&"h"] as Array[StringName])


func test_an_item_dropped_on_the_chart_gets_a_box_where_it_was_dropped() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	chart.add_to_chart(&"h", Vector2(500, 300))
	assert_eq(_box_ids(chart), PackedStringArray(["a", "b", "c", "d", "e", "h"]), "beside the chain already shown")
	assert_eq(chart.box_for(&"h").position_offset, Vector2(500, 300))


# ------------------------------------------------------- Phase 3: creating


func test_each_kind_is_created_with_its_id_in_its_book() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show_shipped(chart)
	var shipped_count: int = chart.news_item_labels().size()
	var cases: Array[Dictionary] = [
		{
			"kind": NewsKind.Value.MARKET,
			"fields": {&"mood": NewsBands.Mood.BEAR, &"move": NewsBands.Move.CRASH},
			"id": &"mkt_bear_crash_3",
			"book": "market.tres",
		},
		{
			"kind": NewsKind.Value.INDUSTRY,
			"fields": {&"industry_id": &"energy", &"move": NewsBands.Move.UP},
			"id": &"ind_energy_up_3",
			"book": "energy.tres",
		},
		{
			"kind": NewsKind.Value.COMPANY,
			"fields": {&"company_id": &"stryker", &"move": NewsBands.Move.SURGE},
			"id": &"cnews_stryker_surge_1",
			"book": "companies.tres",
		},
		{
			"kind": NewsKind.Value.WHISPER,
			"fields": {&"about": NewsBands.Subject.COMPANY, &"outcome": NewsBands.Surprise.WORSE},
			"id": &"whisp_company_worse_2",
			"book": "market.tres",
		},
		{
			"kind": NewsKind.Value.CHATTER,
			"fields": {&"strategy": NpcStrategy.Value.VALUE, &"situation": NpcTraderDefinition.Situation.BOUGHT},
			"id": &"chat_value_bought_1",
			"book": "market.tres",
		},
	]
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	for case: Dictionary in cases:
		chart.start_new_item(case["kind"])
		assert_true(details.is_draft_shown(), "Create and Cancel shown for a new item")
		var fields: Dictionary = case["fields"]
		for field: StringName in fields:
			details.field_changed.emit(field, fields[field])
		details.field_changed.emit(&"text", "Written by the test")
		details.create_pressed.emit()
		var id: StringName = case["id"]
		assert_eq(editor.book_path_of(id), "%s/%s" % [SCRATCH_DIR, case["book"]], String(id))
		assert_not_null(chart.box_for(id), "%s has a box" % id)
		assert_eq(editor.find(id).get("text"), "Written by the test")
	assert_eq(chart.news_item_labels().size(), shipped_count + cases.size())


func test_cancel_makes_nothing() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	chart.start_new_item(NewsKind.Value.MARKET)
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	details.cancel_pressed.emit()
	assert_false(details.is_draft_shown())
	assert_eq(editor.content().size(), 8)
	assert_false(chart.has_unsaved_changes())


# ------------------------------------------------------- Phase 3: editing


func _one_market_item(chart: NewsChart) -> NewsBookEditor:
	var market: MarketNews = MarketNews.new()
	market.id = &"mkt_bear_crash_9"
	market.mood = NewsBands.Mood.BEAR
	market.move = NewsBands.Move.CRASH
	market.headline = "Some words"
	market.requires = [&"a"]
	var lines: Array[Resource] = [_item("a"), market]
	var editor: NewsBookEditor = _show(chart, lines)
	chart.choose_item(&"mkt_bear_crash_9")
	return editor


func test_the_id_is_shown_and_every_other_field_has_a_control_to_edit_it() -> void:
	var chart: NewsChart = _chart()
	_one_market_item(chart)
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	assert_true(details.control_for(&"id") is Label, "an id is fixed once made")
	assert_true(details.control_for(&"mood") is OptionButton)
	assert_true(details.control_for(&"headline") is TextEdit)
	assert_true(details.control_for(&"target_company") is OptionButton, "a dropdown of companies")
	assert_true(details.control_for(&"amount") is SpinBox)


func test_the_company_dropdown_lists_every_company_and_none() -> void:
	var chart: NewsChart = _chart()
	_one_market_item(chart)
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	var option: OptionButton = details.control_for(&"target_company")
	var library: ContentLibrary = NewsFieldChoices.library_from_files()
	assert_eq(option.item_count, library.companies.size() + 1)
	assert_eq(option.get_item_text(0), "(none)")


func test_changing_a_field_in_the_panel_changes_that_field_and_nothing_else() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _one_market_item(chart)
	var before: Dictionary[String, String] = {}
	for field: PackedStringArray in NewsItemSummary.fields(editor.find(&"mkt_bear_crash_9")):
		before[field[0]] = field[1]

	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	var mood: OptionButton = details.control_for(&"mood")
	mood.select(1)
	mood.item_selected.emit(1)
	var headline: TextEdit = details.control_for(&"headline")
	headline.text = "Other words"
	headline.text_changed.emit()

	var after: Dictionary[String, String] = {}
	for field: PackedStringArray in NewsItemSummary.fields(editor.find(&"mkt_bear_crash_9")):
		after[field[0]] = field[1]
	assert_eq(after["Mood"], "Bull")
	assert_eq(after["Headline"], "Other words")
	assert_eq(after["Id"], "mkt_bear_crash_9", "the id does not follow the mood")
	for name: String in before:
		if name != "Mood" and name != "Headline":
			assert_eq(after[name], before[name], name)
	assert_eq(chart.box_for(&"mkt_bear_crash_9").words_text(), "Other words", "the box follows the typing")


# ------------------------------------------------------- Phase 3: names and saving


func test_renaming_a_chain_names_it_in_the_list() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	chart.choose_chain(1)
	chart.rename_chain("Oil crisis")
	assert_eq(chart.chain_labels(), PackedStringArray(["a", "Oil crisis"]))
	assert_true(chart.has_unsaved_changes())
	chart.rename_chain("")
	assert_eq(chart.chain_labels(), PackedStringArray(["a", "f"]), "an empty name gives back the root's id")


func test_a_name_follows_its_chain_when_an_item_is_put_in_front() -> void:
	var names: NewsChainNames = NewsChainNames.new()
	names.names[&"f"] = "Oil crisis"
	var chart: NewsChart = _chart()
	_show(chart, _example(), names)
	chart.link(&"h", &"f")
	assert_has(Array(chart.chain_labels()), "Oil crisis")
	assert_eq(names.names.keys(), [&"h"], "now kept under the new root")


func test_save_writes_the_changed_books_and_names_then_checks_again() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	chart.link(&"c", &"d")
	chart.choose_chain(0)
	chart.rename_chain("Oil crisis")
	var checks_before: int = _checks_run
	assert_eq(chart.save(), [] as Array[String])
	assert_false(chart.has_unsaved_changes())
	assert_eq(_checks_run, checks_before + 1, "Problems is refreshed after a save")

	var path: String = "%s/market.tres" % SCRATCH_DIR
	var saved: NewsBook = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as NewsBook
	var required: Array[StringName] = []
	for line: IndustryReport in saved.industry_reports:
		if line.id == &"d":
			required = line.requires
	assert_eq(required, [&"b", &"c"] as Array[StringName])
	var names: NewsChainNames = NewsChainNames.read(chart.chain_names_path)
	assert_eq(names.names, {&"a": "Oil crisis"} as Dictionary[StringName, String])


func test_nothing_is_written_until_save() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	chart.link(&"c", &"d")
	chart.choose_chain(0)
	chart.rename_chain("Oil crisis")
	assert_false(FileAccess.file_exists("%s/market.tres" % SCRATCH_DIR))
	assert_false(FileAccess.file_exists(chart.chain_names_path))


func test_a_requirement_picked_from_off_the_chart_is_put_on_it_with_its_arrow() -> void:
	# Found in the editor: the arrow was written but its other end was not on
	# the chart, so nothing could be seen.
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	chart.box_for(&"c").selected = true
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	details.requirement_added.emit(&"g")
	assert_eq(_requires(editor, &"c"), [&"a", &"g"] as Array[StringName])
	assert_not_null(chart.box_for(&"g"), "g is put on the chart")
	assert_has(chart.arrows(), PackedStringArray(["g", "c"]))
	assert_true(chart.box_for(&"c").selected, "c stays the one being edited")



# ------------------------------------------------- after the first run of section AA


func test_new_boxes_do_not_cover_one_another() -> void:
	# Found by hand: every new box appeared at the same spot, on top of the
	# first.
	var chart: NewsChart = _chart()
	_show(chart, _example())
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	for word: String in ["one", "two", "three"]:
		chart.start_new_item(NewsKind.Value.INDUSTRY)
		details.field_changed.emit(&"text", word)
		details.create_pressed.emit()
		await wait_process_frames(2)
	var boxes: Array[NewsItemBox] = chart.boxes()
	assert_eq(boxes.size(), 8, "the chain of five and three new ones")
	for first: int in boxes.size():
		for second: int in range(first + 1, boxes.size()):
			var one: Rect2 = Rect2(boxes[first].position_offset, boxes[first].size)
			var other: Rect2 = Rect2(boxes[second].position_offset, boxes[second].size)
			assert_false(one.intersects(other), "%s and %s overlap" % [boxes[first].item_id, boxes[second].item_id])


func test_a_right_click_on_the_chart_offers_every_kind_and_makes_it_there() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	await wait_process_frames(2)
	var canvas: GraphEdit = chart.get_node("%Chart")
	var menu: PopupMenu = chart.get_node("%CreateMenu")
	assert_eq(menu.item_count, NewsKind.ALL.size())
	assert_eq(menu.get_item_text(0), "New market news")
	canvas.popup_request.emit(Vector2(700, 450))
	menu.id_pressed.emit(NewsKind.Value.WHISPER)
	var details: NewsDetailsPanel = chart.get_node("%DetailsPanel")
	assert_eq(details.title_text(), "New whisper")
	details.field_changed.emit(&"outcome", NewsBands.Surprise.WORSE)
	details.field_changed.emit(&"text", "Written by the test")
	details.create_pressed.emit()
	await wait_process_frames(2)
	var made: NewsItemBox = chart.box_for(&"whisp_company_worse_1")
	assert_not_null(made)
	var expected: Vector2 = (Vector2(700, 450) + canvas.scroll_offset) / canvas.zoom
	assert_eq(made.position_offset, expected, "where the right-click was")
	assert_not_null(editor.find(&"whisp_company_worse_1"))


func test_rows_put_each_item_below_everything_it_requires() -> void:
	var lines: Array[Resource] = _example()
	var graph: NewsGraph = NewsGraph.from_lines(lines)
	var ids: Array[StringName] = [&"a", &"b", &"c", &"d", &"e", &"h"]
	var rows: Array[Array] = NewsLayout.rows(graph, ids)
	assert_eq(rows, [[&"a", &"h"], [&"b", &"c"], [&"d", &"e"]] as Array[Array])


func test_a_free_spot_is_right_of_everything_at_the_top() -> void:
	var taken: Array[Rect2] = [Rect2(0, 100, 200, 50), Rect2(-300, 40, 100, 300)]
	assert_eq(NewsLayout.free_spot(taken), Vector2(200 + NewsLayout.COLUMN_GAP, 40))
	assert_eq(NewsLayout.free_spot([] as Array[Rect2]), Vector2.ZERO)


# ------------------------------------------------- after the second run of section AA


func test_arrange_centers_each_item_over_its_own_followers_as_a_tree() -> void:
	# Found by hand: the third row lined up in columns under the second row
	# instead of branching out under the one item it follows.
	var lines: Array[Resource] = [
		_item("m"),
		_item("c2", [&"m"]),
		_item("i", [&"m"]),
		_item("c3", [&"i"]),
		_item("c4", [&"i"]),
	]
	var ids: Array[StringName] = [&"m", &"c2", &"i", &"c3", &"c4"]
	var sizes: Dictionary[StringName, Vector2] = {}
	for id: StringName in ids:
		sizes[id] = Vector2(240, 100)
	var at: Dictionary[StringName, Vector2] = NewsLayout.positions(NewsGraph.from_lines(lines), ids, sizes)
	var gap: float = NewsLayout.COLUMN_GAP
	var row: float = 100 + NewsLayout.ROW_GAP
	assert_eq(at[&"c3"], Vector2(-120, 2 * row), "i's two followers side by side")
	assert_eq(at[&"c4"], Vector2(-120 + 240 + gap, 2 * row))
	assert_eq(at[&"i"], Vector2(20, row), "i centered over its followers")
	assert_eq(at[&"c2"], Vector2(-400, row), "c2 beside i's whole branch, not over c3")
	assert_eq(at[&"m"], Vector2(-120, 0), "m centered over everything under it")


func test_an_arrow_starts_from_the_box_pressed_first_whichever_dot() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	# Pressed on c's top dot and let go on d's bottom dot: Godot reports d's
	# bottom joined to c's top, but c was pressed first, so d requires c.
	canvas.connection_drag_started.emit(&"c", 0, false)
	canvas.connection_request.emit(&"d", 0, &"c", 0)
	canvas.connection_drag_ended.emit()
	assert_eq(_requires(editor, &"d"), [&"b", &"c"] as Array[StringName])
	assert_eq(_requires(editor, &"c"), [&"a"] as Array[StringName], "not the other way round")


func test_letting_go_anywhere_on_a_box_draws_the_arrow_to_it() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	await wait_process_frames(2)
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	var d: NewsItemBox = chart.box_for(&"d")
	var middle_of_d: Vector2 = d.position + d.size * canvas.zoom / 2.0
	canvas.connection_drag_started.emit(&"c", 0, true)
	canvas.connection_to_empty.emit(&"c", 0, middle_of_d)
	canvas.connection_drag_ended.emit()
	assert_eq(_requires(editor, &"d"), [&"b", &"c"] as Array[StringName], "from the bottom dot")
	await wait_process_frames(2)
	canvas.connection_drag_started.emit(&"a", 0, false)
	canvas.connection_from_empty.emit(&"a", 0, middle_of_d)
	canvas.connection_drag_ended.emit()
	assert_eq(_requires(editor, &"d"), [&"b", &"c", &"a"] as Array[StringName], "and from the top dot")
	canvas.connection_to_empty.emit(&"c", 0, middle_of_d + Vector2(5000, 0))
	assert_eq(_requires(editor, &"d"), [&"b", &"c", &"a"] as Array[StringName], "let go on nothing: no arrow")


func test_the_dots_that_answer_the_mouse_are_the_top_and_bottom_middle() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	await wait_process_frames(2)
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	var box: NewsItemBox = chart.box_for(&"a")
	var top: Vector2 = (box.position + NewsItemBox.top_dot(box.size) * canvas.zoom) / canvas.zoom
	var bottom: Vector2 = (box.position + NewsItemBox.bottom_dot(box.size) * canvas.zoom) / canvas.zoom
	var side: Vector2 = (box.position + box.get_output_port_position(0) * canvas.zoom) / canvas.zoom
	assert_true(canvas._is_in_input_hotzone(box, 0, top))
	assert_true(canvas._is_in_output_hotzone(box, 0, bottom))
	assert_false(canvas._is_in_output_hotzone(box, 0, side), "not Godot's side dot")
	assert_false(canvas._is_in_input_hotzone(box, 0, bottom))


func test_a_line_dragged_from_a_box_starts_at_the_dot_pressed() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	await wait_process_frames(2)
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	var a: NewsItemBox = chart.box_for(&"a")
	var port: Vector2 = (a.position_offset + a.get_output_port_position(0)) * canvas.zoom
	var mouse: Vector2 = port + Vector2(300, 300)
	canvas.connection_drag_started.emit(&"a", 0, true)
	var points: PackedVector2Array = canvas._get_connection_line(port, mouse)
	canvas.connection_drag_ended.emit()
	assert_eq(points[0], (a.position_offset + NewsItemBox.bottom_dot(a.size)) * canvas.zoom)
	assert_eq(points[points.size() - 2], mouse, "head at the mouse")


func test_a_clicked_arrow_is_selected_and_delete_removes_it() -> void:
	var chart: NewsChart = _chart()
	var editor: NewsBookEditor = _show(chart, _example())
	await wait_process_frames(2)
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	var a: NewsItemBox = chart.box_for(&"a")
	var b: NewsItemBox = chart.box_for(&"b")
	var from_port: Vector2 = (a.position_offset + a.get_output_port_position(0)) * canvas.zoom
	var to_port: Vector2 = (b.position_offset + b.get_input_port_position(0)) * canvas.zoom
	var line: PackedVector2Array = canvas._get_connection_line(from_port, to_port)
	var on_it: Vector2 = line[(line.size() - 3) / 2] - canvas.scroll_offset
	assert_false(canvas.select_arrow_at(on_it + Vector2(0, 5000)), "nothing there")
	assert_true(canvas.select_arrow_at(on_it), "on the line")
	assert_eq(canvas.selected_arrow(), [&"a", &"b"] as Array[StringName])
	canvas.delete_nodes_request.emit([] as Array[StringName])
	assert_eq(_requires(editor, &"b"), [] as Array[StringName], "b no longer requires a")
	assert_does_not_have(chart.arrows(), PackedStringArray(["a", "b"]))


# ------------------------------------------------- after the third run of section AA


func test_a_dragged_line_runs_dot_to_dot_when_the_chart_is_scrolled() -> void:
	# Found by hand: once the chart had been scrolled, the line being dragged
	# was drawn from the side of one box to the side of the other. Godot hands
	# the dragged line over shifted by the scroll, unlike a finished arrow.
	var chart: NewsChart = _chart()
	_show(chart, _example())
	await wait_process_frames(2)
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	canvas.scroll_offset = Vector2(-321, 77)
	await wait_process_frames(2)
	var shift: Vector2 = -canvas.scroll_offset
	var a: NewsItemBox = chart.box_for(&"a")
	var d: NewsItemBox = chart.box_for(&"d")
	var a_bottom: Vector2 = (a.position_offset + NewsItemBox.bottom_dot(a.size)) * canvas.zoom + shift
	var d_top: Vector2 = (d.position_offset + NewsItemBox.top_dot(d.size)) * canvas.zoom + shift
	var a_port: Vector2 = (a.position_offset + a.get_output_port_position(0)) * canvas.zoom + shift
	var d_port: Vector2 = (d.position_offset + d.get_input_port_position(0)) * canvas.zoom + shift
	var mouse: Vector2 = a_port + Vector2(30, 200)
	canvas.connection_drag_started.emit(&"a", 0, true)
	var free: PackedVector2Array = canvas._get_connection_line(a_port, mouse)
	var snapped: PackedVector2Array = canvas._get_connection_line(a_port, d_port)
	canvas.connection_drag_ended.emit()
	assert_eq(free[0], a_bottom, "from the bottom dot pressed")
	assert_eq(free[free.size() - 2], mouse, "to the mouse")
	assert_eq(snapped[0], a_bottom)
	assert_eq(snapped[snapped.size() - 2], d_top, "on d's top dot, not its side")


func test_a_line_dragged_from_a_top_dot_has_its_head_on_the_other_box() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
	await wait_process_frames(2)
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	var shift: Vector2 = -canvas.scroll_offset
	var d: NewsItemBox = chart.box_for(&"d")
	var c: NewsItemBox = chart.box_for(&"c")
	var d_port: Vector2 = (d.position_offset + d.get_input_port_position(0)) * canvas.zoom + shift
	var c_port: Vector2 = (c.position_offset + c.get_output_port_position(0)) * canvas.zoom + shift
	# Godot draws a drag from an incoming dot from the other box's outgoing dot.
	canvas.connection_drag_started.emit(&"d", 0, false)
	var points: PackedVector2Array = canvas._get_connection_line(c_port, d_port)
	canvas.connection_drag_ended.emit()
	assert_eq(points[0], (d.position_offset + NewsItemBox.top_dot(d.size)) * canvas.zoom + shift, "from d's top dot, pressed")
	assert_eq(points[points.size() - 2], (c.position_offset + NewsItemBox.bottom_dot(c.size)) * canvas.zoom + shift, "head on c's bottom dot")


func test_a_line_whose_button_was_let_go_elsewhere_ends_when_the_mouse_moves() -> void:
	# Found by hand: a screenshot taken mid-drag took the button's release, and
	# the line stayed on the mouse until the next click.
	var chart: NewsChart = _chart()
	_show(chart, _example())
	var canvas: NewsChartCanvas = chart.get_node("%Chart")
	canvas.connection_drag_started.emit(&"a", 0, true)
	var held: InputEventMouseMotion = InputEventMouseMotion.new()
	held.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._input(held)
	assert_eq(canvas._dragged_from, &"a", "still drawing while the button is held")
	canvas._input(InputEventMouseMotion.new())
	assert_eq(canvas._dragged_from, &"", "ended once it is not")
	# Here Godot itself was never drawing a line, since the drag was only
	# signalled, so ending it makes Godot say so. In the editor it is drawing.
	assert_engine_error("connecting", "Godot had no line of its own to end")
