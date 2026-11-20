extends GutTest
## What `Main` does for REJOIN GAME: remembering a match, offering it, going
## back into it, and failing with a sentence when it is not there any more.
##
## **The same reasoning as `test_main_migration.gd`, and the same lesson.** D108
## is that every host-migration fault was in the orchestration in `Main` —
## noticing, deciding, and the order of it — and that none of it was covered
## because reaching it meant reaching Steam. Rejoining runs through the same
## code, so it is tested the same way: Steam's answers are faked
## (`StubSteamService`) and the decisions `Main` makes with them are asserted.
##
## What is still out of reach is the transport. There is no Steam plugin in a
## test run, and calling a real `SteamMultiplayerPeer` uninitialised takes the
## whole process down rather than returning an error, so `StubTransportSource`
## stands in and each test stops at the decision it is about.
##
## The remembered match is written to a temporary file, never to the player's
## own: `Main._last_match_path` exists for that. A suite that wrote the real one
## would either wipe a match somebody meant to go back to or invent one that
## does not exist. See docs/decisions.md D111 and docs/testing.md.


const ME: int = 9001
const HOST_STEAM: int = 9002
const NEW_HOST_STEAM: int = 9003
const LOBBY: int = 4242
const OTHER_LOBBY: int = 5353

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")

## Under `user://` so it is writable on every platform, and named for this file
## so a parallel run of another suite cannot collide with it.
const RECORD: String = "user://test_main_rejoin.cfg"


var _main: Main
var _steam: StubSteamService
var _transports: StubTransportSource


func before_each() -> void:
	LastMatch.forget(RECORD)

	_main = MainScene.instantiate()
	add_child_autofree(_main)

	_steam = StubSteamService.new()
	_steam.name = "StubSteam"
	_steam.me = ME
	_steam.lobby = LOBBY
	_steam.owner_steam_id = HOST_STEAM
	_main.add_child(_steam)
	_main._steam = _steam

	# Never the real one: an uninitialised Steam API takes the process down
	# rather than returning an error. See `SteamTransportSource`.
	_transports = StubTransportSource.new()
	_main._steam_transports = _transports
	_main._last_match_path = RECORD


func after_each() -> void:
	# A session built during a test sets a peer on the tree's own
	# MultiplayerAPI. Left there it would reach the next test.
	if _main != null and _main._session != null:
		_main._discard_session(true)
	LastMatch.forget(RECORD)


## A client that believes it is in the match, which is what `Main` has mounted
## by the time the playing screen goes up.
func _joined_client() -> ClientSession:
	var session: ClientSession = ClientSession.new()
	session.name = NetworkedSession.NODE_NAME
	session._state = StalksFixture.make_state(10, 2)
	session._state.settings.game_name = "Friday night"
	session._local_player_id = &"p1"
	session._has_joined = true
	return session


## Puts `Main` where it is during an online match, without a transport.
func _in_an_online_match() -> ClientSession:
	var session: ClientSession = _joined_client()
	_main._session = session
	_main.add_child(session)
	_main._is_online_match = true
	return session


func _menu() -> MainMenu:
	return _main.current_screen() as MainMenu


# ------------------------------------------------------------ remembering it

## Every route into the playing screen goes through `_show_gameplay`, which is
## why the record is written there and not in each of hosting, joining and
## migrating.
func test_reaching_the_board_remembers_the_lobby() -> void:
	_in_an_online_match()

	_main._show_gameplay()

	var remembered: LastMatch = LastMatch.load_from(RECORD)
	assert_true(remembered.exists())
	assert_eq(remembered.lobby_id, LOBBY)
	assert_eq(remembered.game_name, "Friday night", "so the offer can name it")


func test_a_solo_game_is_not_something_to_rejoin() -> void:
	_in_an_online_match()
	_main._is_online_match = false

	_main._show_gameplay()

	assert_false(
		LastMatch.load_from(RECORD).exists(),
		"there is no lobby and nothing to go back to",
	)


func test_a_match_with_no_steam_lobby_is_not_remembered() -> void:
	_in_an_online_match()
	_steam.lobby = 0

	_main._show_gameplay()

	assert_false(LastMatch.load_from(RECORD).exists())


func test_the_latest_match_is_the_one_remembered() -> void:
	LastMatch.remember(OTHER_LOBBY, "Last week", RECORD)
	_in_an_online_match()

	_main._show_gameplay()

	assert_eq(
		LastMatch.load_from(RECORD).lobby_id, LOBBY,
		"the offer should name the game you were just in",
	)


## A finished match is not a match to rejoin, and this is the one place the game
## knows first-hand that it finished.
func test_the_match_ending_forgets_it() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_in_an_online_match()

	_main._on_match_finished([&"p1"] as Array[StringName])

	assert_false(LastMatch.load_from(RECORD).exists())


