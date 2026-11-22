extends GutTest
## Loans: annuity arithmetic, eligibility, payments, and the yearly assessment.
## See docs/game-rules.md §9.


var _state: GameState
var _player: PlayerState


func before_each() -> void:
	_state = StalksFixture.make_state_with_loans(10, 1)
	_state.year = 2  # loans become available in year 2
	_player = _state.players[0]
	_player.net_worth = 10000


## A player with cash to spare, so payments are never blocked by affordability.
func _solvent_borrower(principal: int = 2500) -> LoanState:
	var loan: LoanState = LoanRules.take_loan(_player, principal)
	_player.cash = 100000
	return loan


# ------------------------------------------------------------------- arithmetic

func test_annuity_factor_for_the_standard_term() -> void:
	assert_almost_eq(LoanRules.annuity_factor(10), 7.360087, 0.00001)


func test_annuity_factor_of_a_nonsense_term_is_zero_not_a_crash() -> void:
	assert_eq(LoanRules.annuity_factor(0), 0.0)
	assert_eq(LoanRules.annuity_factor(-5), 0.0)


func test_minimum_payment_for_the_standard_term() -> void:
	# principal / a(10, 6%), truncated toward zero.
	assert_eq(LoanRules.minimum_payment(100, 10), 13)
	assert_eq(LoanRules.minimum_payment(1000, 10), 135)
	assert_eq(LoanRules.minimum_payment(2500, 10), 339)
	assert_eq(LoanRules.minimum_payment(10000, 10), 1358)


func test_minimum_payment_with_no_time_left_is_the_whole_balance() -> void:
	assert_eq(LoanRules.minimum_payment(500, 0), 500)
	assert_eq(LoanRules.minimum_payment(500, -1), 500)


func test_max_loan_is_a_quarter_of_net_worth() -> void:
	assert_eq(LoanRules.max_loan_for(_player), 2500)
	_player.net_worth = 4001
	assert_eq(LoanRules.max_loan_for(_player), 1000, "truncates, not rounds")
	_player.net_worth = 0
	assert_eq(LoanRules.max_loan_for(_player), 0)


# ------------------------------------------------------------------ eligibility

func test_a_valid_request_is_allowed() -> void:
	assert_eq(LoanRules.validate_take_loan(_player, 1000, _state), "")


func test_rejected_when_loans_are_disabled() -> void:
	_state.settings.loans_enabled = false
	assert_ne(LoanRules.validate_take_loan(_player, 1000, _state), "")


func test_rejected_before_year_two() -> void:
	_state.year = 1
	assert_ne(LoanRules.validate_take_loan(_player, 1000, _state), "")
	_state.year = 2
	assert_eq(LoanRules.validate_take_loan(_player, 1000, _state), "")


func test_rejected_when_bankrupt() -> void:
	_player.is_bankrupt = true
	assert_ne(LoanRules.validate_take_loan(_player, 1000, _state), "")


func test_rejected_above_the_maximum() -> void:
	assert_eq(LoanRules.validate_take_loan(_player, 2500, _state), "",
		"exactly the maximum is allowed")
	assert_ne(LoanRules.validate_take_loan(_player, 2501, _state), "")


func test_rejected_below_the_minimum() -> void:
	assert_eq(LoanRules.validate_take_loan(_player, 100, _state), "",
		"exactly the minimum is allowed")
	assert_ne(LoanRules.validate_take_loan(_player, 99, _state), "")


func test_rejected_when_net_worth_is_too_low_to_borrow_against() -> void:
	# A quarter of 300 is 75, below the 100 minimum.
	_player.net_worth = 300
	assert_ne(LoanRules.validate_take_loan(_player, 100, _state), "")


func test_only_one_loan_per_game_even_after_paying_it_off() -> void:
	# Faithful to the original, where the "has a loan" flag was set once and
	# never cleared. See docs/decisions.md D27.
	var loan: LoanState = _solvent_borrower(1000)
	assert_ne(LoanRules.validate_take_loan(_player, 500, _state), "",
		"cannot take a second loan while one is outstanding")

	LoanRules.apply_payment(_player, loan.balance)
	assert_true(loan.is_paid_off)
	assert_ne(LoanRules.validate_take_loan(_player, 500, _state), "",
		"cannot take another loan even after the first is paid off")


