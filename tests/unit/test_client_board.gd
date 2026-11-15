extends GutTest
## The client's side of starting and leaving a match.
##
## Every test here exists because of a bug found by actually playing two windows,
## not by reasoning about the code. The common thread: `Main` had only ever been
## tested as a *host*, so nothing exercised the client's path from lobby to board.


const GameplayScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")
const LobbyScene: PackedScene = preload("res://src/ui/screens/lobby/lobby_screen.tscn")
const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")

var _library: ContentLibrary
var _harness: NetHarness


func before_all() -> void:
	_library = ContentLibrary.load_from()


func after_each() -> void:
	if _harness != null and is_instance_valid(_harness):
		_harness.queue_free()
	_harness = null


func _started_match() -> bool:
	_harness = NetHarness.new()
	add_child(_harness)
	if not _harness.start(StalksFixture.make_settings(), _library).is_empty():
		fail_test("harness did not start")
		return false
	if not await _harness.await_join(self):
		fail_test("the client did not connect")
		return false
	await _harness.begin_match(self)
	return true


# --------------------------------------------------------- the board, as a client

func test_the_board_builds_and_fills_for_a_client() -> void:
	if not await _started_match():
		return

	var board: GameplayScreen = GameplayScene.instantiate()
	board.setup(_harness.client)
	add_child_autofree(board)
	await wait_process_frames(2)

	assert_eq(board.get_node("%StalkList").get_child_count(), 10, "every stalk")
	assert_eq(board.get_node("%RankingList").get_child_count(), 2, "both players")
	assert_ne(board.get_node("%CashLabel").text, "", "the client's own cash")


# ------------------------------------------------- a swapped-out screen goes quiet
#
# The bug behind "the client didn't load anything". `Main` swaps screens with
# `remove_child` plus `queue_free`, and `queue_free` is deferred. `start_match`
# sends `match_started` and then a state broadcast, so the client swapped to the
# board on the first and the second reached the lobby that was already on its way
# out. It rebuilt its rows while detached from the tree, where `_ready` never
# runs on them, and died on a null `@onready` node.
#
# These reproduce that exact sequence. Both were written vacuous the first time
# DASH they poked the session with a buy at year 0, which is rejected, and a
# rejection broadcasts nothing DASH so they passed with the fix removed. They now
# fail without it.

## A connected lobby that has not started yet.
func _joined_lobby() -> bool:
	_harness = NetHarness.new()
	add_child(_harness)
	if not _harness.start(StalksFixture.make_settings(), _library).is_empty():
		fail_test("harness did not start")
		return false
	if not await _harness.await_join(self):
		fail_test("the client did not connect")
		return false
	return true


func test_a_lobby_swapped_out_on_start_ignores_the_state_that_follows() -> void:
	if not await _joined_lobby():
		return

	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child(lobby)
	lobby.setup(_harness.client)
	assert_gt(lobby.player_rows().size(), 0, "live to begin with")

	# Exactly what Main does: the lobby leaves the tree the moment the match
	# starts, and the state broadcast arrives immediately afterwards.
	lobby.play_requested.connect(func() -> void: remove_child(lobby))

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	_harness.host.start_match()
	await _harness.settle(self)

	lobby.free()
	assert_true(true, "the state that follows must not reach the old lobby")


func test_a_board_out_of_the_tree_ignores_a_trade() -> void:
	# The same exposure on the playing screen, which swaps to the game-over
	# screen the same way. Not seen in play; fixed alongside.
	if not await _started_match():
		return
	# Year 1, so a buy is actually allowed and actually broadcasts.
	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)
	assert_true(_harness.host.state().is_trading_open(), "the test needs an open market")

	var board: GameplayScreen = GameplayScene.instantiate()
	board.setup(_harness.client)
	add_child(board)
	await wait_process_frames(1)

	remove_child(board)
	_harness.host.request_buy(&"p0", _harness.host.state().stalks[0].id, 1)
	await _harness.settle(self)

	board.free()
	assert_true(true, "a detached board must not react, and must not error")


func test_a_lobby_still_in_the_tree_keeps_reacting() -> void:
	# Guards the fix from going too far: detaching on exit must not stop a live
	# screen from updating.
	if not await _joined_lobby():
		return

	var lobby: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(lobby)
	lobby.setup(_harness.host, 1234)
	assert_eq(lobby.player_rows().size(), 2)

	assert_eq(_harness.host.kick_player(&"p1"), "")
	await _harness.settle(self, 30)

	assert_eq(lobby.player_rows().size(), 1, "a live lobby should still update")


# ------------------------------------------------------- being removed from a lobby

