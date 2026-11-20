extends GutTest
## A host and a client, connected over real ENet, in this process.
##
## These are the tests that would otherwise need two windows and a human. They
## are slower than the rest of the suite — each one opens a socket — so the rules
## themselves are left to the tests that need no network (test_trade_rules,
## test_loan_rules, test_local_session for the authority, test_state_sync for
## encoding). What is asserted here is specifically what the *wire* adds: that a
## request reaches the host, that the answer comes back, and that a client cannot
## do what it must not.
##
## The harness and the three things that make one-process testing work are
## documented in tests/fixtures/net_harness.gd.


var _library: ContentLibrary
var _harness: NetHarness


func before_all() -> void:
	_library = ContentLibrary.load_from()
	assert_true(_library.is_valid(), "content must load before networking can be tested")


func after_each() -> void:
	if _harness != null and is_instance_valid(_harness):
		_harness.queue_free()
	_harness = null


## Stands up a connected host and client, failing the test if either end does not
## come up. Returns whether the caller should continue.
func _connect(host_name: String = "Host", guest_name: String = "Guest") -> bool:
	_harness = NetHarness.new()
	add_child(_harness)

	var settings: GameSettings = StalksFixture.make_settings()
	settings.rng_seed = 4242
	settings.loans_enabled = true

	var error: String = _harness.start(settings, _library, host_name, guest_name)
	if not error.is_empty():
		fail_test("harness did not start: %s" % error)
		return false

	var joined: bool = await _harness.await_join(self)
	assert_true(joined, "the client should connect to the host")
	if not joined:
		return false

	# Everything below the lobby tests happens in a running match, so Start is
	# part of getting connected. `_connect_lobby` is the variant that stops short.
	await _harness.begin_match(self)
	return true


## Connects without starting the match, for the lobby tests.
func _connect_lobby(host_name: String = "Host", guest_name: String = "Guest") -> bool:
	_harness = NetHarness.new()
	add_child(_harness)

	var error: String = _harness.start(
		StalksFixture.make_settings(), _library, host_name, guest_name
	)
	if not error.is_empty():
		fail_test("harness did not start: %s" % error)
		return false
	return await _harness.await_join(self)


# ---------------------------------------------------------------------- joining

func test_a_client_connects_and_is_seated() -> void:
	if not await _connect():
		return

	assert_eq(_harness.host.local_player_id(), &"p0", "the host takes the first slot")
	assert_eq(_harness.client.local_player_id(), &"p1", "the joiner takes the next")


func test_a_client_receives_the_opening_market() -> void:
	if not await _connect():
		return

	var host_state: GameState = _harness.host.state()
	var client_state: GameState = _harness.client.state()

	assert_eq(client_state.stalks.size(), host_state.stalks.size())
	assert_eq(client_state.players.size(), 2, "both players should be visible")
	for stalk: StalkState in host_state.stalks:
		var copy: StalkState = client_state.stalk_by_id(stalk.id)
		assert_not_null(copy, "client should know about %s" % stalk.id)
		if copy != null:
			assert_eq(copy.price, stalk.price, "opening price of %s" % stalk.id)


func test_a_client_learns_the_hosts_seed_and_year_limit() -> void:
	if not await _connect():
		return

	assert_eq(_harness.client.state().settings.rng_seed, 4242)
	assert_eq(_harness.client.state().settings.max_years, 10)


# ----------------------------------------------------------------------- yeehaw
#
# The first networked feature, chosen because it needs a request, an authority
# check and a broadcast while being incapable of corrupting the economy.
# See docs/porting-plan.md, Phase 5.

func test_a_clients_yeehaw_request_reaches_the_host_and_every_peer() -> void:
	if not await _connect():
		return

	var on_host: Array = []
	var on_client: Array = []
	_harness.host.yeehaw_requested.connect(func(id: StringName) -> void: on_host.append(id))
	_harness.client.yeehaw_requested.connect(func(id: StringName) -> void: on_client.append(id))

	_harness.client.request_yeehaw(&"p1")
	await _harness.settle(self)

	assert_eq(on_host, [&"p1"], "the host should see the client's ask")
	assert_eq(on_client, [&"p1"], "and the asker should see it went out")


