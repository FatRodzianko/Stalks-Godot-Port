extends GutTest
## The offline session: the seam the UI talks to. See docs/architecture.md §5.
##
## These run headlessly with no scene beyond the session node itself, because the
## session is deliberately free of UI.


var _library: ContentLibrary
var _session: LocalSession


func before_each() -> void:
	_library = ContentLibrary.load_from()
	_session = _make_session()


func after_each() -> void:
	if _session != null and _session.is_inside_tree():
		_session.get_parent().remove_child(_session)
	if _session != null:
		_session.free()
	_session = null


## A match opens at Year 0 with trading closed, which is the original's opening
## position. Most tests here care about trading, so this readies up once to reach
## Year 1 unless asked not to.
func _make_session(
	max_years: int = 10,
	loans: bool = false,
	seed_value: int = 4242,
	open_trading: bool = true,
) -> LocalSession:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = max_years
	settings.player_count = 1
	settings.loans_enabled = loans
	settings.rng_seed = seed_value
	var session: LocalSession = LocalSession.create(settings, _library)
	add_child_autofree(session)
	if open_trading:
		session.set_ready(&"p0", true)
	return session


# -------------------------------------------------------------------- start-up

func test_a_new_match_opens_at_year_zero_with_trading_closed() -> void:
	# The original's opening position: every price at its starting value and no
	# buying until everyone readies up. See docs/game-rules.md §4.
	var fresh: LocalSession = _make_session(10, false, 4242, false)
	assert_eq(fresh.state().year, 0)
	assert_false(fresh.state().is_trading_open())
	for stalk: StalkState in fresh.state().stalks:
		assert_eq(stalk.price, 100, "%s should still be at its opening price" % stalk.id)


func test_readying_up_opens_trading_in_year_one() -> void:
	assert_eq(_session.state().year, 1)
	assert_true(_session.state().is_trading_open())


func test_the_market_is_built_from_the_authored_content() -> void:
	assert_eq(_session.state().stalks.size(), 10)
	assert_not_null(_session.state().stalk_by_id(&"stryker"))


func test_the_player_starts_with_the_configured_cash() -> void:
	var player: PlayerState = _session.state().player_by_id(&"p0")
	assert_not_null(player)
	assert_eq(player.cash, 10000)


func test_the_local_player_is_controlled_here() -> void:
	assert_eq(_session.local_player_id(), &"p0")
	assert_true(_session.controls(&"p0"))
	assert_false(_session.controls(&"p1"))


func test_a_zero_seed_is_replaced_with_a_real_one_and_recorded() -> void:
	# A match must always be reproducible afterwards, even if nobody chose a seed.
	var settings: GameSettings = GameSettings.new()
	settings.rng_seed = 0
	var session: LocalSession = LocalSession.create(settings, _library)
	add_child_autofree(session)

	assert_ne(session.seed_value(), 0)
	assert_eq(session.seed_value(), session.state().settings.rng_seed)


func test_two_sessions_with_the_same_seed_play_identically() -> void:
	var first: LocalSession = _make_session(10, false, 777)
	var second: LocalSession = _make_session(10, false, 777)

	while not first.state().is_over:
		first.set_ready(&"p0", true)
	while not second.state().is_over:
		second.set_ready(&"p0", true)

	assert_eq(first.state().history.size(), second.state().history.size())
	for i: int in first.state().history.size():
		assert_eq(
			first.state().history[i].net_worths[&"p0"],
			second.state().history[i].net_worths[&"p0"],
			"year %d net worth should match" % i
		)


# ---------------------------------------------------------------------- trading

func test_buying_moves_cash_and_shares_and_signals() -> void:
	watch_signals(_session)
	var stalk_id: StringName = _session.state().stalks[0].id
	var price: int = _session.state().stalk_by_id(stalk_id).price

	_session.request_buy(&"p0", stalk_id, 5)

	var player: PlayerState = _session.state().player_by_id(&"p0")
	assert_eq(player.shares_of(stalk_id), 5)
	assert_eq(player.cash, 10000 - price * 5)
	assert_signal_emitted(_session, "player_changed")


func test_an_unaffordable_purchase_is_rejected_with_a_reason() -> void:
	watch_signals(_session)
	_session.request_buy(&"p0", _session.state().stalks[0].id, 100000)

	assert_signal_emitted(_session, "action_rejected")
	assert_signal_not_emitted(_session, "player_changed")

	var params: Array = get_signal_parameters(_session, "action_rejected", 0)
	assert_eq(params[0], &"p0")
	assert_false((params[1] as String).is_empty(), "the reason must be shown to a player")


func test_buying_an_unknown_stalk_is_rejected_rather_than_crashing() -> void:
	watch_signals(_session)
	_session.request_buy(&"p0", &"no_such_stalk", 1)
	assert_signal_emitted(_session, "action_rejected")


func test_selling_returns_cash() -> void:
	var stalk_id: StringName = _session.state().stalks[0].id
	_session.request_buy(&"p0", stalk_id, 10)
	var cash_after_buy: int = _session.state().player_by_id(&"p0").cash

	_session.request_sell(&"p0", stalk_id, 10)

	var player: PlayerState = _session.state().player_by_id(&"p0")
	assert_eq(player.shares_of(stalk_id), 0)
	assert_gt(player.cash, cash_after_buy)


func test_overselling_is_rejected() -> void:
	watch_signals(_session)
	_session.request_sell(&"p0", _session.state().stalks[0].id, 1)
	assert_signal_emitted(_session, "action_rejected")


