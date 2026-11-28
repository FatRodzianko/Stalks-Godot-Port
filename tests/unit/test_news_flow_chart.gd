extends GutTest
## The News Flow Chart's core logic (docs/news-flow-chart.md, Phase 1): the
## ids it writes, the book each new item goes in, the chart worked out from
## `requires`, every edit it makes to the books, chain names, and what each
## dropdown offers. Phase 4: snapshots for undo, the edit history, and the
## requires list the Inspector offers.
##
## All of it runs headless on `NewsBook` objects. Nothing here touches
## src/data/news/: books are loaded fresh (not the shared cached copies) and
## saved only under `user://`.


const SCRATCH_DIR: String = "user://news_flow_chart_test"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)


func after_each() -> void:
	for file_name: String in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, file_name])


func _library() -> ContentLibrary:
	return MatchSetup.load_library(GameMode.Value.STALKLEHEADS)


## A general industry headline with this id, requiring `requires`.
func _item(id: String, requires: Array[StringName] = []) -> IndustryReport:
	var line: IndustryReport = IndustryReport.new()
	line.id = StringName(id)
	line.text = id
	line.requires = requires
	return line


func _graph(lines: Array[Resource]) -> NewsGraph:
	return NewsGraph.from_lines(lines)


## The owner's example shape - A leads to B and C, B leads to D and E - plus a
## second chain F to G, an item on its own, and a requirement that is not an
## item.
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