func test_a_kicked_client_is_told_the_lobby_has_ended() -> void:
	# It used to only write the reason into the status line, leaving the player
	# sitting in a lobby they were no longer part of, still looking at a list of
	# players they could not see any more.
	_harness = NetHarness.new()
	add_child(_harness)
	assert_eq(_harness.start(StalksFixture.make_settings(), _library), "")
	if not await _harness.await_join(self):
		return

	var guest: LobbyScreen = LobbyScene.instantiate()
	add_child_autofree(guest)
	guest.setup(_harness.client)

	var endings: Array[String] = []
	guest.connection_ended.connect(func(reason: String) -> void: endings.append(reason))

	assert_eq(_harness.host.kick_player(&"p1"), "")
	await _harness.settle(self, 30)

	assert_eq(endings.size(), 1, "the screen should end, not just annotate itself")
	if endings.size() == 1:
		assert_string_contains(endings[0].to_lower(), "removed you")


func test_main_returns_to_the_menu_when_a_connection_ends() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	main._on_connection_ended("The host removed you from the lobby.")

	var menu: MainMenu = main.current_screen() as MainMenu
	assert_not_null(menu, "it should go back to the menu")
	if menu == null:
		return
	assert_true(
		menu.get_node("%ContentWarning").visible,
		"carrying the reason, or the player has no idea what happened",
	)
	assert_string_contains(menu.get_node("%ContentWarning").text.to_lower(), "removed you")


# ---------------------------------------------- can a client actually play?
#
# Reported from a real two-window game: "I could join the lobby, but couldn't
# interact with the game at all." Nothing drove the client's board through its
# own controls, so there was nothing to catch it.

func _client_board() -> GameplayScreen:
	var board: GameplayScreen = GameplayScene.instantiate()
	board.setup(_harness.client)
	add_child_autofree(board)
	await wait_process_frames(2)
	return board


func test_a_client_can_ready_up_from_the_board() -> void:
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()

	var ready_button: Button = board.get_node("%ReadyButton")
	gut.p("client ready button disabled: %s" % ready_button.disabled)
	ready_button.pressed.emit()
	await _harness.settle(self)

	assert_true(
		_harness.host.state().player_by_id(&"p1").is_ready,
		"the host should have recorded the client's readiness",
	)


func test_a_clients_board_opens_for_trading_in_year_one() -> void:
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()

	# Both ready, so the year advances.
	board.get_node("%ReadyButton").pressed.emit()
	await _harness.settle(self)
	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)
	await wait_process_frames(2)

	gut.p("host year: %d" % _harness.host.state().year)
	gut.p("client year: %d" % _harness.client.state().year)
	assert_eq(_harness.client.state().year, 1, "the client should have advanced too")

	var first_row: StalkRow = board.get_node("%StalkList").get_child(0)
	var buy_button: Button = first_row.get_node("%BuyButton")
	var amount: LineEdit = first_row.get_node("%Amount")
	gut.p("client buy disabled: %s, field editable: %s" % [buy_button.disabled, amount.editable])
	assert_false(buy_button.disabled, "a client should be able to buy in year 1")
	assert_true(amount.editable, "and type an amount")


func test_a_client_can_buy_through_the_real_controls() -> void:
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()
	board.get_node("%ReadyButton").pressed.emit()
	await _harness.settle(self)
	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)
	await wait_process_frames(2)

	var first_row: StalkRow = board.get_node("%StalkList").get_child(0)
	var amount: LineEdit = first_row.get_node("%Amount")
	amount.text = "2"
	amount.text_changed.emit("2")
	first_row.get_node("%BuyButton").pressed.emit()
	await _harness.settle(self)

	assert_eq(
		_harness.host.state().player_by_id(&"p1").shares_of(first_row.stalk_id()), 2,
		"the host should have applied the client's purchase",
	)


# ------------------------------------------------ the board must answer a press
#
# "Couldn't interact with the game at all." The board never connected
# `ready_state_changed`, so pressing Ready changed nothing on screen: the button
# kept its old label, the rankings did not update, and no message appeared. In a
# solo game the year advances instantly, so it never showed.

func test_the_board_says_you_are_ready_after_you_press_it() -> void:
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()
	var ready_button: Button = board.get_node("%ReadyButton")
	assert_eq(ready_button.text, "Ready for New Year")

	ready_button.pressed.emit()
	await _harness.settle(self)

	assert_eq(ready_button.text, "Waiting...", "the button must acknowledge the press")


func test_the_board_names_who_it_is_waiting_for() -> void:
	# A screen that simply stops responding reads as broken rather than waiting.
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()

	board.get_node("%ReadyButton").pressed.emit()
	await _harness.settle(self)

	assert_string_contains(board.get_node("%InfoLabel").text, "Host")