func test_the_hosts_yeehaw_request_reaches_the_client() -> void:
	if not await _connect():
		return

	var on_client: Array = []
	_harness.client.yeehaw_requested.connect(func(id: StringName) -> void: on_client.append(id))

	_harness.host.request_yeehaw(&"p0")
	await _harness.settle(self)

	assert_eq(on_client, [&"p0"])


func test_giving_a_yeehaw_is_broadcast_to_both_sides() -> void:
	if not await _connect():
		return

	var on_host: Array = []
	var on_client: Array = []
	_harness.host.yeehaw_given.connect(
		func(giver: StringName, receiver: StringName) -> void: on_host.append([giver, receiver])
	)
	_harness.client.yeehaw_given.connect(
		func(giver: StringName, receiver: StringName) -> void: on_client.append([giver, receiver])
	)

	# Somebody has to be asking before there is anything to give.
	_harness.host.request_yeehaw(&"p0")
	await _harness.settle(self)
	_harness.client.give_yeehaw(&"p1")
	await _harness.settle(self)

	assert_eq(on_host, [[&"p1", &"p0"]], "the host should see who gave it to whom")
	assert_eq(on_client, [[&"p1", &"p0"]], "and so should everybody else")


func test_the_host_refuses_a_self_yeehaw_from_a_client() -> void:
	if not await _connect():
		return

	var refusals: Array[String] = []
	_harness.client.action_rejected.connect(
		func(_id: StringName, reason: String) -> void: refusals.append(reason)
	)
	var given: Array = []
	_harness.client.yeehaw_given.connect(
		func(_g: StringName, _r: StringName) -> void: given.append(true)
	)

	# The client asks, then tries to answer its own ask.
	_harness.client.request_yeehaw(&"p1")
	await _harness.settle(self)
	_harness.client.give_yeehaw(&"p1")
	await _harness.settle(self)

	assert_eq(given.size(), 0, "a self-yeehaw must not be broadcast")
	assert_eq(refusals.size(), 1, "and the asker should be told why")
	if refusals.size() == 1:
		assert_string_contains(refusals[0].to_lower(), "yourself")


# ------------------------------------------------------------------------ trading

func test_a_clients_buy_is_applied_by_the_host() -> void:
	if not await _connect():
		return
	await _open_trading()

	var stalk: StalkState = _harness.host.state().stalks[0]
	var price: int = stalk.price

	_harness.client.request_buy(&"p1", stalk.id, 3)
	await _harness.settle(self)

	var on_host: PlayerState = _harness.host.state().player_by_id(&"p1")
	assert_eq(on_host.shares_of(stalk.id), 3, "the host holds the authoritative position")
	assert_eq(on_host.cash, 10000 - price * 3, "and charged for it")


func test_a_client_sees_its_own_purchase_reflected_back() -> void:
	if not await _connect():
		return
	await _open_trading()

	var stalk: StalkState = _harness.host.state().stalks[0]
	_harness.client.request_buy(&"p1", stalk.id, 2)
	await _harness.settle(self)

	var replica: PlayerState = _harness.client.state().player_by_id(&"p1")
	assert_eq(replica.shares_of(stalk.id), 2, "the client's board should update")
	assert_eq(
		replica.cash,
		_harness.host.state().player_by_id(&"p1").cash,
		"and agree with the host on cash",
	)


func test_the_host_refuses_a_purchase_the_client_cannot_afford() -> void:
	if not await _connect():
		return
	await _open_trading()

	var refusals: Array[String] = []
	_harness.client.action_rejected.connect(
		func(_id: StringName, reason: String) -> void: refusals.append(reason)
	)

	var stalk: StalkState = _harness.host.state().stalks[0]
	_harness.client.request_buy(&"p1", stalk.id, 1_000_000)
	await _harness.settle(self)

	assert_eq(
		_harness.host.state().player_by_id(&"p1").shares_of(stalk.id), 0,
		"nothing should have been bought",
	)
	assert_eq(_harness.host.state().player_by_id(&"p1").cash, 10000, "and no cash taken")
	assert_eq(refusals.size(), 1, "the client should be told")