## The shipped books, loaded fresh so editing them cannot touch the copies
## other tests use, keyed by a path in the scratch folder.
func _shipped_books() -> Dictionary[String, NewsBook]:
	var books: Dictionary[String, NewsBook] = {}
	for file_name: String in DirAccess.get_files_at(ContentLibrary.NEWS_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [ContentLibrary.NEWS_DIR, file_name]
		var book: NewsBook = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as NewsBook
		books["%s/%s" % [SCRATCH_DIR, file_name]] = book
	return books


func _editor() -> NewsBookEditor:
	return NewsBookEditor.new(_shipped_books())


func _requires(editor: NewsBookEditor, id: StringName) -> Array[StringName]:
	return editor.find(id).get("requires")


# ------------------------------------------------------------------- ids


func test_each_kind_gets_an_id_from_its_own_fields() -> void:
	var market: MarketNews = MarketNews.new()
	market.mood = NewsBands.Mood.BEAR
	market.move = NewsBands.Move.CRASH
	assert_eq(NewsIdMaker.next_id(market, []), &"mkt_bear_crash_1")

	var industry: IndustryReport = IndustryReport.new()
	industry.industry_id = &"energy"
	industry.move = NewsBands.Move.DOWN
	assert_eq(NewsIdMaker.next_id(industry, []), &"ind_energy_down_1")
	industry.industry_id = &""
	assert_eq(NewsIdMaker.next_id(industry, []), &"ind_any_down_1", "a headline for any industry")

	var company: CompanyNews = CompanyNews.new()
	company.company_id = &"stryker"
	company.move = NewsBands.Move.SURGE
	assert_eq(NewsIdMaker.next_id(company, []), &"cnews_stryker_surge_1")

	var whisper: Whisper = Whisper.new()
	whisper.about = NewsBands.Subject.COMPANY
	whisper.outcome = NewsBands.Surprise.MUCH_WORSE
	assert_eq(NewsIdMaker.next_id(whisper, []), &"whisp_company_much_worse_1")
	whisper.about = NewsBands.Subject.SQUEEZE
	assert_eq(NewsIdMaker.next_id(whisper, []), &"whisp_squeeze_1", "a squeeze whisper has no outcome")

	var chatter: NpcChatter = NpcChatter.new()
	chatter.strategy = NpcStrategy.Value.VALUE
	chatter.situation = NpcTraderDefinition.Situation.BOUGHT
	assert_eq(NewsIdMaker.next_id(chatter, []), &"chat_value_bought_1")
	chatter.npc_id = &"value_1"
	assert_eq(NewsIdMaker.next_id(chatter, []), &"chat_value_1_bought_1", "one trader's own line")


func test_the_number_follows_the_highest_taken_and_never_reuses_a_retired_id() -> void:
	var market: MarketNews = MarketNews.new()
	market.mood = NewsBands.Mood.BEAR
	market.move = NewsBands.Move.CRASH
	var taken: Array[StringName] = [&"mkt_bear_crash_1", &"mkt_bear_crash_2"]
	assert_eq(NewsIdMaker.next_id(market, taken), &"mkt_bear_crash_3")
	taken.append(&"mkt_bear_crash_7")
	assert_eq(NewsIdMaker.next_id(market, taken), &"mkt_bear_crash_8", "after the highest, not the first gap")
	var lookalikes: Array[StringName] = [&"mkt_bear_crash_9x", &"mkt_bear_crash_extra_9", &"xmkt_bear_crash_9"]
	assert_eq(NewsIdMaker.next_id(market, lookalikes), &"mkt_bear_crash_1", "only this exact prefix counts")


func test_a_new_id_never_collides_with_the_shipped_news() -> void:
	var editor: NewsBookEditor = _editor()
	var market: MarketNews = MarketNews.new()
	market.mood = NewsBands.Mood.BULL
	market.move = NewsBands.Move.FLAT
	assert_eq(NewsIdMaker.next_id(market, editor.taken_ids()), &"mkt_bull_flat_3", "the shipped book has _1 and _2")


# ------------------------------------------------------------------- the router


func test_each_new_item_goes_in_the_book_the_shipped_ones_are_in() -> void:
	var industry: IndustryReport = IndustryReport.new()
	industry.industry_id = &"energy"
	assert_eq(NewsBookRouter.book_path_for(industry), "res://src/data/news/energy.tres")
	industry.industry_id = &""
	assert_eq(NewsBookRouter.book_file_for(industry), "market.tres", "a headline for any industry")

	var company: CompanyNews = CompanyNews.new()
	company.company_id = &"stryker"
	assert_eq(NewsBookRouter.book_file_for(company), "companies.tres")
	company.company_id = &""
	assert_eq(NewsBookRouter.book_file_for(company), "market.tres", "company news for any company")

	assert_eq(NewsBookRouter.book_file_for(MarketNews.new()), "market.tres")
	assert_eq(NewsBookRouter.book_file_for(Whisper.new()), "market.tres")
	assert_eq(NewsBookRouter.book_file_for(NpcChatter.new()), "market.tres")
	assert_eq(NewsBookRouter.book_path_for(MarketNews.new(), SCRATCH_DIR), "%s/market.tres" % SCRATCH_DIR)


# ------------------------------------------------------------------- the graph


func test_the_graph_draws_an_arrow_for_each_requires() -> void:
	var graph: NewsGraph = _graph(_example())
	assert_eq(graph.followers_of(&"a"), [&"b", &"c"] as Array[StringName], "a leads to b and c")
	assert_eq(graph.followers_of(&"b"), [&"d", &"e"] as Array[StringName], "b leads to d and e")
	assert_eq(graph.requires_of(&"e"), [&"b"] as Array[StringName], "an id that is not an item makes no arrow")
	assert_eq(graph.arrow_count(&"b"), 3, "one in, two out")
	assert_eq(graph.arrow_count(&"h"), 0)


func test_chains_roots_and_keys() -> void:
	var graph: NewsGraph = _graph(_example())
	var chains: Array[Array] = graph.chains()
	assert_eq(chains.size(), 2, "a to e is one chain, f to g another; h is in neither")
	assert_eq(str(chains[0]), str([&"a", &"b", &"c", &"d", &"e"]))
	assert_eq(str(chains[1]), str([&"f", &"g"]))
	assert_eq(graph.unchained(), [&"h"] as Array[StringName])
	var first: Array[StringName] = []
	first.assign(chains[0])
	assert_eq(graph.roots(first), [&"a"] as Array[StringName])
	assert_eq(graph.chain_key(first), &"a", "a chain is known by its root")
	assert_eq(graph.chain_of(&"d"), first, "every member finds the same chain")


func test_a_chain_with_two_roots_is_known_by_the_first() -> void:
	var lines: Array[Resource] = [_item("m"), _item("k"), _item("z", [&"m", &"k"])]
	var chain: Array[StringName] = _graph(lines).chain_of(&"z")
	assert_eq(_graph(lines).roots(chain), [&"k", &"m"] as Array[StringName])
	assert_eq(_graph(lines).chain_key(chain), &"k")


func test_a_chain_that_is_all_loop_is_known_by_its_first_id() -> void:
	var lines: Array[Resource] = [_item("q", [&"p"]), _item("p", [&"q"])]
	var graph: NewsGraph = _graph(lines)
	assert_eq(graph.chain_key(graph.chain_of(&"q")), &"p")


func test_an_arrow_that_would_close_a_loop_is_found() -> void:
	var graph: NewsGraph = _graph(_example())
	assert_true(graph.would_loop(&"d", &"a"), "a requiring d, when d already waits for a through b")
	assert_true(graph.would_loop(&"a", &"a"), "an item requiring itself")
	assert_false(graph.would_loop(&"a", &"d"), "d requiring a as well is no loop")
	assert_false(graph.would_loop(&"g", &"a"), "joining two chains is no loop")


# ------------------------------------------------------------------- the book editor


func test_a_new_item_gets_its_id_and_goes_in_its_book() -> void:
	var editor: NewsBookEditor = _editor()
	var industry: IndustryReport = IndustryReport.new()
	industry.industry_id = &"energy"
	industry.move = NewsBands.Move.SURGE
	industry.text = "placeholder"
	assert_eq(editor.add(industry, SCRATCH_DIR), "")
	assert_eq(industry.id, &"ind_energy_surge_3", "the shipped book has _1 and _2")
	assert_eq(editor.book_path_of(industry.id), "%s/energy.tres" % SCRATCH_DIR)
	assert_eq(editor.changed_paths(), ["%s/energy.tres" % SCRATCH_DIR] as Array[String], "only that book changed")


func test_an_item_goes_in_a_book_whose_list_is_read_only() -> void:
	# Found by hand: in the editor, an industry headline for (any) goes in
	# market.tres, which has none yet, and its empty list is the script's
	# read-only default. Appending to it failed and left an empty box.
	var market: NewsBook = NewsBook.new()
	var empty: Array[IndustryReport] = []
	empty.make_read_only()
	market.industry_reports = empty
	var path: String = "%s/market.tres" % SCRATCH_DIR
	var editor: NewsBookEditor = NewsBookEditor.new({path: market} as Dictionary[String, NewsBook])
	var industry: IndustryReport = IndustryReport.new()
	industry.move = NewsBands.Move.CRASH
	industry.text = "test"
	assert_eq(editor.add(industry, SCRATCH_DIR), "")
	assert_eq(editor.find(industry.id), industry)
	assert_eq(market.industry_reports.size(), 1)
	assert_eq(editor.delete(industry.id), "")
	assert_true(market.industry_reports.is_empty(), "deleted again")


func test_an_item_whose_book_is_missing_is_refused() -> void:
	var books: Dictionary[String, NewsBook] = {"%s/market.tres" % SCRATCH_DIR: NewsBook.new()}
	var editor: NewsBookEditor = NewsBookEditor.new(books)
	var industry: IndustryReport = IndustryReport.new()
	industry.industry_id = &"energy"
	assert_string_contains(editor.add(industry, SCRATCH_DIR), "no book energy.tres")
	assert_eq(industry.id, &"", "no id given out")
	assert_true(editor.changed_paths().is_empty())


func test_linking_writes_requires_and_refuses_what_cannot_work() -> void:
	var editor: NewsBookEditor = _editor()
	assert_eq(editor.link(&"mkt_bear_crash_1", &"ind_energy_down_1"), "")
	assert_eq(_requires(editor, &"ind_energy_down_1"), [&"mkt_bear_crash_1"] as Array[StringName])
	assert_string_contains(editor.link(&"mkt_bear_crash_1", &"ind_energy_down_1"), "already requires")
	assert_string_contains(editor.link(&"ind_energy_down_1", &"mkt_bear_crash_1"), "loop")
	assert_string_contains(editor.link(&"no_such_item", &"ind_energy_down_1"), "must be news items")
	assert_eq(_requires(editor, &"mkt_bear_crash_1"), [] as Array[StringName], "a refused arrow changes nothing")


func test_removing_one_arrow_keeps_the_rest() -> void:
	var editor: NewsBookEditor = _editor()
	editor.link(&"mkt_bear_crash_1", &"ind_energy_down_1")
	editor.link(&"ind_energy_down_1", &"cnews_mafia_bear_1")
	assert_eq(editor.unlink(&"mkt_bear_crash_1", &"ind_energy_down_1"), "")
	assert_eq(_requires(editor, &"ind_energy_down_1"), [] as Array[StringName])
	assert_eq(_requires(editor, &"cnews_mafia_bear_1"), [&"ind_energy_down_1"] as Array[StringName], "b to c stays")
	assert_string_contains(editor.unlink(&"mkt_bear_crash_1", &"ind_energy_down_1"), "does not require")


func test_deleting_an_item_removes_its_arrows_and_retires_its_id() -> void:
	var editor: NewsBookEditor = _editor()
	editor.link(&"mkt_bear_crash_1", &"ind_energy_down_1")
	editor.link(&"ind_energy_down_1", &"cnews_mafia_bear_1")
	assert_eq(editor.delete(&"ind_energy_down_1"), "")
	assert_null(editor.find(&"ind_energy_down_1"))
	assert_eq(_requires(editor, &"cnews_mafia_bear_1"), [] as Array[StringName], "what followed it waits for nothing")
	assert_true(editor.retired_ids.has(&"ind_energy_down_1"))
	assert_eq(editor.changed_paths().size(), 2, "its own book and the follower's")
	var again: IndustryReport = IndustryReport.new()
	again.industry_id = &"energy"
	again.move = NewsBands.Move.DOWN
	again.text = "placeholder"
	editor.add(again, SCRATCH_DIR)
	assert_eq(again.id, &"ind_energy_down_3", "not the deleted _1, nor the shipped _2")


func test_a_field_can_be_changed_but_an_id_cannot() -> void:
	var editor: NewsBookEditor = _editor()
	assert_eq(editor.set_field(&"mkt_bear_crash_1", &"amount", -5), "")
	assert_eq(editor.find(&"mkt_bear_crash_1").get("amount"), -5)
	assert_string_contains(editor.set_field(&"mkt_bear_crash_1", &"id", &"renamed"), "fixed")
	assert_string_contains(editor.set_field(&"mkt_bear_crash_1", &"no_such_field", 1), "no field")
	assert_string_contains(editor.set_field(&"no_such_item", &"amount", 1), "no news item")


## The whole round trip: edit, save, load the saved books afresh, and the
## content validator accepts them with the edits in place.
func test_saved_books_reload_with_the_edits_and_pass_the_validator() -> void:
	var editor: NewsBookEditor = _editor()
	var company: CompanyNews = CompanyNews.new()
	company.company_id = &"stryker"
	company.move = NewsBands.Move.CRASH
	company.text = "placeholder"
	editor.add(company, SCRATCH_DIR)
	editor.link(&"mkt_bear_crash_1", company.id)
	assert_eq(editor.save_changed(), [] as Array[String])
	assert_true(editor.changed_paths().is_empty(), "nothing left to save")

	var reloaded: Dictionary[String, NewsBook] = _shipped_books()
	for path: String in DirAccess.get_files_at(SCRATCH_DIR):
		var saved_path: String = "%s/%s" % [SCRATCH_DIR, path]
		reloaded[saved_path] = ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as NewsBook
	assert_eq(DirAccess.get_files_at(SCRATCH_DIR).size(), 1, "only the changed book was saved")
	var books: Array[NewsBook] = []
	books.assign(reloaded.values())
	var library: ContentLibrary = _library()
	library.news = NewsContent.build(books, library.traders)
	library.validate()
	assert_eq(library.errors, [] as Array[String])
	var saved: CompanyNews = NewsBookEditor.new(reloaded).find(company.id) as CompanyNews
	assert_not_null(saved, "the new item was saved")
	assert_eq(saved.requires, [&"mkt_bear_crash_1"] as Array[StringName], "with its arrow")


func test_retired_ids_are_written_under_the_file_explanation() -> void:
	var path: String = "%s/retired.txt" % SCRATCH_DIR
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# why this file exists\n#\n\nold_one\n")
	file.close()
	var editor: NewsBookEditor = NewsBookEditor.new({}, ContentLibrary.read_retired_news_ids(path))
	editor.retired_ids.append(&"new_one")
	assert_eq(editor.save_retired_ids(path), "")
	assert_eq(FileAccess.get_file_as_string(path), "# why this file exists\n#\nold_one\nnew_one\n")
	assert_eq(ContentLibrary.read_retired_news_ids(path), [&"old_one", &"new_one"] as Array[StringName])


# ------------------------------------------------------------------- chain names


func test_a_chain_is_called_by_its_key_until_it_is_named() -> void:
	var graph: NewsGraph = _graph(_example())
	var chain: Array[StringName] = graph.chain_of(&"d")
	var chain_names: NewsChainNames = NewsChainNames.new()
	assert_eq(chain_names.name_for(graph, chain), "a")
	chain_names.rename(graph, chain, "  Oil crisis ")
	assert_eq(chain_names.name_for(graph, chain), "Oil crisis")
	chain_names.rename(graph, chain, "")
	assert_eq(chain_names.name_for(graph, chain), "a", "an empty name gives it back its key")


func test_names_are_written_and_read_back() -> void:
	var path: String = "%s/chains.cfg" % SCRATCH_DIR
	var chain_names: NewsChainNames = NewsChainNames.new()
	chain_names.names = {&"a": "Oil crisis", &"f": "The \"big\" one"}
	assert_eq(chain_names.write(path), OK)
	var read: NewsChainNames = NewsChainNames.read(path)
	assert_eq(read.names, chain_names.names)
	assert_true(NewsChainNames.read("%s/none.cfg" % SCRATCH_DIR).names.is_empty(), "no file, no names")


func test_a_name_moves_to_a_new_root_put_in_front() -> void:
	var before: NewsGraph = _graph(_example())
	var chain_names: NewsChainNames = NewsChainNames.new()
	chain_names.rename(before, before.chain_of(&"a"), "Oil crisis")
	var lines: Array[Resource] = _example()
	lines[0].set("requires", [&"start"] as Array[StringName])
	lines.append(_item("start"))
	var after: NewsGraph = _graph(lines)
	assert_eq(chain_names.follow(after, before), [] as Array[String])
	assert_eq(chain_names.names, {&"start": "Oil crisis"} as Dictionary[StringName, String])


func test_a_name_moves_on_when_its_root_or_middle_is_deleted() -> void:
	var a_b_c_d: Array[Resource] = [_item("a"), _item("b", [&"a"]), _item("c", [&"b"]), _item("d", [&"c"])]
	var before: NewsGraph = _graph(a_b_c_d)
	var chain_names: NewsChainNames = NewsChainNames.new()
	chain_names.rename(before, before.chain_of(&"a"), "Saga")

	var without_a: Array[Resource] = [_item("b"), _item("c", [&"b"]), _item("d", [&"c"])]
	chain_names.follow(_graph(without_a), before)
	assert_eq(chain_names.names, {&"b": "Saga"} as Dictionary[StringName, String], "to the next root")

	chain_names.names = {&"a": "Saga"}
	var without_b: Array[Resource] = [_item("a"), _item("c"), _item("d", [&"c"])]
	chain_names.follow(_graph(without_b), before)
	assert_eq(chain_names.names, {&"c": "Saga"} as Dictionary[StringName, String], "a is left alone, so to c and d")


func test_a_name_that_cannot_be_placed_is_dropped_and_reported() -> void:
	var before: NewsGraph = _graph([_item("a"), _item("b", [&"a"])] as Array[Resource])
	var chain_names: NewsChainNames = NewsChainNames.new()
	chain_names.rename(before, before.chain_of(&"a"), "Short")
	var problems: Array[String] = chain_names.follow(_graph([_item("a")] as Array[Resource]), before)
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "\"Short\" is gone")
	assert_true(chain_names.names.is_empty())