func test_readying_up_can_be_undone_from_the_board() -> void:
	# Readying by accident would otherwise trap you waiting for a year you did
	# not want to start.
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()
	var ready_button: Button = board.get_node("%ReadyButton")

	ready_button.pressed.emit()
	await _harness.settle(self)
	assert_true(_harness.host.state().player_by_id(&"p1").is_ready)

	ready_button.pressed.emit()
	await _harness.settle(self)

	assert_false(_harness.host.state().player_by_id(&"p1").is_ready, "un-readied")
	assert_eq(ready_button.text, "Ready for New Year", "and the button says so")


func test_the_board_shows_another_players_readiness() -> void:
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()

	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)

	var host_row: RankingRow = null
	for row: RankingRow in board.get_node("%RankingList").get_children():
		if row.get_node("%Name").text.begins_with("Host"):
			host_row = row
	assert_not_null(host_row, "the host should be in the rankings")
	if host_row == null:
		return
	# The dot is green when ready, red when not. Asserting the colour rather
	# than a label because that is what a player actually reads here.
	assert_eq(
		host_row.get_node("%ReadyDot").modulate, Palette.BULL,
		"the other player's dot should turn ready",
	)


# --------------------------------------------------------------- yeehaw, both ways
#
# Reported: "one player presses 'Can I get a yeehaw?' and there's a message, but
# the button does not change to 'give' for the other player." A pending request
# was a passing signal, so there was nothing left to answer. It is match state
# now, exactly as the original kept it. See docs/game-rules.md 10.

func test_asking_turns_the_other_players_button_into_give() -> void:
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()
	var button: Button = board.get_node("%YeehawButton")
	assert_eq(button.text, "Can I Get a Yeehaw?")

	_harness.host.request_yeehaw(&"p0")
	await _harness.settle(self)

	assert_eq(button.text, "Give Yeehaw", "the client should be offered the answer")
	assert_false(button.disabled, "and be able to press it")


func test_the_asker_cannot_answer_their_own_ask() -> void:
	# The original hid the button for the asker. This disables it instead, to
	# keep the top bar from reflowing (D37), with the reason in the tooltip.
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()

	_harness.client.request_yeehaw(&"p1")
	await _harness.settle(self)

	var button: Button = board.get_node("%YeehawButton")
	assert_eq(button.text, "Give Yeehaw")
	assert_true(button.disabled, "you cannot yeehaw yourself")
	assert_string_contains(button.tooltip_text.to_lower(), "yourself")


func test_pressing_give_answers_the_request_for_everybody() -> void:
	if not await _started_match():
		return
	var board: GameplayScreen = await _client_board()
	var given: Array = []
	_harness.host.yeehaw_given.connect(
		func(giver: StringName, receiver: StringName) -> void: given.append([giver, receiver])
	)

	_harness.host.request_yeehaw(&"p0")
	await _harness.settle(self)
	board.get_node("%YeehawButton").pressed.emit()
	await _harness.settle(self)

	assert_eq(given, [[&"p1", &"p0"]], "the client gave one to the host")
	assert_false(_harness.host.state().is_yeehaw_pending(), "and the ask is answered")
	assert_eq(
		board.get_node("%YeehawButton").text, "Can I Get a Yeehaw?",
		"the button should go back to asking",
	)


func test_only_one_request_is_pending_at_a_time() -> void:
	if not await _started_match():
		return
	_harness.host.request_yeehaw(&"p0")
	await _harness.settle(self)

	var refusals: Array[String] = []
	_harness.client.action_rejected.connect(
		func(_id: StringName, reason: String) -> void: refusals.append(reason)
	)
	_harness.client.request_yeehaw(&"p1")
	await _harness.settle(self)

	assert_eq(_harness.host.state().yeehaw_requested_by, &"p0", "the first ask stands")
	assert_eq(refusals.size(), 1, "and the second is refused")


func test_an_unanswered_request_does_not_outlive_the_year() -> void:
	# The original left it pending forever, so one ignored ask locked the button
	# into "Give Yeehaw" for the rest of the match. See D52.
	if not await _started_match():
		return
	_harness.host.request_yeehaw(&"p0")
	await _harness.settle(self)
	assert_true(_harness.host.state().is_yeehaw_pending())

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)

	assert_eq(_harness.host.state().year, 1)
	assert_false(_harness.host.state().is_yeehaw_pending(), "a new year clears it")
	assert_false(_harness.client.state().is_yeehaw_pending(), "on both sides")
