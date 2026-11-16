extends GutTest
## Scene tests for the lobby and the menu's three paths.
##
## The lobby ones use a real `HostSession` from the networked harness rather than
## a stub: the screen's whole job is to reflect a live session, and a stub would
## only prove it reflects a stub. The menu ones need no session at all.


const LobbyScene: PackedScene = preload("res://src/ui/screens/lobby/lobby_screen.tscn")
const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")

var _library: ContentLibrary
var _harness: NetHarness


func before_all() -> void:
	_library = ContentLibrary.load_from()


func after_each() -> void:
	if _harness != null and is_instance_valid(_harness):
		_harness.queue_free()
	_harness = null


# ------------------------------------------------------------------------- menu

func _menu() -> MainMenu:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	return menu


func test_the_menu_opens_on_single_player() -> void:
	var menu: MainMenu = _menu()
	assert_eq(menu.current_mode(), MainMenu.Mode.SINGLE)


## The fault this screen was rebuilt for.
##
## Steam is how the game is played; the settings used to sit on the solo and
## local-host tabs only, so the configuration lived on the development path
## and the real one had none - a Steam match was hosted with defaults, loans
## off, whatever the player had chosen. See decisions.md D65.
func test_both_ways_of_making_a_game_are_offered_the_same_settings() -> void:
	var menu: MainMenu = _menu()
	for mode: int in [MainMenu.Mode.SINGLE, MainMenu.Mode.HOST]:
		menu.show_mode(mode)
		for field: String in ["%YearsSpin", "%CashSpin", "%LoansCheck", "%SeedField"]:
			assert_true((menu.get_node(field) as Control).is_visible_in_tree(),
				"%s belongs to the match, not to one kind of game" % field)


## A single-player game has no second player, so a limit and a privacy setting
## would be decoration, and the player names themselves.
func test_a_single_player_game_is_not_asked_about_other_players() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.SINGLE)

	assert_true(menu.get_node("%NameField").is_visible_in_tree(), "names themselves")
	assert_false(menu.get_node("%PlayersSpin").is_visible_in_tree())
	assert_false(menu.get_node("%InviteOnlyCheck").is_visible_in_tree())
	assert_false(menu.get_node("%GameNameField").is_visible_in_tree())


## An online game is named from the Steam account, so a name field there would
## be a control that silently does nothing (D66).
func test_hosting_online_asks_about_players_and_not_about_your_name() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)

	assert_false(menu.get_node("%NameField").is_visible_in_tree(), "Steam says who you are")
	assert_true(menu.get_node("%PlayersSpin").is_visible_in_tree())
	assert_true(menu.get_node("%InviteOnlyCheck").is_visible_in_tree())
	assert_true(menu.get_node("%GameNameField").is_visible_in_tree())


func test_a_joiner_is_not_offered_the_match_settings() -> void:
	# The host owns them, and a joiner is told the year limit and seed by the
	# host. Offering the controls here would be a lie.
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.JOIN)

	assert_false(menu.get_node("%YearsSpin").is_visible_in_tree())
	assert_true(menu.lobby_browser().is_visible_in_tree(), "the list, instead")


func test_a_single_player_game_carries_the_settings() -> void:
	var menu: MainMenu = _menu()
	menu.get_node("%YearsSpin").value = 12
	menu.get_node("%LoansCheck").button_pressed = true

	var seen: Array = []
	menu.start_requested.connect(
		func(settings: GameSettings) -> void:
			seen.append([settings.max_years, settings.loans_enabled])
	)
	menu.get_node("%StartButton").pressed.emit()

	assert_eq(seen, [[12, true]])


func test_hosting_online_carries_the_same_settings() -> void:
	# The one that was broken in play: loans ticked here, loans off in the game.
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)
	menu.get_node("%YearsSpin").value = 25
	menu.get_node("%LoansCheck").button_pressed = true

	var seen: Array = []
	menu.host_online_requested.connect(
		func(settings: GameSettings) -> void:
			seen.append([settings.max_years, settings.loans_enabled])
	)
	menu.get_node("%StartButton").pressed.emit()

	assert_eq(seen, [[25, true]])


## One button, two meanings, decided by the tab. If this ever stops switching,
## Host Online silently starts a solo game instead.
func test_the_start_button_follows_the_tab() -> void:
	var menu: MainMenu = _menu()
	var solo: Array = []
	var online: Array = []
	menu.start_requested.connect(func(_s: GameSettings) -> void: solo.append(true))
	menu.host_online_requested.connect(func(_s: GameSettings) -> void: online.append(true))

	menu.show_mode(MainMenu.Mode.SINGLE)
	menu.get_node("%StartButton").pressed.emit()
	menu.show_mode(MainMenu.Mode.HOST)
	menu.get_node("%StartButton").pressed.emit()

	assert_eq(solo.size(), 1)
	assert_eq(online.size(), 1)


