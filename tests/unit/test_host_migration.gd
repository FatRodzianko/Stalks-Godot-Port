extends GutTest
## Carrying a match on after its host walks out.
##
## **Two halves, and only one of them can be tested here.** Deciding *who*
## takes over is Steam's job and `LobbyMigration`'s (test_lobby_migration.gd).
## This file is the other half: once a player knows they are the new host, can
## they actually continue the match, and can everybody else get back into the
## seat they were playing?
##
## None of it needs a network. `take_over` is handed a GameState - the copy the
## client was already holding - and builds an authority round it, so the
## interesting behaviour is reachable with a stub transport and no peers at
## all. What cannot be tested here is the Steam plumbing that calls it; see
## docs/manual-testing.md.
##
## See docs/decisions.md D105.


const HOST_STEAM: int = 7001
const GUEST_STEAM: int = 7002


var _library: ContentLibrary


func before_all() -> void:
	_library = ContentLibrary.load_from()


## A match two years in, with both players holding something distinctive, as a
## client would be holding it.
func _match_in_progress() -> GameState:
	var state: GameState = StalksFixture.make_state(10, 2)
	state.year = 3
	state.players[0].display_name = "Departed"
	state.players[0].steam_id = HOST_STEAM
	state.players[0].cash = 4321
	state.players[0].set_shares(state.stalks[0].id, 11)
	state.players[1].display_name = "Survivor"
	state.players[1].steam_id = GUEST_STEAM
	state.players[1].cash = 8765
	state.players[1].set_shares(state.stalks[1].id, 7)
	StalksFixture.give_loan(state.players[1], 2000)
	return state


## The surviving player takes over. `p1` is them; `p0` is the host who left.
func _taken_over(state: GameState, rng_state: int = 0) -> HostSession:
	var opened: Dictionary = HostSession.take_over(
		StubTransport.new(), state, _library, &"p1", rng_state
	)
	assert_eq(String(opened["error"]), "", "take-over should succeed")
	var session: HostSession = opened["session"]
	autofree(session)
	return session


# ------------------------------------------------------------- what is carried

## The whole point: the new host's match is the one that was being played, not
## a fresh one.
func test_the_match_carries_on_where_it_stood() -> void:
	var state: GameState = _match_in_progress()
	state.stalks[0].price = 137

	var session: HostSession = _taken_over(state)

	assert_eq(session.state().year, 3, "the same year")
	assert_eq(session.state().stalk_by_id(state.stalks[0].id).price, 137, "the same prices")


## **Everybody's position, not just the new host's.** This is what the complete
## snapshot bought: a client holds every player's real cash and holdings, so
## promoting its copy loses nothing. A redacted copy would have arrived here
## with the departed host's portfolio missing and the survivor's intact.
func test_every_players_position_survives_the_handover() -> void:
	var session: HostSession = _taken_over(_match_in_progress())

	var survivor: PlayerState = session.state().player_by_id(&"p1")
	assert_eq(survivor.cash, 8765)
	assert_eq(survivor.shares_of(session.state().stalks[1].id), 7)
	assert_not_null(survivor.loan, "and their loan")
	assert_eq(survivor.loan.balance, 2000)

	# The departed host is off the active roster, but nothing was thrown away.
	assert_eq(session.display_name_of(&"p0"), "Departed", "still on the roster")


func test_the_new_host_plays_their_own_slot() -> void:
	var session: HostSession = _taken_over(_match_in_progress())

	# Seating happens when the peer is attached; before that the roster is what
	# says which slot is the host's.
	assert_eq(session.roster()[1].id, &"p1")
	assert_false(session.is_vacated(&"p1"), "the new host is in the match")


## **Everybody else starts vacated, on purpose.** Nobody is connected to the
## new host yet, and the year gate counts every active player - so leaving them
## in would hang the match on people who have not had a chance to reconnect.
## Same reasoning as D47.
func test_everybody_else_starts_vacated() -> void:
	var session: HostSession = _taken_over(_match_in_progress())

	assert_true(session.is_vacated(&"p0"), "the departed host")
	assert_eq(session.state().players.size(), 1, "only the new host is active")


func test_the_lobby_is_closed_because_the_match_is_under_way() -> void:
	var session: HostSession = _taken_over(_match_in_progress())

	assert_false(session.lobby_is_open())


func test_a_transport_failure_reaches_the_caller() -> void:
	var transport: StubTransport = StubTransport.new()
	transport.failure = "no socket"

	var opened: Dictionary = HostSession.take_over(
		transport, _match_in_progress(), _library, &"p1", 0
	)

	assert_null(opened["session"])
	assert_string_contains(String(opened["error"]), "no socket")


# ------------------------------------------------------------- the random stream

## **The match must not deal its own past out again.** Seeded afresh from
## `rng_seed`, a new host would replay the rolls the departed one already used
## for years one to three. The stream's position travels in the snapshot so the
## sequence continues instead.
func test_the_random_stream_continues_rather_than_restarting() -> void:
	var state: GameState = _match_in_progress()
	var mid_match: int = 999_000_111

	assert_eq(_taken_over(state, mid_match).rng_state(), mid_match)