func test_two_named_chains_joined_keep_one_name_and_report_the_other() -> void:
	var before: NewsGraph = _graph(_example())
	var chain_names: NewsChainNames = NewsChainNames.new()
	chain_names.names = {&"a": "First", &"f": "Second"}
	var lines: Array[Resource] = _example()
	lines[6].set("requires", [&"f", &"e"] as Array[StringName])
	var problems: Array[String] = chain_names.follow(_graph(lines), before)
	assert_eq(chain_names.names, {&"a": "First"} as Dictionary[StringName, String])
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "\"Second\" was dropped")


func test_with_no_earlier_graph_a_name_keeps_to_its_key() -> void:
	var chain_names: NewsChainNames = NewsChainNames.new()
	chain_names.names = {&"b": "Kept", &"gone": "Lost"}
	var problems: Array[String] = chain_names.follow(_graph(_example()))
	assert_eq(chain_names.names, {&"a": "Kept"} as Dictionary[StringName, String], "b is in a's chain now")
	assert_eq(problems.size(), 1, "the name whose item is gone")


# ------------------------------------------------------------------- dropdowns


func test_each_dropdown_lists_what_exists() -> void:
	var library: ContentLibrary = _library()
	var market: MarketNews = MarketNews.new()
	var companies: Array[NewsFieldChoices.Choice] = NewsFieldChoices.choices_for(market, &"target_company", library)
	assert_eq(companies.size(), library.companies.size() + 1)
	assert_eq(companies[0].id, &"")
	assert_eq(companies[0].label, "(none)", "market news may move nothing")
	assert_eq(companies[1].id, library.companies[0].id)
	assert_eq(companies[1].label, "%s (%s)" % [library.companies[0].display_name, library.companies[0].id])

	var industries: Array[NewsFieldChoices.Choice] = NewsFieldChoices.choices_for(IndustryReport.new(), &"industry_id", library)
	assert_eq(industries.size(), library.industries.size() + 1)
	assert_eq(industries[0].label, "(any)")

	var chatter: Array[NewsFieldChoices.Choice] = NewsFieldChoices.choices_for(NpcChatter.new(), &"npc_id", library)
	assert_eq(chatter.size(), library.traders.size() + 1)

	assert_false(NewsFieldChoices.has_choices(market, &"headline"), "free text gets no dropdown")
	assert_true(NewsFieldChoices.choices_for(market, &"headline", library).is_empty())


