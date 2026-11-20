extends GutTest
## Playing again with the same people: the host reopens the lobby, and whoever
## wants another game comes back to it.
##
## **Driven over a real socket**, like `test_networked_session.gd`, because the
## whole of this feature is a conversation between two peers — an offer going
## out, a seat coming back — and a host tested on its own would prove only that
## it set its own fields. The two faults most worth catching here are both
## invisible to a one-sided test: a seat that loses its Steam ID, and a peer map
## that still points at the finished match.
##
## See docs/decisions.md D124.


const ResultScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")
const BoardScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")

const HOST_ACCOUNT: int = 7001
const GUEST_ACCOUNT: int = 7002

var _harness: NetHarness
var _library: ContentLibrary


func before_each() -> void:
	_library = ContentLibrary.load_from()
	assert_true(_library.is_valid(), "content must load before networking can be tested")


func after_each() -> void:
	if _harness != null:
		_harness.queue_free()
		_harness = null


## A finished two-player match, both peers connected, with the result screen's
## worth of state in place.
##
## The match is ended by setting the flag rather than by playing the years out:
## what is under test is what happens afterwards, and `is_over` is the only part
## of "finished" any of it reads.
func _finished_match() -> bool:
	_harness = NetHarness.new()
	add_child(_harness)
	var problem: String = _harness.start(
		StalksFixture.make_settings(), _library, "Host", "Guest",
		HOST_ACCOUNT, GUEST_ACCOUNT,
	)
	assert_eq(problem, "", "harness should start")
	if not problem.is_empty():
		return false
	if not await _harness.await_join(self):
		assert_true(false, "the client should have joined")
		return false
	await _harness.begin_match(self)

	# Ended on the host **and broadcast**, so the client's replica agrees. Set
	# on the host alone it would not: the client would still hold a match at
	# year 0 that nobody had told it was finished, and any screen driven from
	# that replica would render a game still in progress.
	var finished: GameState = _harness.host.state()
	finished.year = finished.settings.max_years
	finished.is_over = true
	_harness.host._broadcast_state(&"")
	await _harness.settle(self, 6)
	return true


## The host offers, the client takes it up, and both ends settle.
func _rematch_begun() -> bool:
	if not await _finished_match():
		return false
	_harness.host.offer_rematch()
	await _harness.settle(self, 10)
	_harness.client.join_rematch()
	await _harness.settle(self, 10)
	return true


# ----------------------------------------------------------------- the offer

func test_a_rematch_can_only_be_offered_once_the_match_is_over() -> void:
	if not await _finished_match():
		return

	assert_true(_harness.host.can_offer_rematch(), "a finished match may be played again")

	_harness.host.state().is_over = false
	assert_false(
		_harness.host.can_offer_rematch(),
		"a match still being played is not something to offer a rematch of",
	)


func test_offering_reopens_the_lobby() -> void:
	if not await _finished_match():
		return

	_harness.host.offer_rematch()

	assert_true(_harness.host.lobby_is_open(), "the lobby should be open again")
	assert_false(_harness.host.state().is_over, "and the new match has not been played")
	assert_eq(_harness.host.state().year, 0, "it starts at year 0 like any match")


## **A new market, not the one everybody just played.** `build_authority` writes
## the chosen seed back into the settings, so a finished match's settings carry
## a concrete number; reusing them would deal the same years out again.
func test_a_rematch_gets_a_new_seed() -> void:
	if not await _finished_match():
		return
	var before: int = _harness.host.state().settings.rng_seed
	assert_ne(before, 0, "the test needs the finished match to have a seed")

	_harness.host.offer_rematch()

	assert_ne(_harness.host.state().settings.rng_seed, before, "a rematch is a new market")
	assert_ne(_harness.host.state().settings.rng_seed, 0, "and it is a real seed")


func test_the_settings_otherwise_carry_over() -> void:
	if not await _finished_match():
		return
	var years: int = _harness.host.state().settings.max_years

	_harness.host.offer_rematch()

	assert_eq(
		_harness.host.state().settings.max_years, years,
		"a rematch is the same game again, not a differently configured one",
	)


func test_offering_twice_does_nothing_the_second_time() -> void:
	if not await _finished_match():
		return
	_harness.host.offer_rematch()
	var seed_value: int = _harness.host.state().settings.rng_seed

	_harness.host.offer_rematch()

	assert_eq(
		_harness.host.state().settings.rng_seed, seed_value,
		"a second press must not throw the lobby people are sitting in away",
	)