func test_a_refusal_goes_only_to_the_peer_that_asked() -> void:
	if not await _connect():
		return
	await _open_trading()

	var host_refusals: Array[String] = []
	_harness.host.action_rejected.connect(
		func(_id: StringName, reason: String) -> void: host_refusals.append(reason)
	)

	_harness.client.request_buy(&"p1", _harness.host.state().stalks[0].id, 1_000_000)
	await _harness.settle(self)

	assert_eq(host_refusals.size(), 0, "the host's own UI should not show a client's refusal")


func test_a_client_cannot_buy_a_stalk_that_does_not_exist() -> void:
	if not await _connect():
		return
	await _open_trading()

	var refusals: Array[String] = []
	_harness.client.action_rejected.connect(
		func(_id: StringName, reason: String) -> void: refusals.append(reason)
	)

	_harness.client.request_buy(&"p1", &"definitely_not_a_stalk", 1)
	await _harness.settle(self)

	assert_eq(refusals.size(), 1, "a nonsense id should be refused, not crash the host")
	assert_eq(_harness.host.state().player_by_id(&"p1").cash, 10000)


# -------------------------------------------------------------- the authority line

func test_a_client_cannot_act_as_another_player() -> void:
	# Belt and braces. The wire carries no player id at all — the host derives the
	# actor from the peer — so this is really asserting that the client-side guard
	# also refuses, and that nothing happens to the host's player either way.
	if not await _connect():
		return
	await _open_trading()

	var refusals: Array[String] = []
	_harness.client.action_rejected.connect(
		func(_id: StringName, reason: String) -> void: refusals.append(reason)
	)

	var stalk: StalkState = _harness.host.state().stalks[0]
	_harness.client.request_buy(&"p0", stalk.id, 1)
	await _harness.settle(self)

	assert_eq(
		_harness.host.state().player_by_id(&"p0").shares_of(stalk.id), 0,
		"the host's own player must be untouched",
	)
	assert_eq(refusals.size(), 1, "and the attempt refused")


func test_a_client_is_told_which_player_it_controls_and_no_other() -> void:
	if not await _connect():
		return

	assert_true(_harness.client.controls(&"p1"), "a client controls its own player")
	assert_false(_harness.client.controls(&"p0"), "and nobody else's")


## A client ends up holding the whole match, over a real connection.
##
## **This is the end-to-end half of host migration.** A new host carries the
## match on from the copy it already has (`HostSession.take_over`), so that
## copy has to be the real thing and not a redacted sketch. The unit tests in
## test_state_sync assert the snapshot *can* carry everything; this asserts the
## host actually sends it and the client actually ends up holding it.
##
## It replaced a test asserting the opposite - that a rival's cash never
## crossed the wire. See docs/decisions.md D105 for why that rule went.
func test_a_client_ends_up_holding_the_hosts_whole_match() -> void:
	if not await _connect():
		return
	await _open_trading()

	# Move the host's position somewhere distinctive, then let a snapshot out.
	_harness.host.request_buy(&"p0", _harness.host.state().stalks[0].id, 5)
	await _harness.settle(self)

	var stalk_id: StringName = _harness.host.state().stalks[0].id
	var theirs: PlayerState = _harness.host.state().player_by_id(&"p0")
	var seen: PlayerState = _harness.client.state().player_by_id(&"p0")

	assert_ne(theirs.cash, 10000, "the host should have spent something")
	assert_eq(seen.cash, theirs.cash, "a client holds a rival's real cash")
	assert_eq(
		seen.shares_of(stalk_id),
		theirs.shares_of(stalk_id),
		"and the size of their position",
	)


## Seeing is not writing, which is the rule that did not change.
##
## The permissive half above costs nothing only because the host validates
## every request against its own state. A client asking to spend somebody
## else's money is refused however much of that money it can see.
func test_seeing_a_rivals_cash_does_not_let_a_client_spend_it() -> void:
	if not await _connect():
		return
	await _open_trading()

	var before: int = _harness.host.state().player_by_id(&"p0").cash
	_harness.client.request_buy(&"p0", _harness.host.state().stalks[0].id, 1)
	await _harness.settle(self)

	assert_eq(
		_harness.host.state().player_by_id(&"p0").cash,
		before,
		"a client must not move a rival's money",
	)


