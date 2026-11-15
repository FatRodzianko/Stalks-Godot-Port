extends GutTest
## Encoding, decoding, and — most importantly — what a client is NOT told.
##
## These run without a network on purpose. A privacy leak is invisible while
## playing and obvious in a test like this one, so the redaction rules are
## asserted here rather than left to the networked tests.


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


# ---------------------------------------------------------------------- privacy

func test_a_player_sees_their_own_cash() -> void:
	var state: GameState = _state_with_two_players()
	state.players[0].cash = 7777

	var data: Dictionary = StateSync.encode_state(state, &"p0")
	var mine: Dictionary = data["players"][0]

	assert_eq(mine.get("cash"), 7777, "own cash should be sent")


func test_another_players_cash_is_never_sent() -> void:
	var state: GameState = _state_with_two_players()
	state.players[1].cash = 54321

	var data: Dictionary = StateSync.encode_state(state, &"p0")
	var theirs: Dictionary = data["players"][1]

	assert_false(theirs.has("cash"), "a rival's cash must not cross the wire")
	assert_false(theirs.has("holdings"), "a rival's holdings must not cross the wire")
	assert_false(theirs.has("loan"), "a rival's loan schedule must not cross the wire")


func test_another_players_net_worth_is_sent() -> void:
	# Public on purpose: the rankings board exists to show it.
	var state: GameState = _state_with_two_players()
	state.players[1].net_worth = 12345

	var data: Dictionary = StateSync.encode_state(state, &"p0")

	assert_eq(data["players"][1].get("net_worth"), 12345)


func test_whether_a_rival_has_a_loan_is_public_but_not_its_balance() -> void:
	var state: GameState = _state_with_two_players()
	StalksFixture.give_loan(state.players[1], 5000)

	var data: Dictionary = StateSync.encode_state(state, &"p0")
	var theirs: Dictionary = data["players"][1]

	assert_true(theirs.get("has_loan"), "that they borrowed is public")
	assert_false(theirs.has("loan"), "the balance and schedule are not")


func test_every_public_field_is_present_for_a_rival() -> void:
	# Guards the redaction going too far: a rival still has to be renderable.
	var state: GameState = _state_with_two_players()
	var theirs: Dictionary = StateSync.encode_state(state, &"p0")["players"][1]

	for field: String in StateSync.PUBLIC_PLAYER_FIELDS:
		assert_true(theirs.has(field), "public field '%s' should be sent" % field)


func test_applying_a_redacted_entry_leaves_cash_alone() -> void:
	# A client holds no real figure for a rival's cash. Zeroing it would make
	# every rival look broke, so the field is simply not touched.
	var state: GameState = _state_with_two_players()
	var player: PlayerState = state.players[1]
	player.cash = 999

	StateSync.apply_player(player, {"id": "p1", "display_name": "Guest", "net_worth": 500})

	assert_eq(player.cash, 999, "a redacted update must not overwrite cash")
	assert_eq(player.net_worth, 500, "but the public figure should update")


# ------------------------------------------------------------------- round trips

func test_a_snapshot_round_trips_the_market() -> void:
	var state: GameState = _state_with_two_players()
	state.year = 4
	state.stalks[0].price = 123
	state.stalks[0].last_yearly_change = -7
	state.stalks[1].is_bankrupt = true
	state.stalks[2].did_split = true

	var replica: GameState = _replica_of(state, &"p0")

	assert_eq(replica.year, 4)
	assert_eq(replica.stalks[0].price, 123)
	assert_eq(replica.stalks[0].last_yearly_change, -7)
	assert_true(replica.stalks[1].is_bankrupt)
	assert_true(replica.stalks[2].did_split)


func test_a_snapshot_round_trips_own_holdings_and_loan() -> void:
	var state: GameState = _state_with_two_players()
	var me: PlayerState = state.players[0]
	me.cash = 4200
	me.set_shares(&"mutuals", 9)
	me.set_shares(&"stryker", 3)
	var loan: LoanState = StalksFixture.give_loan(me, 2000)
	loan.missed_payments = 2

	var replica: GameState = _replica_of(state, &"p0")
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

	var replica: GameState = _replica_of(state, &"p0")

	assert_eq(replica.settings.max_years, 25)
	assert_eq(replica.settings.rng_seed, 987654)
	assert_true(replica.settings.loans_enabled)


func test_sold_out_positions_disappear_from_the_replica() -> void:
	# Holdings are replaced wholesale, not merged, or a sold position would
	# linger on the client's board for the rest of the match.
	var state: GameState = _state_with_two_players()
	state.players[0].set_shares(&"mutuals", 5)
	var replica: GameState = _replica_of(state, &"p0")
	assert_eq(replica.player_by_id(&"p0").shares_of(&"mutuals"), 5)

	state.players[0].set_shares(&"mutuals", 0)
	StateSync.apply_state(replica, StateSync.encode_state(state, &"p0"), _library)

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

	StateSync.apply_state(replica, StateSync.encode_state(state, &"p0"), _library)

	assert_eq(replica.players[0].id, &"p0")
	assert_eq(replica.players[1].id, &"p1")


# -------------------------------------------------------------- mismatched content

func test_an_unknown_stalk_is_reported_rather_than_ignored() -> void:
	# A host running different content is a real failure. Rendering a short board
	# would hide it; saying so does not.
	var state: GameState = _state_with_two_players()
	var data: Dictionary = StateSync.encode_state(state, &"p0")
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
		_objects_in(StateSync.encode_state(state, &"p0"), "state"),
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

func _replica_of(state: GameState, for_player: StringName) -> GameState:
	var replica: GameState = GameState.new(null)
	var problem: String = StateSync.apply_state(
		replica, StateSync.encode_state(state, for_player), _library
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
