extends GutTest
## Encoding, decoding, and what a client is told - which is now everything.
##
## These run without a network on purpose. The snapshot is the one thing both
## sides of a match agree on, and it is also what a new host has to rebuild
## the match from when the old one leaves, so what it contains is asserted
## here rather than left to the networked tests.
##
## **The rule these guard is integrity, not secrecy.** Every client sees every
## player's position (decisions.md D105); no client may change one. The first
## half is this file; the second is `host_session.gd` validating every request
## against its own state, tested in test_host_session.gd.


var _library: ContentLibrary


func before_all() -> void:
	_library = ContentLibrary.load_from()


func _state_with_two_players() -> GameState:
	var state: GameState = StalksFixture.make_state(10, 2)
	state.players[0].id = &"p0"
	state.players[1].id = &"p1"
	state.players[0].display_name = "Host"
	state.players[1].display_name = "Guest"
	return state


# ----------------------------------------------------------------- completeness
#
# A snapshot is the whole match. These are the tests that would fail if
# anything started being held back again - and with it, host migration, which
# needs every client to be holding a copy it could carry on from.

func test_a_player_sees_their_own_cash() -> void:
	var state: GameState = _state_with_two_players()
	state.players[0].cash = 7777

	var data: Dictionary = StateSync.encode_state(state)

	assert_eq(data["players"][0].get("cash"), 7777, "own cash should be sent")


## The reversal of what this file used to assert. See decisions.md D105.
func test_a_rivals_whole_position_is_sent() -> void:
	var state: GameState = _state_with_two_players()
	state.players[1].cash = 54321
	state.players[1].set_shares(&"stryker", 40)

	var theirs: Dictionary = StateSync.encode_state(state)["players"][1]

	assert_eq(theirs.get("cash"), 54321, "a rival's cash crosses the wire")
	assert_eq(
		(theirs["holdings"] as Dictionary).get("stryker"),
		40,
		"and the size of their position with it",
	)


func test_a_rivals_loan_schedule_is_sent() -> void:
	var state: GameState = _state_with_two_players()
	var loan: LoanState = StalksFixture.give_loan(state.players[1], 5000)
	loan.missed_payments = 2

	var theirs: Dictionary = StateSync.encode_state(state)["players"][1]
	var sent: Dictionary = theirs["loan"]

	assert_eq(sent.get("balance"), loan.balance)
	assert_eq(sent.get("missed_payments"), 2)


func test_another_players_net_worth_is_sent() -> void:
	# The rankings board exists to show it.
	var state: GameState = _state_with_two_players()
	state.players[1].net_worth = 12345

	assert_eq(StateSync.encode_state(state)["players"][1].get("net_worth"), 12345)


## **The property host migration rests on.** Every client is sent the same
## snapshot, so every client is holding a copy that could become the match. If
## this ever stops being true, `HostSession.take_over` has nothing sound to
## promote.
func test_every_player_is_sent_the_same_snapshot() -> void:
	var state: GameState = _state_with_two_players()
	state.players[0].cash = 1111
	state.players[1].cash = 2222
	state.players[1].set_shares(&"monorail", 6)
	StalksFixture.give_loan(state.players[0], 3000)

	var mine: GameState = _replica_of(state)
	var theirs: GameState = _replica_of(state)

	for index: int in state.players.size():
		assert_eq(mine.players[index].cash, theirs.players[index].cash)
		assert_eq(
			mine.players[index].holdings,
			theirs.players[index].holdings,
			"holdings should not vary by recipient",
		)


func test_a_rivals_position_round_trips_onto_a_client() -> void:
	var state: GameState = _state_with_two_players()
	state.players[1].cash = 808
	state.players[1].set_shares(&"monorail", 3)
	StalksFixture.give_loan(state.players[1], 1500)

	var rival: PlayerState = _replica_of(state).player_by_id(&"p1")

	assert_eq(rival.cash, 808)
	assert_eq(rival.shares_of(&"monorail"), 3)
	assert_not_null(rival.loan, "a rival's loan arrives too")


## The question the board's Investors list asks, answered the same way about
## anybody now that the amounts travel.
func test_a_player_knows_which_stalks_anybody_is_in() -> void:
	var state: GameState = _state_with_two_players()
	state.players[0].set_shares(&"stryker", 10)
	state.players[1].set_shares(&"monorail", 3)

	var seen: GameState = _replica_of(state)

	assert_true(seen.players[0].invests_in(&"stryker"))
	assert_true(seen.players[1].invests_in(&"monorail"))
	assert_false(seen.players[1].invests_in(&"stryker"))


