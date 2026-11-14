class_name LoanState
extends RefCounted
## One player's loan. Pure data — the rules that act on it live in LoanRules.
##
## A player may take **one loan for the entire game**, even after paying it off.
## That is faithful to the original, where the "has a loan" flag was set once and
## never cleared (the only line that would reset it is commented out). So the
## presence of a LoanState on a player means "has taken a loan", not "currently
## owes money" — use `is_settled()` for that.
##
## See docs/game-rules.md §9.


var balance: int = 0

## Recalculated every year and after every payment, which is why it drifts by
## about ±1 from integer truncation. That drift is faithful behaviour, not a bug.
var min_payment: int = 0

## Starts at 11, not 10. The year-end pass decrements this before doing anything
## else, so a loan taken during year N has 10 payment years left once that first
## year closes. The opening minimum payment is still amortised over 10.
var years_remaining: int = 0

var missed_payments: int = 0

## Whether a payment has been made for the current year. Set true the moment the
## loan is taken out, which is how "your first payment is next year" is
## implemented: the first year-end sees it as paid and counts no miss.
var paid_this_year: bool = false

var is_paid_off: bool = false

## Set when a third missed payment wipes the player out.
var is_defaulted: bool = false


## Nothing more is owed — either cleared, or written off by a default.
func is_settled() -> bool:
	return is_paid_off or is_defaulted


## What this loan currently subtracts from net worth.
func amount_owed() -> int:
	return 0 if is_settled() else balance


func _to_string() -> String:
	var tag: String = ""
	if is_paid_off:
		tag = " PAID OFF"
	elif is_defaulted:
		tag = " DEFAULTED"
	return "LoanState(balance=%d min=%d years=%d missed=%d%s)" % [
		balance, min_payment, years_remaining, missed_payments, tag,
	]
