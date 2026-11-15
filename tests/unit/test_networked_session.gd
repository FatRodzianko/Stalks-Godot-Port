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
func _connect(player_names: Array[String] = ["Host", "Guest"]) -> bool:
	_harness = NetHarness.new()
	add_child(_harness)

	var settings: GameSettings = StalksFixture.make_settings()
	settings.rng_seed = 4242
	settings.loans_enabled = true

	var error: String = _harness.start(settings, _library, player_names)
	if not error.is_empty():
		fail_test("harness did not start: %s" % error)
		return false

	var joined: bool = await _harness.await_join(self)
	assert_true(joined, "the client should connect to the host")
	return joined


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

	_harness.client.give_yeehaw(&"p1", &"p0")
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

	_harness.client.give_yeehaw(&"p1", &"p1")
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


func test_a_client_never_learns_a_rivals_cash() -> void:
	# The end-to-end counterpart of the redaction tests in test_state_sync: this
	# asserts the host actually sends the redacted view, not just that it can.
	if not await _connect():
		return
	await _open_trading()

	# Move the host's cash somewhere distinctive, then let a snapshot go out.
	_harness.host.request_buy(&"p0", _harness.host.state().stalks[0].id, 5)
	await _harness.settle(self)

	var host_cash: int = _harness.host.state().player_by_id(&"p0").cash
	var seen_by_client: int = _harness.client.state().player_by_id(&"p0").cash

	assert_ne(host_cash, 10000, "the host should have spent something")
	assert_ne(seen_by_client, host_cash, "a client must not be told a rival's cash")


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
# Leaving a dropped player in the match deadlocked the year, because the
# all-ready gate counts every player. These assert the fix and its limits.
# See docs/decisions.md D47.

func test_a_dropped_player_leaves_the_active_roster() -> void:
	if not await _connect():
		return
	assert_eq(_harness.host.state().players.size(), 2)

	assert_true(await _harness.drop_client(self), "the host should notice the drop")

	assert_eq(
		_harness.host.state().players.size(), 1,
		"a dropped player should be out of the economy",
	)
	assert_null(_harness.host.state().player_by_id(&"p1"))


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