func test_a_client_does_learn_a_rivals_net_worth() -> void:
	if not await _connect():
		return
	await _open_trading()

	_harness.host.request_buy(&"p0", _harness.host.state().stalks[0].id, 5)
	await _harness.settle(self)

	assert_eq(
		_harness.client.state().player_by_id(&"p0").net_worth,
		_harness.host.state().player_by_id(&"p0").net_worth,
		"rankings need net worth, so it is public",
	)


# --------------------------------------------------------------- the year advance

func test_the_year_does_not_advance_until_every_player_is_ready() -> void:
	if not await _connect():
		return

	var years: Array = []
	_harness.client.year_resolved.connect(func(_r: YearResult) -> void: years.append(true))

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)

	assert_eq(_harness.host.state().year, 0, "one player ready is not enough")
	assert_eq(years.size(), 0)
	assert_true(
		_harness.host.state().player_by_id(&"p1").is_ready,
		"but the host should have recorded the readiness",
	)


func test_readiness_is_visible_to_the_other_side() -> void:
	if not await _connect():
		return

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)

	assert_true(
		_harness.client.state().player_by_id(&"p1").is_ready,
		"the client's own replica should show it ready",
	)

	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)
	# Both are now ready, so the year has advanced — see the next test.


func test_both_sides_agree_on_the_market_after_a_year() -> void:
	if not await _connect():
		return

	var results: Array[YearResult] = []
	_harness.client.year_resolved.connect(func(r: YearResult) -> void: results.append(r))

	await _advance_a_year()

	assert_eq(_harness.host.state().year, 1, "the host should have advanced")
	assert_eq(_harness.client.state().year, 1, "and told the client")
	assert_eq(results.size(), 1, "the client should have been handed the result")

	for stalk: StalkState in _harness.host.state().stalks:
		var copy: StalkState = _harness.client.state().stalk_by_id(stalk.id)
		assert_eq(copy.price, stalk.price, "price of %s should match" % stalk.id)
		assert_eq(copy.is_bankrupt, stalk.is_bankrupt, "bankruptcy of %s" % stalk.id)
		assert_eq(
			copy.last_yearly_change, stalk.last_yearly_change,
			"change shown for %s" % stalk.id,
		)


func test_the_client_receives_the_years_event_and_its_text() -> void:
	if not await _connect():
		return

	var results: Array[YearResult] = []
	_harness.client.year_resolved.connect(func(r: YearResult) -> void: results.append(r))

	await _advance_a_year()

	assert_eq(results.size(), 1)
	if results.is_empty():
		return
	var host_result: YearResult = _harness.host.state().latest_result()
	if host_result.event == null:
		pass_test("no event fired this year, nothing to compare")
		return
	assert_not_null(results[0].event, "the client should have resolved the event")
	assert_eq(results[0].event.id, host_result.event.id)
	assert_eq(
		results[0].event.flavour_text, host_result.event.flavour_text,
		"and read its own copy of the text",
	)


func test_a_client_keeps_its_own_match_history() -> void:
	# Charts and year-over-year figures are built from history later, so a client
	# has to accumulate it rather than ask the host for it. See architecture §7.
	if not await _connect():
		return

	await _advance_a_year()
	assert_eq(_harness.client.state().history.size(), 1)

	await _advance_a_year()
	assert_eq(_harness.client.state().history.size(), 2)
	assert_eq(_harness.client.state().history[1].year, 2)


func test_ready_flags_clear_on_both_sides_after_a_year() -> void:
	if not await _connect():
		return

	await _advance_a_year()

	assert_false(
		_harness.client.state().player_by_id(&"p1").is_ready,
		"a client must not stay ready, or the next year would advance on one click",
	)
	assert_false(_harness.host.state().player_by_id(&"p0").is_ready)


# ---------------------------------------------------------------------- helpers

