extends GutTest
## Player-written content, and what happens when it is hostile.
##
## **Two callers, one rule set.** `StalkSchema` is reached from a file the
## player wrote (`CustomStalkStore`) and from a definition another player sent
## (`StateSync.decode_content`). The checks are the same; only the answer to a
## failure differs. So most of these test the schema directly, and a smaller
## number prove each caller reacts to a refusal the way it should.
##
## **Every rejection test here was written by reinstating the fault.** A test
## that asserts a refusal passes just as well when the refusal is unreachable,
## so each one was first run against a schema with that check deleted, and each
## failed. See docs/decisions.md D108 for why that is the standard here.
##
## The companion file is `test_custom_stalk_ui.gd`, which covers the picker and
## the board.


## A file with everything required and nothing else, as a starting point each
## test bends in one direction.
func _good_file() -> Dictionary:
	return {
		"name": "Example Holdings",
		"bull_change": [0, 15],
		"bear_change": [5, 25],
		"bull_dividend": 3,
		"bear_dividend": 1,
	}


func _built(changes: Dictionary) -> StalkSchema:
	var data: Dictionary = _good_file()
	for key: Variant in changes:
		data[key] = changes[key]
	return StalkSchema.from_file_data(data, "example")


func _errors_of(schema: StalkSchema) -> String:
	return "\n".join(schema.errors)


# ------------------------------------------------------------------- the basics

func test_a_minimal_file_loads() -> void:
	var schema: StalkSchema = StalkSchema.from_file_data(_good_file(), "example")
	assert_true(schema.is_valid(), _errors_of(schema))
	assert_eq(schema.definition.display_name, "Example Holdings")
	assert_eq(schema.definition.bull_dividend, 3)
	assert_eq(schema.definition.bear_change, Vector2i(5, 25))


func test_a_missing_description_is_simply_blank() -> void:
	# The owner's instruction: a description is optional and blank when absent.
	var schema: StalkSchema = StalkSchema.from_file_data(_good_file(), "example")
	assert_true(schema.is_valid(), _errors_of(schema))
	assert_eq(schema.definition.description, "")


func test_a_stalk_with_no_events_is_never_drawn_for_one() -> void:
	# Also the owner's instruction, and it needs no rule of its own: a stalk
	# that puts nothing in the pool cannot come out of it.
	var schema: StalkSchema = StalkSchema.from_file_data(_good_file(), "example")
	assert_eq(schema.definition.all_events().size(), 0)

	var pool: EventPool = ContentLibrary.of([schema.definition]).build_event_pool()
	var state: GameState = StalksFixture.make_state(10, 1, [schema.definition])
	assert_null(
		pool.draw(MarketMood.Value.BULL, state, StalksFixture.rng(1)),
		"a stalk with no events should never be picked for one",
	)


func test_events_load_into_the_right_pools() -> void:
	var schema: StalkSchema = _built({"events": [
		{"mood": "bull", "text": "Up it went.", "price_change": 10},
		{"mood": "bear", "text": "Down it went.", "price_change": -15},
		{"mood": "bull", "text": "Up again.", "price_change": 5},
	]})
	assert_true(schema.is_valid(), _errors_of(schema))
	assert_eq(schema.definition.bull_events.size(), 2)
	assert_eq(schema.definition.bear_events.size(), 1)
	assert_eq(schema.definition.bear_events[0].price_change, -15)


func test_an_event_targets_the_stalk_it_lives_on() -> void:
	# The mismatch ContentLibrary exists to catch cannot be expressed in a file
	# at all: the target is set from the stalk, never read from the data.
	var schema: StalkSchema = _built({"events": [
		{"mood": "bull", "text": "Up it went.", "price_change": 10},
	]})
	assert_eq(schema.definition.bull_events[0].target_stalk_id, schema.definition.id)


# --------------------------------------------------------------------- the ids

func test_a_custom_id_cannot_collide_with_a_shipped_one() -> void:
	# A file claiming to be BERRY BONDS gets its own id, not that one.
	var schema: StalkSchema = _built({"id": "berry_bonds"})
	assert_true(schema.is_valid(), _errors_of(schema))
	assert_eq(schema.definition.id, &"custom:berry_bonds")
	assert_ne(schema.definition.id, &"berry_bonds")


func test_the_id_comes_from_the_file_name_when_none_is_given() -> void:
	var schema: StalkSchema = StalkSchema.from_file_data(_good_file(), "My Company!")
	assert_eq(schema.definition.id, &"custom:my_company")


