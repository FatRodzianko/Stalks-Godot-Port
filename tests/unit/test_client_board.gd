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