func test_a_whisper_subject_lists_what_the_whisper_is_about() -> void:
	var library: ContentLibrary = _library()
	var whisper: Whisper = Whisper.new()
	whisper.about = NewsBands.Subject.INDUSTRY
	assert_eq(NewsFieldChoices.choices_for(whisper, &"subject", library).size(), library.industries.size() + 1)
	whisper.about = NewsBands.Subject.SQUEEZE
	assert_eq(NewsFieldChoices.choices_for(whisper, &"subject", library).size(), library.companies.size() + 1)


func test_requires_offers_every_other_item() -> void:
	var lines: Array[Resource] = _example()
	var choices: Array[StringName] = NewsFieldChoices.requires_choices(lines[1], _graph(lines))
	assert_eq(choices.size(), lines.size() - 1)
	assert_false(choices.has(&"b"), "not itself")


func test_requires_for_the_inspector_leaves_out_ids_that_would_loop() -> void:
	# b requires a, and d requires b: a requiring b or d would be a loop.
	var lines: Array[Resource] = _example()
	var choices: Array[StringName] = NewsFieldChoices.requires_choices_without_loops(lines[0], _graph(lines))
	assert_false(choices.has(&"b"), "b already waits for a")
	assert_false(choices.has(&"d"), "nor d, which waits for b")
	assert_true(choices.has(&"f"), "an item in another chain is fine")
	assert_false(choices.has(&"a"), "not itself")