func test_an_id_cannot_be_a_path() -> void:
	var schema: StalkSchema = _built({"id": "../../secrets"})
	# Slugged rather than refused, because the result is unmistakably not a
	# path: every separator is gone.
	assert_true(schema.is_valid(), _errors_of(schema))
	assert_false(String(schema.definition.id).contains("/"))
	assert_false(String(schema.definition.id).contains(".."))


func test_an_id_of_nothing_usable_is_refused() -> void:
	var schema: StalkSchema = _built({"id": "!!!"})
	assert_false(schema.is_valid(), "an id with no usable characters should be refused")


# --------------------------------------------------------------- hostile text

func test_a_name_outside_printable_ascii_is_refused() -> void:
	# The owner chose printable ASCII: wide enough for PG&Enron and strYker!!!,
	# narrow enough that Terminus can draw every character of it.
	assert_false(_built({"name": "Café Corp"}).is_valid(), "accented letters")
	assert_false(_built({"name": "Rocket \U0001F680 Ltd"}).is_valid(), "emoji")
	assert_false(_built({"name": "Tab\there"}).is_valid(), "a tab")
	assert_false(_built({"name": "Two\nlines"}).is_valid(), "a newline")


func test_the_punctuation_the_game_itself_uses_is_allowed() -> void:
	# The rule has to admit the shipped names or it is the wrong rule.
	for name: String in [
		"My Pillow, Your Pillow, We're All Pillows!",
		"PG&Enron",
		"strYker!!!",
		"BERRY BONDS FROM DIE HARD",
	]:
		assert_true(_built({"name": name}).is_valid(), "should allow %s" % name)


func test_every_shipped_stalk_passes_the_rule_imposed_on_custom_ones() -> void:
	# The strongest form of the test above. If a rule here would reject the
	# game's own content, the rule is wrong — and this says so by name rather
	# than leaving somebody to discover it on the wire.
	var shipped: ContentLibrary = ContentLibrary.load_from()
	assert_true(shipped.is_valid(), "the shipped content should load")
	var decoded: Dictionary = StateSync.decode_content(
		StateSync.encode_content(shipped)
	)
	assert_eq(String(decoded["error"]), "", "shipped content must survive its own rules")
	assert_eq(
		(decoded["library"] as ContentLibrary).stalks.size(), shipped.stalks.size()
	)


func test_text_may_not_hold_a_link() -> void:
	assert_false(_built({"description": "See http://example.com"}).is_valid())
	assert_false(_built({"name": "res://thing"}).is_valid())


func test_ordinary_prose_with_dots_is_allowed() -> void:
	# The traversal check used to run on prose and rejected the shipped
	# "You're not my mutual...". Ids are where traversal is stopped, by
	# permitting no dot at all; prose is not a path and is not treated as one.
	assert_true(_built({"description": "You're not my mutual..."}).is_valid())


func test_a_name_longer_than_the_limit_is_refused() -> void:
	var long_name: String = "A".repeat(StalkSchema.MAX_NAME_LENGTH + 1)
	assert_false(_built({"name": long_name}).is_valid())
	assert_true(_built({"name": "A".repeat(StalkSchema.MAX_NAME_LENGTH)}).is_valid())


func test_a_description_longer_than_the_limit_is_refused() -> void:
	var long: String = "A".repeat(StalkSchema.MAX_DESCRIPTION_LENGTH + 1)
	assert_false(_built({"description": long}).is_valid())


func test_an_empty_name_is_refused() -> void:
	assert_false(_built({"name": ""}).is_valid())
	assert_false(_built({"name": "   "}).is_valid())


# --------------------------------------------------------------- square brackets
#
# `[` is the one character that is dangerous rather than merely ugly: the event
# strip is a RichTextLabel with BBCode on, so a `[` in text is markup. It is
# allowed in content — it is ordinary punctuation — and escaped where it is
# drawn. These prove both halves, because allowing it without escaping it is
# the bug and escaping it somewhere it never reaches is no protection.

func test_a_square_bracket_is_allowed_in_text() -> void:
	assert_true(_built({"name": "Brackets [Inc]"}).is_valid())


