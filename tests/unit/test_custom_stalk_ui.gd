extends GutTest
## The Custom Stalks picker, and a board holding more stalks than fit.
##
## Scene-tree tests driving the real scenes, for the same reason
## `test_gameplay_screen.gd` gives: these prove the wiring, which no amount of
## testing the data layer can. `test_custom_stalks.gd` is the companion, and
## holds the loader and the validation.


const PickerScene: PackedScene = preload("res://src/ui/widgets/stalk_picker.tscn")
const GameplayScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")


var _picker: StalkPicker


func before_each() -> void:
	_picker = PickerScene.instantiate()
	add_child_autofree(_picker)


func _a_custom_stalk(suffix: String) -> StalkDefinition:
	var schema: StalkSchema = StalkSchema.from_file_data({
		"name": "Custom %s" % suffix,
		"bull_change": [0, 10],
		"bear_change": [0, 10],
		"bull_dividend": 2,
		"bear_dividend": 1,
	}, "custom_%s" % suffix)
	return schema.definition


func _shipped() -> Array[StalkDefinition]:
	return ContentLibrary.load_from().stalks


func _shipped_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for stalk: StalkDefinition in _shipped():
		out.append(stalk.id)
	return out


func _open(
	available: Array[StalkDefinition],
	chosen: Array[StringName] = [],
	problems: Array[String] = [],
) -> void:
	_picker.show_stalks(available, chosen, problems)
	await wait_process_frames(1)


# ------------------------------------------------------------------- the list

func test_the_picker_lists_shipped_and_custom_together() -> void:
	var available: Array[StalkDefinition] = _shipped()
	available.append(_a_custom_stalk("one"))
	await _open(available)

	assert_eq(_picker.row_count(), 11)
	assert_not_null(_picker.row_for(&"berry_bonds"), "a shipped stalk should be listed")
	assert_not_null(_picker.row_for(&"custom:custom_one"), "a custom one should be too")


func test_an_unconfigured_picker_opens_on_the_shipped_set() -> void:
	# Empty means "the game as it ships" everywhere else, and it has to mean
	# that here too or opening the screen would silently deselect everything.
	var available: Array[StalkDefinition] = _shipped()
	available.append(_a_custom_stalk("one"))
	await _open(available)

	assert_eq(_picker.chosen_ids().size(), _shipped().size())
	assert_false(
		&"custom:custom_one" in _picker.chosen_ids(),
		"a custom stalk should not be in a match nobody chose it for",
	)


func test_a_remembered_choice_comes_back_ticked() -> void:
	var available: Array[StalkDefinition] = _shipped()
	available.append(_a_custom_stalk("one"))
	await _open(available, [&"berry_bonds", &"custom:custom_one"] as Array[StringName])

	assert_eq(_picker.chosen_ids().size(), 2)
	assert_true(_picker.row_for(&"custom:custom_one").is_chosen())
	assert_false(_picker.row_for(&"pgenron").is_chosen())


func test_a_custom_stalk_is_marked_as_one() -> void:
	# The id says `custom:` but a player never typed that and never sees it.
	await _open([_a_custom_stalk("one")] as Array[StalkDefinition])
	var row: StalkPickRow = _picker.row_for(&"custom:custom_one")
	var origin: Label = row.get_node("%Origin")
	assert_eq(origin.text, StalkPickRow.CUSTOM_TAG)


# -------------------------------------------------------------------- the cap

func test_the_cap_greys_out_everything_not_already_chosen() -> void:
	var available: Array[StalkDefinition] = _shipped()
	available.append(_a_custom_stalk("one"))
	available.append(_a_custom_stalk("two"))
	# The shipped ten is exactly the cap, so the match is full on opening.
	await _open(available, _shipped_ids())

	assert_eq(_picker.chosen_ids().size(), StalkSchema.MAX_STALKS_PER_MATCH)
	var spare: StalkPickRow = _picker.row_for(&"custom:custom_one")
	var check: CheckBox = spare.get_node("%Check")
	assert_true(check.disabled, "an eleventh should not be tickable")

	var chosen_row: StalkPickRow = _picker.row_for(&"berry_bonds")
	var chosen_check: CheckBox = chosen_row.get_node("%Check")
	assert_false(chosen_check.disabled, "an already-chosen row stays tickable, to untick")


func test_unticking_one_lets_another_in() -> void:
	var available: Array[StalkDefinition] = _shipped()
	available.append(_a_custom_stalk("one"))
	await _open(available, _shipped_ids())

	var shipped_check: CheckBox = _picker.row_for(&"berry_bonds").get_node("%Check")
	shipped_check.button_pressed = false
	await wait_process_frames(1)

	var spare_check: CheckBox = _picker.row_for(&"custom:custom_one").get_node("%Check")
	assert_false(spare_check.disabled, "room should have been made")

	spare_check.button_pressed = true
	await wait_process_frames(1)
	assert_eq(_picker.chosen_ids().size(), StalkSchema.MAX_STALKS_PER_MATCH)
	assert_true(&"custom:custom_one" in _picker.chosen_ids())


