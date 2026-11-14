class_name LoanRules
extends RefCounted
## Loan arithmetic, eligibility, payments and the yearly assessment. All static,
## all pure. See docs/game-rules.md §9.
##
## The scheme is a textbook amortising loan: 10 years at 6% compound, with the
## minimum payment being `principal / a(n, 6%)` truncated to an integer. The
## annual re-amortisation is load-bearing, not cosmetic — hold the payment fixed
## and truncation makes the schedule overshoot.
##
## As with TradeRules, the validation functions are the single implementation
## shared by the host's enforcement and a client's instant pre-check. They return
## an empty string for "allowed", or a player-facing reason why not.


const TERM_YEARS: int = 10
const ANNUAL_RATE: float = 0.06
const MIN_PRINCIPAL: int = 100
const MAX_NET_WORTH_FRACTION: float = 0.25

## Loans only become available from this year onward.
const FIRST_YEAR_AVAILABLE: int = 2

## A third missed payment wipes the player out.
const MISSES_BEFORE_DEFAULT: int = 3

const FIRST_MISS_MULTIPLIER: float = 1.10
const SECOND_MISS_MULTIPLIER: float = 1.15


# ------------------------------------------------------------------- arithmetic

## The present-value annuity factor a(n, 6%): `((1+i)^n - 1) / (i * (1+i)^n)`.
##
## Dividing a principal by this gives the level payment that amortises it to zero
## over n years. For the standard 10-year term it is about 7.360087.
static func annuity_factor(years: int) -> float:
	if years <= 0:
		return 0.0
	var growth: float = pow(1.0 + ANNUAL_RATE, years)
	return (growth - 1.0) / (ANNUAL_RATE * growth)


## The minimum yearly payment for a principal over a term.
##
## Truncated toward zero, matching the original's `(int)` cast. That truncation
## is what makes the minimum drift by about ±1 between years.
##
## A term of zero or less means there is no time left to spread the balance over,
## so the whole balance is due.
static func minimum_payment(principal: int, years: int) -> int:
	if years <= 0:
		return principal
	var factor: float = annuity_factor(years)
	if factor <= 0.0:
		return principal
	return int(principal / factor)


## The largest loan this player could take: 25% of their last computed net worth.
##
## Deliberately uses the stored `net_worth` rather than recomputing, matching the
## original — the figure a player sees offered is the one from the last year-end.
static func max_loan_for(player: PlayerState) -> int:
	return int(player.net_worth * MAX_NET_WORTH_FRACTION)


# ------------------------------------------------------------------ taking a loan

static func validate_take_loan(
	player: PlayerState,
	amount: int,
	state: GameState,
) -> String:
	if state.settings == null or not state.settings.loans_enabled:
		return "Loans are disabled in this game."
	if state.year < FIRST_YEAR_AVAILABLE:
		return "Loans are not available until year %d." % FIRST_YEAR_AVAILABLE
	if player.is_bankrupt:
		return "You are bankrupt."
	if player.loan != null:
		# One loan per player for the whole game, even once it is paid off.
		return "You have already taken a loan this game."

	var maximum: int = max_loan_for(player)
	if maximum < MIN_PRINCIPAL:
		return "Your net worth is too low to borrow against."
	if amount > maximum:
		return "A loan of %d is more than your maximum of %d." % [amount, maximum]
	if amount < MIN_PRINCIPAL:
		return "The minimum loan is %d." % MIN_PRINCIPAL
	return ""


## Issues the loan and pays the cash out immediately. Caller must have validated.
static func take_loan(player: PlayerState, amount: int) -> LoanState:
	var loan: LoanState = LoanState.new()
	loan.balance = amount
	# The opening minimum is amortised over the full term...
	loan.min_payment = minimum_payment(amount, TERM_YEARS)
	# ...but the counter starts one higher, because the year-end pass decrements
	# it before assessing anything. See LoanState.years_remaining.
	loan.years_remaining = TERM_YEARS + 1
	# Treated as already paid for the current year, which is how "your first
	# payment is next year" avoids counting an immediate miss.
	loan.paid_this_year = true
	loan.missed_payments = 0

	player.loan = loan
	player.cash += amount
	return loan


# --------------------------------------------------------------------- payments

static func validate_payment(player: PlayerState, amount: int) -> String:
	var loan: LoanState = player.loan
	if loan == null:
		return "You do not have a loan."
	if loan.is_settled():
		return "Your loan is already settled."
	if amount <= 0:
		return "Enter a payment amount."
	if amount < loan.min_payment:
		# Partial payments are refused outright — the original did the same.
		return "The minimum payment is %d." % loan.min_payment
	if amount > player.cash:
		return "A payment of %d is more than your cash of %d." % [amount, player.cash]
	return ""


## Applies a payment. Caller must have validated.
##
## Overpaying is allowed and is clamped to the outstanding balance, so a player
## can never pay a loan below zero. Any remaining balance is then re-amortised
## over the years that will be left after this year closes, which is why
## overpaying visibly lowers next year's minimum.
static func apply_payment(player: PlayerState, amount: int) -> int:
	var loan: LoanState = player.loan
	if loan == null or loan.is_settled():
		return 0

	var payment: int = mini(amount, loan.balance)
	loan.balance -= payment
	player.cash -= payment
	loan.paid_this_year = true

	if loan.balance > 0:
		loan.min_payment = minimum_payment(loan.balance, loan.years_remaining - 1)
	else:
		loan.balance = 0
		loan.min_payment = 0
		loan.is_paid_off = true

	return payment


# ----------------------------------------------------------- the yearly assessment

## Runs the year-end pass for one player's loan, in the original's order:
## decrement the term, assess a missed payment and its penalty, then charge
## interest on whatever remains.
##
## Returns null when the player has no outstanding loan to process.
static func process_year_end(player: PlayerState) -> LoanYearChange:
	var loan: LoanState = player.loan
	if loan == null or loan.is_settled():
		return null

	var change: LoanYearChange = LoanYearChange.new()
	change.player_id = player.id
	change.balance_before = loan.balance
	change.paid_during_year = loan.paid_this_year

	loan.years_remaining -= 1

	if loan.paid_this_year:
		loan.paid_this_year = false
	else:
		loan.missed_payments += 1
		change.missed_payments = loan.missed_payments

		if loan.missed_payments >= MISSES_BEFORE_DEFAULT:
			_default(player, loan, change)
			return change

		var multiplier: float = (
			FIRST_MISS_MULTIPLIER
			if loan.missed_payments == 1
			else SECOND_MISS_MULTIPLIER
		)
		var penalised: int = int(loan.balance * multiplier)
		change.penalty_added = penalised - loan.balance
		loan.balance = penalised
		loan.min_payment = minimum_payment(loan.balance, loan.years_remaining)

	change.missed_payments = loan.missed_payments

	var with_interest: int = int(loan.balance * (1.0 + ANNUAL_RATE))
	change.interest_added = with_interest - loan.balance
	loan.balance = with_interest

	change.balance_after = loan.balance
	change.min_payment_after = loan.min_payment
	return change


## A third missed payment: all assets seized, player out of the game.
static func _default(
	player: PlayerState,
	loan: LoanState,
	change: LoanYearChange,
) -> void:
	loan.is_defaulted = true
	loan.balance = 0
	loan.min_payment = 0
	loan.years_remaining = 0

	player.cash = 0
	player.net_worth = 0
	player.clear_holdings()
	player.is_bankrupt = true

	change.defaulted = true
	change.balance_after = 0
	change.min_payment_after = 0