func test_a_rival_sold_out_of_a_stalk_stops_being_an_investor() -> void:
	var state: GameState = _state_with_two_players()
	state.players[1].set_shares(&"stryker", 40)
	state.players[1].set_shares(&"stryker", 0)

	assert_false(_replica_of(state).players[1].invests_in(&"stryker"))


func test_applying_an_entry_overwrites_cash() -> void:
	# The mirror of encode_player: a snapshot is complete, so what it says
	# about a player replaces what the client had.
	var state: GameState = _state_with_two_players()
	var player: PlayerState = state.players[1]
	player.cash = 999

	StateSync.apply_player(
		player, {"id": "p1", "display_name": "Guest", "net_worth": 500, "cash": 42}
	)

	assert_eq(player.cash, 42)
	assert_eq(player.net_worth, 500)


# -------------------------------------------------------------- the random stream
#
# Carried so a new host continues the match instead of re-rolling its past.
# See decisions.md D105.

func test_the_random_streams_position_travels() -> void:
	var state: GameState = _state_with_two_players()

	assert_eq(StateSync.rng_state_of(StateSync.encode_state(state, 9876)), 9876)


func test_a_payload_without_a_stream_position_reads_as_zero() -> void:
	# Only a hand-built payload lacks one; a real snapshot always carries it.
	# Zero is not a reserved value - it is simply the default - so a new host
	# adopts whatever it is given rather than testing for "unset".
	assert_eq(StateSync.rng_state_of({}), 0)


# ------------------------------------------------------------------- round trips

func test_a_snapshot_round_trips_the_market() -> void:
	var state: GameState = _state_with_two_players()
	state.year = 4
	state.stalks[0].price = 123
	state.stalks[0].last_yearly_change = -7
	state.stalks[1].is_bankrupt = true
	state.stalks[2].did_split = true

	var replica: GameState = _replica_of(state)

	assert_eq(replica.year, 4)
	assert_eq(replica.stalks[0].price, 123)
	assert_eq(replica.stalks[0].last_yearly_change, -7)
	assert_true(replica.stalks[1].is_bankrupt)
	assert_true(replica.stalks[2].did_split)


func test_a_snapshot_round_trips_holdings_and_loan() -> void:
	var state: GameState = _state_with_two_players()
	var me: PlayerState = state.players[0]
	me.cash = 4200
	me.set_shares(&"mutuals", 9)
	me.set_shares(&"stryker", 3)
	var loan: LoanState = StalksFixture.give_loan(me, 2000)
	loan.missed_payments = 2

	var replica: GameState = _replica_of(state)
	var mine: PlayerState = replica.player_by_id(&"p0")

	assert_eq(mine.cash, 4200)
	assert_eq(mine.shares_of(&"mutuals"), 9)
	assert_eq(mine.shares_of(&"stryker"), 3)
	assert_not_null(mine.loan, "own loan should arrive")
	assert_eq(mine.loan.balance, loan.balance)
	assert_eq(mine.loan.missed_payments, 2)


func test_settings_arrive_with_the_snapshot() -> void:
	# A client guesses nothing: the year limit and seed come from the host.
	var state: GameState = _state_with_two_players()
	state.settings.max_years = 25
	state.settings.rng_seed = 987654
	state.settings.loans_enabled = true

	var replica: GameState = _replica_of(state)

	assert_eq(replica.settings.max_years, 25)
	assert_eq(replica.settings.rng_seed, 987654)
	assert_true(replica.settings.loans_enabled)


func test_the_multiple_loans_toggle_arrives_with_the_snapshot() -> void:
	# A client's instant loan pre-check runs the host's rule, so it must know it.
	var state: GameState = _state_with_two_players()
	state.settings.multiple_loans_enabled = true
	assert_true(_replica_of(state).settings.multiple_loans_enabled)


func test_sold_out_positions_disappear_from_the_replica() -> void:
	# Holdings are replaced wholesale, not merged, or a sold position would
	# linger on the client's board for the rest of the match.
	var state: GameState = _state_with_two_players()
	state.players[0].set_shares(&"mutuals", 5)
	var replica: GameState = _replica_of(state)
	assert_eq(replica.player_by_id(&"p0").shares_of(&"mutuals"), 5)

	state.players[0].set_shares(&"mutuals", 0)
	StateSync.apply_state(replica, StateSync.encode_state(state), _library)

	assert_eq(replica.player_by_id(&"p0").shares_of(&"mutuals"), 0)
	assert_false(
		replica.player_by_id(&"p0").holdings.has(&"mutuals"),
		"a sold-out position should leave no dead key",
	)