## Trading is closed in year 0, so most trading tests need a year behind them.
func _open_trading() -> void:
	await _advance_a_year()
	assert_true(_harness.host.state().is_trading_open(), "year 1 should allow trading")


## Readies both players and waits for the year to resolve on both sides.
func _advance_a_year() -> void:
	var year_before: int = _harness.host.state().year
	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)
	assert_eq(
		_harness.host.state().year, year_before + 1,
		"both ready should have advanced the year",
	)


# ------------------------------------------------------------------- disconnects
#
# Leaving a dropped player in the match untouched deadlocked the year, because
# the all-ready gate counted every player (D46). Taking them out of the match
# fixed the deadlock and cost them their position (D47). Marking them away does
# neither: they stay in the economy and out of the gate (D110). These assert
# that, and its limits.

func test_a_dropped_player_stays_in_the_match_but_is_marked_away() -> void:
	if not await _connect():
		return
	assert_eq(_harness.host.state().players.size(), 2)

	assert_true(await _harness.drop_client(self), "the host should notice the drop")

	assert_eq(
		_harness.host.state().players.size(), 2,
		"a dropped player is still in the economy",
	)
	var dropped: PlayerState = _harness.host.state().player_by_id(&"p1")
	assert_not_null(dropped, "and still findable")
	if dropped != null:
		assert_true(dropped.is_away, "but marked away")
	assert_true(_harness.host.is_away(&"p1"))


## The year gate is the one thing being away changes.
func test_a_dropped_player_is_not_waited_for() -> void:
	if not await _connect():
		return
	if not await _harness.drop_client(self):
		return

	assert_eq(
		_harness.host.state().players_present().size(), 1,
		"only the host is here",
	)
	# The host has not readied up, so they are still in the list. The player who
	# dropped is not, which is the whole difference.
	var waiting: Array[StringName] = _harness.host.state().players_not_ready()
	assert_has(waiting, &"p0", "the host has not readied up")
	assert_does_not_have(waiting, &"p1", "an away player is not somebody to wait for")


func test_the_year_can_still_advance_after_a_player_drops() -> void:
	# The deadlock this change exists to fix: with the dropped player still in the
	# match, the host could ready up forever and nothing would happen.
	if not await _connect():
		return
	if not await _harness.drop_client(self):
		return

	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)

	assert_eq(_harness.host.state().year, 1, "the remaining player should be enough")


func test_a_drop_completes_a_year_the_departed_player_was_holding_up() -> void:
	# The host is ready and waiting on the client. The client vanishes. That
	# departure is the last thing the year was waiting for, so it should resolve
	# rather than sit until somebody clicks again.
	if not await _connect():
		return

	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)
	assert_eq(_harness.host.state().year, 0, "still waiting on the client")

	if not await _harness.drop_client(self):
		return

	assert_eq(_harness.host.state().year, 1, "the drop should have released the year")


func test_a_dropped_players_portfolio_is_kept_not_destroyed() -> void:
	# Removal from the roster is not destruction. A bot taking over, or a proper
	# rejoin, both need the position to still be there — see porting-plan Phase 8.
	if not await _connect():
		return
	await _open_trading()

	var stalk: StalkState = _harness.host.state().stalks[0]
	_harness.client.request_buy(&"p1", stalk.id, 4)
	await _harness.settle(self)
	var cash_before: int = _harness.host.state().player_by_id(&"p1").cash

	if not await _harness.drop_client(self):
		return

	var kept: PlayerState = null
	for player: PlayerState in _harness.host.roster():
		if player.id == &"p1":
			kept = player
	assert_not_null(kept, "the player should still be in the roster")
	if kept == null:
		return
	assert_eq(kept.shares_of(stalk.id), 4, "their holdings should be intact")
	assert_eq(kept.cash, cash_before, "and their cash")


func test_a_dropped_player_is_not_left_marked_ready() -> void:
	# Otherwise a resumed player would count as ready for a year they were not
	# present for.
	if not await _connect():
		return

	_harness.client.set_ready(&"p1", true)
	await _harness.settle(self)
	if not await _harness.drop_client(self):
		return

	var kept: PlayerState = null
	for player: PlayerState in _harness.host.roster():
		if player.id == &"p1":
			kept = player
	assert_not_null(kept)
	if kept != null:
		assert_false(kept.is_ready)