## The host is seated by the reset, with its own identity, and the board's host
## marker moves with it.
func test_the_host_is_seated_in_its_own_rematch() -> void:
	if not await _finished_match():
		return

	_harness.host.offer_rematch()

	var seats: Array[PlayerState] = _harness.host.state().players
	assert_eq(seats.size(), 1, "only the host is seated until somebody else joins")
	assert_eq(_harness.host.local_player_id(), seats[0].id, "the host plays that seat")
	assert_eq(seats[0].display_name, "Host", "with the name it was playing under")
	assert_eq(seats[0].steam_id, HOST_ACCOUNT, "and the account it was playing as")
	assert_eq(_harness.host.state().hosted_by, seats[0].id, "the host marker moves too")


func test_a_client_is_told_a_rematch_is_on_offer() -> void:
	if not await _finished_match():
		return
	assert_false(_harness.client.rematch_is_offered(), "nothing is on offer yet")

	_harness.host.offer_rematch()
	await _harness.settle(self, 10)

	assert_true(_harness.client.rematch_is_offered())


# ------------------------------------------------------------- taking a seat

func test_joining_a_rematch_seats_the_client() -> void:
	if not await _rematch_begun():
		return

	assert_eq(
		_harness.host.state().players.size(), 2,
		"both players should be in the new lobby",
	)
	assert_true(_harness.client.has_joined())


## **The fault this test exists for.** The seats are rebuilt, and a seat built
## without its Steam ID cannot be reclaimed — so a rematch would silently lose
## reconnecting, REJOIN GAME and the seat-matching half of host migration, all
## at once and only in a rematch.
func test_a_rejoined_seat_keeps_its_name_and_account() -> void:
	if not await _rematch_begun():
		return

	var guest: PlayerState = _harness.host.state().players[1]
	assert_eq(guest.display_name, "Guest", "the name is taken from the finished match")
	assert_eq(
		guest.steam_id, GUEST_ACCOUNT,
		"and so is the account, or nobody could ever reconnect to this match",
	)


## **The other fault this test exists for.** `local_player_id()` *is*
## `_player_by_peer[HOST_PEER_ID]`, and every request is resolved through
## `_require_player`, so a peer map left pointing at the finished match does not
## fail loudly — it makes every button answer nothing.
func test_both_ends_can_act_immediately_after_a_rematch() -> void:
	if not await _rematch_begun():
		return
	await _harness.begin_match(self)
	_harness.host.set_ready(_harness.host.local_player_id(), true)
	_harness.client.set_ready(_harness.client.local_player_id(), true)
	await _harness.settle(self, 10)

	assert_eq(_harness.host.state().year, 1, "the first year should have resolved")

	var stalk_id: StringName = _harness.host.state().stalks[0].id
	_harness.client.request_buy(_harness.client.local_player_id(), stalk_id, 1)
	await _harness.settle(self, 10)

	var guest: PlayerState = _harness.host.state().player_by_id(&"p1")
	assert_eq(guest.shares_of(stalk_id), 1, "the client's buy should have been applied")


func test_a_rematch_starts_everybody_from_the_same_cash() -> void:
	if not await _rematch_begun():
		return

	var starting: int = _harness.host.state().settings.starting_cash
	for player: PlayerState in _harness.host.state().players:
		assert_eq(player.cash, starting, "%s should start level" % player.display_name)
		assert_eq(player.holdings.size(), 0, "holding nothing")
		assert_null(player.loan, "and owing nothing")


## The year-by-year belongs to the match it happened in. `apply_history` clears
## before it appends, so an empty history in the welcome is what empties it —
## which D118 bought without knowing it.
func test_a_rematch_does_not_inherit_the_old_year_by_year() -> void:
	if not await _rematch_begun():
		return

	assert_eq(_harness.host.state().history.size(), 0, "the host starts a fresh record")
	assert_eq(_harness.client.state().history.size(), 0, "and so does the client")


# --------------------------------------------------- the people who do not join

## **Nobody is waited on.** The new roster is built from arrivals, so a player
## who never answers is not in it — which is why this needs no timeout, no vote
## and no way to kick somebody off the result screen. D48 did the work.
func test_a_player_who_never_joins_is_not_in_the_rematch() -> void:
	if not await _finished_match():
		return

	_harness.host.offer_rematch()
	await _harness.settle(self, 10)

	assert_eq(_harness.host.state().players.size(), 1, "only the host is in it")
	assert_eq(
		_harness.host.why_not_start(), "",
		"and the host is not held up by somebody still reading the standings",
	)


## They are told it went ahead, so their own way in stops looking open. The
## broadcast reaches them because `start_match` sends to every peer, seated or
## not.
func test_a_player_who_never_joined_is_told_it_started_without_them() -> void:
	if not await _finished_match():
		return
	_harness.host.offer_rematch()
	await _harness.settle(self, 10)
	assert_true(_harness.client.rematch_is_offered(), "the test needs the offer to land")

	_harness.host.start_match()
	await _harness.settle(self, 10)

	assert_false(
		_harness.client.rematch_is_offered(),
		"an offer that has been started is not an offer any more",
	)


