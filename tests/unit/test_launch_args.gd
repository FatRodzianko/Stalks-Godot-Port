extends GutTest
## The `--host` / `--join` development flags.
##
## Parsing is pure, so almost all of this needs no command line and no window.
## The two tests at the bottom drive `Main` with a parsed result, which is the
## part that could actually auto-host a shipped game if the debug gate were ever
## removed.


const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")


func _parsed(args: Array[String]) -> LaunchArgs:
	return LaunchArgs.parse(PackedStringArray(args))


# -------------------------------------------------------------------- defaults

func test_no_flags_means_the_menu() -> void:
	assert_eq(_parsed([] as Array[String]).mode, LaunchArgs.Mode.MENU)


func test_godots_own_arguments_are_ignored() -> void:
	# The command line carries Godot's arguments too, which are none of this
	# class's business. Anything unrecognised must pass straight through.
	var args: Array[String] = [
		"godot.exe", "--path", ".", "--headless", "-s", "res://addons/gut/gut_cmdln.gd",
	]
	assert_eq(_parsed(args).mode, LaunchArgs.Mode.MENU)


func test_the_default_port_matches_the_menus() -> void:
	# A flag-launched instance and a clicked one must meet on the same port, or
	# the flags are a trap.
	assert_eq(LaunchArgs.DEFAULT_PORT, DevOverlay.DEFAULT_PORT)


# ---------------------------------------------------------------------- hosting

func test_host_opens_a_lobby() -> void:
	assert_eq(_parsed(["--host"] as Array[String]).mode, LaunchArgs.Mode.HOST)


func test_a_host_is_named_host_by_default() -> void:
	# So two windows launched from one dialog are told apart at a glance.
	assert_eq(_parsed(["--host"] as Array[String]).resolved_name(), "Host")


func test_a_flag_launched_host_enables_loans() -> void:
	# Deliberately unlike GameSettings' own default: these flags exist to test
	# the game, and the loan panel is part of it.
	assert_true(_parsed(["--host"] as Array[String]).host_settings().loans_enabled)


func test_a_seed_can_be_fixed_to_reproduce_a_bug() -> void:
	var launch: LaunchArgs = _parsed(["--host", "--seed=4242"] as Array[String])
	assert_eq(launch.rng_seed, 4242)
	assert_eq(launch.host_settings().rng_seed, 4242)


func test_no_seed_means_choose_one() -> void:
	assert_eq(_parsed(["--host"] as Array[String]).host_settings().rng_seed, 0)


# ---------------------------------------------------------------------- joining

func test_join_defaults_to_this_machine() -> void:
	var launch: LaunchArgs = _parsed(["--join"] as Array[String])
	assert_eq(launch.mode, LaunchArgs.Mode.JOIN)
	assert_eq(launch.address, "127.0.0.1")


func test_join_takes_an_address() -> void:
	assert_eq(_parsed(["--join=10.0.0.5"] as Array[String]).address, "10.0.0.5")


func test_a_joiner_is_named_guest_by_default() -> void:
	assert_eq(_parsed(["--join"] as Array[String]).resolved_name(), "Guest")


# ----------------------------------------------------------------------- shared

func test_a_name_overrides_the_default() -> void:
	assert_eq(_parsed(["--host", "--name=Murph"] as Array[String]).resolved_name(), "Murph")


func test_a_port_can_be_given() -> void:
	assert_eq(_parsed(["--join", "--port=43210"] as Array[String]).port, 43210)


func test_a_nonsense_port_is_ignored_rather_than_breaking_the_launch() -> void:
	# `to_int()` would turn "banana" into 0 and bind to a random port, which is
	# a baffling way to fail.
	assert_eq(_parsed(["--host", "--port=banana"] as Array[String]).port, LaunchArgs.DEFAULT_PORT)


func test_a_nonsense_seed_is_ignored() -> void:
	assert_eq(_parsed(["--host", "--seed=soon"] as Array[String]).rng_seed, 0)


func test_the_last_mode_flag_wins() -> void:
	# Not a case worth agonising over, but it should be defined rather than
	# accidental.
	assert_eq(_parsed(["--host", "--join"] as Array[String]).mode, LaunchArgs.Mode.JOIN)
	assert_eq(_parsed(["--join", "--host"] as Array[String]).mode, LaunchArgs.Mode.HOST)


func test_an_empty_name_falls_back_to_the_default() -> void:
	assert_eq(_parsed(["--host", "--name="] as Array[String]).resolved_name(), "Host")


# ------------------------------------------------------------------- driving Main

func test_no_flags_leaves_main_on_the_menu() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.apply_launch_args(LaunchArgs.new())

	assert_true(main.current_screen() is MainMenu)
	assert_null(main.session(), "nothing should have been started")


func test_the_host_flag_puts_main_straight_into_a_lobby() -> void:
	var launch: LaunchArgs = _parsed(
		["--host", "--port=%d" % TestPorts.next(TestPorts.LAUNCH_BASE)] as Array[String]
	)
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.apply_launch_args(launch)
	await get_tree().process_frame

	assert_true(main.current_screen() is LobbyScreen, "no menu in the way")
	assert_true(main.session() is HostSession)
	assert_eq(main.session().state().player_by_id(&"p0").display_name, "Host")


func test_a_failed_auto_host_falls_back_to_the_menu_with_the_reason() -> void:
	# A blank screen would be a miserable way to discover the port is busy.
	var port: int = TestPorts.next(TestPorts.LAUNCH_BASE)
	var squatter: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(squatter.create_server(port, 1), OK, "the test needs the port held")

	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.apply_launch_args(_parsed(["--host", "--port=%d" % port] as Array[String]))
	squatter.close()

	var menu: MainMenu = main.current_screen() as MainMenu
	assert_not_null(menu, "it should fall back to the menu")
	if menu == null:
		return
	assert_true(menu.get_node("%ContentWarning").visible, "with the reason on it")
	assert_engine_error("host", "ENet should report the failed bind")