func test_players_adopt_the_hosts_order() -> void:
	# Rankings and the lobby both render in roster order, so the replica must not
	# keep an order of its own.
	var state: GameState = _state_with_two_players()
	var replica: GameState = GameState.new(null)
	replica.stalks = _library.build_stalk_states()
	replica.players = [
		PlayerState.new(&"p1", "Guest", 0),
		PlayerState.new(&"p0", "Host", 0),
	] as Array[PlayerState]

	StateSync.apply_state(replica, StateSync.encode_state(state), _library)

	assert_eq(replica.players[0].id, &"p0")
	assert_eq(replica.players[1].id, &"p1")


# -------------------------------------------------------------- mismatched content

func test_an_unknown_stalk_is_reported_rather_than_ignored() -> void:
	# A host running different content is a real failure. Rendering a short board
	# would hide it; saying so does not.
	var state: GameState = _state_with_two_players()
	var data: Dictionary = StateSync.encode_state(state)
	data["stalks"].append({"id": "not_a_real_stalk", "price": 50})

	var problem: String = StateSync.apply_state(GameState.new(null), data, _library)

	assert_string_contains(problem, "not_a_real_stalk")


func test_a_malformed_snapshot_is_refused() -> void:
	assert_ne(StateSync.apply_state(GameState.new(null), {}, _library), "")


# ------------------------------------------------------------------- year results

func test_a_year_result_round_trips() -> void:
	var state: GameState = StalksFixture.make_state(10, 2)
	var resolver: YearResolver = StalksFixture.real_resolver(_library.stalks)
	var result: YearResult = resolver.advance_year(state, StalksFixture.rng(99))

	var decoded: YearResult = StateSync.decode_year_result(
		StateSync.encode_year_result(result), _library
	)

	assert_eq(decoded.year, result.year)
	assert_eq(decoded.mood, result.mood)
	assert_eq(decoded.is_final_year, result.is_final_year)
	assert_eq(decoded.stalk_changes.size(), result.stalk_changes.size())
	assert_eq(decoded.rankings, result.rankings)
	assert_eq(decoded.net_worths, result.net_worths)
	assert_eq(decoded.dividends, result.dividends)


func test_every_stalk_change_survives_the_wire() -> void:
	var state: GameState = StalksFixture.make_state(10, 1)
	var resolver: YearResolver = StalksFixture.real_resolver(_library.stalks)
	var result: YearResult = resolver.advance_year(state, StalksFixture.rng(7))

	var decoded: YearResult = StateSync.decode_year_result(
		StateSync.encode_year_result(result), _library
	)

	for original: StalkYearChange in result.stalk_changes:
		var copy: StalkYearChange = decoded.change_for(original.stalk_id)
		assert_not_null(copy, "change for %s should survive" % original.stalk_id)
		if copy == null:
			continue
		assert_eq(copy.price_before, original.price_before)
		assert_eq(copy.price_after, original.price_after)
		assert_eq(copy.base_delta, original.base_delta)
		assert_eq(copy.event_delta, original.event_delta)
		assert_eq(copy.did_split, original.did_split)
		assert_eq(copy.went_bankrupt, original.went_bankrupt)


func test_only_the_event_id_travels_and_the_text_is_resolved_locally() -> void:
	var event: SpecialEventDefinition = _library.all_events()[0]
	var result: YearResult = YearResult.new()
	result.event = event

	var data: Dictionary = StateSync.encode_year_result(result)
	assert_eq(data["event_id"], String(event.id))
	assert_false(
		data.has("flavour_text"), "flavour text is content, not state, and stays local"
	)

	var decoded: YearResult = StateSync.decode_year_result(data, _library)
	assert_not_null(decoded.event)
	assert_eq(decoded.event.flavour_text, event.flavour_text)


func test_a_year_with_no_event_round_trips_as_no_event() -> void:
	var decoded: YearResult = StateSync.decode_year_result(
		StateSync.encode_year_result(YearResult.new()), _library
	)
	assert_null(decoded.event)


func test_loan_changes_round_trip() -> void:
	var change: LoanYearChange = LoanYearChange.new()
	change.player_id = &"p0"
	change.balance_before = 5000
	change.penalty_added = 500
	change.interest_added = 300
	change.balance_after = 5800
	change.missed_payments = 2
	change.defaulted = false
	var result: YearResult = YearResult.new()
	result.loan_changes.append(change)

	var decoded: YearResult = StateSync.decode_year_result(
		StateSync.encode_year_result(result), _library
	)
	var copy: LoanYearChange = decoded.loan_change_for(&"p0")

	assert_not_null(copy)
	if copy == null:
		return
	assert_eq(copy.balance_before, 5000)
	assert_eq(copy.penalty_added, 500)
	assert_eq(copy.interest_added, 300)
	assert_eq(copy.balance_after, 5800)
	assert_eq(copy.missed_payments, 2)


# ------------------------------------------------------------------- the wire itself