## Restores the original's Max. Number of Players field, 1 to 10, default 4
## (audit 17.4). The port used to create every lobby with ten slots.
func test_hosting_online_carries_the_player_limit() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)
	menu.get_node("%PlayersSpin").value = 3

	assert_eq(menu.chosen_settings().player_count, 3)


func test_a_single_player_game_is_one_player_and_never_private() -> void:
	# The controls are hidden rather than reset, so whatever they hold must not
	# reach the settings.
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)
	menu.get_node("%PlayersSpin").value = 8
	menu.get_node("%InviteOnlyCheck").button_pressed = true
	menu.show_mode(MainMenu.Mode.SINGLE)

	var settings: GameSettings = menu.chosen_settings()
	assert_eq(settings.player_count, 1)
	assert_false(settings.invite_only)


## Found in play: every player in a Steam game showed as "Player", and typing
## a name for an earlier local game made everyone show as that instead.
##
## An online game names you from your Steam account, so the title screen's
## name field has no say in it - and therefore nothing to send. See
## decisions.md D66.
func test_hosting_online_sends_no_player_name_at_all() -> void:
	var menu: MainMenu = _menu()

	for entry: Dictionary in menu.get_signal_list():
		if entry["name"] != "host_online_requested":
			continue
		var args: Array = entry["args"]
		assert_eq(args.size(), 1, "settings only; Steam supplies the name")
		if args.size() == 1:
			assert_eq(String(args[0]["name"]), "settings")


func test_the_host_can_name_the_game() -> void:
	# There was no way to: a lobby was always the persona's game, and the
	# player could name themselves but not the thing they were making.
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)
	menu.get_node("%GameNameField").text = "  Friday night  "

	assert_eq(menu.chosen_settings().game_name, "Friday night",
		"trimmed, because a leading space in a heading looks like a fault")


func test_a_blank_game_name_is_left_for_the_host_to_be_named_after() -> void:
	# Blank is not a failure: `Main` fills it in once it knows who is hosting,
	# which for an online game means once Steam has been asked.
	assert_eq(_menu().chosen_settings().game_name, "")


## The lobby list loads because you opened Join Game, not because you then
## pressed a button asking for the thing you had just asked for. The separate
## BROWSE ONLINE GAMES button is gone.
func test_opening_join_game_asks_for_the_lobby_list() -> void:
	var menu: MainMenu = _menu()

	# An Array, not an int: GDScript lambdas capture by value, so incrementing
	# a captured integer changes the copy and the test watches nothing.
	var seen: Array = []
	menu.browse_online_requested.connect(func() -> void: seen.append(true))
	menu.show_mode(MainMenu.Mode.JOIN)

	assert_eq(seen.size(), 1)


func test_going_back_to_join_game_does_not_ask_twice() -> void:
	# Asking again would start Steam again. REFRESH is how a player asks for a
	# fresh list.
	var menu: MainMenu = _menu()
	var seen: Array = []
	menu.browse_online_requested.connect(func() -> void: seen.append(true))

	menu.show_mode(MainMenu.Mode.JOIN)
	menu.show_mode(MainMenu.Mode.SINGLE)
	menu.show_mode(MainMenu.Mode.JOIN)

	assert_eq(seen.size(), 1)


func test_a_blank_name_gets_a_stand_in() -> void:
	assert_eq(_menu().chosen_name(), "Player")


func test_a_failure_is_reported_on_the_menu() -> void:
	var menu: MainMenu = _menu()
	menu.show_problem("Could not listen on port 42420.")
	var warning: Label = menu.get_node("%ContentWarning")
	assert_true(warning.visible)
	assert_string_contains(warning.text, "42420")


# ------------------------------------------------------------------------ lobby

## A connected host and client, plus a lobby screen watching the host.
func _lobby_on_host() -> LobbyScreen:
	_harness = NetHarness.new()
	add_child(_harness)
	var error: String = _harness.start(
		StalksFixture.make_settings(), _library, "Murph", "Guest"
	)
	if not error.is_empty():
		fail_test("harness did not start: %s" % error)
		return null
	if not await _harness.await_join(self):
		fail_test("the client did not connect")
		return null

	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(lobby)
	lobby.setup(_harness.host, _harness.port())
	return lobby


