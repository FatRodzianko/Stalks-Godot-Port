extends GutTest
## Buying, selling, net worth and standings. See docs/game-rules.md §1 and §11.
##
## The validation functions here are the single implementation shared by the
## host's enforcement and a client's instant pre-check, so these tests cover both.


var _state: GameState
var _player: PlayerState
var _stryker: StalkState


func before_each() -> void:
	_state = StalksFixture.make_state(10, 1)
	_state.year = 1  # trading is closed in year 0
	_player = _state.players[0]
	_stryker = _state.stalk_by_id(&"stryker")


# ------------------------------------------------------------------------ buying

func test_affordable_purchase_is_allowed() -> void:
	assert_eq(TradeRules.validate_buy(_player, _stryker, 10, _state), "")


func test_unaffordable_purchase_is_rejected_with_a_reason() -> void:
	# The original failed silently here; the port must always explain itself.
	var reason: String = TradeRules.validate_buy(_player, _stryker, 1000, _state)
	assert_ne(reason, "", "an unaffordable purchase must be rejected")
	assert_true(reason.contains("10000"), "the reason should state the player's cash")


func test_zero_or_negative_shares_are_rejected() -> void:
	assert_ne(TradeRules.validate_buy(_player, _stryker, 0, _state), "")
	assert_ne(TradeRules.validate_buy(_player, _stryker, -5, _state), "")


func test_buying_a_bankrupt_stalk_is_rejected() -> void:
	_stryker.is_bankrupt = true
	assert_ne(TradeRules.validate_buy(_player, _stryker, 1, _state), "")


func test_trading_is_closed_in_year_zero() -> void:
	_state.year = 0
	assert_ne(TradeRules.validate_buy(_player, _stryker, 1, _state), "")
	assert_ne(TradeRules.validate_sell(_player, _stryker, 1, _state), "")


func test_trading_is_closed_once_the_game_is_over() -> void:
	_state.is_over = true
	assert_ne(TradeRules.validate_buy(_player, _stryker, 1, _state), "")


func test_exact_cash_purchase_is_allowed() -> void:
	# 100 shares at 100 is exactly the 10000 starting cash.
	assert_eq(TradeRules.validate_buy(_player, _stryker, 100, _state), "")
	assert_ne(TradeRules.validate_buy(_player, _stryker, 101, _state), "")


func test_applying_a_purchase_moves_cash_and_shares() -> void:
	TradeRules.apply_buy(_player, _stryker, 10)
	assert_eq(_player.cash, 9000)
	assert_eq(_player.shares_of(&"stryker"), 10)


func test_max_affordable() -> void:
	assert_eq(TradeRules.max_affordable(_player, _stryker), 100)
	_player.cash = 250
	assert_eq(TradeRules.max_affordable(_player, _stryker), 2)


func test_max_affordable_of_a_worthless_stalk_is_zero_not_a_crash() -> void:
	_stryker.is_bankrupt = true
	_stryker.price = 0
	assert_eq(TradeRules.max_affordable(_player, _stryker), 0)


# ----------------------------------------------------------------------- selling

func test_selling_what_you_do_not_own_is_rejected() -> void:
	assert_ne(TradeRules.validate_sell(_player, _stryker, 5, _state), "")


func test_overselling_is_rejected() -> void:
	TradeRules.apply_buy(_player, _stryker, 10)
	assert_eq(TradeRules.validate_sell(_player, _stryker, 10, _state), "")
	assert_ne(TradeRules.validate_sell(_player, _stryker, 11, _state), "")


func test_selling_returns_cash_at_the_current_price() -> void:
	TradeRules.apply_buy(_player, _stryker, 10)
	_stryker.price = 150
	TradeRules.apply_sell(_player, _stryker, 10)
	assert_eq(_player.cash, 9000 + 1500)
	assert_eq(_player.shares_of(&"stryker"), 0)


func test_holdings_entry_is_removed_at_zero() -> void:
	TradeRules.apply_buy(_player, _stryker, 5)
	TradeRules.apply_sell(_player, _stryker, 5)
	assert_false(_player.holdings.has(&"stryker"),
		"a zero position should leave no dead key behind")


# --------------------------------------------------------------------- net worth

func test_net_worth_of_cash_only() -> void:
	assert_eq(TradeRules.net_worth(_player, _state), 10000)


func test_net_worth_includes_holdings() -> void:
	TradeRules.apply_buy(_player, _stryker, 10)  # -1000 cash, +10 shares at 100
	assert_eq(TradeRules.net_worth(_player, _state), 10000)
	_stryker.price = 150
	assert_eq(TradeRules.net_worth(_player, _state), 9000 + 1500)


func test_net_worth_excludes_bankrupt_holdings() -> void:
	TradeRules.apply_buy(_player, _stryker, 10)
	_stryker.is_bankrupt = true
	_stryker.price = 0
	assert_eq(TradeRules.net_worth(_player, _state), 9000)


func test_net_worth_subtracts_an_outstanding_loan() -> void:
	_player.loan_balance = 2500
	assert_eq(TradeRules.net_worth(_player, _state), 7500)


func test_holdings_value_excludes_cash_and_loans() -> void:
	TradeRules.apply_buy(_player, _stryker, 10)
	_player.loan_balance = 5000
	assert_eq(TradeRules.holdings_value(_player, _state), 1000)


# --------------------------------------------------------------------- standings

func test_ranked_by_net_worth_then_cash() -> void:
	var a: PlayerState = PlayerState.new(&"a", "A", 0)
	var b: PlayerState = PlayerState.new(&"b", "B", 0)
	var c: PlayerState = PlayerState.new(&"c", "C", 0)
	a.net_worth = 500
	a.cash = 100
	b.net_worth = 500
	b.cash = 300
	c.net_worth = 900
	c.cash = 50

	var players: Array[PlayerState] = [a, b, c]
	assert_eq(TradeRules.rank(players), [&"c", &"b", &"a"] as Array[StringName])


func test_single_clear_winner() -> void:
	var a: PlayerState = PlayerState.new(&"a", "A", 0)
	var b: PlayerState = PlayerState.new(&"b", "B", 0)
	a.net_worth = 900
	a.cash = 10
	b.net_worth = 500
	b.cash = 10

	assert_eq(TradeRules.winners([a, b] as Array[PlayerState]),
		[&"a"] as Array[StringName])


func test_cash_breaks_a_net_worth_tie() -> void:
	var a: PlayerState = PlayerState.new(&"a", "A", 0)
	var b: PlayerState = PlayerState.new(&"b", "B", 0)
	a.net_worth = 500
	a.cash = 100
	b.net_worth = 500
	b.cash = 300

	assert_eq(TradeRules.winners([a, b] as Array[PlayerState]),
		[&"b"] as Array[StringName], "higher cash should break the tie")


func test_players_tied_on_both_net_worth_and_cash_all_win() -> void:
	var a: PlayerState = PlayerState.new(&"a", "A", 0)
	var b: PlayerState = PlayerState.new(&"b", "B", 0)
	var c: PlayerState = PlayerState.new(&"c", "C", 0)
	for p: PlayerState in [a, b, c]:
		p.net_worth = 777
		p.cash = 77

	assert_eq(TradeRules.winners([a, b, c] as Array[PlayerState]).size(), 3,
		"a three-way exact tie means all three win")


func test_winners_of_an_empty_field_is_empty() -> void:
	assert_eq(TradeRules.winners([] as Array[PlayerState]).size(), 0)