func test_nothing_but_built_in_types_crosses_the_wire() -> void:
	# Object decoding is disabled on purpose — see StateSync's class docs. If a
	# snapshot ever contains a script object, RPCs will drop it silently, so this
	# walks the whole payload.
	var state: GameState = _state_with_two_players()
	StalksFixture.give_loan(state.players[0], 3000)
	state.players[0].set_shares(&"mutuals", 4)

	assert_eq(
		_objects_in(StateSync.encode_state(state), "state"),
		PackedStringArray(),
		"no part of a snapshot may be an object",
	)


func test_nothing_but_built_in_types_crosses_the_wire_for_a_year() -> void:
	var state: GameState = StalksFixture.make_state(10, 2)
	var resolver: YearResolver = StalksFixture.real_resolver(_library.stalks)
	var result: YearResult = resolver.advance_year(state, StalksFixture.rng(3))

	assert_eq(
		_objects_in(StateSync.encode_year_result(result), "year result"),
		PackedStringArray(),
		"no part of a year result may be an object",
	)


# ---------------------------------------------------------------------- helpers

func _replica_of(state: GameState) -> GameState:
	var replica: GameState = GameState.new(null)
	var problem: String = StateSync.apply_state(
		replica, StateSync.encode_state(state), _library
	)
	assert_eq(problem, "", "snapshot should apply cleanly")
	return replica


## Every path inside `value` that holds an Object. Empty means the payload is
## entirely built-in types and will survive an RPC.
func _objects_in(value: Variant, path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if value is Object:
		found.append(path)
		return found
	if value is Dictionary:
		var entries: Dictionary = value
		for key: Variant in entries:
			found.append_array(_objects_in(key, "%s key" % path))
			found.append_array(_objects_in(entries[key], "%s.%s" % [path, key]))
		return found
	if value is Array:
		var items: Array = value
		for index: int in items.size():
			found.append_array(_objects_in(items[index], "%s[%d]" % [path, index]))
	return found


func test_the_lobbys_privacy_crosses_the_wire() -> void:
	# Not a rule, but a client that showed the wrong thing would be lying
	# about the game it is in.
	var state: GameState = StalksFixture.make_state(10, 2)
	state.settings.invite_only = true
	state.settings.game_name = "Friday night"

	var replica: GameState = GameState.new(null)
	assert_eq(StateSync.apply_state(replica, StateSync.encode_state(state), _library), "")
	assert_true(replica.settings.invite_only)
	assert_eq(replica.settings.game_name, "Friday night")



# ------------------------------------------------------------- the whole record
#
# The year-by-year history, which a snapshot does not carry and a welcome does.
# See decisions.md D118.

func _match_with_two_years_behind_it() -> GameState:
	var state: GameState = _state_with_two_players()
	var resolver: YearResolver = StalksFixture.real_resolver(_library.stalks)
	var rng: RandomNumberGenerator = StalksFixture.rng(7)
	resolver.advance_year(state, rng)
	resolver.advance_year(state, rng)
	return state


func test_a_played_year_lands_in_the_history() -> void:
	# The test below means nothing unless resolving a year records one.
	assert_eq(_match_with_two_years_behind_it().history.size(), 2)


func test_the_whole_history_crosses_the_wire() -> void:
	var state: GameState = _match_with_two_years_behind_it()

	var replica: GameState = GameState.new(null)
	StateSync.apply_history(replica, StateSync.encode_history(state), _library)

	assert_eq(replica.history.size(), 2, "both years should arrive")
	for index: int in state.history.size():
		assert_eq(replica.history[index].year, state.history[index].year)
		assert_eq(replica.history[index].mood, state.history[index].mood)
		assert_eq(
			replica.history[index].net_worths,
			state.history[index].net_worths,
			"the figures the year-by-year page prints",
		)


## **Wholesale, not appended.** A reconnecting client may already hold the years
## it was present for; the host's record is the one that is right, and adding
## to it would print some years twice.
func test_applying_a_history_replaces_whatever_was_there() -> void:
	var state: GameState = _match_with_two_years_behind_it()
	var replica: GameState = GameState.new(null)
	StateSync.apply_history(replica, StateSync.encode_history(state), _library)

	StateSync.apply_history(replica, StateSync.encode_history(state), _library)

	assert_eq(replica.history.size(), 2, "not four")


func test_a_history_that_is_not_a_list_of_years_is_skipped() -> void:
	var replica: GameState = GameState.new(null)

	StateSync.apply_history(replica, [1, "two", null] as Array, _library)

	assert_eq(replica.history.size(), 0)


## A snapshot still carries no history: it goes out on every trade.
func test_a_snapshot_does_not_carry_the_history() -> void:
	var state: GameState = _match_with_two_years_behind_it()

	assert_false(StateSync.encode_state(state).has("history"))