## The heading used to read "LOBBY" for the host and "JOINED" for everyone
## else — a word telling you which end of the connection you were on, which
## you already knew, where the name of the thing you are in should be. D66.
func test_the_lobby_is_headed_with_the_name_of_the_game() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	_harness.host.state().settings.game_name = "Friday night"
	lobby.refresh()

	assert_string_contains(
		(lobby.get_node("%Title") as Label).text.to_lower(), "friday night"
	)


func test_a_guest_sees_the_same_heading_as_the_host() -> void:
	# The name travels with the settings in the opening snapshot, so both ends
	# have it without anything being sent for the heading's sake.
	_harness = NetHarness.new()
	add_child(_harness)
	var settings: GameSettings = StalksFixture.make_settings()
	settings.game_name = "Friday night"
	if not _harness.start(settings, _library, "Murph", "Guest").is_empty():
		fail_test("harness did not start")
		return
	if not await _harness.await_join(self):
		fail_test("the client did not connect")
		return

	var guest: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(guest)
	guest.setup(_harness.client)

	assert_string_contains(
		(guest.get_node("%Title") as Label).text.to_lower(), "friday night"
	)


func test_an_unnamed_match_still_has_a_heading() -> void:
	# `Main` names every match it creates, so this should be unreachable in
	# play. It is here because a blank heading is the worst outcome and the
	# cheapest to rule out.
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	_harness.host.state().settings.game_name = "   "
	lobby.refresh()

	assert_false((lobby.get_node("%Title") as Label).text.strip_edges().is_empty())


func test_the_lobby_lists_every_player() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	assert_eq(lobby.player_rows().size(), 2, "the host and the joiner")


func test_the_lobby_marks_who_you_are_and_who_is_hosting() -> void:
	# The first thing anybody looks for in a lobby.
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	var first: LobbyRow = lobby.player_rows()[0]
	assert_eq(first.get_node("%Name").text, "Murph")
	assert_string_contains(first.get_node("%Tag").text, "HOST")
	assert_string_contains(first.get_node("%Tag").text, "YOU")

	var second: LobbyRow = lobby.player_rows()[1]
	assert_eq(second.get_node("%Name").text, "Guest")
	assert_eq(second.get_node("%Tag").text, "", "the guest is neither, on this screen")


func test_a_new_arrival_appears_in_the_list() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	assert_eq(lobby.player_rows().size(), 2)

	var extra: Dictionary = ClientSession.join(
		EnetTransport.new(_harness.port()), _library, "Third"
	)
	_harness.attach_extra_client(extra["session"], extra["peer"])
	await _harness.settle(self, 30)

	assert_eq(lobby.player_rows().size(), 3, "the list should grow")
	assert_eq(lobby.player_rows()[2].get_node("%Name").text, "Third")


func test_leaving_the_lobby_removes_the_row() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	if not await _harness.drop_client(self):
		fail_test("the client did not drop")
		return
	await _harness.settle(self)

	assert_eq(lobby.player_rows().size(), 1, "only the host should be left")


## A guest's own lobby screen, which is the side that has a ready button.
func _guest_lobby() -> LobbyScreen:
	var guest: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(guest)
	guest.setup(_harness.client)
	return guest


func test_a_guest_pressing_ready_readies_them_on_the_host() -> void:
	if await _lobby_on_host() == null:
		return
	var guest: LobbyScreen = _guest_lobby()

	guest.get_node("%ReadyButton").pressed.emit()
	await _harness.settle(self)

	assert_true(
		_harness.host.state().player_by_id(&"p1").is_ready,
		"the host holds the authoritative flag",
	)
	assert_eq(
		guest.get_node("%ReadyButton").text, "NOT READY",
		"the button should offer the way back",
	)


func test_a_guest_pressing_ready_twice_un_readies_them() -> void:
	if await _lobby_on_host() == null:
		return
	var guest: LobbyScreen = _guest_lobby()

	guest.get_node("%ReadyButton").pressed.emit()
	await _harness.settle(self)
	guest.get_node("%ReadyButton").pressed.emit()
	await _harness.settle(self)

	assert_false(_harness.host.state().player_by_id(&"p1").is_ready)


func test_a_players_readiness_shows_in_their_row() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	assert_eq(lobby.player_rows()[1].get_node("%Ready").text, "WAITING")

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)

	assert_eq(lobby.player_rows()[1].get_node("%Ready").text, "READY")


