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


func test_the_menu_opens_on_solo() -> void:
	var menu: MainMenu = _menu()
	assert_eq(menu.current_mode(), MainMenu.Mode.SOLO)


func test_choosing_host_offers_a_lobby_instead_of_a_start() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)

	assert_false(menu.get_node("%StartButton").visible, "solo start should be hidden")
	assert_true(menu.get_node("%HostButton").visible)
	assert_true(menu.get_node("%NetworkBox").visible, "a name and port are needed")
	assert_true(
		menu.get_node("%SettingsBox").visible,
		"the host chooses the match settings",
	)


func test_a_joiner_is_not_offered_the_match_settings() -> void:
	# The host owns them, and a joiner is told the year limit and seed by the
	# host. Offering the controls here would be a lie.
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.JOIN)

	assert_false(menu.get_node("%SettingsBox").visible)
	assert_true(menu.get_node("%JoinButton").visible)
	assert_true(menu.get_node("%AddressField").visible)


func test_only_joining_asks_for_an_address() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)
	assert_false(
		menu.get_node("%AddressField").get_parent().visible,
		"a host has nowhere to connect to",
	)


func test_hosting_emits_the_name_port_and_settings() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.HOST)
	menu.get_node("%NameField").text = "Murph"
	menu.get_node("%PortSpin").value = 43000
	menu.get_node("%YearsSpin").value = 12

	var seen: Array = []
	menu.host_requested.connect(
		func(settings: GameSettings, player_name: String, port: int) -> void:
			seen.append([settings.max_years, player_name, port])
	)
	menu.get_node("%HostButton").pressed.emit()

	assert_eq(seen, [[12, "Murph", 43000]])


func test_joining_emits_the_address_port_and_name() -> void:
	var menu: MainMenu = _menu()
	menu.show_mode(MainMenu.Mode.JOIN)
	menu.get_node("%AddressField").text = "10.0.0.5"
	menu.get_node("%PortSpin").value = 43001
	menu.get_node("%NameField").text = "Guest"

	var seen: Array = []
	menu.join_requested.connect(
		func(address: String, port: int, player_name: String) -> void:
			seen.append([address, port, player_name])
	)
	menu.get_node("%JoinButton").pressed.emit()

	assert_eq(seen, [["10.0.0.5", 43001, "Guest"]])


func test_a_blank_address_means_this_machine() -> void:
	# Two windows on one computer is the commonest case, so it should need no
	# typing at all.
	var menu: MainMenu = _menu()
	assert_eq(menu.chosen_address(), "127.0.0.1")


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
		"127.0.0.1", _harness.port(), _library, "Third"
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
	return randi_range(43100, 43599)


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

	menu.show_mode(MainMenu.Mode.HOST)
	menu.get_node("%PortSpin").value = port
	menu.get_node("%HostButton").pressed.emit()
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
