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

## The StalkleHeads market - fundamentals, industries, sentiment, the index - or
## null in a base-game match, which never reads it. See EarningsMarket and
## docs/stalkleheads-design.md §10.2.
var market: EarningsMarket = null

## Who is currently asking for a yeehaw, or empty when nobody is.
##
## **One at a time, and it is state rather than an event**, which is what lets
## everybody else's button turn into "Give Yeehaw". The original kept exactly
## this as a pair of synced fields; see docs/game-rules.md 10.
var yeehaw_requested_by: StringName = &""


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


## Who is hosting, or an empty id in a solo game with nobody to host for.
##
## **The host is always the first player**, on every machine. The host seats
## themselves before anybody can connect (`HostSession`), and the roster order
## is preserved through the snapshot, so a client's copy agrees. Written down
## here once rather than spelled `players[0]` at each screen that needs it,
## because it is a rule about how a match is built and not a fact about lists.
## Which player's machine is running the match, when something has said so.
##
## **Not the same as "the first player", which is what this used to be.** That
## held only while a host never changed. After a migration the new host can be
## any slot, and the player who left is out of `players` entirely (D47), so
## first-in-the-list names whoever happens to be left - a bystander wearing the
## host's label. Invisible in a two-player game, where the survivor is alone
## and therefore first; wrong from three players up.
##
## Empty in a local game, and in a replica built before the host said who it
## was, where falling back to the first player is right by definition.
var hosted_by: StringName = &""


func host_player_id() -> StringName:
	if not hosted_by.is_empty():
		return hosted_by
	if players.is_empty():
		return &""
	return players[0].id


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


## The players whose peer is still connected, in roster order.
##
## **The list every "is everybody done?" question wants.** An away player is in
## `players` for every purpose that touches their money — dividends, splits,
## loans, the standings, who wins — and out of every purpose that waits for a
## decision, because nobody is there to make one. See `PlayerState.is_away` and
## docs/decisions.md D110.
func players_present() -> Array[PlayerState]:
	var here: Array[PlayerState] = []
	for player: PlayerState in players:
		if not player.is_away:
			here.append(player)
	return here


## Whether the year may resolve: everybody who is here has readied up.
##
## **False when nobody is here**, and false for an empty roster. A match whose
## players have all dropped must not sit resolving years to itself — there is
## nobody to see them, and the match would run to its end unattended before
## anybody could rejoin.
func all_players_ready() -> bool:
	var here: Array[PlayerState] = players_present()
	if here.is_empty():
		return false
	for player: PlayerState in here:
		if not player.is_ready:
			return false
	return true


## Ids of the players who have not readied up, in roster order.
##
## What the UI needs to say "waiting on Ann and Bob" rather than leaving a
## screen that looks broken while it waits.
##
## **Away players are not in this list.** The year does not wait for them, so
## naming them would be telling a player to wait for somebody who is not coming.
func players_not_ready() -> Array[StringName]:
	var waiting: Array[StringName] = []
	for player: PlayerState in players_present():
		if not player.is_ready:
			waiting.append(player.id)
	return waiting


func is_yeehaw_pending() -> bool:
	return not yeehaw_requested_by.is_empty()


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