# ---------------------------------------------------------------- offering it

func test_the_title_screen_offers_a_match_there_is_one_to_rejoin() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)

	_main.show_menu()

	var button: Button = _menu().get_node("%RejoinButton")
	assert_true(button.visible, "REJOIN GAME should be there to press")


func test_the_title_screen_offers_nothing_when_there_is_nothing_to_rejoin() -> void:
	_main.show_menu()

	var button: Button = _menu().get_node("%RejoinButton")
	assert_false(
		button.visible,
		"a button that explains itself only by failing is worse than no button",
	)


## It mirrors QUIT TO DESKTOP, which is the owner's description of where it
## goes: the two things you can do with a title screen that are not starting a
## game, one at each end of the same row.
func test_the_button_sits_opposite_quit_to_desktop() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_main.show_menu()
	var menu: MainMenu = _menu()

	var quit: Control = menu.get_node("%QuitButton")
	var rejoin: Control = menu.get_node("%RejoinButton")

	assert_eq(quit.get_parent(), rejoin.get_parent(), "the same row")
	assert_eq(quit.size, rejoin.size, "and the same size")


# ---------------------------------------------------------------- rejoining it

func _press_rejoin() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_main.show_menu()
	_main._on_rejoin_requested()


func test_pressing_rejoin_asks_steam_for_the_remembered_lobby() -> void:
	_press_rejoin()

	assert_eq(_steam.joined_lobbies, [LOBBY] as Array[int])


func test_pressing_rejoin_with_nothing_remembered_does_nothing() -> void:
	_main.show_menu()

	_main._on_rejoin_requested()

	assert_eq(_steam.joined_lobbies, [] as Array[int])
	assert_false(_main._rejoining)


func test_a_rejoin_builds_a_client_rather_than_a_host() -> void:
	_press_rejoin()

	assert_eq(_transports.built, [&"client"] as Array[StringName])
	assert_true(_main._session is ClientSession, "the match is somebody else's")


## **The lobby is kept, not left.** It is the lobby the match is in, so leaving
## it on the way to joining it would be leaving the game this is trying to get
## back into. The same reason migration keeps it (D106).
func test_a_rejoin_stays_in_the_steam_lobby() -> void:
	_press_rejoin()

	assert_does_not_have(_steam.calls, &"leave")
	assert_does_not_have(_steam.calls, &"leave_as_host")


## **No screen is swapped until the host says yes.** A half-built session would
## otherwise put an empty market up and call it the match.
func test_a_rejoin_stays_on_the_title_screen_until_it_lands() -> void:
	_press_rejoin()

	assert_true(
		_main.current_screen() is MainMenu,
		"nothing has been welcomed back yet",
	)


func test_the_welcome_puts_the_board_up() -> void:
	_press_rejoin()
	var client: ClientSession = _main._session as ClientSession
	assert_not_null(client, "the test needs a session to welcome")
	if client == null:
		return

	# What `_on_welcomed` emits once the host has seated this player again.
	client._has_joined = true
	client.joined.emit(&"p1")

	assert_true(
		_main.current_screen() is GameplayScreen,
		"a rejoin lands mid-match, not in a lobby",
	)
	assert_false(_main._rejoining, "and the rejoin is over")


## A match that changed hands while this player was away is rejoined through
## whoever is hosting it now. Steam names the owner and the new host is the
## owner (D104), so reading it at rejoin time is all this takes.
func test_a_match_that_has_changed_hands_is_rejoined_through_the_new_host() -> void:
	_steam.owner_steam_id = NEW_HOST_STEAM

	_press_rejoin()

	assert_eq(
		_main._online_host_steam_id, NEW_HOST_STEAM,
		"not the host who was running it when this player left",
	)


# ----------------------------------------------------------- failing cleanly
#
# A rejoin that cannot happen must say so on screen. The three ways it fails are
# Steam refusing the lobby, the host refusing the seat, and a welcome that never
# comes - and the last of those is `ClientSession`'s join timeout (D67), which
# arrives here as a lost connection like any other.

## **This is the gap REJOIN GAME found.** `lobby_failed` used to be connected
## only when hosting, so a join Steam refused reported nothing at all. See D112.
func test_steam_refusing_the_lobby_says_so_on_the_title_screen() -> void:
	_steam.refuse_join_with = "That game no longer exists."

	_press_rejoin()

	assert_true(_main.current_screen() is MainMenu, "still on the title screen")
	var message: Label = _menu().get_node("%ContentWarning")
	assert_true(message.visible, "with something on it")
	assert_string_contains(message.text, "no longer exists")
	assert_false(_main._rejoining, "and nothing still waiting")