func test_multiple_loans_are_off_by_default() -> void:
	# The base game's rule is the default; StalkleHeads turns it on (D159).
	assert_false(GameSettings.new().multiple_loans_enabled)


func test_with_multiple_loans_a_settled_loan_frees_the_slot() -> void:
	_state.settings.multiple_loans_enabled = true
	var loan: LoanState = _solvent_borrower(1000)
	LoanRules.apply_payment(_player, loan.balance)
	assert_true(loan.is_paid_off)
	assert_eq(LoanRules.validate_take_loan(_player, 500, _state), "",
		"a paid-off loan no longer blocks a new one")

	var second: LoanState = LoanRules.take_loan(_player, 500)
	assert_eq(_player.loan, second, "the new loan replaces the settled one")
	assert_eq(second.balance, 500)
	assert_eq(second.years_remaining, LoanRules.TERM_YEARS + 1, "a fresh term")


func test_with_multiple_loans_it_is_still_one_at_a_time() -> void:
	_state.settings.multiple_loans_enabled = true
	_solvent_borrower(1000)
	assert_eq(LoanRules.validate_take_loan(_player, 500, _state),
		"You must pay off your loan before taking another.")


func test_multiple_loans_change_nothing_while_loans_are_disabled() -> void:
	_state.settings.multiple_loans_enabled = true
	_state.settings.loans_enabled = false
	assert_eq(LoanRules.validate_take_loan(_player, 500, _state), "Loans are disabled in this game.")


# ---------------------------------------------------------------- taking a loan

func test_taking_a_loan_pays_cash_out_immediately() -> void:
	_player.cash = 500
	LoanRules.take_loan(_player, 2000)
	assert_eq(_player.cash, 2500)


func test_a_new_loan_is_set_up_correctly() -> void:
	var loan: LoanState = LoanRules.take_loan(_player, 2500)
	assert_eq(loan.balance, 2500)
	assert_eq(loan.min_payment, 339, "amortised over the 10-year term")
	assert_eq(loan.years_remaining, 11,
		"starts at 11 because the year-end pass decrements before assessing")
	assert_true(loan.paid_this_year,
		"treated as paid so the first year-end counts no miss")
	assert_eq(loan.missed_payments, 0)
	assert_false(loan.is_settled())


# --------------------------------------------------------------------- payments

func test_payment_below_the_minimum_is_rejected() -> void:
	var loan: LoanState = _solvent_borrower()
	assert_ne(LoanRules.validate_payment(_player, loan.min_payment - 1), "",
		"partial payments are refused outright")
	assert_eq(LoanRules.validate_payment(_player, loan.min_payment), "")


func test_payment_above_available_cash_is_rejected() -> void:
	_solvent_borrower()
	_player.cash = 200
	assert_ne(LoanRules.validate_payment(_player, 500), "")


func test_payment_without_a_loan_is_rejected() -> void:
	assert_ne(LoanRules.validate_payment(_player, 100), "")


func test_payment_on_a_settled_loan_is_rejected() -> void:
	var loan: LoanState = _solvent_borrower()
	LoanRules.apply_payment(_player, loan.balance)
	assert_ne(LoanRules.validate_payment(_player, 100), "")


func test_a_payment_reduces_balance_and_cash_together() -> void:
	var loan: LoanState = _solvent_borrower()
	var cash_before: int = _player.cash
	LoanRules.apply_payment(_player, 339)
	assert_eq(loan.balance, 2161)
	assert_eq(_player.cash, cash_before - 339)


func test_overpayment_is_clamped_to_the_balance() -> void:
	var loan: LoanState = _solvent_borrower(1000)
	var cash_before: int = _player.cash
	var paid: int = LoanRules.apply_payment(_player, 5000)
	assert_eq(paid, 1000, "cannot pay more than is owed")
	assert_eq(loan.balance, 0)
	assert_eq(_player.cash, cash_before - 1000, "only the owed amount leaves cash")
	assert_true(loan.is_paid_off)
	assert_eq(loan.min_payment, 0)


func test_overpayment_lowers_the_next_minimum() -> void:
	var loan: LoanState = _solvent_borrower()
	var minimum_before: int = loan.min_payment
	LoanRules.apply_payment(_player, 1000)
	assert_lt(loan.min_payment, minimum_before,
		"a bigger payment leaves less to amortise, so the minimum drops")