func test_net_worth_is_kept_current_after_a_trade() -> void:
	var stalk_id: StringName = _session.state().stalks[0].id
	_session.request_buy(&"p0", stalk_id, 10)
	var player: PlayerState = _session.state().player_by_id(&"p0")
	assert_eq(player.net_worth, TradeRules.net_worth(player, _session.state()))


# ---------------------------------------------------------------- pre-checks

func test_pre_checks_agree_with_what_the_session_will_do() -> void:
	# The UI greys out controls using these. If they disagreed with enforcement
	# the player would see an enabled button that then fails.
	var stalk_id: StringName = _session.state().stalks[0].id

	assert_eq(_session.why_not_buy(&"p0", stalk_id, 10), "",
		"an affordable buy should pre-check clean")
	assert_ne(_session.why_not_buy(&"p0", stalk_id, 100000), "",
		"an unaffordable buy should be caught before sending")
	assert_ne(_session.why_not_sell(&"p0", stalk_id, 1), "",
		"selling what you do not own should be caught before sending")


func test_max_affordable_matches_the_rules() -> void:
	var stalk_id: StringName = _session.state().stalks[0].id
	var expected: int = TradeRules.max_affordable(
		_session.state().player_by_id(&"p0"),
		_session.state().stalk_by_id(stalk_id),
	)
	assert_eq(_session.max_affordable(&"p0", stalk_id), expected)


func test_pre_checks_on_unknown_ids_do_not_crash() -> void:
	assert_ne(_session.why_not_buy(&"nobody", &"nothing", 1), "")
	assert_eq(_session.max_affordable(&"nobody", &"nothing"), 0)


# ------------------------------------------------------------ advancing the year

func test_readying_up_advances_the_year_in_a_solo_game() -> void:
	watch_signals(_session)
	var year_before: int = _session.state().year

	_session.set_ready(&"p0", true)

	assert_eq(_session.state().year, year_before + 1)
	assert_signal_emitted(_session, "year_resolved")
	assert_signal_emitted(_session, "ready_state_changed")


func test_the_year_result_is_handed_to_the_ui() -> void:
	watch_signals(_session)
	_session.set_ready(&"p0", true)

	var params: Array = get_signal_parameters(_session, "year_resolved", 0)
	var result: YearResult = params[0]
	assert_not_null(result)
	assert_eq(result.year, _session.state().year)
	assert_eq(result.stalk_changes.size(), 10)


func test_readiness_clears_after_the_year_advances() -> void:
	_session.set_ready(&"p0", true)
	assert_false(_session.state().player_by_id(&"p0").is_ready,
		"the next year needs its own ready-up")


func test_a_two_player_game_waits_for_both() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.rng_seed = 9
	var session: LocalSession = LocalSession.create(
		settings, _library, ["One", "Two"] as Array[String]
	)
	add_child_autofree(session)

	var year_before: int = session.state().year
	session.set_ready(&"p0", true)
	assert_eq(session.state().year, year_before, "should still be waiting for p1")

	session.set_ready(&"p1", true)
	assert_eq(session.state().year, year_before + 1)


func test_a_full_solo_game_can_be_played_through_the_session() -> void:
	watch_signals(_session)
	var guard: int = 0
	while not _session.state().is_over and guard < 30:
		_session.set_ready(&"p0", true)
		guard += 1

	assert_true(_session.state().is_over)
	assert_eq(_session.state().year, 11)
	assert_signal_emitted(_session, "game_over")

	var params: Array = get_signal_parameters(_session, "game_over", 0)
	assert_eq((params[0] as Array)[0], &"p0", "the only player wins")


func test_trading_is_refused_once_the_game_is_over() -> void:
	while not _session.state().is_over:
		_session.set_ready(&"p0", true)

	watch_signals(_session)
	_session.request_buy(&"p0", _session.state().stalks[0].id, 1)
	assert_signal_emitted(_session, "action_rejected")

	_session.set_ready(&"p0", true)
	assert_signal_emitted(_session, "action_rejected")


# ------------------------------------------------------------------------- loans

func test_loans_are_refused_when_disabled() -> void:
	watch_signals(_session)
	_session.request_loan(&"p0", 1000)
	assert_signal_emitted(_session, "action_rejected")


func test_a_loan_pays_out_and_shows_in_net_worth() -> void:
	var session: LocalSession = _make_session(10, true, 31337)
	session.set_ready(&"p0", true)  # reach year 2, when loans open

	var player: PlayerState = session.state().player_by_id(&"p0")
	var cash_before: int = player.cash
	var max_loan: int = LoanRules.max_loan_for(player)

	session.request_loan(&"p0", max_loan)

	assert_eq(player.cash, cash_before + max_loan)
	assert_true(player.has_outstanding_loan())
	assert_eq(player.net_worth, TradeRules.net_worth(player, session.state()))


func test_paying_a_loan_is_validated() -> void:
	var session: LocalSession = _make_session(10, true, 31337)
	session.set_ready(&"p0", true)
	session.request_loan(&"p0", LoanRules.max_loan_for(session.state().player_by_id(&"p0")))

	watch_signals(session)
	session.pay_loan(&"p0", 1)  # below the minimum
	assert_signal_emitted(session, "action_rejected")


func test_a_player_may_ready_up_with_an_unpaid_loan() -> void:
	# Deliberate: the prompt is advisory. The game must never withhold the choice
	# to skip a payment and take the penalty. See docs/game-rules.md §9.5.
	var session: LocalSession = _make_session(10, true, 31337)
	session.set_ready(&"p0", true)
	session.request_loan(&"p0", LoanRules.max_loan_for(session.state().player_by_id(&"p0")))

	var year_before: int = session.state().year
	session.set_ready(&"p0", true)
	assert_eq(session.state().year, year_before + 1,
		"readying up with an unpaid loan must be allowed")