func test_detach_cuts_every_arrow_and_joins_nothing_around_it() -> void:
	var lines: Array[Resource] = _example()
	var book: NewsBook = NewsBook.new()
	book.industry_reports.assign(lines)
	var editor: NewsBookEditor = NewsBookEditor.new({"%s/market.tres" % SCRATCH_DIR: book} as Dictionary[String, NewsBook])
	assert_eq(editor.detach(&"b"), "")
	assert_not_null(editor.find(&"b"), "still in its book")
	assert_eq(_requires(editor, &"b"), [] as Array[StringName])
	assert_eq(_requires(editor, &"d"), [] as Array[StringName], "d is not given a instead")
	assert_eq(_requires(editor, &"e"), [&"no_such_item"] as Array[StringName], "not an item, so not an arrow")
	assert_eq(_requires(editor, &"c"), [&"a"] as Array[StringName])
	assert_false(editor.retired_ids.has(&"b"))
	assert_ne(editor.detach(&"nothing"), "")


# ------------------------------------------------------------- Phase 4: undo


func test_a_snapshot_restored_puts_a_deleted_item_back_as_the_same_object() -> void:
	var lines: Array[Resource] = _example()
	var book: NewsBook = NewsBook.new()
	book.industry_reports.assign(lines)
	var path: String = "%s/market.tres" % SCRATCH_DIR
	var editor: NewsBookEditor = NewsBookEditor.new({path: book} as Dictionary[String, NewsBook])
	var saved: Dictionary = editor.snapshot()
	assert_eq(editor.delete(&"b"), "")
	assert_null(editor.find(&"b"))
	assert_eq(_requires(editor, &"d"), [] as Array[StringName], "the arrow from b went with it")
	editor.restore(saved)
	assert_same(editor.find(&"b"), lines[1], "the item itself, not a copy")
	assert_eq(_requires(editor, &"d"), [&"b"] as Array[StringName], "its arrows are back")
	assert_false(editor.retired_ids.has(&"b"), "and its id is not retired")
	assert_true(editor.retired_ids_changed(), "the retired list is to be written again")
	assert_eq(editor.changed_paths(), [path] as Array[String])


