extends GutTest
## Preferences kept between runs.
##
## Only things a player sets once and expects to stay set live here. An
## earlier version also remembered the Create Game fields; that was removed,
## and `test_the_title_screen_remembers_nothing` is what stops it coming back
## by accident. See docs/decisions.md D71.


## A real file, in a real writable directory, under a name no shipped build
## uses. Reading and writing is the whole subject, so a stub would test
## nothing.
const TEST_PATH: String = "user://test_settings.cfg"


func after_each() -> void:
	# Only if it is there: several tests never create one.
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_nothing_saved_yet_means_full_volume() -> void:
	# The first run. Not a failure, and not logged as one.
	var fresh: UserSettings = UserSettings.load_from("user://no_such_file.cfg")
	assert_eq(fresh.volume_percent, 100)


func test_a_volume_survives_a_round_trip() -> void:
	var settings: UserSettings = UserSettings.new()
	settings.volume_percent = 40
	settings.save_to(TEST_PATH)

	assert_eq(UserSettings.load_from(TEST_PATH).volume_percent, 40)


func test_silence_is_remembered_as_silence() -> void:
	# Zero is the value a default-shaped store gets wrong: read back as the
	# default 100, so muting never sticks.
	var settings: UserSettings = UserSettings.new()
	settings.volume_percent = 0
	settings.save_to(TEST_PATH)

	assert_eq(UserSettings.load_from(TEST_PATH).volume_percent, 0)


func test_a_nonsense_volume_is_clamped_rather_than_obeyed() -> void:
	# A hand-edited file should not be able to make the game deafening.
	var file: ConfigFile = ConfigFile.new()
	file.set_value(UserSettings.SECTION_AUDIO, "volume_percent", 9000)
	file.save(TEST_PATH)

	assert_eq(UserSettings.load_from(TEST_PATH).volume_percent, 100)


func test_a_corrupt_file_reads_as_a_first_run() -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("this is not a config file {{{")
	file.close()

	assert_eq(
		UserSettings.load_from(TEST_PATH).volume_percent, 100, "defaults, not a crash"
	)


func test_saving_twice_replaces_rather_than_accumulates() -> void:
	var first: UserSettings = UserSettings.new()
	first.volume_percent = 10
	first.save_to(TEST_PATH)

	var second: UserSettings = UserSettings.new()
	second.volume_percent = 90
	second.save_to(TEST_PATH)

	assert_eq(UserSettings.load_from(TEST_PATH).volume_percent, 90)


## The title screen does not read or write this file, and should not start.
##
## Match settings are chosen fresh each time from documented defaults. A
## remembered year limit would mean the controls stopped showing what the
## game's defaults actually are, with nothing on screen to say so — which is
## why the seed was excluded even when the rest were being kept, and then why
## the rest went too.
func test_the_title_screen_remembers_nothing() -> void:
	var menu: MainMenu = preload(
		"res://src/ui/screens/main_menu/main_menu.tscn"
	).instantiate()
	add_child_autofree(menu)

	(menu.get_node("%YearsSpin") as SpinBox).value = 33
	(menu.get_node("%SeedField") as LineEdit).text = "4242"
	(menu.get_node("%SinglePlayerButton") as Button).pressed.emit()

	var next_time: MainMenu = preload(
		"res://src/ui/screens/main_menu/main_menu.tscn"
	).instantiate()
	add_child_autofree(next_time)

	assert_eq(next_time.chosen_settings().max_years, 10, "the documented default")
	assert_eq((next_time.get_node("%SeedField") as LineEdit).text, "")