func test_only_the_host_gets_a_start_button() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	assert_true(lobby.is_hosting())
	assert_true(lobby.get_node("%StartButton").visible)

	var client_lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(client_lobby)
	client_lobby.setup(_harness.client)

	assert_false(client_lobby.is_hosting())
	assert_false(
		client_lobby.get_node("%StartButton").visible,
		"a client cannot start the match",
	)


func test_the_host_pressing_start_asks_to_play() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	var asked: Array = []
	lobby.play_requested.connect(func() -> void: asked.append(true))

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	lobby.get_node("%StartButton").pressed.emit()
	await _harness.settle(self)

	assert_eq(asked.size(), 1, "the screen host should be told to show the board")
	assert_false(_harness.host.lobby_is_open())


func test_a_client_is_asked_to_play_when_the_host_starts() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	var client_lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(client_lobby)
	client_lobby.setup(_harness.client)
	var asked: Array = []
	client_lobby.play_requested.connect(func() -> void: asked.append(true))

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	_harness.host.start_match()
	await _harness.settle(self)

	assert_eq(asked.size(), 1, "the client should follow the host into the match")


func test_the_host_is_told_which_port_to_share() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	assert_string_contains(
		lobby.get_node("%Subtitle").text, str(_harness.port())
	)


func test_leave_is_offered_on_both_sides() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	var asked: Array = []
	lobby.leave_requested.connect(func() -> void: asked.append(true))
	lobby.get_node("%LeaveButton").pressed.emit()

	assert_eq(asked.size(), 1)


# ------------------------------------------------------------- the screen host
#
# Main opening a lobby, reporting a failure, and carrying on into the match.
#
# **Only one Main can hold a peer in a single process.** `Main` uses the tree's
# default `MultiplayerAPI`, as a shipped game should, and a tree has exactly one
# of those — so a second Main calling `host_match` or `join_match` overwrites the
# first one's peer and both break. Two *sessions* in one process is what
# `NetHarness` is for, and it works only because it gives each side its own
# subtree and its own API (see architecture.md §5.2). The host-and-client
# handshake is therefore tested in `test_networked_session.gd`, and what is
# tested here is Main's own behaviour with one session at a time.

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")


func _free_port() -> int:
	return TestPorts.next(TestPorts.LOBBY_BASE)


func test_hosting_through_main_opens_a_lobby() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	assert_eq(main.host_match(StalksFixture.make_settings(), "Murph", _free_port()), "")
	await get_tree().process_frame

	assert_true(main.current_screen() is LobbyScreen, "the lobby should be showing")
	assert_true(main.session() is HostSession)
	assert_eq(main.session().state().players.size(), 1, "just the host so far")


func test_hosting_on_a_taken_port_reports_rather_than_crashing() -> void:
	# The port is held by a bare peer rather than a second Main, which could not
	# coexist here — see the note above.
	var port: int = _free_port()
	var squatter: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(squatter.create_server(port, 1), OK, "the test needs the port held")

	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	var problem: String = main.host_match(StalksFixture.make_settings(), "Murph", port)
	squatter.close()

	assert_ne(problem, "", "the host should be told the port is taken")
	assert_false(main.current_screen() is LobbyScreen, "and stay on the menu")
	# ENet complains to the engine log when a bind fails. That is expected here,
	# and asserting it keeps GUT from treating it as an unhandled error.
	assert_engine_error("host", "ENet should report the failed bind")


func test_a_failed_host_leaves_the_player_on_the_menu_with_the_reason() -> void:
	var port: int = _free_port()
	var squatter: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(squatter.create_server(port, 1), OK)

	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.show_menu()
	var menu: MainMenu = main.current_screen() as MainMenu
	assert_not_null(menu, "the menu should be showing to start with")
	if menu == null:
		return

	var overlay: DevOverlay = main.dev_overlay()
	assert_not_null(overlay, "the development overlay hosts direct games now")
	if overlay == null:
		return
	overlay.get_node("%DevPortSpin").value = port
	overlay.get_node("%DevHostButton").pressed.emit()
	squatter.close()

	assert_same(main.current_screen(), menu, "the player should still be on the menu")
	assert_true(
		menu.get_node("%ContentWarning").visible,
		"and the reason should be on screen, not only in the log",
	)
	assert_engine_error("host", "ENet should report the failed bind")


func test_leaving_a_lobby_frees_the_port_for_the_next_attempt() -> void:
	# The session holds a socket, so a lobby left behind without closing it would
	# block the next attempt on the same port — hence `close()` in
	# `Main._discard_session`.
	var port: int = _free_port()
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	assert_eq(main.host_match(StalksFixture.make_settings(), "Murph", port), "")

	main.show_menu()
	await get_tree().process_frame

	assert_eq(
		main.host_match(StalksFixture.make_settings(), "Murph", port), "",
		"the same port should be usable again",
	)


