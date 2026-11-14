class_name YearResult
extends RefCounted
## An immutable record of everything one year advance did.
##
## This is the keystone of the design and serves four jobs at once:
##   1. The UI animates from it — it already knows what changed, and in what order.
##   2. The host broadcasts it; clients never compute economics themselves.
##   3. Tests assert on it — a whole year's outcome is one inspectable value.
##   4. A list of them is the match history, which later feeds charts and
##      year-over-year figures. See docs/architecture.md §3 and §7.


var year: int = 0

var mood: MarketMood.Value = MarketMood.Value.BULL

## This year's special event, or null if no viable event could be drawn — which
## happens when every candidate targets an already-bankrupt stalk.
var event: SpecialEventDefinition = null

## One entry per stalk, in board order.
var stalk_changes: Array[StalkYearChange] = []

## Dividend paid this year, keyed by player id. Players who earned nothing are
## still present, with 0.
var dividends: Dictionary[StringName, int] = {}

## One entry per player who had an outstanding loan processed this year. Players
## without a loan are absent entirely, so this is usually empty.
var loan_changes: Array[LoanYearChange] = []

## Net worth after everything settled, keyed by player id.
var net_worths: Dictionary[StringName, int] = {}

## Player ids ordered best first: by net worth, then by cash on hand.
## Ties remain adjacent — use `winners` for the actual result.
var rankings: Array[StringName] = []

## Set only on the final year advance. All tied players win, so this may hold
## more than one id. See docs/game-rules.md §1 and §12.
var winners: Array[StringName] = []

var is_final_year: bool = false


func change_for(stalk_id: StringName) -> StalkYearChange:
	for change: StalkYearChange in stalk_changes:
		if change.stalk_id == stalk_id:
			return change
	return null


func split_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for change: StalkYearChange in stalk_changes:
		if change.did_split:
			ids.append(change.stalk_id)
	return ids


func bankrupt_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for change: StalkYearChange in stalk_changes:
		if change.went_bankrupt:
			ids.append(change.stalk_id)
	return ids


## Loan record for one player this year, or null if they had none processed.
func loan_change_for(player_id: StringName) -> LoanYearChange:
	for change: LoanYearChange in loan_changes:
		if change.player_id == player_id:
			return change
	return null


## Players wiped out by a third missed loan payment this year.
func defaulted_player_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for change: LoanYearChange in loan_changes:
		if change.defaulted:
			ids.append(change.player_id)
	return ids


func _to_string() -> String:
	return "YearResult(year=%d mood=%s splits=%d bankruptcies=%d)" % [
		year, MarketMood.label(mood), split_ids().size(), bankrupt_ids().size(),
	]