# ------------------------------------------------------------------ the asking

func test_a_client_can_ask_the_host_for_another_game() -> void:
	if not await _finished_match():
		return

	_harness.client.ask_for_rematch()
	await _harness.settle(self, 10)

	var asked: PackedStringArray = _harness.host.rematch_asked_for_by()
	assert_eq(asked.size(), 1, "the host should know somebody asked")
	assert_eq(asked[0], "Guest", "and who")


func test_asking_twice_names_them_once() -> void:
	if not await _finished_match():
		return

	_harness.client.ask_for_rematch()
	await _harness.settle(self, 6)
	_harness.client.ask_for_rematch()
	await _harness.settle(self, 6)

	assert_eq(_harness.host.rematch_asked_for_by().size(), 1)


## **Asking decides nothing.** It is there so the host knows somebody is
## waiting; the host is under no obligation, and no gate anywhere reads it.
func test_asking_does_not_start_anything() -> void:
	if not await _finished_match():
		return

	_harness.client.ask_for_rematch()
	await _harness.settle(self, 10)

	assert_false(_harness.host.lobby_is_open(), "an ask must not reopen the lobby")
	assert_true(_harness.host.state().is_over, "nor restart the match")


func test_the_asks_are_forgotten_once_a_rematch_is_offered() -> void:
	if not await _finished_match():
		return
	_harness.client.ask_for_rematch()
	await _harness.settle(self, 10)

	_harness.host.offer_rematch()

	assert_eq(
		_harness.host.rematch_asked_for_by().size(), 0,
		"the ask has been answered; leaving it up would ask again for ever",
	)


func test_an_ask_from_somebody_who_leaves_is_withdrawn() -> void:
	if not await _finished_match():
		return
	_harness.client.ask_for_rematch()
	await _harness.settle(self, 10)
	assert_eq(_harness.host.rematch_asked_for_by().size(), 1, "the test needs the ask")

	if not await _harness.drop_client(self):
		return

	assert_eq(
		_harness.host.rematch_asked_for_by().size(), 0,
		"an ask from somebody who has gone is not an ask",
	)


# ------------------------------------------------------------ saying it out loud

## **A button quietly changing its label is not news.** A player reading the
## standings is not watching the buttons, and the host going back to the lobby
## is the moment the game starts waiting on them. Reported from play on
## 2026-11-20, after the rest of this worked.
func test_a_client_is_told_in_words_that_the_host_wants_another_game() -> void:
	if not await _finished_match():
		return
	var screen: GameOverScreen = _result_screen_for(_harness.client)
	assert_eq(screen.rematch_note_for_testing(), "", "nothing to say yet")

	_harness.host.offer_rematch()
	await _harness.settle(self, 10)
	screen._refresh_rematch()

	assert_ne(
		screen.rematch_note_for_testing(), "",
		"the offer should be said, not only shown as a button",
	)


## The host's side of the same line, which came first: who has asked.
func test_the_host_is_told_who_asked() -> void:
	if not await _finished_match():
		return
	var screen: GameOverScreen = _result_screen_for(_harness.host)
	assert_eq(screen.rematch_note_for_testing(), "", "nobody has asked yet")

	_harness.client.ask_for_rematch()
	await _harness.settle(self, 10)

	assert_true(
		screen.rematch_note_for_testing().contains("Guest"),
		"the host should be told who wants another game",
	)


## A result screen wired to one end of the harness, in the tree so its
## `@onready` nodes exist.
func _result_screen_for(session: GameSession) -> GameOverScreen:
	var screen: GameOverScreen = ResultScene.instantiate()
	screen.setup(session)
	add_child_autofree(screen)
	screen.display(session.state(), session.local_player_id())
	return screen

## **And the final board shows it too.** A player who pressed View board to
## look the market over is still in the finished match, and would otherwise be
## the one person never told that a rematch is on offer. The bottom bar carries
## it on the line that already says the game is over - two lines is all that bar
## reserves (D63).
func test_the_final_board_carries_the_rematch_news() -> void:
	if not await _finished_match():
		return
	var board: GameplayScreen = BoardScene.instantiate()
	board.setup(_harness.client)
	add_child_autofree(board)
	board.show_as_final_board()
	assert_false(
		board.info_text_for_testing().contains("lobby"),
		"nothing to say before the host offers",
	)

	_harness.host.offer_rematch()
	await _harness.settle(self, 10)

	assert_true(
		board.info_text_for_testing().contains("lobby"),
		"the board should say the host has gone back to the lobby",
	)
	assert_true(
		board.info_text_for_testing().contains("over"),
		"without losing the line saying the match has ended",
	)