func test_starting_the_match_carries_the_host_to_the_board() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	assert_eq(main.host_match(StalksFixture.make_settings(), "Murph", _free_port()), "")
	await get_tree().process_frame

	var host: HostSession = main.session()
	host.start_match()
	await wait_process_frames(3)

	assert_true(
		main.current_screen() is GameplayScreen,
		"the lobby should give way to the playing screen",
	)
	assert_same(
		main.session(), host,
		"and the same session should carry through — the match has begun",
	)


func test_the_board_shows_the_hosts_own_player() -> void:
	# Proves the session survives the screen swap intact, which is the thing that
	# would silently break if the lobby handed the gameplay screen a new one.
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	assert_eq(main.host_match(StalksFixture.make_settings(), "Murph", _free_port()), "")
	await get_tree().process_frame

	var host: HostSession = main.session()
	host.start_match()
	await wait_process_frames(3)

	assert_eq(main.session().local_player_id(), &"p0")
	assert_eq(main.session().state().player_by_id(&"p0").display_name, "Murph")


# ----------------------------------------------- who readies up, and who starts
#
# The host does not ready up: pressing Start is their readiness. They had a
# READY button that changed nothing, which is what prompted this.

func test_the_host_has_no_ready_button() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	assert_false(
		lobby.get_node("%ReadyButton").visible,
		"Start is the host's readiness; a second control would do nothing",
	)
	assert_true(lobby.get_node("%StartButton").visible)


func test_a_guest_readies_up_and_cannot_start() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	var guest: LobbyScreen = _guest_lobby()

	assert_true(guest.get_node("%ReadyButton").visible, "a guest readies up")
	assert_false(guest.get_node("%StartButton").visible, "and cannot start")


func test_the_host_is_told_who_is_still_waiting() -> void:
	# Named rather than counted: the host is deciding whether to wait for a
	# particular person.
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	assert_string_contains(lobby.get_node("%Status").text, "Guest")

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)

	assert_string_contains(
		lobby.get_node("%Status").text.to_lower(), "everybody is ready"
	)


func test_the_host_alone_is_told_they_can_still_start() -> void:
	_harness = NetHarness.new()
	add_child(_harness)
	assert_eq(_harness.start(StalksFixture.make_settings(), _library, "Murph"), "")

	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(lobby)
	lobby.setup(_harness.host, _harness.port())

	assert_string_contains(lobby.get_node("%Status").text.to_lower(), "on your own")
	assert_false(lobby.get_node("%StartButton").disabled)


func test_several_waiting_players_are_listed_readably() -> void:
	# Shared with the playing screen, which says the same thing while waiting
	# for a year to start.
	assert_eq(Palette.list_names(PackedStringArray([])), "")
	assert_eq(Palette.list_names(PackedStringArray(["Ann"])), "Ann")
	assert_eq(Palette.list_names(PackedStringArray(["Ann", "Bob"])), "Ann and Bob")
	assert_eq(
		Palette.list_names(PackedStringArray(["Ann", "Bob", "Cal"])),
		"Ann, Bob and Cal",
	)


# ------------------------------------------------------- the all-ready gate
#
# Start waits for everybody. The host's way out of a lobby held up by somebody
# who has wandered off is to remove them, not to override the gate. See D49.

func test_start_is_refused_until_everybody_is_ready() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	assert_ne(_harness.host.why_not_start(), "", "a waiting player blocks the start")
	assert_true(lobby.get_node("%StartButton").disabled)

	lobby.get_node("%StartButton").pressed.emit()
	await _harness.settle(self)

	assert_true(_harness.host.lobby_is_open(), "pressing it anyway should do nothing")


func test_start_opens_once_the_last_player_readies_up() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)

	assert_eq(_harness.host.why_not_start(), "")
	assert_false(lobby.get_node("%StartButton").disabled)

	lobby.get_node("%StartButton").pressed.emit()
	await _harness.settle(self)

	assert_false(_harness.host.lobby_is_open(), "and now it starts")


func test_the_host_does_not_have_to_ready_themselves() -> void:
	# Start is the host's readiness. Requiring both would be the dead button
	# again, one turn later.
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)

	assert_false(_harness.host.state().player_by_id(&"p0").is_ready)
	assert_eq(_harness.host.why_not_start(), "", "the host is not waited on")


