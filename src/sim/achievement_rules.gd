class_name AchievementRules
extends RefCounted
## Which achievements a match has earned. All static, all pure.
##
## The ids and what each one means live in `Achievements`, read out of the
## original game. This is the other half: given a match, which of them the
## local player has just earned.
##
## **Pure on purpose, like every other rule in `src/sim/`.** Steam is nowhere
## in this file. It takes state and returns ids, which means every threshold
## can be tested without Steam, without a window and without a network — and
## they have to be, because the only other way to check an achievement is to
## unlock it for real on somebody's Steam account, which cannot be undone a
## test at a time. `AchievementReporter` is the part that talks to Steam.
##
## **These are per-player and local.** Each machine judges its own player from
## the replica it already has, so nothing needs to cross the wire and a client
## does not depend on the host to award anything.


## Hold this many shares of one stalk. From the original.
const ALL_IN_SHARES: int = 300

## Hold at least this many of *every* stalk at once.
const DIVERSIFIED_SHARES: int = 10

## `NETWORTH_FIFTY` wants this much at the end, and only counts if the match
## started with `NETWORTH_FIFTY_MAX_START` or less — otherwise a generous
## lobby setting buys it.
const NETWORTH_FIFTY_TARGET: int = 50000
const NETWORTH_FIFTY_MAX_START: int = 10000

## `NETWORTH_HUNDRED` is a wipe-out, not a milestone: finish with this or less.
const WIPEOUT_NET_WORTH: int = 100

const MORTGAGE_YEARS: int = 30
const CENTURY_YEARS: int = 99


## Earned by the position a player is in right now, checked whenever their
## holdings or their loan change.
static func while_playing(player: PlayerState, game: GameState) -> Array[StringName]:
	var earned: Array[StringName] = []
	if player == null or game == null:
		return earned

	for stalk: StalkState in game.stalks:
		if player.shares_of(stalk.id) >= ALL_IN_SHARES:
			earned.append(Achievements.ALL_IN)
			break

	if _holds_some_of_everything(player, game):
		earned.append(Achievements.DIVERSIFIED)

	# A player may only ever take one loan per game, so `loan` being set at all
	# means they borrowed, whether or not anything is still owed.
	if player.loan != null:
		earned.append(Achievements.TOOK_OUT_LOAN)
		if player.loan.is_paid_off:
			earned.append(Achievements.PAID_LOAN)

	return earned


## Earned by what a year did to you.
##
## `held_before` is the player's holdings as they were **before** the year
## resolved, because a stalk going bankrupt sets those shares to zero
## (`YearResolver`). Asking the current state whether you held the stalk that
## just went under would always answer no.
static func for_year(
	player_id: StringName,
	held_before: Dictionary[StringName, int],
	result: YearResult,
) -> Array[StringName]:
	var earned: Array[StringName] = []
	if result == null:
		return earned

	for stalk_id: StringName in result.split_ids():
		if held_before.get(stalk_id, 0) > 0:
			earned.append(Achievements.SPLIT)
			break

	for stalk_id: StringName in result.bankrupt_ids():
		if held_before.get(stalk_id, 0) > 0:
			earned.append(Achievements.BANKRUPT)
			break

	var loan_change: LoanYearChange = result.loan_change_for(player_id)
	if loan_change != null and loan_change.defaulted:
		earned.append(Achievements.DEFAULT_LOAN)

	return earned


## Earned by how the match finished.
static func at_the_end(
	player: PlayerState,
	game: GameState,
	winners: Array[StringName],
) -> Array[StringName]:
	var earned: Array[StringName] = []
	if player == null or game == null or game.settings == null:
		return earned

	if winners.has(player.id):
		earned.append(Achievements.WIN_ONE)
	else:
		earned.append(Achievements.LOSE_ONE)

	var started_with: int = game.settings.starting_cash
	var ended_with: int = player.net_worth

	var modest_start: bool = started_with <= NETWORTH_FIFTY_MAX_START
	if ended_with >= NETWORTH_FIFTY_TARGET and modest_start:
		earned.append(Achievements.NETWORTH_FIFTY)
	if ended_with <= WIPEOUT_NET_WORTH:
		earned.append(Achievements.NETWORTH_HUNDRED)

	if ended_with >= started_with * 2:
		earned.append(Achievements.DOUBLED)
	# Integer division, deliberately: all money in this game is whole numbers
	# and an odd starting cash should not make this a near-miss.
	if ended_with <= started_with / 2:
		earned.append(Achievements.HALVED)

	if game.settings.max_years >= MORTGAGE_YEARS:
		earned.append(Achievements.MORTGAGE)
	if game.settings.max_years == CENTURY_YEARS:
		earned.append(Achievements.CENTURY)

	return earned


## Earned by a lifetime counter reaching a figure.
##
## The counters are Steam stats, which survive between matches; everything
## else here is decided inside one match. The thresholds are the original's.
static func for_total(stat: StringName, value: int) -> Array[StringName]:
	if stat == Achievements.STAT_WINS:
		return _past(value, {
			10: Achievements.WIN_TEN,
			100: Achievements.WIN_HUNDRED,
			1000: Achievements.WIN_THOUSAND,
		})
	if stat == Achievements.STAT_LOSSES:
		return _past(value, {
			10: Achievements.LOSE_TEN,
			100: Achievements.LOSE_HUNDRED,
			1000: Achievements.LOSE_THOUSAND,
		})
	if stat == Achievements.STAT_LIFETIME_NET_WORTH:
		return _past(value, {
			1000000: Achievements.ONE_MIL,
			1000000000: Achievements.ONE_BIL,
		})
	if stat == Achievements.STAT_YEEHAWS:
		return _past(value, {
			1: Achievements.YEEHAW_ONE,
			100: Achievements.YEEHAW_HUNDRED,
		})
	return []


## Every id whose threshold `value` has reached.
##
## All of them, not just the one just crossed: a player whose stats were
## already past a threshold before the port existed should still be given it,
## and setting an achievement that is already set is harmless.
static func _past(value: int, thresholds: Dictionary[int, StringName]) -> Array[StringName]:
	var earned: Array[StringName] = []
	for threshold: int in thresholds:
		if value >= threshold:
			earned.append(thresholds[threshold])
	return earned


static func _holds_some_of_everything(player: PlayerState, game: GameState) -> bool:
	if game.stalks.is_empty():
		return false
	for stalk: StalkState in game.stalks:
		if player.shares_of(stalk.id) < DIVERSIFIED_SHARES:
			return false
	return true