func test_a_drop_does_not_advance_the_year_on_its_own() -> void:
	# Only if the remaining players were already waiting. Nobody is ready here,
	# so nothing should resolve.
	if not await _connect():
		return
	if not await _harness.drop_client(self):
		return

	assert_eq(_harness.host.state().year, 0, "a drop is not a ready-up")


# ------------------------------------------------------------------------- lobby
#
# Players are created as they arrive, and the roster is whatever is present when
# the host presses Start. Declaring the size up front was the first design and it
# was wrong — see docs/decisions.md D48.

func test_a_host_alone_is_a_one_player_lobby() -> void:
	_harness = NetHarness.new()
	add_child(_harness)
	assert_eq(_harness.start(StalksFixture.make_settings(), _library), "")

	assert_eq(_harness.host.state().players.size(), 1, "no empty slots waiting")
	assert_true(_harness.host.lobby_is_open())


func test_a_joining_player_is_added_to_the_lobby() -> void:
	if not await _connect_lobby():
		return

	assert_eq(_harness.host.state().players.size(), 2)
	assert_eq(_harness.client.local_player_id(), &"p1")


func test_a_player_arrives_with_the_name_they_typed() -> void:
	if not await _connect_lobby("Murph", "Rodzianko"):
		return

	assert_eq(_harness.host.state().player_by_id(&"p0").display_name, "Murph")
	assert_eq(
		_harness.host.state().player_by_id(&"p1").display_name, "Rodzianko",
		"the host should seat the client under its chosen name",
	)
	assert_eq(
		_harness.client.state().player_by_id(&"p1").display_name, "Rodzianko",
		"and the client should see it too",
	)


func test_leaving_the_lobby_removes_the_player_outright() -> void:
	# Before the match there is no portfolio to preserve and nobody waiting on
	# them, so the slot goes rather than being vacated.
	if not await _connect_lobby():
		return
	assert_eq(_harness.host.state().players.size(), 2)

	assert_true(await _harness.drop_client(self))

	assert_eq(_harness.host.state().players.size(), 1)
	assert_eq(_harness.host.roster().size(), 1, "the slot should be gone, not away")
	assert_false(_harness.host.is_away(&"p1"))


func test_the_year_does_not_advance_while_the_lobby_is_open() -> void:
	# Readiness means "ready to begin" here, not "advance the year". Without the
	# guard a full lobby of ready players would resolve year 1 unseen.
	if not await _connect_lobby():
		return

	_harness.client.set_ready(&"p1", true)
	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)

	assert_eq(_harness.host.state().year, 0, "the lobby must not resolve a year")


func test_starting_the_match_closes_the_lobby_and_tells_the_client() -> void:
	if not await _connect_lobby():
		return

	var started: Array = []
	_harness.client.match_started.connect(func() -> void: started.append(true))

	await _harness.begin_match(self)

	assert_false(_harness.host.lobby_is_open())
	assert_eq(started.size(), 1, "the client should be told to leave the lobby")


func test_starting_the_match_clears_ready_flags() -> void:
	# Otherwise "ready to begin" would carry over and instantly advance year 1.
	if not await _connect_lobby():
		return

	_harness.client.set_ready(&"p1", true)
	_harness.host.set_ready(&"p0", true)
	await _harness.settle(self)

	await _harness.begin_match(self)

	assert_eq(_harness.host.state().year, 0, "the match should begin at year 0")
	assert_false(_harness.host.state().player_by_id(&"p0").is_ready)
	assert_false(_harness.host.state().player_by_id(&"p1").is_ready)


