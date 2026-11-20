class_name AchievementReporter
extends Node
## Watches a match and tells Steam what the local player has earned.
##
## The join between two halves that know nothing about each other:
## `AchievementRules` decides what was earned and has never heard of Steam,
## and `SteamService` can set an achievement but has no idea what a match is.
##
## **Only the local player.** Each machine judges its own from the replica it
## already has, so nothing crosses the wire and a client does not wait on the
## host to be given anything.
##
## **Does nothing without Steam**, which is the normal state for a solo game
## played offline. It is created anyway rather than conditionally, so there is
## one code path and not two.


## The holdings the local player had before the current year resolved.
##
## Needed because a stalk going bankrupt sets those shares to zero, so by the
## time the year's result arrives the state no longer remembers that you held
## the thing that went under. See `AchievementRules.for_year`.
var _held_before: Dictionary[StringName, int] = {}

var _session: GameSession
var _steam: SteamService


## Call once, after the session is mounted. Safe with a null service.
func setup(session: GameSession, steam: SteamService) -> void:
	_session = session
	_steam = steam
	if _session == null:
		return

	_session.player_changed.connect(_on_player_changed)
	_session.year_resolved.connect(_on_year_resolved)
	_session.game_over.connect(_on_game_over)
	_session.yeehaw_given.connect(_on_yeehaw_given)
	_remember_holdings()


## Throws away the holdings remembered from the match just finished.
##
## **Called when a rematch reopens the lobby.** This reporter is created once
## per *session* (`Main._watch_for_achievements`), and a rematch reuses the
## session — which is right, because a rematch is a real match and its wins,
## losses and net worth should count. But `_held_before` would still hold the
## previous match's final position when the new match's first year resolved, and
## `AchievementRules.for_year` reads it to decide whether a stalk that split or
## went bankrupt was one you owned. Without this, a company you held last game
## could award you either of those in a game where you own nothing.
##
## See docs/decisions.md D124.
func forget_holdings() -> void:
	_held_before = {}


## The remembered position, for a test that has no way to see an award.
## Nothing in the game calls this.
func held_before_for_testing() -> Dictionary[StringName, int]:
	return _held_before


func _exit_tree() -> void:
	if _session == null:
		return
	if not _session.player_changed.is_connected(_on_player_changed):
		return
	_session.player_changed.disconnect(_on_player_changed)
	_session.year_resolved.disconnect(_on_year_resolved)
	_session.game_over.disconnect(_on_game_over)
	_session.yeehaw_given.disconnect(_on_yeehaw_given)


# ------------------------------------------------------------- what happened

func _on_player_changed(player_id: StringName) -> void:
	if player_id != _session.local_player_id():
		# Somebody else traded. Their holdings are not ours to be awarded for,
		# and ours have not moved.
		return
	_award(AchievementRules.while_playing(_local_player(), _session.state()))
	_remember_holdings()


func _on_year_resolved(result: YearResult) -> void:
	_award(AchievementRules.for_year(
		_session.local_player_id(), _held_before, result
	))
	# The position after the year counts too: a split can push a holding past
	# the all-in threshold without anybody buying anything.
	_award(AchievementRules.while_playing(_local_player(), _session.state()))
	_remember_holdings()


func _on_yeehaw_given(giver_id: StringName, _receiver_id: StringName) -> void:
	if giver_id != _session.local_player_id():
		# The stat counts what you hand out, not what you are given.
		return
	_award_for_total(Achievements.STAT_YEEHAWS, 1)


func _on_game_over(winners: Array[StringName]) -> void:
	var player: PlayerState = _local_player()
	if player == null:
		return

	_award(AchievementRules.at_the_end(player, _session.state(), winners))

	if winners.has(player.id):
		_award_for_total(Achievements.STAT_WINS, 1)
	else:
		_award_for_total(Achievements.STAT_LOSSES, 1)
	_award_for_total(Achievements.STAT_LIFETIME_NET_WORTH, player.net_worth)


# -------------------------------------------------------------------- telling

## Adds to a lifetime counter and awards whatever that figure now reaches.
##
## Read, add, write: Steam owns the running total, so a fresh install picks up
## where the player's account left off rather than starting from nothing.
func _award_for_total(stat_name: StringName, added: int) -> void:
	if _steam == null:
		return
	var total: int = _steam.stat(stat_name) + added
	_steam.set_stat(stat_name, total)
	_award(AchievementRules.for_total(stat_name, total))


func _award(ids: Array[StringName]) -> void:
	if _steam == null or ids.is_empty():
		return
	for id: StringName in ids:
		_steam.unlock(id)
	_steam.store_progress()


# ------------------------------------------------------------------ internals

func _local_player() -> PlayerState:
	if _session == null or _session.state() == null:
		return null
	return _session.state().player_by_id(_session.local_player_id())


func _remember_holdings() -> void:
	var player: PlayerState = _local_player()
	if player == null:
		_held_before = {}
		return
	_held_before = player.holdings.duplicate()
