extends GutTest
## StalkleHeads phase S6: a match over the wire (docs/stalkleheads-design.md §9,
## §11 S6; decisions.md D176-D178).
##
## **The one property everything here is a case of:** a client's copy of a
## StalkleHeads match, built from what the host sent, is the host's match -
## every company field, every derived readout, every year's result - to the
## last bit of every float. Compared as lines of text (`WireMatch`), so a
## failure names the field that parted.
##
## The cases are the ways a copy is made:
##
## - **every snapshot** in a long match, applied to a fresh replica that loaded
##   only the base game's content, as a joining client does;
## - **every live year**, replayed from the replica's market before the year;
## - **a whole history**, replayed from year 0 on a player who was not there;
## - **a host migration**, where the replica becomes the host and the match must
##   go on to make exactly the years the departed host would have made;
## - **over ENet**, through the real sessions, to prove the order a client
##   applies things in.
##
## And the refusals: content that does not match, and blocks that are short or
## point outside what they index.


const SEEDS: Array[int] = [11, 4242, 90210]
const YEARS: int = 60


# ------------------------------------------------------------------ helpers

func _client_library() -> ContentLibrary:
	# A joining client loads the base game's content and learns the mode from
	# the first snapshot (decisions.md D171), so the tests do the same.
	return ContentLibrary.load_from()


## A fresh replica holding the host's match as a welcome would leave it.
func _welcomed(host: GameState, library: ContentLibrary) -> GameState:
	var replica: GameState = GameState.new(GameSettings.new())
	assert_eq(StateSync.apply_state(replica, StateSync.encode_state(host, 0), library), "")
	assert_eq(StateSync.apply_history(replica, StateSync.encode_history(host), library), "")
	return replica


func _assert_same(host: PackedStringArray, replica: PackedStringArray, what: String) -> bool:
	var difference: String = WireMatch.first_difference(host, replica)
	assert_eq(difference, "", what)
	return difference.is_empty()


# ------------------------------------------------------------ the snapshot

## Every year of three long matches, a snapshot onto a fresh replica, which
## must hold the host's market exactly - derived readouts included. This is the
## test of `CompanyState.derive_readouts` against `reprice`.
func test_every_snapshot_rebuilds_the_hosts_market_exactly() -> void:
	var splits: int = 0
	var failures: int = 0
	for seed_value: int in SEEDS:
		var played: WireMatch = WireMatch.start(seed_value)
		for _year: int in YEARS:
			var replica: GameState = GameState.new(GameSettings.new())
			assert_eq(
				StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), _client_library()), ""
			)
			if not _assert_same(
				WireMatch.state_lines(played.state), WireMatch.state_lines(replica),
				"seed %d year %d" % [seed_value, played.state.year],
			):
				return
			if played.state.is_over:
				break
			var result: EarningsYearResult = WireMatch.play_year(played.authority)
			for change: StalkYearChange in result.stalk_changes:
				splits += int(change.did_split)
				failures += int(change.went_bankrupt)
	# The comparison only means something if the matches split and failed
	# companies, which are where a derivation could go wrong.
	assert_gt(splits, 0, "the matches should include splits")
	assert_gt(failures, 0, "and bankruptcies")


## Year 0, before any earnings season, is the profiles' own figures; a replica
## that derived them instead would be a float's width out.
func test_a_year_zero_snapshot_is_the_profiles_market() -> void:
	var played: WireMatch = WireMatch.start(4242)
	var replica: GameState = GameState.new(GameSettings.new())
	StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), _client_library())

	_assert_same(WireMatch.state_lines(played.state), WireMatch.state_lines(replica), "year 0")


## A replica already holding a market gets it overwritten, not merged.
func test_a_snapshot_overwrites_a_replica_that_already_has_a_market() -> void:
	var played: WireMatch = WireMatch.start(11)
	var replica: GameState = _welcomed(played.state, _client_library())
	played.play(12)

	StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), _client_library())

	_assert_same(WireMatch.state_lines(played.state), WireMatch.state_lines(replica), "year 12")


