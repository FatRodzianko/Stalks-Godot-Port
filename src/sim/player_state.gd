class_name PlayerState
extends RefCounted
## One player's live position: cash, holdings, loan, and last computed net worth.
##
## Pure data. Knows nothing about peers, nodes, or who is authoritative.


var id: StringName = &""

var display_name: String = ""

## This player's Steam account, or 0 when they are not playing through Steam.
##
## **Identity for display, nothing else.** It sits beside `display_name`, which
## is the same kind of thing: an online game reads both from Steam, a local one
## has no Steam at all. No rule may branch on it, and nothing in `src/sim`
## does — it exists so the lobby can show an avatar (audit 17.7).
##
## Public on purpose. A Steam ID is already visible to everyone in a lobby
## through Steam itself, so redacting it from the snapshot would protect
## nothing (see `state_sync.gd`).
var steam_id: int = 0

var cash: int = 0

## Shares held, keyed by StalkDefinition.id. A stalk absent from this dictionary
## is held in zero quantity; nothing distinguishes "zero" from "never owned".
var holdings: Dictionary[StringName, int] = {}

## This player's loan, or null if they have never taken one.
##
## Note that a non-null loan does NOT mean money is currently owed — it may be
## paid off or defaulted. A player may only ever take **one** loan per game, so
## the presence of this object is also what blocks a second. Use `owes()` for the
## amount outstanding. See LoanState and docs/game-rules.md §9.
var loan: LoanState = null

## Last value computed by the year resolver. Never derive gameplay from this —
## recompute with TradeRules.net_worth() when the answer must be current.
var net_worth: int = 0

## Set when a player is wiped out by a third missed loan payment.
var is_bankrupt: bool = false

## Readiness for the next year. The year only advances once every player who is
## here is ready — see `is_away`.
var is_ready: bool = false

## Whether this player's peer has gone while the match carries on without them.
##
## **They are still in the match.** An away player is paid dividends, has their
## stalks split and bankrupted, is charged loan interest, misses a loan payment
## every year they are gone, keeps their place in the standings and can still
## win. The one thing being away changes is that the year does not wait for
## them: `GameState.all_players_ready()` skips them, which is the whole purpose
## of the flag. See docs/decisions.md D47 and D110.
##
## This replaced taking the player out of `state.players` altogether, which was
## the quick way to stop one dropout deadlocking the year and cost them their
## position in the process.
##
## Cleared when they come back (`HostSession._reclaim_slot`). Always false in a
## local game, which has no peers to lose.
var is_away: bool = false


func _init(player_id: StringName = &"", name_to_show: String = "", starting_cash: int = 0) -> void:
	id = player_id
	display_name = name_to_show
	cash = starting_cash
	net_worth = starting_cash


## The loan balance currently subtracted from net worth. Zero when there is no
## loan, or when it has been paid off or written off by a default.
func owes() -> int:
	return loan.amount_owed() if loan != null else 0


## Whether this player currently has money outstanding on a loan.
func has_outstanding_loan() -> bool:
	return loan != null and not loan.is_settled()


func shares_of(stalk_id: StringName) -> int:
	return holdings.get(stalk_id, 0)


## Whether this player is in a stalk at all.
##
## The one question the board's Investors list asks. A client holds every
## player's real share counts (see `state_sync.gd`), so this is simply "do they
## hold any", asked of whoever.
func invests_in(stalk_id: StringName) -> bool:
	return shares_of(stalk_id) > 0


## Sets an absolute share count, removing the entry entirely at zero so holdings
## stays free of dead keys.
func set_shares(stalk_id: StringName, count: int) -> void:
	if count <= 0:
		holdings.erase(stalk_id)
	else:
		holdings[stalk_id] = count


func add_shares(stalk_id: StringName, count: int) -> void:
	set_shares(stalk_id, shares_of(stalk_id) + count)


## Wipes out every position. Used by split-adjacent bookkeeping and by loan
## default (docs/game-rules.md §9.3).
func clear_holdings() -> void:
	holdings.clear()


## Stalk ids currently held in a non-zero quantity.
func held_stalk_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for stalk_id: StringName in holdings:
		if holdings[stalk_id] > 0:
			ids.append(stalk_id)
	return ids


func _to_string() -> String:
	return "PlayerState(%s cash=%d net=%d)" % [id, cash, net_worth]