## Not forgotten on a failure. A relay having a bad minute would otherwise
## destroy the only route back into a game that is still being played.
func test_a_refused_rejoin_keeps_the_remembered_match() -> void:
	_steam.refuse_join_with = "That game no longer exists."

	_press_rejoin()

	assert_true(
		LastMatch.load_from(RECORD).exists(),
		"the button stays, so a second try is possible",
	)


## The host's own refusal — a stranger's Steam ID, or a match that has since
## finished — reaches the client as a lost connection carrying that reason.
func test_the_host_refusing_the_seat_says_so_on_the_title_screen() -> void:
	_press_rejoin()
	var client: ClientSession = _main._session as ClientSession
	assert_not_null(client)
	if client == null:
		return

	client.connection_lost.emit("That game has finished.")

	assert_true(_main.current_screen() is MainMenu)
	var message: Label = _menu().get_node("%ContentWarning")
	assert_string_contains(message.text, "That game has finished.")


## Once the board is up this is an ordinary client session, and the playing
## screen reports its own lost connections. Left connected, the rejoin's own
## handler would answer a disconnect an hour later as well, and the player
## would be sent to the title screen twice.
func test_the_rejoin_stops_listening_once_it_has_landed() -> void:
	_press_rejoin()
	var client: ClientSession = _main._session as ClientSession
	assert_not_null(client)
	if client == null:
		return

	client._has_joined = true
	client.joined.emit(&"p1")

	assert_false(client.connection_lost.is_connected(_main._give_up_on_rejoin))
	assert_false(client.joined.is_connected(_main._on_rejoin_landed))


## A transport that will not open is the same kind of failure as Steam saying no,
## and must not leave the player on a title screen that says nothing.
func test_a_transport_that_will_not_open_fails_with_a_sentence() -> void:
	_transports.failure = "no socket"

	_press_rejoin()

	assert_true(_main.current_screen() is MainMenu)
	var message: Label = _menu().get_node("%ContentWarning")
	assert_string_contains(message.text, "no socket")


## Going back to the title screen cancels a rejoin that was in flight. Left set,
## the next game picked out of the browser would be treated as a return to a
## match in progress and land on the board instead of in the lobby.
func test_leaving_the_title_screen_and_coming_back_cancels_a_rejoin() -> void:
	_press_rejoin()
	assert_true(_main._rejoining, "the test needs one in flight")

	_main.show_menu()

	assert_false(_main._rejoining)


# ------------------------------------------ is the remembered game still on?
#
# **Reported from play on 2026-11-18, once the feature itself worked.** A player
# who left a game they were the last one in came back to a title screen still
# offering it, pressed the button, and was told the game no longer exists; a
# single-player game in between changed nothing. The record outlived the match
# and nothing ever asked whether it was still a game.
#
# So the record is a candidate and Steam is the authority. See decisions.md
# D115.

## A host session over a stub transport, so leaving it exercises the real
## `_discard_session` path without a socket.
func _hosting_online() -> HostSession:
	var opened: Dictionary = HostSession.host(
		StubTransport.new(), StalksFixture.make_settings(), ContentLibrary.load_from(), "Ann"
	)
	var session: HostSession = opened["session"]
	_main._session = session
	_main.add_child(session)
	_main._is_online_match = true
	return session


func _rejoin_button() -> Button:
	return _menu().get_node("%RejoinButton")


func test_the_title_screen_asks_steam_about_the_remembered_lobby() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)

	_main.show_menu()

	assert_eq(_steam.asked_about, [LOBBY] as Array[int])


func test_nothing_is_asked_when_there_is_nothing_remembered() -> void:
	_main.show_menu()

	assert_eq(_steam.asked_about, [] as Array[int])


## The answer offers the button. This is the ordinary case and the only one of
## the four that ends with anything on screen.
func test_a_lobby_still_playing_is_offered() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_steam.details_exist = true
	_steam.details_state = SteamService.STATE_PLAYING

	_main.show_menu()

	assert_true(_rejoin_button().visible)


## **The fault that was reported.** Everybody left, so Steam has nothing for
## that id any more.
func test_a_lobby_that_no_longer_exists_is_forgotten() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_steam.details_exist = false

	_main.show_menu()

	assert_false(_rejoin_button().visible, "nothing to offer")
	assert_false(
		LastMatch.load_from(RECORD).exists(),
		"and nothing to ask about next time either",
	)


## **The other half of it.** The lobby is alive - everybody in it is reading the
## result screen - but the match it belongs to is finished. The host says so
## with the `state` key, because a player who was away cannot have seen it end.
func test_a_lobby_whose_match_is_over_is_forgotten() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_steam.details_exist = true
	_steam.details_state = SteamService.STATE_OVER

	_main.show_menu()

	assert_false(_rejoin_button().visible)
	assert_false(LastMatch.load_from(RECORD).exists())