func test_paying_marks_the_year_as_paid() -> void:
	var loan: LoanState = _solvent_borrower()
	loan.paid_this_year = false
	LoanRules.apply_payment(_player, loan.min_payment)
	assert_true(loan.paid_this_year)


# ------------------------------------------------- the canonical 10-year schedule

func test_the_first_year_is_interest_only_and_not_a_miss() -> void:
	# "If you take out a loan this year, your first payment is NEXT year."
	var loan: LoanState = _solvent_borrower()
	var change: LoanYearChange = LoanRules.process_year_end(_player)

	assert_eq(loan.missed_payments, 0, "not paying in the loan year is not a miss")
	assert_eq(change.penalty_added, 0)
	assert_eq(change.interest_added, 150, "2500 at 6%")
	assert_eq(loan.balance, 2650)
	assert_eq(loan.years_remaining, 10)


func test_paying_the_minimum_each_year_settles_in_exactly_ten_payments() -> void:
	# The canonical schedule, matching docs/game-rules.md §9.2.1 exactly:
	# nothing in the loan year, then ten payments, landing precisely on zero.
	var loan: LoanState = _solvent_borrower()
	LoanRules.process_year_end(_player)  # the interest-only first year
	assert_eq(loan.balance, 2650)

	# year, payment due, balance after that year's interest
	var schedule: Array = [
		[2, 339, 2449],
		[3, 339, 2236],
		[4, 339, 2010],
		[5, 339, 1771],
		[6, 339, 1517],
		[7, 339, 1248],
		[8, 339, 963],
		[9, 340, 660],
		[10, 339, 340],
		[11, 340, 0],
	]

	var payments: int = 0
	var total_paid: int = 0
	for row: Array in schedule:
		var year: int = row[0]
		var expected_payment: int = row[1]
		var expected_balance: int = row[2]

		assert_eq(loan.min_payment, expected_payment,
			"year %d minimum payment" % year)
		total_paid += LoanRules.apply_payment(_player, loan.min_payment)
		payments += 1
		LoanRules.process_year_end(_player)
		assert_eq(loan.balance, expected_balance, "year %d balance" % year)

	assert_eq(payments, 10, "the advertised ten-year term means ten payments")
	assert_eq(loan.balance, 0, "lands exactly on zero")
	assert_true(loan.is_paid_off)
	assert_eq(total_paid, 3392, "2500 borrowed, 892 in interest")


func test_the_minimum_payment_drifts_by_one_from_truncation() -> void:
	# Expected behaviour, not a bug — the original did this too, and the write-up
	# describes it. Over the schedule above the minimum is 339 or 340, never
	# further from 339 than that.
	var loan: LoanState = _solvent_borrower()
	LoanRules.process_year_end(_player)

	var seen: Dictionary[int, bool] = {}
	while not loan.is_settled():
		seen[loan.min_payment] = true
		LoanRules.apply_payment(_player, loan.min_payment)
		LoanRules.process_year_end(_player)

	for amount: int in seen:
		assert_between(amount, 338, 341,
			"minimum payment %d drifted further than +/-1" % amount)
	assert_true(seen.size() > 1, "the drift should actually occur, not be flat")


# ----------------------------------------------------------- missed payments

func test_first_missed_payment_adds_ten_percent() -> void:
	var loan: LoanState = _solvent_borrower()
	LoanRules.process_year_end(_player)  # free first year, balance 2650

	var change: LoanYearChange = LoanRules.process_year_end(_player)
	assert_eq(loan.missed_payments, 1)
	assert_eq(change.penalty_added, 265, "10% of 2650")
	assert_false(change.defaulted)


func test_second_missed_payment_adds_fifteen_percent() -> void:
	var loan: LoanState = _solvent_borrower()
	LoanRules.process_year_end(_player)
	LoanRules.process_year_end(_player)  # first miss
	var before: int = loan.balance

	var change: LoanYearChange = LoanRules.process_year_end(_player)
	assert_eq(loan.missed_payments, 2)
	assert_eq(change.penalty_added, int(before * 1.15) - before, "15% penalty")
	assert_false(change.defaulted)


func test_a_penalty_raises_the_minimum_payment() -> void:
	var loan: LoanState = _solvent_borrower()
	LoanRules.process_year_end(_player)
	var minimum_before: int = loan.min_payment
	LoanRules.process_year_end(_player)  # first miss
	assert_gt(loan.min_payment, minimum_before,
		"a bigger balance over fewer years means a bigger minimum")


