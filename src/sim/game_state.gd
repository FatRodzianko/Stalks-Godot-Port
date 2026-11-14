class_name GameState
extends RefCounted
## The entire state of one match: settings, the market, the players, and the
## history of every year so far.
##
## Pure data with lookup helpers. No nodes, no RNG of its own, no I/O. Everything
## that mutates this lives in YearResolver or TradeRules.


var settings: GameSettings

## Year 0 is the opening position: all prices at starting value, no trading
## allowed. See docs/game-rules.md §4.
var year: int = 0

var stalks: Array[StalkState] = []

var players: Array[PlayerState] = []

## Every YearResult produced so far, oldest first.
##
## Recorded from Year 0 onward because this data cannot be reconstructed after the
## fact — a finished match's final state says nothing about what a stalk cost in
## year 3. Keeping it costs one append per year and is what makes charts,
## year-over-year figures and replays possible later. See docs/architecture.md §7.
var history: Array[YearResult] = []

var is_over: bool = false


func _init(game_settings: GameSettings = null) -> void:
	settings = game_settings


## Trading is closed in Year 0 (the opening position) and once the match is over.
## The final year advance also resolves with trading closed — see
## docs/game-rules.md §12.
func is_trading_open() -> bool:
	return year > 0 and not is_over


func stalk_by_id(stalk_id: StringName) -> StalkState:
	for stalk: StalkState in stalks:
		if stalk.id == stalk_id:
			return stalk
	return null


func player_by_id(player_id: StringName) -> PlayerState:
	for player: PlayerState in players:
		if player.id == player_id:
			return player
	return null


## Stalks that can still move. Excludes bankrupt and static-price instruments.
func active_stalks() -> Array[StalkState]:
	var result: Array[StalkState] = []
	for stalk: StalkState in stalks:
		if not stalk.is_bankrupt and not stalk.is_price_static():
			result.append(stalk)
	return result


func all_players_ready() -> bool:
	if players.is_empty():
		return false
	for player: PlayerState in players:
		if not player.is_ready:
			return false
	return true


func clear_ready_flags() -> void:
	for player: PlayerState in players:
		player.is_ready = false


## True once the year counter has passed the configured limit, which is the
## original's game-end condition (`currentYear > maxNumberOfYears`).
func has_passed_final_year() -> bool:
	return settings != null and year > settings.max_years


func latest_result() -> YearResult:
	return history.back() if not history.is_empty() else null


func _to_string() -> String:
	return "GameState(year=%d stalks=%d players=%d)" % [
		year, stalks.size(), players.size(),
	]