## **Silence is not a no.** Steam is entitled never to answer, and a flicker of
## a bad connection must not cost somebody their seat in a game that is still
## being played. The button stays off, the record stays put, and the next tick
## asks again.
func test_steam_not_answering_hides_the_button_without_forgetting() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_steam.details_never_arrive = true

	_main.show_menu()

	assert_false(_rejoin_button().visible, "never offer what cannot be confirmed")
	assert_true(
		LastMatch.load_from(RECORD).exists(),
		"but the route back is not destroyed on a silence",
	)


func test_steam_being_closed_asks_nothing_and_forgets_nothing() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_main._steam = null

	_main.show_menu()

	assert_false(_rejoin_button().visible)
	assert_true(LastMatch.load_from(RECORD).exists())


## An answer that arrives about some other lobby is not an answer to this
## question. Steam raises `lobby_data_update` for every key anybody changes.
func test_an_answer_about_a_different_lobby_is_ignored() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_steam.details_never_arrive = true
	_main.show_menu()

	_steam.lobby_details.emit(OTHER_LOBBY, false, "")

	assert_true(
		LastMatch.load_from(RECORD).exists(),
		"another lobby cannot forget this one",
	)


# --------------------------------------------------------------- the re-check

func _tick(seconds: float) -> void:
	_main._process(seconds)


func test_the_question_is_asked_again_while_the_title_screen_is_up() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_main.show_menu()
	assert_eq(_steam.asked_about.size(), 1, "asked once on the way in")

	_tick(Main.REJOIN_CHECK_SECONDS + 0.01)

	assert_eq(_steam.asked_about.size(), 2, "and again on the timer")


func test_it_is_not_asked_again_before_the_interval() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_main.show_menu()

	_tick(Main.REJOIN_CHECK_SECONDS - 0.5)

	assert_eq(_steam.asked_about.size(), 1)


## The owner's second ask: a match that ends while somebody is sitting on the
## title screen should take its button away with it.
func test_the_button_goes_away_when_the_match_ends_out_there() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_main.show_menu()
	assert_true(_rejoin_button().visible, "the test needs it showing first")

	_steam.details_state = SteamService.STATE_OVER
	_tick(Main.REJOIN_CHECK_SECONDS + 0.01)

	assert_false(_rejoin_button().visible)
	assert_false(LastMatch.load_from(RECORD).exists())


## And the other way: a Steam hiccup that hid the button puts it back, without
## the player having to do anything.
func test_the_button_comes_back_when_steam_answers_again() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_steam.details_never_arrive = true
	_main.show_menu()
	assert_false(_rejoin_button().visible, "the test needs it hidden first")

	_steam.details_never_arrive = false
	_tick(Main.REJOIN_CHECK_SECONDS + 0.01)

	assert_true(_rejoin_button().visible)


func test_nothing_is_asked_from_any_other_screen() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_in_an_online_match()
	_main._show_gameplay()
	var asked_so_far: int = _steam.asked_about.size()

	_tick(Main.REJOIN_CHECK_SECONDS + 0.01)

	assert_eq(_steam.asked_about.size(), asked_so_far, "there is no button here")


# ------------------------------------------- what this process knows for itself

## **The case that was reported, answered without asking Steam anything.** The
## player hosted a game nobody else was in and left it. The lobby died with
## them and this process watched it happen, so there is nothing to wait to be
## told.
func test_leaving_a_lobby_you_were_the_last_one_in_forgets_it() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_hosting_online()
	_steam.last_one_out = true

	_main._discard_session()

	assert_false(LastMatch.load_from(RECORD).exists())


func test_leaving_a_lobby_other_people_are_still_in_keeps_it() -> void:
	LastMatch.remember(LOBBY, "Friday night", RECORD)
	_hosting_online()
	_steam.last_one_out = false

	_main._discard_session()

	assert_true(
		LastMatch.load_from(RECORD).exists(),
		"they are still playing it, and the seat is still there",
	)


# ---------------------------------------------- telling the lobby it is over

## For whoever is not here to see it. Their remembered lobby is alive, because
## everybody else is in it reading the result, so without this their title
## screen would offer a game that has finished.
func test_the_host_marks_the_lobby_finished_when_the_match_ends() -> void:
	_hosting_online()

	_main._on_match_finished([&"p0"] as Array[StringName])

	assert_has(_steam.calls, &"mark_finished")


## Only the host owns the lobby, so only the host says so. A client calling it
## would change nothing, and asking for something that cannot happen reads as
## though it might.
func test_a_client_does_not_try_to_mark_the_lobby_finished() -> void:
	_in_an_online_match()

	_main._on_match_finished([&"p0"] as Array[StringName])

	assert_does_not_have(_steam.calls, &"mark_finished")