func test_the_event_strip_escapes_a_square_bracket() -> void:
	var label: ScrollingLabel = ScrollingLabel.new()
	add_child_autofree(label)
	label.size = Vector2(600, 40)
	label.set_full_text("[color=red]not actually red[/color]")
	await wait_process_frames(1)

	# The markup must survive as text rather than being interpreted. `text`
	# holds what is handed to the engine, so the opening bracket must be
	# escaped in it.
	assert_true(
		label.text.contains("[lb]color=red"),
		"a bracket should be escaped, got: %s" % label.text,
	)
	assert_false(
		label.text.contains("[color=red]"),
		"raw BBCode reached the label: %s" % label.text,
	)


func test_the_company_panel_draws_text_rather_than_markup() -> void:
	# StalkPanel is a plain Label, so markup in a name or description is shown
	# literally. Asserted rather than assumed, because turning that Label into
	# a RichTextLabel later would silently open the hole.
	var panel: StalkPanel = preload(
		"res://src/ui/widgets/stalk_panel.tscn"
	).instantiate()
	add_child_autofree(panel)
	await wait_process_frames(1)
	panel.show_stalk("[b]Bold[/b] Corp", "[url=x]link[/url]", PackedStringArray())

	assert_eq(panel.description_text(), "[url=x]link[/url]", "shown as written")
	var name_label: Label = panel.get_node("%StalkName")
	assert_eq(name_label.text, "[b]Bold[/b] Corp")


# ------------------------------------------------------------------- the numbers
#
# Every one of these feeds integer money or a column measured in characters.
# They are refused rather than clamped: a host sending a dividend of 2^40 is
# not somebody whose number wants quietly correcting.

func test_an_enormous_integer_is_refused_not_clamped() -> void:
	var schema: StalkSchema = _built({"bull_dividend": 1099511627776})
	assert_false(schema.is_valid(), "a huge dividend should be refused")
	assert_null(schema.definition, "nothing should be built from it")


func test_an_integer_beyond_what_a_float_can_hold_is_refused() -> void:
	# JSON numbers arrive as floats, so a value this large has already lost
	# precision by the time it is seen. Comparing it against the bounds would
	# be comparing something other than what was sent.
	assert_false(_built({"starting_price": 1.0e300}).is_valid())
	assert_false(_built({"bear_dividend": -1.0e300}).is_valid())


func test_a_negative_dividend_is_refused() -> void:
	assert_false(_built({"bull_dividend": -1}).is_valid())


func test_a_price_outside_the_range_is_refused() -> void:
	assert_false(_built({"starting_price": 0}).is_valid(), "zero")
	assert_false(_built({"starting_price": -50}).is_valid(), "negative")
	assert_false(
		_built({"starting_price": StalkSchema.MAX_PRICE + 1}).is_valid(),
		"above the split threshold",
	)
	assert_true(_built({"starting_price": StalkSchema.MAX_PRICE}).is_valid())


func test_a_fractional_number_is_refused() -> void:
	# All currency in this game is int. A price of 100.5 is not a price.
	assert_false(_built({"starting_price": 100.5}).is_valid())
	assert_true(_built({"starting_price": 100.0}).is_valid(), "100.0 is a whole number")


func test_true_is_not_a_number() -> void:
	# `true` converts to 1 in GDScript, so without the explicit bool check a
	# boolean would sail through as a dividend.
	assert_false(_built({"bull_dividend": true}).is_valid())


func test_a_range_with_its_bounds_the_wrong_way_round_is_refused() -> void:
	assert_false(_built({"bull_change": [20, 5]}).is_valid())


func test_a_negative_range_bound_is_refused() -> void:
	# Magnitudes are stored positive and applied in the mood's direction, so a
	# negative one would be a bear year that raised the price.
	assert_false(_built({"bear_change": [-5, 25]}).is_valid())


func test_a_range_of_the_wrong_shape_is_refused() -> void:
	assert_false(_built({"bull_change": [1, 2, 3]}).is_valid(), "three values")
	assert_false(_built({"bull_change": 15}).is_valid(), "not a list")
	assert_false(_built({"bull_change": ["a", "b"]}).is_valid(), "not numbers")


# -------------------------------------------------------------------- the counts

func test_more_events_than_allowed_are_refused() -> void:
	var events: Array = []
	for index: int in StalkSchema.MAX_EVENTS_PER_MOOD + 1:
		events.append({"mood": "bull", "text": "Event %d." % index, "price_change": 5})
	assert_false(_built({"events": events}).is_valid())