func test_a_host_alone_can_start() -> void:
	_harness = NetHarness.new()
	add_child(_harness)
	assert_eq(_harness.start(StalksFixture.make_settings(), _library, "Murph"), "")

	assert_eq(_harness.host.why_not_start(), "")
	_harness.host.start_match()
	assert_false(_harness.host.lobby_is_open())


func test_un_readying_closes_the_start_again() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	assert_false(lobby.get_node("%StartButton").disabled)

	_harness.client.set_ready(&"p1", false)
	await _harness.settle(self)

	assert_true(lobby.get_node("%StartButton").disabled, "the gate should close again")


# ------------------------------------------------------------------- kicking

func test_the_host_can_remove_a_player_who_is_holding_things_up() -> void:
	# The escape from the all-ready gate, and the reason the gate is safe.
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	assert_ne(_harness.host.why_not_start(), "", "blocked to begin with")

	assert_eq(_harness.host.kick_player(&"p1"), "")
	await _harness.settle(self, 30)

	assert_eq(_harness.host.state().players.size(), 1, "they should be gone")
	assert_eq(_harness.host.why_not_start(), "", "and the lobby should be free to start")


func test_a_kicked_player_is_told_why() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	var reasons: Array[String] = []
	_harness.client.connection_lost.connect(
		func(reason: String) -> void: reasons.append(reason)
	)

	assert_eq(_harness.host.kick_player(&"p1"), "")
	await _harness.settle(self, 30)

	assert_true(reasons.size() >= 1, "being dropped in silence would be worse")
	if reasons.size() >= 1:
		assert_string_contains(reasons[0].to_lower(), "removed you")


func test_the_kick_button_shows_only_to_the_host_and_not_on_their_own_row() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	assert_false(
		lobby.player_rows()[0].get_node("%Kick").visible,
		"the host cannot remove themselves",
	)
	assert_true(lobby.player_rows()[1].get_node("%Kick").visible)

	var guest: LobbyScreen = _guest_lobby()
	for row: LobbyRow in guest.player_rows():
		assert_false(row.get_node("%Kick").visible, "a guest cannot remove anybody")


func test_pressing_the_kick_button_removes_the_player() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return

	lobby.player_rows()[1].get_node("%Kick").pressed.emit()
	await _harness.settle(self, 30)

	assert_eq(lobby.player_rows().size(), 1, "the row should go with them")


func test_the_host_cannot_kick_themselves() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	assert_ne(_harness.host.kick_player(&"p0"), "")
	assert_eq(_harness.host.state().players.size(), 2, "nobody removed")


func test_kicking_is_refused_once_the_match_has_started() -> void:
	# Removing somebody from a running match is a different act with different
	# consequences for the economy. Nothing asks for it yet.
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	_harness.host.start_match()
	await _harness.settle(self)

	assert_ne(_harness.host.kick_player(&"p1"), "")
	assert_eq(_harness.host.state().players.size(), 2, "still both playing")


func test_the_host_is_told_how_to_get_unstuck() -> void:
	var lobby: LobbyScreen = await _lobby_on_host()
	if lobby == null:
		return
	assert_string_contains(lobby.get_node("%Status").text, "Guest")
	assert_string_contains(lobby.get_node("%Status").text.to_lower(), "remove")


# ---------------------------------------------- joining, before the host answers
#
# Found in play: the host left while somebody was joining, and that player sat
# on the lobby for ever. It showed the normal waiting message and a Ready
# button that refused every press, so nothing on screen said anything was
# wrong. The only way out was LEAVE. See decisions.md D67.

## A client with a socket but no welcome: exactly the state a join sits in.
func _client_awaiting_welcome() -> ClientSession:
	var result: Dictionary = ClientSession.join(StubTransport.new(), _library, "Guest")
	var client: ClientSession = result["session"]
	add_child_autofree(client)
	return client


func test_a_joining_client_says_it_is_connecting() -> void:
	var client: ClientSession = _client_awaiting_welcome()
	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(lobby)
	lobby.setup(client)

	assert_false(client.has_joined(), "the test needs an unwelcomed client")
	assert_string_contains((lobby.get_node("%Status") as Label).text.to_lower(), "connecting")
	assert_true((lobby.get_node("%ReadyButton") as Button).disabled,
		"there is nothing to be ready for until the host answers")


func test_a_join_that_never_completes_gives_up() -> void:
	# Over ENet a vanished host produces a disconnect signal. Over Steam the
	# session just goes quiet, so a clock is the only thing that catches it.
	var client: ClientSession = _client_awaiting_welcome()
	var endings: Array[String] = []
	client.connection_lost.connect(func(reason: String) -> void: endings.append(reason))

	client._process(ClientSession.JOIN_TIMEOUT_SECONDS - 1.0)
	assert_eq(endings.size(), 0, "it must not give up early")

	client._process(2.0)
	assert_eq(endings.size(), 1, "it must give up eventually")
	if endings.is_empty():
		return
	assert_string_contains(endings[0].to_lower(), "host")