# ---------------------------------------------------------- the live year

## A client present for the whole match: each year arrives as its inputs, is
## replayed from the replica's market before the year, and then the snapshot
## lands. The replayed result must be the host's result, ledgers and all.
func test_every_live_year_replays_to_the_hosts_result() -> void:
	var library: ContentLibrary = _client_library()
	for seed_value: int in SEEDS:
		var played: WireMatch = WireMatch.start(seed_value)
		var replica: GameState = _welcomed(played.state, library)
		for _year: int in YEARS:
			if played.state.is_over:
				break
			var result: EarningsYearResult = WireMatch.play_year(played.authority)
			var data: Dictionary = StateSync.encode_year_result(result, played.state)
			var replayed: YearResult = StateSync.decode_live_year(replica, data, library)
			assert_not_null(replayed)
			StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), library)
			if not _assert_same(
				WireMatch.result_lines(result), WireMatch.result_lines(replayed),
				"seed %d year %d result" % [seed_value, result.year],
			):
				return
			if not _assert_same(
				WireMatch.state_lines(played.state), WireMatch.state_lines(replica),
				"seed %d year %d state" % [seed_value, result.year],
			):
				return


## The year record carries inputs, not outcomes: no row changes and no mood.
func test_a_year_travels_as_its_inputs() -> void:
	var played: WireMatch = WireMatch.start(4242)
	var result: EarningsYearResult = WireMatch.play_year(played.authority)

	var data: Dictionary = StateSync.encode_year_result(result, played.state)

	assert_false(data.has("stalk_changes"), "the changes are the replay's to rebuild")
	assert_false(data.has("mood"), "and so is the mood")
	assert_true(data["inputs"] is PackedInt32Array, "the inputs are one packed block")


# ---------------------------------------------------------------- rejoining

## A player who was not there: the whole record, replayed from year 0, must be
## the host's record year for year.
func test_a_welcomed_history_is_the_hosts_year_for_year() -> void:
	for seed_value: int in SEEDS:
		var played: WireMatch = WireMatch.start(seed_value)
		played.play(YEARS)

		var replica: GameState = _welcomed(played.state, _client_library())

		assert_eq(replica.history.size(), played.state.history.size())
		for index: int in played.state.history.size():
			if not _assert_same(
				WireMatch.result_lines(played.state.history[index]),
				WireMatch.result_lines(replica.history[index]),
				"seed %d history year %d" % [seed_value, index + 1],
			):
				return


## A rejoining player and one who never left end up holding the same match.
func test_a_rejoiner_holds_the_same_match_as_a_player_who_stayed() -> void:
	var library: ContentLibrary = _client_library()
	var played: WireMatch = WireMatch.start(90210)
	var stayed: GameState = _welcomed(played.state, library)
	for _year: int in 25:
		var result: EarningsYearResult = WireMatch.play_year(played.authority)
		var replayed: YearResult = StateSync.decode_live_year(
			stayed, StateSync.encode_year_result(result, played.state), library
		)
		StateSync.apply_state(stayed, StateSync.encode_state(played.state, 0), library)
		stayed.history.append(replayed)

	var rejoined: GameState = _welcomed(played.state, library)

	_assert_same(WireMatch.state_lines(stayed), WireMatch.state_lines(rejoined), "state")
	for index: int in stayed.history.size():
		_assert_same(
			WireMatch.result_lines(stayed.history[index]),
			WireMatch.result_lines(rejoined.history[index]),
			"year %d" % (index + 1),
		)


# --------------------------------------------------------------- migration