func test_the_allowed_number_of_events_is_accepted() -> void:
	var events: Array = []
	for index: int in StalkSchema.MAX_EVENTS_PER_MOOD:
		events.append({"mood": "bull", "text": "Event %d." % index, "price_change": 5})
	assert_true(_built({"events": events}).is_valid())


func test_an_event_that_does_nothing_is_refused() -> void:
	assert_false(_built({"events": [
		{"mood": "bull", "text": "Nothing happens.", "price_change": 0},
	]}).is_valid())


func test_an_event_with_no_mood_is_refused() -> void:
	assert_false(_built({"events": [
		{"text": "Something.", "price_change": 5},
	]}).is_valid())
	assert_false(_built({"events": [
		{"mood": "sideways", "text": "Something.", "price_change": 5},
	]}).is_valid())


func test_a_static_stalk_may_not_carry_events() -> void:
	assert_false(_built({
		"is_price_static": true,
		"events": [{"mood": "bull", "text": "Something.", "price_change": 5}],
	}).is_valid())


# ------------------------------------------------------------------ the whitelist

func test_a_field_the_game_does_not_know_is_refused() -> void:
	# A typo would otherwise become a silent default, which is the class of
	# content bug ContentLibrary was written to catch.
	var schema: StalkSchema = _built({"bull_dividends": 3})
	assert_false(schema.is_valid(), "a misspelled field should be named")
	assert_true(_errors_of(schema).contains("bull_dividends"))


func test_a_field_the_game_does_not_know_on_an_event_is_refused() -> void:
	assert_false(_built({"events": [
		{"mood": "bull", "text": "Something.", "price_change": 5, "script": "evil"},
	]}).is_valid())


func test_a_future_format_is_refused_with_a_reason() -> void:
	var schema: StalkSchema = _built({"format": 99})
	assert_false(schema.is_valid())
	assert_true(_errors_of(schema).contains("99"))


# ------------------------------------------------------------- the whole payload

func test_a_match_may_not_hold_more_stalks_than_the_cap() -> void:
	var wire: Array = []
	for index: int in StalkSchema.MAX_STALKS_PER_MATCH + 1:
		var schema: StalkSchema = StalkSchema.from_file_data(
			_good_file(), "stalk%d" % index
		)
		wire.append(StalkSchema.encode(schema.definition))

	var decoded: Dictionary = StateSync.decode_content(wire)
	assert_ne(String(decoded["error"]), "", "an oversized match should be refused")
	assert_null(decoded["library"])


func test_two_stalks_with_one_id_are_refused() -> void:
	var schema: StalkSchema = StalkSchema.from_file_data(_good_file(), "twice")
	var one: Dictionary = StalkSchema.encode(schema.definition)
	var decoded: Dictionary = StateSync.decode_content([one, one.duplicate()])
	assert_ne(String(decoded["error"]), "", "a duplicate id should be refused")


func test_an_empty_payload_is_refused() -> void:
	var decoded: Dictionary = StateSync.decode_content([])
	assert_ne(String(decoded["error"]), "")


func test_a_payload_entry_that_is_not_a_stalk_is_refused() -> void:
	assert_ne(String(StateSync.decode_content(["nonsense"]).error), "")
	assert_ne(String(StateSync.decode_content([42]).error), "")


func test_a_hostile_field_on_the_wire_is_refused_whole() -> void:
	# Nothing partial comes back: a library missing the stalk that failed
	# would be a board quietly short a column.
	var schema: StalkSchema = StalkSchema.from_file_data(_good_file(), "wire")
	var entry: Dictionary = StalkSchema.encode(schema.definition)
	entry["bull_dividend"] = 999999999
	var decoded: Dictionary = StateSync.decode_content([entry])
	assert_null(decoded["library"], "no partial library")
	assert_ne(String(decoded["error"]), "")


func test_the_reason_a_payload_was_refused_is_fit_to_show_a_player() -> void:
	# The refusal is put on screen, so a hostile id must not be able to use
	# the complaint about itself as a way in.
	var schema: StalkSchema = StalkSchema.from_file_data(_good_file(), "wire")
	var entry: Dictionary = StalkSchema.encode(schema.definition)
	entry["id"] = "bad\u0007id\nwith junk"
	var decoded: Dictionary = StateSync.decode_content([entry])
	var reason: String = String(decoded["error"])
	assert_ne(reason, "")
	assert_false(reason.contains("\n"), "a reason should stay one line: %s" % reason)
	assert_false(reason.contains("\u0007"), "control characters should not be echoed")


