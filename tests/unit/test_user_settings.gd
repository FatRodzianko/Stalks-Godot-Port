extends GutTest
## What the game remembers between runs.
##
## Nothing here changes how a match plays: it fills in the controls a player
## can then change. That is why a wrong value is a nuisance rather than a bug,
## and why the seed is deliberately **not** among them.


## A real file, in a real writable directory, under a name no shipped build
## uses. Reading and writing is the whole subject, so a stub would test
## nothing.
const TEST_PATH: String = "user://test_settings.cfg"


func after_each() -> void:
	# Only if it is there: several tests never create one, and asking Godot to
	# remove a file that does not exist logs an error, which GUT counts as a
	# failure of whichever test happened to run last.
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## A menu that has not been told where its settings live, so it neither reads
## nor writes anything until a test says so.
func _menu() -> MainMenu:
	var menu: MainMenu = preload(
		"res://src/ui/screens/main_menu/main_menu.tscn"
	).instantiate()
	add_child_autofree(menu)
	return menu


func _saved(changes: Callable) -> UserSettings:
	var settings: UserSettings = UserSettings.new()
	changes.call(settings)
	settings.save_to(TEST_PATH)
	return UserSettings.load_from(TEST_PATH)


func test_nothing_saved_yet_gives_the_defaults() -> void:
	# The first run. Not a failure, and not logged as one.
	var fresh: UserSettings = UserSettings.load_from("user://no_such_file.cfg")
	assert_eq(fresh.player_name, "")
	assert_eq(fresh.years, 10)
	assert_eq(fresh.starting_cash, 10000)
	assert_true(fresh.loans_enabled)
	assert_false(fresh.invite_only)


func test_a_name_comes_back() -> void:
	var back: UserSettings = _saved(
		func(s: UserSettings) -> void: s.player_name = "Murph"
	)
	assert_eq(back.player_name, "Murph")


func test_every_create_game_field_comes_back() -> void:
	var back: UserSettings = _saved(func(s: UserSettings) -> void:
		s.player_name = "Murph"
		s.game_name = "Friday night"
		s.years = 25
		s.starting_cash = 5000
		s.loans_enabled = false
		s.invite_only = true
	)
	assert_eq(back.player_name, "Murph")
	assert_eq(back.game_name, "Friday night")
	assert_eq(back.years, 25)
	assert_eq(back.starting_cash, 5000)
	assert_false(back.loans_enabled)
	assert_true(back.invite_only)


func test_switching_a_flag_off_is_remembered_as_off() -> void:
	# The failure mode a default-shaped store has: `false` read back as the
	# default `true`, so unticking never sticks.
	var back: UserSettings = _saved(
		func(s: UserSettings) -> void: s.loans_enabled = false
	)
	assert_false(back.loans_enabled)


func test_a_corrupt_file_reads_as_a_first_run() -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("this is not a config file {{{")
	file.close()

	var back: UserSettings = UserSettings.load_from(TEST_PATH)
	assert_eq(back.years, 10, "defaults, not a crash")


func test_saving_twice_replaces_rather_than_accumulates() -> void:
	var first: UserSettings = UserSettings.new()
	first.player_name = "First"
	first.save_to(TEST_PATH)

	var second: UserSettings = UserSettings.new()
	second.player_name = "Second"
	second.save_to(TEST_PATH)

	assert_eq(UserSettings.load_from(TEST_PATH).player_name, "Second")


# ------------------------------------------------------------- the menu's end

func test_the_menu_fills_itself_in_from_what_was_saved() -> void:
	var remembered: UserSettings = UserSettings.new()
	remembered.player_name = "Murph"
	remembered.years = 25
	remembered.loans_enabled = false
	remembered.save_to(TEST_PATH)

	var menu: MainMenu = _menu()
	menu.recall_settings(TEST_PATH)

	assert_eq((menu.get_node("%NameField") as LineEdit).text, "Murph")
	assert_eq(menu.chosen_settings().max_years, 25)
	assert_false(menu.chosen_settings().loans_enabled)


func test_the_seed_is_never_remembered() -> void:
	# A remembered seed would make every match identical, and a player would
	# have no reason to suspect why. It is the one field left out on purpose.
	var menu: MainMenu = _menu()
	menu.recall_settings(TEST_PATH)
	(menu.get_node("%SeedField") as LineEdit).text = "4242"
	(menu.get_node("%SinglePlayerButton") as Button).pressed.emit()

	var next_time: MainMenu = _menu()
	next_time.recall_settings(TEST_PATH)
	assert_eq((next_time.get_node("%SeedField") as LineEdit).text, "")
	assert_eq(next_time.chosen_settings().rng_seed, 0)


func test_a_menu_that_was_never_told_where_to_save_saves_nothing() -> void:
	# What keeps every other menu test deterministic: pressing buttons in a
	# test must not write the developer's real settings file.
	var menu: MainMenu = _menu()
	(menu.get_node("%YearsSpin") as SpinBox).value = 33
	(menu.get_node("%SinglePlayerButton") as Button).pressed.emit()

	var elsewhere: MainMenu = _menu()
	elsewhere.recall_settings(TEST_PATH)
	assert_eq(elsewhere.chosen_settings().max_years, 10, "defaults, not 33")