func test_the_count_says_how_full_the_match_is() -> void:
	await _open(_shipped(), [&"berry_bonds", &"pgenron"] as Array[StringName])
	var count: Label = _picker.get_node("%CountLabel")
	assert_eq(count.text, "2 of %d chosen" % StalkSchema.MAX_STALKS_PER_MATCH)


func test_a_match_with_nothing_in_it_is_called_out() -> void:
	await _open(_shipped(), [&"berry_bonds"] as Array[StringName])
	var check: CheckBox = _picker.row_for(&"berry_bonds").get_node("%Check")
	check.button_pressed = false
	await wait_process_frames(1)

	var count: Label = _picker.get_node("%CountLabel")
	assert_eq(count.text, "0 of %d chosen" % StalkSchema.MAX_STALKS_PER_MATCH)
	assert_eq(count.theme_type_variation, &"Danger")


# ------------------------------------------------------------------- the reset

func test_reset_puts_the_shipped_set_back() -> void:
	# This button is the whole reason remembering the choice is allowed at all
	# (D71, amended by D123). If it stops working, the reason goes with it.
	var available: Array[StalkDefinition] = _shipped()
	available.append(_a_custom_stalk("one"))
	await _open(available, [&"custom:custom_one"] as Array[StringName])
	assert_eq(_picker.chosen_ids(), [&"custom:custom_one"] as Array[StringName])

	_picker.reset_to_shipped()
	await wait_process_frames(1)

	assert_eq(_picker.chosen_ids().size(), _shipped().size())
	assert_false(&"custom:custom_one" in _picker.chosen_ids())
	for id: StringName in _shipped_ids():
		assert_true(id in _picker.chosen_ids(), "%s should be back" % id)


# ----------------------------------------------------------------- the problems

func test_an_unreadable_file_is_named_on_the_screen() -> void:
	await _open(
		_shipped(), [], ["broken.json: line 1: Expected key"] as Array[String]
	)
	var problems: Label = _picker.get_node("%ProblemLabel")
	assert_true(problems.visible)
	assert_true(problems.text.contains("broken.json"), problems.text)


func test_nothing_is_said_about_problems_when_there_are_none() -> void:
	await _open(_shipped())
	var problems: Label = _picker.get_node("%ProblemLabel")
	assert_false(problems.visible)


func test_the_folder_is_named_to_somebody_with_no_custom_stalks() -> void:
	await _open(_shipped())
	var hint: Label = _picker.get_node("%HintLabel")
	assert_true(hint.visible, "somebody with none needs to know where they go")
	assert_true(hint.text.contains("custom_stalks"), hint.text)


func test_the_folder_is_not_laboured_to_somebody_who_found_it() -> void:
	await _open([_a_custom_stalk("one")] as Array[StalkDefinition])
	var hint: Label = _picker.get_node("%HintLabel")
	assert_false(hint.visible)


# --------------------------------------------------------------- the board

## A match library of `count` stalks, so the board can be given more than it
## has room for.
func _library_of(count: int) -> ContentLibrary:
	var defs: Array[StalkDefinition] = []
	var shipped: Array[StalkDefinition] = _shipped()
	for index: int in count:
		if index < shipped.size():
			defs.append(shipped[index])
			continue
		defs.append(_a_custom_stalk("extra%d" % index))
	return ContentLibrary.of(defs)


func test_the_board_draws_a_row_for_every_stalk_in_the_match() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.rng_seed = 1
	var session: LocalSession = LocalSession.create(settings, _library_of(10))

	var screen: Control = GameplayScene.instantiate()
	screen.setup(session)
	add_child_autofree(screen)
	add_child_autofree(session)
	await wait_process_frames(2)

	var list: VBoxContainer = screen.get_node("%StalkList")
	assert_eq(list.get_child_count(), 10, "one row per stalk")


func test_a_board_taller_than_its_panel_scrolls() -> void:
	# The owner asked for a scroll so a larger board can be read. The
	# container was already there; this is what says it still is, and that it
	# actually has somewhere to scroll to once the rows outgrow the panel.
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.rng_seed = 1
	var session: LocalSession = LocalSession.create(settings, _library_of(10))

	var screen: Control = GameplayScene.instantiate()
	screen.setup(session)
	add_child_autofree(screen)
	add_child_autofree(session)
	# Deliberately short: ten rows of board cannot be shown at once in this
	# much height, which is the only condition under which a scroll means
	# anything. The assertion below fails loudly if that stops being true.
	screen.size = Vector2(900, 200)
	await wait_process_frames(3)

	var scroll: ScrollContainer = screen.get_node("%StalkScroll")
	var list: VBoxContainer = screen.get_node("%StalkList")

	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"the board must never scroll sideways: the columns are the layout")
	assert_gt(list.size.y, scroll.size.y,
		"the rows should not fit, or this test is not testing anything")

	var bar: VScrollBar = scroll.get_v_scroll_bar()
	assert_gt(bar.max_value, bar.page, "there should be somewhere to scroll to")

	scroll.scroll_vertical = 10000
	await wait_process_frames(1)
	assert_gt(scroll.scroll_vertical, 0, "the board should actually move")