# -------------------------------------------------------------- the round trip

func test_a_custom_stalk_survives_the_wire_unchanged() -> void:
	var schema: StalkSchema = _built({
		"description": "A company.",
		"ticker": "EXH",
		"investors_are_anonymous": true,
		"events": [
			{"mood": "bull", "text": "Up it went.", "price_change": 10},
			{"mood": "bear", "text": "Down it went.", "price_change": -15},
		],
	})
	assert_true(schema.is_valid(), _errors_of(schema))

	var decoded: Dictionary = StateSync.decode_content(
		[StalkSchema.encode(schema.definition)]
	)
	assert_eq(String(decoded["error"]), "")

	var back: StalkDefinition = (decoded["library"] as ContentLibrary).stalks[0]
	assert_eq(back.id, schema.definition.id)
	assert_eq(back.display_name, "Example Holdings")
	assert_eq(back.description, "A company.")
	assert_eq(back.ticker, &"EXH")
	assert_true(back.investors_are_anonymous)
	assert_eq(back.bull_events.size(), 1)
	assert_eq(back.bear_events.size(), 1)
	assert_eq(back.bear_events[0].price_change, -15)


func test_an_event_keeps_its_id_across_the_wire() -> void:
	# The year result names its event by id and the receiver looks the flavour
	# text up by it. Re-deriving ids on the far side would break that quietly:
	# the news panel would simply show nothing.
	var shipped: ContentLibrary = ContentLibrary.load_from()
	var decoded: Dictionary = StateSync.decode_content(StateSync.encode_content(shipped))
	var library: ContentLibrary = decoded["library"]

	var original: SpecialEventDefinition = shipped.all_events()[0]
	var found: SpecialEventDefinition = library.event_by_id(original.id)
	assert_not_null(found, "event %s should be findable by its id" % original.id)
	assert_eq(found.flavour_text, original.flavour_text)


# ------------------------------------------------------------------- the folder

func _temp_dir() -> String:
	var path: String = "user://test_custom_stalks_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path)
	return path