func test_a_latecomer_is_turned_away_with_a_reason() -> void:
	# A silent failure to join is the worst version of this: the player cannot
	# tell a started game from a broken one.
	if not await _connect_lobby():
		return
	await _harness.begin_match(self)

	var latecomer: Dictionary = ClientSession.join(
		EnetTransport.new(_harness.port()), _library, "Late"
	)
	assert_eq(String(latecomer["error"]), "")
	var late: ClientSession = latecomer["session"]
	var reasons: Array[String] = []
	late.connection_lost.connect(func(reason: String) -> void: reasons.append(reason))
	_harness.attach_extra_client(late, latecomer["peer"])

	await _harness.settle(self, 30)

	assert_false(late.has_joined(), "a latecomer must not be seated")
	assert_eq(_harness.host.state().players.size(), 2, "and must not appear in the match")
	assert_true(reasons.size() >= 1, "they should be told why")
	if reasons.size() >= 1:
		assert_string_contains(reasons[0].to_lower(), "already started")


# -------------------------------------------------------------- name sanitising
#
# A display name arrives from a client, so it is untrusted input. These are pure
# and need no connection.

func test_a_blank_name_becomes_a_numbered_placeholder() -> void:
	assert_eq(HostSession.sanitised_name("", 0), "Player 1")
	assert_eq(HostSession.sanitised_name("   ", 3), "Player 4")


func test_a_name_is_trimmed() -> void:
	assert_eq(HostSession.sanitised_name("  Murph  ", 0), "Murph")


func test_an_overlong_name_is_cut_to_the_column_width() -> void:
	var long_name: String = "A".repeat(40)
	assert_eq(HostSession.sanitised_name(long_name, 0).length(), HostSession.MAX_NAME_LENGTH)


func test_control_characters_are_stripped_from_a_name() -> void:
	# A newline or a tab would corrupt a fixed-width row.
	assert_eq(HostSession.sanitised_name("Mur\nph", 0), "Mur ph")
	assert_eq(HostSession.sanitised_name("\n\t", 0), "Player 1")


# ------------------------------------------------- coming back to your own seat
#
# **The reclaim, end to end over a real socket.** Everything else about rejoining
# is tested either side of this: the economics of being away in
# `test_away_players.gd`, the host's refusals in `test_host_migration.gd`, and
# `Main`'s orchestration in `test_main_rejoin.gd`. None of them is the thing
# itself - a peer dropping, a peer coming back, and the host putting them where
# they were.
#
# It works here because `_slot_to_reclaim` only ever asks for a Steam id, and a
# Steam id is just an integer to everything below `SteamService`. The harness
# hands both sides one, ENet carries the match, and Steam is not involved.
#
# See docs/decisions.md D105, D110 and D116.

const HOST_ACCOUNT: int = 76561190000000001
const GUEST_ACCOUNT: int = 76561190000000002


## A match in progress, with both sides carrying a Steam account.
func _match_with_steam_ids() -> bool:
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
		assert_true(false, "client should connect")
		return false
	await _harness.begin_match(self)
	return true


## Builds a second client for the same Steam account and connects it, the way a
## player who restarted the game would arrive.
func _come_back() -> ClientSession:
	var returning: Dictionary = ClientSession.join(
		EnetTransport.new(_harness.port()), _library, "Guest", GUEST_ACCOUNT
	)
	assert_eq(String(returning["error"]), "")
	var back: ClientSession = returning["session"]
	_harness.attach_extra_client(back, returning["peer"])
	return back


func test_a_returning_player_is_seated_back_on_their_own_slot() -> void:
	if not await _match_with_steam_ids():
		return
	await _open_trading()
	var stalk: StalkState = _harness.host.state().stalks[0]
	_harness.client.request_buy(&"p1", stalk.id, 6)
	await _harness.settle(self)
	if not await _harness.drop_client(self):
		return

	var back: ClientSession = _come_back()
	await _harness.settle(self, 30)

	assert_true(back.has_joined(), "the host should have welcomed them")
	assert_eq(back.local_player_id(), &"p1", "onto their own slot, not a new one")
	assert_eq(
		back.state().player_by_id(&"p1").shares_of(stalk.id), 6,
		"with the position the match has been keeping for them",
	)