func test_a_snapshot_restored_puts_fields_back_and_marks_the_book_changed() -> void:
	var editor: NewsBookEditor = _editor()
	var id: StringName = editor.content().all_lines()[0].get("id")
	var path: String = editor.book_path_of(id)
	editor.save_changed()
	var saved: Dictionary = editor.snapshot()
	var words_field: StringName = &"text"
	if not words_field in editor.find(id):
		words_field = &"headline"
	var words: String = editor.find(id).get(words_field)
	assert_eq(editor.set_field(id, words_field, "Changed"), "")
	editor.save_changed()
	assert_eq(editor.changed_paths(), [] as Array[String], "saved")
	editor.restore(saved)
	assert_eq(editor.find(id).get(words_field), words)
	assert_eq(editor.changed_paths(), [path] as Array[String], "the saved file no longer matches")


func test_retired_ids_count_as_changed_until_written() -> void:
	var editor: NewsBookEditor = NewsBookEditor.new({} as Dictionary[String, NewsBook])
	assert_false(editor.retired_ids_changed())
	var lines: Array[Resource] = [_item("a")]
	var book: NewsBook = NewsBook.new()
	book.industry_reports.assign(lines)
	editor = NewsBookEditor.new({"%s/market.tres" % SCRATCH_DIR: book} as Dictionary[String, NewsBook])
	editor.delete(&"a")
	assert_true(editor.retired_ids_changed())
	assert_eq(editor.save_retired_ids("%s/retired.txt" % SCRATCH_DIR), "")
	assert_false(editor.retired_ids_changed())