func _write(dir_path: String, file_name: String, text: String) -> void:
	var file: FileAccess = FileAccess.open("%s/%s" % [dir_path, file_name], FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean_up(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(dir_path)


func test_a_folder_of_files_loads() -> void:
	var dir_path: String = _temp_dir()
	_write(dir_path, "alpha.json", JSON.stringify(_good_file()))
	var second: Dictionary = _good_file()
	second["name"] = "Beta Industries"
	_write(dir_path, "beta.json", JSON.stringify(second))

	var store: CustomStalkStore = CustomStalkStore.load_from(dir_path)
	assert_eq(store.problems, [] as Array[String])
	assert_eq(store.stalks.size(), 2)
	assert_eq(store.stalks[0].id, &"custom:alpha")
	_clean_up(dir_path)


func test_one_broken_file_does_not_stop_the_others() -> void:
	# Nine good files and a typo should give nine stalks and one message, not
	# an empty picker.
	var dir_path: String = _temp_dir()
	_write(dir_path, "good.json", JSON.stringify(_good_file()))
	_write(dir_path, "broken.json", "{ this is not json")

	var store: CustomStalkStore = CustomStalkStore.load_from(dir_path)
	assert_eq(store.stalks.size(), 1, "the good file should still load")
	assert_eq(store.problems.size(), 1)
	assert_true(store.problems[0].begins_with("broken.json"), store.problems[0])
	_clean_up(dir_path)


func test_a_file_that_is_not_an_object_is_reported() -> void:
	var dir_path: String = _temp_dir()
	_write(dir_path, "list.json", "[1, 2, 3]")
	var store: CustomStalkStore = CustomStalkStore.load_from(dir_path)
	assert_eq(store.stalks.size(), 0)
	assert_eq(store.problems.size(), 1)
	_clean_up(dir_path)


func test_an_oversized_file_is_refused_without_being_read() -> void:
	var dir_path: String = _temp_dir()
	var padded: Dictionary = _good_file()
	padded["description"] = "A".repeat(StalkSchema.MAX_FILE_BYTES + 16)
	_write(dir_path, "huge.json", JSON.stringify(padded))

	var store: CustomStalkStore = CustomStalkStore.load_from(dir_path)
	assert_eq(store.stalks.size(), 0)
	assert_eq(store.problems.size(), 1)
	assert_true(store.problems[0].contains("limit"), store.problems[0])
	_clean_up(dir_path)


func test_two_files_claiming_one_id_are_reported() -> void:
	var dir_path: String = _temp_dir()
	var first: Dictionary = _good_file()
	first["id"] = "shared"
	var second: Dictionary = _good_file()
	second["id"] = "shared"
	_write(dir_path, "one.json", JSON.stringify(first))
	_write(dir_path, "two.json", JSON.stringify(second))

	var store: CustomStalkStore = CustomStalkStore.load_from(dir_path)
	assert_eq(store.stalks.size(), 1, "only the first should load")
	assert_eq(store.problems.size(), 1)
	assert_true(store.problems[0].begins_with("two.json"), store.problems[0])
	_clean_up(dir_path)


func test_a_missing_folder_is_created_rather_than_reported() -> void:
	# A player who has never written a stalk is not an error condition.
	var dir_path: String = "user://test_custom_stalks_missing_%d" % Time.get_ticks_usec()
	var store: CustomStalkStore = CustomStalkStore.load_from(dir_path)
	assert_eq(store.problems, [] as Array[String])
	assert_true(store.is_empty())
	assert_true(DirAccess.dir_exists_absolute(dir_path), "the folder should be made")
	assert_true(
		FileAccess.file_exists("%s/%s" % [dir_path, CustomStalkStore.GUIDE_NAME]),
		"the guide should be written into it",
	)
	_clean_up(dir_path)


func test_the_guide_quotes_the_limits_rather_than_repeating_them() -> void:
	# A guide with its own copy of the numbers is a guide that goes stale.
	var text: String = CustomStalkStore.guide_text()
	assert_true(text.contains(str(StalkSchema.MAX_NAME_LENGTH)))
	assert_true(text.contains(str(StalkSchema.MAX_FILE_BYTES)))
	assert_false(text.contains("{name}"), "a placeholder was left unsubstituted")


# -------------------------------------------------------- content as match state

func test_a_match_is_the_stalks_that_were_chosen() -> void:
	var available: ContentLibrary = ContentLibrary.load_from()
	var wanted: Array[StringName] = [&"berry_bonds", &"pgenron", &"stryker"]
	var match_library: ContentLibrary = available.subset(wanted)

	assert_true(match_library.is_valid(), "\n".join(match_library.errors))
	assert_eq(match_library.stalks.size(), 3)
	assert_eq(match_library.build_stalk_states().size(), 3)
	# The event pool follows the content, so an unchosen stalk's events cannot
	# be drawn against a board it is not on.
	for event: SpecialEventDefinition in match_library.all_events():
		assert_true(event.target_stalk_id in wanted, "stray event %s" % event.id)


func test_choosing_a_stalk_that_is_not_installed_is_reported() -> void:
	var library: ContentLibrary = ContentLibrary.load_from().subset(
		[&"berry_bonds", &"custom:not_here"] as Array[StringName]
	)
	assert_false(library.is_valid())
	assert_true("\n".join(library.errors).contains("not_here"))


func test_a_match_may_not_exceed_the_cap() -> void:
	var defs: Array[StalkDefinition] = StalksFixture.build_stalks()
	for index: int in 3:
		var extra: StalkSchema = StalkSchema.from_file_data(_good_file(), "extra%d" % index)
		defs.append(extra.definition)

	var library: ContentLibrary = ContentLibrary.of(defs).subset([] as Array[StringName])
	assert_false(library.is_valid(), "13 stalks should not make a match")
	assert_true("\n".join(library.errors).contains(str(StalkSchema.MAX_STALKS_PER_MATCH)))


func test_the_cap_is_one_number() -> void:
	# The owner asked for the limit to be raisable by changing one number
	# rather than reworking a shape. This is that promise, asserted: the
	# picker, the wire and the match library all read the same constant.
	assert_eq(StalkSchema.MAX_STALKS_PER_MATCH, 10)

	var defs: Array[StalkDefinition] = []
	for index: int in StalkSchema.MAX_STALKS_PER_MATCH:
		defs.append(StalkSchema.from_file_data(_good_file(), "s%d" % index).definition)
	var library: ContentLibrary = ContentLibrary.of(defs).subset([] as Array[StringName])
	assert_true(library.is_valid(), "exactly the cap should be allowed")
