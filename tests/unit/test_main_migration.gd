extends GutTest
## What `Main` does when it is told the host has gone.
##
## **This is the file that should have existed first.** `test_lobby_migration`
## covers the decision - who takes over - and `test_host_migration` covers
## continuing a match from a client's copy. Both passed throughout three
## successive faults reported from play, because every one of them was in the
## orchestration between those two pieces: noticing, waiting, tearing down,
## retrying, and the order of it. That code never calls the Steam API. It only
## acts on answers that come from it, and those are faked here
## (`StubSteamService`).
##
## What is still out of reach is the transport: there is no Steam plugin in a
## test run, so a session that would really be built cannot be. Each test below
## therefore stops at the decision it is about. See decisions.md D108 and
## docs/testing.md.


const ME: int = 9001
const DEPARTED: int = 9002
const SOMEBODY: int = 9003
const LOBBY: int = 4242

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")


var _main: Main
var _steam: StubSteamService
var _transports: StubTransportSource


func before_each() -> void:
	_main = MainScene.instantiate()
	add_child_autofree(_main)

	_steam = StubSteamService.new()
	_steam.name = "StubSteam"
	_steam.me = ME
	_steam.lobby = LOBBY
	_main.add_child(_steam)
	_main._steam = _steam

	# Never the real one: an uninitialised Steam API takes the process down
	# rather than returning an error. See `SteamTransportSource`.
	_transports = StubTransportSource.new()
	_main._steam_transports = _transports

	# A client in a lobby hosted by the player who is about to leave.
	_main._session = _joined_client()
	_main.add_child(_main._session)
	_main._online_host_steam_id = DEPARTED


func after_each() -> void:
	# A session built during a test sets a peer on the tree's own
	# MultiplayerAPI. Left there it would reach the next test.
	if _main != null and _main._session != null:
		_main._discard_session(true)


## A client session that believes it is connected, because it is: it joined the
## host that is about to walk out.
func _joined_client() -> ClientSession:
	var session: ClientSession = ClientSession.new()
	session.name = NetworkedSession.NODE_NAME
	session._state = StalksFixture.make_state(10, 2)
	session._state.settings.game_name = "Friday night"
	session._local_player_id = &"p1"
	session._has_joined = true
	return session


## One turn of the migration clock, long enough to reach a poll.
func _tick() -> void:
	_main._process(Main.MIGRATION_POLL_SECONDS + 0.01)


func _host_leaves() -> void:
	_main._on_steam_lobby_member_left(DEPARTED)


# ----------------------------------------------------------------- noticing it

func test_the_host_leaving_starts_a_migration() -> void:
	_host_leaves()

	assert_not_null(_main._migration, "a migration should be under way")


func test_somebody_else_leaving_is_not_a_migration() -> void:
	_main._on_steam_lobby_member_left(SOMEBODY)

	assert_null(_main._migration, "only the host leaving matters")


## Without a Steam lobby there is nothing to hand on, so it ends as it always
## did rather than waiting twenty seconds for an answer that cannot come.
func test_a_game_with_no_steam_lobby_does_not_try_to_migrate() -> void:
	_steam.lobby = 0

	_host_leaves()

	assert_null(_main._migration)


# -------------------------------------------------------------- D108, the fault

## **The bug that shipped: a migration that ended before it began.**
##
## The session still mounted when the host leaves is a client that has joined -
## it joined the host who just left. The reconnect check asked "is the client
## connected?" and got yes on the very first poll, so the migration declared
## success and stopped. In play that looked like no migration at all: the lobby
## kept showing the departed player as host until the dead connection timed
## out, and anybody trying to rejoin sat on "connecting" because nobody had
## taken over.
func test_the_session_the_departed_host_left_is_not_mistaken_for_success() -> void:
	_host_leaves()
	assert_true(
		(_main._session as ClientSession).has_joined(),
		"the test means nothing unless the stale session claims to be connected",
	)

	_tick()

	assert_not_null(_main._migration, "the migration must still be looking for a host")


## Steam has not named an owner yet, which it does not for a moment or two.
func test_it_keeps_waiting_while_steam_has_not_decided() -> void:
	_steam.owner_steam_id = 0
	_host_leaves()

	_tick()
	_tick()

	assert_not_null(_main._migration)
	assert_lt(_main._hosting_in, 0.0, "and it is not hosting yet")


## Steam naming the departed player is Steam not having noticed yet.
func test_steam_still_naming_the_departed_host_is_not_an_answer() -> void:
	_steam.owner_steam_id = DEPARTED
	_host_leaves()

	_tick()

	assert_not_null(_main._migration)
	assert_lt(_main._hosting_in, 0.0)


# ------------------------------------------------------------ being made the host

## The old connection goes first and the listen socket follows a moment later,
## never in the same frame - see D107, and `NEW_HOST_START_SECONDS`.
func test_being_made_the_owner_tears_the_old_session_down_and_waits() -> void:
	_steam.owner_steam_id = ME
	_host_leaves()

	_tick()

	assert_null(_main._session, "the old connection should be gone")
	assert_gt(_main._hosting_in, 0.0, "and hosting should be a moment away")