## **The round trip that matters.** The host plays ten years; a client welcomed
## then becomes the host; both go on with the same trades. Every year after the
## handover must be the year the departed host would have made - prices, desk,
## events, players, the lot.
func test_a_promoted_host_makes_the_years_the_old_host_would_have() -> void:
	for seed_value: int in SEEDS:
		var played: WireMatch = WireMatch.start(seed_value)
		played.play(10)
		var replica: GameState = _welcomed(played.state, _client_library())

		var promoted: MatchAuthority = _take_over(replica, played.authority.rng_state())

		for _year: int in 30:
			if played.state.is_over:
				break
			var expected: EarningsYearResult = WireMatch.play_year(played.authority)
			var actual: EarningsYearResult = WireMatch.play_year(promoted)
			if not _assert_same(
				WireMatch.result_lines(expected), WireMatch.result_lines(actual),
				"seed %d year %d result" % [seed_value, expected.year],
			):
				return
			# Presence is left out: a new host marks everybody but itself away
			# until they reconnect, on purpose (D105).
			if not _assert_same(
				WireMatch.state_lines(played.state, false), WireMatch.state_lines(promoted.state, false),
				"seed %d year %d state" % [seed_value, expected.year],
			):
				return


## Why the event bags travel (D177). Without them a promoted host deals its
## events from freshly shuffled bags, and sooner or later the year it makes is
## not the year the old host would have made. This is that fault, put back.
func test_without_the_bags_a_promoted_host_deals_a_different_match() -> void:
	var played: WireMatch = WireMatch.start(4242)
	played.play(10)
	var replica: GameState = _welcomed(played.state, _client_library())
	replica.market.event_bags = {}

	var promoted: MatchAuthority = _take_over(replica, played.authority.rng_state())

	var parted: bool = false
	for _year: int in 30:
		var expected: EarningsYearResult = WireMatch.play_year(played.authority)
		var actual: EarningsYearResult = WireMatch.play_year(promoted)
		if WireMatch.result_lines(expected) != WireMatch.result_lines(actual):
			parted = true
			break
	assert_true(parted, "forgetting the bags should change the match")


## The new host's random stream carries on, its draws now the same as the old
## host's would have been - the base game's rule (D105), held in this mode.
func test_a_stalkleheads_match_can_change_hosts() -> void:
	var played: WireMatch = WireMatch.start(11)
	played.play(3)
	var replica: GameState = _welcomed(played.state, _client_library())

	assert_eq(MatchSetup.why_not_take_over(replica), "")


func _take_over(replica: GameState, rng_state: int) -> MatchAuthority:
	var opened: Dictionary = HostSession.take_over(
		StubTransport.new(), replica, MatchSetup.load_library(GameMode.Value.STALKLEHEADS),
		&"p1", rng_state,
	)
	assert_eq(String(opened["error"]), "", "take-over should succeed")
	var session: HostSession = opened["session"]
	autofree(session)
	return session._authority


# ------------------------------------------------------------ over ENet

## The same property through the real sessions on a loopback socket: the
## welcome, the trade snapshots and the year packets, in the order
## `ClientSession` applies them. This is what catches a client that applied the
## snapshot before replaying the year, which the in-process tests cannot.
func test_over_enet_the_client_holds_the_hosts_match() -> void:
	var harness: NetHarness = NetHarness.new()
	add_child_autofree(harness)
	var settings: GameSettings = GameSettings.new()
	settings.mode = GameMode.Value.STALKLEHEADS
	settings.rng_seed = 4242
	settings.max_years = 10
	settings.loans_enabled = true
	var error: String = harness.start(settings, MatchSetup.load_library(settings.mode))
	assert_eq(error, "", "the harness should start")
	if not error.is_empty():
		return
	assert_true(await harness.await_join(self), "the client should join")
	await harness.begin_match(self)

	for year: int in 4:
		var row: StalkState = harness.host.state().stalks[year * 2]
		harness.client.request_buy(&"p1", row.id, 3 + year)
		await harness.settle(self)
		harness.client.set_ready(&"p1", true)
		await harness.settle(self)
		harness.host.set_ready(&"p0", true)
		await harness.settle(self)

	var host: GameState = harness.host.state()
	var client: GameState = harness.client.state()
	assert_eq(host.year, 4, "four years should have passed")
	_assert_same(WireMatch.state_lines(host, false), WireMatch.state_lines(client, false), "state")
	assert_eq(client.history.size(), host.history.size())
	for index: int in mini(host.history.size(), client.history.size()):
		_assert_same(
			WireMatch.result_lines(host.history[index]),
			WireMatch.result_lines(client.history[index]),
			"year %d" % (index + 1),
		)