func test_the_edit_history_undoes_and_redoes_in_order() -> void:
	var history: NewsEditHistory = NewsEditHistory.new()
	assert_eq(history.undo(), {}, "nothing to undo")
	history.record("first", {&"n": 0}, {&"n": 1})
	history.record("second", {&"n": 1}, {&"n": 2})
	assert_eq(history.next_undo_name(), "second")
	assert_eq(history.undo(), {&"n": 1})
	assert_eq(history.undo(), {&"n": 0})
	assert_false(history.can_undo())
	assert_eq(history.redo(), {&"n": 1})
	history.record("third", {&"n": 1}, {&"n": 3})
	assert_false(history.can_redo(), "a new edit forgets what was undone")


func test_edits_with_the_same_merge_key_are_undone_as_one() -> void:
	var history: NewsEditHistory = NewsEditHistory.new()
	history.record("type", {&"t": ""}, {&"t": "a"}, "x:text")
	history.record("type", {&"t": "a"}, {&"t": "ab"}, "x:text")
	history.record("other", {&"t": "ab"}, {&"t": "ab", &"m": 1}, "x:headline")
	assert_eq(history.undo(), {&"t": "ab"})
	assert_eq(history.undo(), {&"t": ""}, "both keystrokes at once")
	assert_eq(history.redo(), {&"t": "ab"}, "redone to the last keystroke")
