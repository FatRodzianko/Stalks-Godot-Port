class_name LobbyMigration
extends RefCounted
## Who takes over a lobby when its host walks out of it.
##
## **Pure decision, no Steam.** It is told who it is, who left, and who Steam
## currently says owns the lobby, and it answers with one of four things to do.
## Everything that talks to Steam or builds a session lives in `Main`; this is
## the part that can be tested without a Steam client, a second machine or a
## network. See docs/decisions.md D104.
##
## **Steam picks the new owner, not this.** When a lobby's owner leaves, Steam
## hands ownership to another member on its own. So the question is never "who
## should it be" - it is "has Steam decided yet, and is it me". That is also
## how the owner's Unity game does it (`LobbyHostMigration.SteamMoveRoutine`),
## and it is the right shape: every client asks the same authority and nobody
## has to agree with anybody.
##
## **It gives up eventually.** Steam can take a moment, and it can also never
## answer - the whole lobby may have gone. Without a deadline a player sits on
## a dead lobby for ever, which is the fault the client join timeout was
## written for (decisions.md D68).


## How long to keep asking before deciding the lobby is gone. Twenty seconds,
## the same as the Unity game's, which was arrived at by playing it.
const GIVE_UP_SECONDS: float = 20.0


enum Step {
	## Steam has not named a new owner yet. Ask again shortly.
	WAITING,
	## This player is the new owner and should start hosting.
	BECOME_HOST,
	## Somebody else is the new owner and should be joined.
	JOIN_NEW_HOST,
	## Long enough. The lobby is not coming back.
	GAVE_UP,
}


## This player's Steam id.
var _me: int

## The host who left, so their id is never mistaken for a new one.
var _departed: int

## Seconds spent waiting so far.
var _waited: float = 0.0


func _init(my_steam_id: int, departed_host_steam_id: int) -> void:
	_me = my_steam_id
	_departed = departed_host_steam_id


## Counts time towards giving up. Call it with the frame's delta.
func wait(seconds: float) -> void:
	_waited += seconds


func waited() -> float:
	return _waited


## What to do now, given who Steam says owns the lobby this moment.
##
## `owner_steam_id` is 0 when there is no lobby or Steam has not said yet.
##
## **The departed host is treated as "not decided yet".** Steam can go on
## reporting the leaver as the owner for a moment after they have gone, and
## taking that at face value would mean trying to rejoin the player who just
## left.
func next_step(owner_steam_id: int) -> Step:
	var undecided: bool = owner_steam_id == 0 or owner_steam_id == _departed
	if undecided:
		if _waited >= GIVE_UP_SECONDS:
			return Step.GAVE_UP
		return Step.WAITING

	if owner_steam_id == _me:
		return Step.BECOME_HOST
	return Step.JOIN_NEW_HOST


## Whether this is a step that ends the waiting, one way or another.
static func is_settled(step: Step) -> bool:
	return step != Step.WAITING