# ----------------------------------------------------------------- refusals

func test_a_snapshot_from_different_content_is_refused() -> void:
	var played: WireMatch = WireMatch.start(11)
	var data: Dictionary = StateSync.encode_state(played.state, 0)
	data["market"]["content"] = int(data["market"]["content"]) + 1

	var problem: String = StateSync.apply_state(GameState.new(GameSettings.new()), data, _client_library())

	assert_eq(problem, MarketSync.MISMATCH)


func test_a_short_company_block_is_refused() -> void:
	var played: WireMatch = WireMatch.start(11)
	var data: Dictionary = StateSync.encode_state(played.state, 0)
	var companies: PackedInt32Array = data["market"]["companies"]
	companies.resize(companies.size() - 1)
	data["market"]["companies"] = companies

	var problem: String = StateSync.apply_state(GameState.new(GameSettings.new()), data, _client_library())

	assert_eq(problem, MarketSync.MALFORMED)


## 32-bit reals would arrive as different numbers; refused rather than used.
func test_reals_narrower_than_64_bits_are_refused() -> void:
	var played: WireMatch = WireMatch.start(11)
	var data: Dictionary = StateSync.encode_state(played.state, 0)
	var narrow: PackedFloat32Array = []
	for value: float in data["market"]["reals"] as PackedFloat64Array:
		narrow.append(value)
	data["market"]["reals"] = narrow

	var problem: String = StateSync.apply_state(GameState.new(GameSettings.new()), data, _client_library())

	assert_eq(problem, MarketSync.MALFORMED)


## A trader's holding pointing past the end of the board is refused, not read.
func test_a_desk_entry_outside_the_board_is_refused() -> void:
	var played: WireMatch = WireMatch.start(11)
	played.play(2)
	var data: Dictionary = StateSync.encode_state(played.state, 0)
	var desk: PackedInt32Array = data["market"]["desk"]
	# The first trader: cash, then its holdings count, then a (row, shares).
	desk[1] = 1
	desk.insert(2, 999)
	desk.insert(3, 5)
	data["market"]["desk"] = desk

	var problem: String = StateSync.apply_state(GameState.new(GameSettings.new()), data, _client_library())

	assert_eq(problem, MarketSync.MALFORMED)


func test_a_truncated_year_record_is_refused() -> void:
	var played: WireMatch = WireMatch.start(11)
	var replica: GameState = _welcomed(played.state, _client_library())
	var result: EarningsYearResult = WireMatch.play_year(played.authority)
	var data: Dictionary = StateSync.encode_year_result(result, played.state)
	var inputs: PackedInt32Array = data["inputs"]
	inputs.resize(inputs.size() - 2)
	data["inputs"] = inputs

	assert_null(StateSync.decode_live_year(replica, data, _client_library()))


func test_a_history_with_a_broken_year_is_refused_whole() -> void:
	var played: WireMatch = WireMatch.start(11)
	played.play(4)
	var history: Array = StateSync.encode_history(played.state)
	var inputs: PackedInt32Array = history[2]["inputs"]
	inputs.resize(3)
	history[2]["inputs"] = inputs
	var replica: GameState = GameState.new(GameSettings.new())
	StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), _client_library())

	var problem: String = StateSync.apply_history(replica, history, _client_library())

	assert_ne(problem, "")
	assert_eq(replica.history.size(), 0, "no half a record")


# ---------------------------------------------------------- the payload

## The welcome a rejoining player gets after a full 99-year, ten-player match
## must stay far inside one Steam message (512 KB as documented; design §9.2).
## tools/wire_report.gd is where the real figures come from (D178); this is the
## tripwire that notices if a change makes them grow a lot.
func test_a_99_year_welcome_stays_far_inside_one_steam_message() -> void:
	var played: WireMatch = WireMatch.start(4242, 10)
	played.play(99)

	var snapshot: int = var_to_bytes(StateSync.encode_state(played.state, 0)).size()
	var history: int = var_to_bytes(StateSync.encode_history(played.state)).size()

	assert_lt(snapshot, 16 * 1024, "the per-trade snapshot (measured about 11 KB)")
	assert_lt(snapshot + history, 256 * 1024, "the welcome (measured about 160 KB)")