func test_the_clock_stops_once_the_host_answers() -> void:
	# Otherwise a seated player would be thrown out mid-lobby.
	var client: ClientSession = _client_awaiting_welcome()
	var endings: Array[String] = []
	client.connection_lost.connect(func(reason: String) -> void: endings.append(reason))

	client._on_welcomed(&"p1", StateSync.encode_state(
		StalksFixture.make_state(10, 2), &"p1"
	))
	assert_true(client.has_joined(), "the test needs a welcomed client")

	client._process(ClientSession.JOIN_TIMEOUT_SECONDS * 2.0)
	assert_eq(endings, [] as Array[String])


# -------------------------------------------------------------- inviting people
#
# Phase 6 is not done until two accounts can meet through an invite as well as
# through the browser. The lobby does the asking; Steam's own friend picker
# does the choosing.

func test_a_lobby_does_not_offer_invites_by_default() -> void:
	# A local game has nobody to invite through.
	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(lobby)
	assert_false((lobby.get_node("%InviteButton") as Button).visible)


func test_a_lobby_told_to_offer_invites_shows_the_button() -> void:
	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(lobby)
	lobby.offer_invites()
	assert_true((lobby.get_node("%InviteButton") as Button).visible)


func test_offering_invites_before_the_screen_exists_still_works() -> void:
	# `Main` sets this up before the swap, as it does everything else.
	var lobby: LobbyScreen = LobbyScene.instantiate()
	lobby.offer_invites()
	add_child_autofree(lobby)
	assert_true((lobby.get_node("%InviteButton") as Button).visible)


func test_the_invite_button_asks_rather_than_acting() -> void:
	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(lobby)
	var asked: Array = []
	lobby.invite_requested.connect(func() -> void: asked.append(true))

	(lobby.get_node("%InviteButton") as Button).pressed.emit()

	assert_eq(asked.size(), 1)


func test_the_menu_offers_invite_only_games() -> void:
	# Listed in game-rules.md §2 since the port began, and until now it was the
	# one setting there with no implementation.
	# An online game only: a private lobby means nothing without a lobby, so
	# the control is hidden under Single Player and its value never reaches
	# the settings there.
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)
	assert_false(menu.chosen_settings().invite_only, "public by default")

	menu.get_node("%InviteOnlyCheck").button_pressed = true
	assert_true(menu.chosen_settings().invite_only)


# ------------------------------------------------------------- the settings tab
#
# Volume had existed, persisted and applied at startup for a while with
# nothing on screen to change it. Settings sits beside Create Game and Join
# Game rather than behind a cog, because it is one of the three places a
# player goes from the title screen. See decisions.md D74.

func test_settings_is_its_own_tab() -> void:
	var menu: MainMenu = _menu()
	assert_false(menu.get_node("%SettingsBox").is_visible_in_tree())

	menu.get_node("%SettingsTab").pressed.emit()
	assert_eq(menu.current_mode(), MainMenu.Mode.SETTINGS)
	assert_true(menu.get_node("%SettingsBox").is_visible_in_tree())
	assert_false(menu.get_node("%YearsSpin").is_visible_in_tree(),
		"the match settings are not these settings")


func test_the_name_field_is_not_offered_under_settings() -> void:
	# Nothing there is done under a name, so the field would only invite a
	# player to wonder what it was for.
	var menu: MainMenu = _menu()
	assert_true(menu.get_node("%NameField").is_visible_in_tree())

	menu.show_mode(MainMenu.Mode.SETTINGS)
	assert_false(menu.get_node("%NameField").is_visible_in_tree())


func test_the_slider_starts_where_the_volume_actually_is() -> void:
	# Rather than wherever the scene file last left it.
	var before: int = Audio.volume_percent()
	Audio.set_volume_percent(35)

	var menu: MainMenu = _menu()
	assert_almost_eq(int((menu.settings_panel().get_node("%VolumeSlider") as HSlider).value), 35, 5)

	Audio.set_volume_percent(before)


func test_moving_the_slider_changes_the_volume_and_says_so() -> void:
	var before: int = Audio.volume_percent()
	var menu: MainMenu = _menu()

	(menu.settings_panel().get_node("%VolumeSlider") as HSlider).value = 50
	assert_almost_eq(Audio.volume_percent(), 50, 5)
	assert_string_contains((menu.settings_panel().get_node("%VolumeValue") as Label).text, "50")

	Audio.set_volume_percent(before)


