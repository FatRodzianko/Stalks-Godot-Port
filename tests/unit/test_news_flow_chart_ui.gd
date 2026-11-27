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


func test_choosing_an_item_in_the_list_shows_its_chain_and_selects_its_box() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
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


func test_arrange_lays_each_follower_out_to_the_right_of_what_it_requires() -> void:
	var chart: NewsChart = _chart()
	_show(chart, _example())
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
	var canvas: GraphEdit = chart.get_node("%Chart")
	canvas.disconnection_request.emit(&"b", 0, &"e", 0)
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