# ------------------------------------------------------- the packing rules

func test_integers_go_32_bit_until_one_does_not_fit() -> void:
	assert_true(MarketSync._pack([1, -2, 2147483647] as Array[int]) is PackedInt32Array)
	assert_true(MarketSync._pack([1, 2147483648] as Array[int]) is PackedInt64Array)
	assert_true(MarketSync._pack([-2147483649] as Array[int]) is PackedInt64Array)


func test_either_width_reads_back_the_same() -> void:
	assert_eq(MarketSync._ints(PackedInt32Array([3, -4])), PackedInt64Array([3, -4]))
	assert_eq(MarketSync._ints(PackedInt64Array([3, -4])), PackedInt64Array([3, -4]))
	assert_eq(MarketSync._ints("nonsense"), PackedInt64Array())


## The packed layout is the wire format. Changing a width without changing the
## other end is a silent disagreement about what every number means.
func test_the_layout_widths_are_pinned() -> void:
	assert_eq(MarketSync.COMPANY_REALS, 6)
	assert_eq(MarketSync.COMPANY_INTS, 7)
	assert_eq(MarketSync.MARKET_REALS, 3)
	assert_eq(MarketSync.YEAR_COMPANY_INTS, 3)
	assert_eq(MarketSync.YEAR_TRADER_INTS, 3)


# ---------------------------------------------- the base game is untouched

## A base-game snapshot has no market and its years no inputs: the wire the
## base game always had. The golden history proves the year is unchanged; this
## proves the bytes are.
func test_the_base_games_wire_carries_nothing_new() -> void:
	var library: ContentLibrary = ContentLibrary.load_from()
	var settings: GameSettings = GameSettings.new()
	settings.rng_seed = 4242
	var authority: MatchAuthority = LocalSession.build_authority(settings, library, ["You"] as Array[String])
	authority.set_ready(&"p0", true)
	var result: YearResult = authority.advance_year()

	var snapshot: Dictionary = StateSync.encode_state(authority.state, 0)
	var year: Dictionary = StateSync.encode_year_result(result, authority.state)

	assert_eq(
		snapshot.keys(),
		["year", "is_over", "rng_state", "hosted_by", "yeehaw_requested_by", "stalks", "players", "settings"],
	)
	assert_eq(
		year.keys(),
		["year", "mood", "event_id", "stalk_changes", "dividends", "loan_changes", "net_worths", "rankings", "winners", "is_final_year"],
	)


## A replica that held a StalkleHeads market and is sent a base-game snapshot
## (a rematch in the other mode) must not keep it.
func test_a_base_snapshot_clears_a_stale_market() -> void:
	var played: WireMatch = WireMatch.start(11)
	var replica: GameState = _welcomed(played.state, _client_library())
	var library: ContentLibrary = ContentLibrary.load_from()
	var base: MatchAuthority = LocalSession.build_authority(GameSettings.new(), library, ["You"] as Array[String])

	StateSync.apply_state(replica, StateSync.encode_state(base.state, 0), library)

	assert_null(replica.market)


# ------------------------------------------------------- a failed company

## A failed company has no valuation, on the host as on a replica (D176).
func test_a_failed_company_has_no_valuation() -> void:
	var played: WireMatch = WireMatch.start(90210)
	var failed: CompanyState = null
	for _year: int in YEARS:
		WireMatch.play_year(played.authority)
		for company: CompanyState in played.state.market.companies:
			if played.state.stalk_by_id(company.id).is_bankrupt:
				failed = company
		if failed != null:
			break
	assert_not_null(failed, "this seed should bankrupt a company")
	if failed == null:
		return
	assert_eq(failed.price, 0)
	assert_eq(failed.multiple, 0.0)
	assert_eq(failed.fair_value, 0.0)
	assert_false(failed.valuation_clamped)