## Reported from play: a drag played a clip at every step, and they overlapped
## into an echo. The preview now waits for the slider to be let go.
func test_dragging_the_slider_does_not_preview_until_it_is_let_go() -> void:
	var before: int = Audio.volume_percent()
	var menu: MainMenu = _menu()
	var slider: HSlider = menu.settings_panel().get_node("%VolumeSlider") as HSlider
	Audio.preview_voice().stop()
	Audio.preview_voice().stream = null

	slider.drag_started.emit()
	slider.value = 40
	slider.value = 25
	assert_null(Audio.preview_voice().stream, "no clip while the drag is going")

	slider.drag_ended.emit(true)
	assert_eq(Audio.preview_voice().stream, AudioService.BULL[1], "one on release")

	Audio.set_volume_percent(before)


func test_a_change_with_no_drag_previews_straight_away() -> void:
	# The arrow keys, Home and End. There is no release to wait for, so
	# waiting for one would mean no feedback at all.
	var before: int = Audio.volume_percent()
	var menu: MainMenu = _menu()
	Audio.preview_voice().stop()
	Audio.preview_voice().stream = null

	(menu.settings_panel().get_node("%VolumeSlider") as HSlider).value = 65

	assert_eq(Audio.preview_voice().stream, AudioService.BULL[1])

	Audio.set_volume_percent(before)


func test_letting_go_without_moving_anything_is_silent() -> void:
	var menu: MainMenu = _menu()
	var slider: HSlider = menu.settings_panel().get_node("%VolumeSlider") as HSlider
	Audio.preview_voice().stop()
	Audio.preview_voice().stream = null

	slider.drag_started.emit()
	slider.drag_ended.emit(false)

	assert_null(Audio.preview_voice().stream, "a sound in answer to nothing")


## Reported from play, after the deferral above: a clip still sounding when a
## drag began rode the volume up and down with the slider. Correct for a
## mixer, wrong for feedback, and it put sound back into a drag that was
## supposed to be silent.
func test_starting_a_drag_silences_the_last_preview() -> void:
	var before: int = Audio.volume_percent()
	var menu: MainMenu = _menu()
	var slider: HSlider = menu.settings_panel().get_node("%VolumeSlider") as HSlider
	Audio.play_volume_preview()
	assert_not_null(Audio.preview_voice().stream, "the test needs a clip loaded")

	slider.drag_started.emit()

	assert_null(Audio.preview_voice().stream, "the drag should begin in silence")

	Audio.set_volume_percent(before)


## Reported from play: typing 1,234 produced a game that started with 1,200.
##
## The spin box carried `step = 100`, which is not a rounding rule anybody
## chose — it is what the control does with a step. The original's field was
## free text and took any whole number in range.
## The original's bounds, restored 2026-11-16: its create-game form tested
## `wealth > 149 && wealth < 69421`. The port had 100 to 1,000,000, guessed
## before the audit read the real ones.
func test_the_starting_cash_field_holds_the_originals_bounds() -> void:
	var menu: MainMenu = _menu()
	var cash: SpinBox = menu.get_node("%CashSpin")

	assert_eq(int(cash.min_value), GameSettings.MIN_STARTING_CASH)
	assert_eq(int(cash.max_value), GameSettings.MAX_STARTING_CASH)


func test_the_joke_ceiling_is_itself_allowed() -> void:
	# 69,420 is legal and 69,421 is not, which is the whole point of it.
	var menu: MainMenu = _menu()
	var cash: SpinBox = menu.get_node("%CashSpin")

	cash.value = 69420
	assert_eq(menu.chosen_settings().starting_cash, 69420)

	cash.value = 69421
	assert_eq(menu.chosen_settings().starting_cash, 69420, "clamped, not accepted")


func test_too_little_to_start_with_is_raised_to_the_floor() -> void:
	var menu: MainMenu = _menu()
	var cash: SpinBox = menu.get_node("%CashSpin")

	cash.value = 1
	assert_eq(menu.chosen_settings().starting_cash, 150)


func test_starting_cash_is_taken_as_typed() -> void:
	var menu: MainMenu = _menu()
	var cash: SpinBox = menu.get_node("%CashSpin")

	cash.value = 1234
	assert_eq(menu.chosen_settings().starting_cash, 1234)

	cash.value = 10001
	assert_eq(menu.chosen_settings().starting_cash, 10001)