## **The position is a number that actually moves**, so the test above is not
## quietly passing against a stream that never advances.
##
## A seed decides where the stream starts; resolving a year moves it on from
## there. Both are ordinary positions - there is no reserved value meaning
## "unset", which is why `take_over` adopts whatever the snapshot carries
## rather than testing it for one.
func test_a_resolved_years_stream_position_is_what_a_new_host_adopts() -> void:
	var state: GameState = _match_in_progress()
	var authority: MatchAuthority = MatchAuthority.new(
		state, StalksFixture.real_resolver(_library.stalks), StalksFixture.rng(4242)
	)
	var at_the_start: int = authority.rng_state()

	authority.advance_year()
	var after_a_year: int = authority.rng_state()

	assert_ne(after_a_year, at_the_start, "resolving a year draws from the stream")
	assert_eq(
		_taken_over(state, after_a_year).rng_state(),
		after_a_year,
		"a new host picks it up exactly where the departed one left it",
	)


# --------------------------------------------------------- reclaiming your seat

## A returning player is recognised by Steam, not by what they say they are.
func test_a_returning_player_is_offered_their_own_slot() -> void:
	var session: HostSession = _taken_over(_match_in_progress())

	assert_eq(session._slot_to_reclaim(GUEST_STEAM), &"p1")
	assert_eq(session._slot_to_reclaim(HOST_STEAM), &"p0")


func test_an_unknown_steam_account_reclaims_nothing() -> void:
	var session: HostSession = _taken_over(_match_in_progress())

	assert_eq(session._slot_to_reclaim(99999), &"")


## **No Steam, no reclaim.** A direct connection has `steam_id` 0 on every
## player, so matching 0 against 0 would hand the first arrival whichever
## vacant slot came first in the roster - including the richest one.
func test_a_connection_with_no_steam_reclaims_nothing() -> void:
	var state: GameState = _match_in_progress()
	state.players[0].steam_id = 0
	state.players[1].steam_id = 0

	assert_eq(_taken_over(state)._slot_to_reclaim(0), &"")


## One Steam account is one player. A second client signed in to the same
## account is not somebody coming back.
func test_a_slot_already_being_played_cannot_be_claimed() -> void:
	var session: HostSession = _taken_over(_match_in_progress())
	session._seat(2, &"p0")

	assert_eq(session._slot_to_reclaim(HOST_STEAM), &"")


func test_reclaiming_a_slot_restores_the_position_that_was_left() -> void:
	var session: HostSession = _taken_over(_match_in_progress())
	assert_true(session.is_vacated(&"p0"), "the test needs them out first")

	session._reclaim_slot(2, &"p0")

	assert_false(session.is_vacated(&"p0"))
	assert_eq(session.state().players.size(), 2, "back in the economy")
	var back: PlayerState = session.state().player_by_id(&"p0")
	assert_eq(back.cash, 4321, "with the cash they left")
	assert_eq(back.shares_of(session.state().stalks[0].id), 11, "and their holdings")


## They were not here for whatever the others readied for, so they do not
## arrive already ready - which would otherwise advance the year the moment
## they reconnected.
func test_a_returning_player_is_not_already_ready() -> void:
	var state: GameState = _match_in_progress()
	state.players[0].is_ready = true
	var session: HostSession = _taken_over(state)

	session._reclaim_slot(2, &"p0")

	assert_false(session.state().player_by_id(&"p0").is_ready)


## Roster order is what the rankings and the lobby draw in, so a player
## returning must not jump to the end of the board.
func test_a_returning_player_keeps_their_place_in_the_order() -> void:
	var session: HostSession = _taken_over(_match_in_progress())

	session._reclaim_slot(2, &"p0")

	assert_eq(session.state().players[0].id, &"p0")
	assert_eq(session.state().players[1].id, &"p1")


# ------------------------------------------------------- who wears the marker
#
# The board puts "(Host)" against one player. Until migration existed that was
# always the first player, because the host never changed. See
# GameState.hosted_by.

## **The fault this guards is invisible with two players.** The survivor is
## alone, so first-in-the-list is them and the marker looks right by accident.
## From three players up it names whoever happens to be left.
func test_the_host_marker_follows_the_match_to_its_new_host() -> void:
	var state: GameState = StalksFixture.make_state(10, 3)
	state.players[0].steam_id = HOST_STEAM
	state.players[1].steam_id = GUEST_STEAM
	state.players[2].steam_id = 7003
	assert_eq(state.host_player_id(), &"p0", "p0 hosts to begin with")

	# p2 takes over, so p1 is the first player still in the match.
	var opened: Dictionary = HostSession.take_over(
		StubTransport.new(), state, _library, &"p2", 0
	)
	var session: HostSession = opened["session"]
	autofree(session)

	assert_eq(session.state().players[0].id, &"p2", "the roster is down to the new host")
	assert_eq(session.state().host_player_id(), &"p2", "and the marker is on them")


## A client's board has to be told, or it would draw the marker from its own
## list and reach the same wrong answer.
func test_the_host_marker_crosses_the_wire() -> void:
	var state: GameState = StalksFixture.make_state(10, 3)
	state.hosted_by = &"p2"

	var replica: GameState = GameState.new(null)
	assert_eq(StateSync.apply_state(replica, StateSync.encode_state(state), _library), "")

	assert_eq(replica.host_player_id(), &"p2")


## A local game names nobody, and the fallback is right by definition.
func test_a_game_with_no_stated_host_still_names_one() -> void:
	var state: GameState = StalksFixture.make_state(10, 2)

	assert_eq(state.hosted_by, &"")
	assert_eq(state.host_player_id(), &"p0")