## It is the lobby being taken over, so this process stays in it. Leaving would
## be leaving the game it is trying to rescue.
func test_standing_down_to_host_stays_in_the_steam_lobby() -> void:
	_steam.owner_steam_id = ME
	_host_leaves()

	_tick()

	assert_false(_steam.calls.has(&"leave"), "it must not leave the lobby")
	assert_false(_steam.calls.has(&"leave_as_host"))


# --------------------------------------------------------- following somebody else

## One attempt is not enough (D107): every poll makes another until one lands.
func test_being_told_somebody_else_hosts_makes_an_attempt() -> void:
	_steam.owner_steam_id = SOMEBODY
	_host_leaves()

	_tick()

	assert_true(_main._reconnect_attempted, "it should have tried to reconnect")
	assert_not_null(_main._migration, "and be ready to try again")


## An attempt that fails is not the end of it. There is no Steam plugin in a
## test run, so every attempt here fails at the transport - which makes this
## the easiest place to assert that failing is survivable.
func test_a_failed_attempt_does_not_end_the_migration() -> void:
	_steam.owner_steam_id = SOMEBODY
	_host_leaves()

	_tick()
	_tick()
	_tick()

	assert_not_null(_main._migration, "still trying")


func test_an_attempt_keeps_this_process_in_the_steam_lobby() -> void:
	_steam.owner_steam_id = SOMEBODY
	_host_leaves()

	_tick()

	assert_false(
		_steam.calls.has(&"leave"),
		"the lobby is where the new host is, not something to leave",
	)


# -------------------------------------------------------------------- giving up

## The lobby may simply be gone. Twenty seconds, then the player is told,
## rather than waiting for ever (D68, D104).
func test_it_gives_up_after_the_deadline() -> void:
	_steam.owner_steam_id = 0
	_host_leaves()

	_main._process(LobbyMigration.GIVE_UP_SECONDS + 1.0)

	assert_null(_main._migration, "the migration should be over")


## While a migration is running the session's own notice that the connection
## died must not reach the player: it is the same departure, arriving twice,
## and acting on the second drops them onto the title screen mid-rescue.
func test_the_dying_connection_does_not_cancel_the_migration() -> void:
	_host_leaves()

	_main._on_connection_ended("The host closed the game.")

	assert_not_null(_main._migration, "the migration should survive it")


# ------------------------------------------------ taking a lobby over, in full
#
# These run the whole sequence: noticing, standing down, the pause, and
# hosting. They are reachable only because the transport is a seam
# (`SteamTransportSource`) - the real one crashes a test run.

## Stands down and then hosts, which takes two turns of the clock by design.
func _take_the_lobby_over() -> void:
	_steam.owner_steam_id = ME
	_host_leaves()
	_tick()
	_tick()


func test_taking_over_a_lobby_ends_with_this_process_hosting() -> void:
	_take_the_lobby_over()

	assert_true(_main._session is HostSession, "it should be the host now")
	assert_null(_main._migration, "and the migration should be over")


## **The fault reported from play as "the lobby isn't in the list".** The
## player who left shut the lobby down on their way out, so whoever takes it
## over has to advertise it again. See decisions.md D106.
func test_taking_over_a_lobby_puts_it_back_in_the_browser() -> void:
	_take_the_lobby_over()

	assert_true(_steam.calls.has(&"reopen"), "the lobby should be advertised again")
	assert_false(_steam.calls.has(&"hide"), "a lobby that has not started is not hidden")


## **The fault reported from play as "the lobby is just called LOBBY".** The
## settings come from the copy of the match this client was already holding,
## so the game keeps the name the player who left gave it.
func test_the_lobbys_name_survives_the_handover() -> void:
	_take_the_lobby_over()

	assert_eq(_main._session.state().settings.game_name, "Friday night")


## A match under way goes the other way: unlisted, because it cannot be
## joined fresh, but still reachable by somebody coming back for their seat.
func test_taking_over_a_match_hides_it_from_the_browser_instead() -> void:
	_steam.owner_steam_id = ME
	_host_leaves()
	# Standing in for the playing screen being up, which is all `Main` reads.
	_main._migrating_in_match = true
	_tick()
	_tick()

	assert_true(_steam.calls.has(&"hide"), "a match under way is not advertised")
	assert_false(_steam.calls.has(&"reopen"))


## The transport failing is a normal outcome, not a crash: the player is told
## and put back on the menu.
func test_a_transport_that_will_not_open_gives_up_cleanly() -> void:
	_transports.failure = "no socket"

	_take_the_lobby_over()

	assert_null(_main._migration, "the migration should be over")
	assert_false(_main._session is HostSession, "and nothing should be hosting")


## A lobby that somehow arrived unnamed gets a name rather than the lobby
## screen's last resort, which is the bare word "LOBBY".
##
## This is a guard, not a reproduction: the name reported as lost in play came
## back as "LOBBY" because nothing had migrated at all (D108), and a handover
## carries the name across (the test above). This stops the *other* way of
## getting there.
func test_an_unnamed_lobby_is_given_a_name_rather_than_headed_LOBBY() -> void:
	_main._session.state().settings.game_name = ""

	_take_the_lobby_over()

	assert_ne(
		_main._session.state().settings.game_name.strip_edges(),
		"",
		"the new host should name the match",
	)
