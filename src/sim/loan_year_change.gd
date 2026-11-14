class_name LoanYearChange
extends RefCounted
## What the year-end pass did to one player's loan.
##
## Part of YearResult, for the same reasons as StalkYearChange: the UI reports
## from it, and tests assert on it rather than reaching into loan internals.


var player_id: StringName = &""

var balance_before: int = 0

## Whether the player had made a payment during the year just ending.
var paid_during_year: bool = false

## Total misses so far, after this year's assessment.
var missed_payments: int = 0

## Amount added to the balance by a missed-payment penalty this year (0 if none).
var penalty_added: int = 0

## Amount added to the balance by the annual interest charge.
var interest_added: int = 0

var balance_after: int = 0

var min_payment_after: int = 0

## True on the third missed payment, which bankrupts the player outright.
var defaulted: bool = false


func _to_string() -> String:
	var tag: String = " DEFAULTED" if defaulted else ""
	return "LoanYearChange(%s %d -> %d penalty=%d interest=%d%s)" % [
		player_id, balance_before, balance_after, penalty_added, interest_added, tag,
	]