func test_third_missed_payment_bankrupts_the_player() -> void:
	var loan: LoanState = _solvent_borrower()
	_player.cash = 5000
	_player.set_shares(&"stryker", 25)

	LoanRules.process_year_end(_player)  # free first year
	LoanRules.process_year_end(_player)  # miss 1
	LoanRules.process_year_end(_player)  # miss 2
	var change: LoanYearChange = LoanRules.process_year_end(_player)  # miss 3

	assert_true(change.defaulted)
	assert_true(_player.is_bankrupt)
	assert_eq(_player.cash, 0, "all assets seized")
	assert_eq(_player.net_worth, 0)
	assert_eq(_player.shares_of(&"stryker"), 0, "holdings cleared")
	assert_true(loan.is_defaulted)
	assert_true(loan.is_settled())
	assert_eq(loan.balance, 0)


func test_default_lands_on_the_fourth_year_end_because_the_first_is_free() -> void:
	var loan: LoanState = _solvent_borrower()
	var year_ends: int = 0
	while not loan.is_settled() and year_ends < 10:
		LoanRules.process_year_end(_player)
		year_ends += 1
	assert_eq(year_ends, 4,
		"one free year plus three misses")


func test_a_settled_loan_is_not_processed_again() -> void:
	var loan: LoanState = _solvent_borrower(1000)
	LoanRules.apply_payment(_player, 1000)
	assert_true(loan.is_paid_off)
	assert_null(LoanRules.process_year_end(_player),
		"a settled loan yields no year-end record")


func test_a_player_without_a_loan_yields_no_record() -> void:
	assert_null(LoanRules.process_year_end(_player))


# ---------------------------------------------------------- net worth and pipeline

func test_an_outstanding_loan_reduces_net_worth() -> void:
	_solvent_borrower()
	_player.cash = 10000
	assert_eq(_player.owes(), 2500)
	assert_eq(TradeRules.net_worth(_player, _state), 7500)


func test_a_settled_loan_stops_reducing_net_worth() -> void:
	var loan: LoanState = _solvent_borrower()
	_player.cash = 10000
	LoanRules.apply_payment(_player, loan.balance)
	assert_eq(_player.owes(), 0)
	assert_eq(TradeRules.net_worth(_player, _state), 10000 - 2500)


func test_a_defaulted_loan_stops_reducing_net_worth() -> void:
	_solvent_borrower()
	for i: int in 4:
		LoanRules.process_year_end(_player)
	assert_eq(_player.owes(), 0, "a written-off balance is not still owed")


func test_the_year_pipeline_processes_loans() -> void:
	var loan: LoanState = _solvent_borrower()
	var result: YearResult = StalksFixture.frozen_resolver().advance_year(
		_state, StalksFixture.rng(1)
	)

	assert_eq(result.loan_changes.size(), 1)
	var change: LoanYearChange = result.loan_change_for(&"p0")
	assert_not_null(change)
	assert_eq(change.interest_added, 150)
	assert_eq(loan.balance, 2650, "interest charged by the pipeline")


func test_the_pipeline_skips_loans_entirely_when_disabled() -> void:
	var loan: LoanState = _solvent_borrower()
	_state.settings.loans_enabled = false

	var result: YearResult = StalksFixture.frozen_resolver().advance_year(
		_state, StalksFixture.rng(1)
	)

	assert_eq(result.loan_changes.size(), 0)
	assert_eq(loan.balance, 2500, "no interest charged when loans are off")


func test_the_pipeline_reports_a_default() -> void:
	_solvent_borrower()
	var resolver: YearResolver = StalksFixture.frozen_resolver()
	var defaulted: bool = false
	for i: int in 4:
		var result: YearResult = resolver.advance_year(_state, StalksFixture.rng(1))
		if result.defaulted_player_ids().has(&"p0"):
			defaulted = true
	assert_true(defaulted, "the third miss should surface in a YearResult")
	assert_true(_player.is_bankrupt)


func test_net_worth_after_the_pipeline_accounts_for_the_loan() -> void:
	_solvent_borrower()
	_player.cash = 10000
	var result: YearResult = StalksFixture.frozen_resolver().advance_year(
		_state, StalksFixture.rng(1)
	)
	# Interest took the balance to 2650, so net worth is cash less that.
	assert_eq(result.net_worths[&"p0"], 10000 - 2650)