func test_coming_back_clears_the_away_flag() -> void:
	if not await _match_with_steam_ids():
		return
	if not await _harness.drop_client(self):
		return
	assert_true(_harness.host.is_away(&"p1"), "the test needs them away first")

	_come_back()
	await _harness.settle(self, 30)

	assert_false(_harness.host.is_away(&"p1"))
	assert_eq(
		_harness.host.state().players_present().size(), 2,
		"and the year waits for them again",
	)


## **The fault this guards.** The welcome says who you are and what the match
## looks like; it does not say whether the match has *started*. A client that is
## only welcomed cannot tell a lobby from a game - year 0 is a real year - so it
## sits on the lobby screen while the match runs on without it.
##
## REJOIN GAME never hit this, because `Main` suppresses the lobby screen on that
## route and puts the board up itself. Steam's friends-list "Join Game" and an
## accepted invite both come in through the ordinary join path, which shows the
## lobby and waits to be told. See D116.
func test_a_returning_player_is_told_the_match_is_under_way() -> void:
	if not await _match_with_steam_ids():
		return
	if not await _harness.drop_client(self):
		return

	var back: ClientSession = _come_back()
	var started: Array[bool] = []
	back.match_started.connect(_on_match_started_for_testing.bind(started))
	await _harness.settle(self, 30)

	assert_true(back.has_joined(), "the test needs the welcome to land")
	assert_eq(
		started.size(), 1,
		"a reclaiming client must be told the lobby is closed and the game is on",
	)


## Named rather than inline, because connecting an anonymous function to a signal
## is the thing `test_conventions.gd` exists to stop.
func _on_match_started_for_testing(seen: Array[bool]) -> void:
	seen.append(true)


## **And it remembers being told**, which the signal above does not provide for.
## `match_started` is acted on the instant it arrives by whichever screen is up;
## a migration has to answer "lobby or match" long afterwards, and the state
## cannot say, because year 0 is a real year. See `ClientSession._match_is_on`
## and `Main._show_the_screen_for`.
func test_a_returning_player_remembers_that_the_match_is_on() -> void:
	if not await _match_with_steam_ids():
		return
	if not await _harness.drop_client(self):
		return

	var back: ClientSession = _come_back()
	await _harness.settle(self, 30)

	assert_true(back.has_joined(), "the test needs the welcome to land")
	assert_true(back.match_is_on(), "a client reclaiming a seat is in a match")


## The other side of it: arriving in a lobby, nobody says the match is on,
## because it is not.
func test_a_client_in_a_lobby_does_not_think_the_match_is_on() -> void:
	_harness = NetHarness.new()
	add_child(_harness)
	var problem: String = _harness.start(
		StalksFixture.make_settings(), _library, "Host", "Guest"
	)
	assert_eq(problem, "", "harness should start")
	if not problem.is_empty():
		return
	if not await _harness.await_join(self):
		return

	assert_true(_harness.client.has_joined(), "the test needs the welcome to land")
	assert_false(
		_harness.client.match_is_on(),
		"nothing has started a match, so no screen should be told one is on",
	)


## A second client on a **different** account is not somebody coming back, and
## must not be handed the seat that is waiting for its owner.
func test_somebody_elses_account_cannot_take_the_waiting_seat() -> void:
	if not await _match_with_steam_ids():
		return
	if not await _harness.drop_client(self):
		return

	var stranger: Dictionary = ClientSession.join(
		EnetTransport.new(_harness.port()), _library, "Stranger", 76561190000000009
	)
	assert_eq(String(stranger["error"]), "")
	var intruder: ClientSession = stranger["session"]
	var reasons: Array[String] = []
	intruder.connection_lost.connect(_on_refusal_for_testing.bind(reasons))
	_harness.attach_extra_client(intruder, stranger["peer"])
	await _harness.settle(self, 30)

	assert_false(intruder.has_joined(), "a stranger must not be seated")
	assert_true(_harness.host.is_away(&"p1"), "and the seat is still waiting")
	assert_true(reasons.size() >= 1, "they should be told why")
	if reasons.size() >= 1:
		assert_string_contains(reasons[0].to_lower(), "already started")


func _on_refusal_for_testing(reason: String, seen: Array[String]) -> void:
	seen.append(reason)
