class_name StubSteamService
extends SteamService
## A `SteamService` that answers without Steam.
##
## **Why this exists.** Every host-migration fault so far has been in the
## orchestration in `Main` - noticing the host left, deciding what to do, and
## doing it in the right order - and none of it was covered, because reaching
## it meant reaching Steam. Three bugs shipped in a row: a migrated lobby that
## could not be listed (D106), a new host nobody could connect to (D107), and a
## migration that congratulated itself and stopped before it had done anything
## (D108). The suite caught none of them, and every one was decided by code
## that never touches the Steam API - only by answers that come *from* it.
##
## So the answers are faked and the orchestration is tested. What Steam does
## with a lobby still cannot be, and is not pretended to be: the calls that
## write lobby data are recorded here rather than made, so a test can assert
## which one `Main` chose. See docs/testing.md.
##
## Lives outside tests/unit so GUT does not scan it.


## Whose Steam account this process is signed in to.
var me: int = 0

## The lobby this process is in, or 0 for none.
var lobby: int = 0

## Who Steam currently says owns that lobby. 0 means it has not decided, which
## is the answer the real one gives for a moment after an owner leaves.
var owner_steam_id: int = 0

var persona: String = "Tester"

## Every lobby-visibility call made, in order, by name. What `Main` *chose* is
## the testable part; what Steam would have done with it is not.
var calls: Array[StringName] = []


func is_running() -> bool:
	return true


func local_steam_id() -> int:
	return me


func persona_name() -> String:
	return persona


func current_lobby() -> int:
	return lobby


func lobby_owner(_lobby_id: int) -> int:
	return owner_steam_id


func hide_lobby_from_the_browser() -> void:
	calls.append(&"hide")


func reopen_lobby_to_the_browser(_settings: GameSettings = null) -> void:
	calls.append(&"reopen")


## Whether this process was the last one in the lobby when it left, which is
## what the real one answers by counting members.
var last_one_out: bool = false


func leave_lobby_as_host() -> bool:
	calls.append(&"leave_as_host")
	return last_one_out


func mark_lobby_finished() -> void:
	calls.append(&"mark_finished")


func leave_lobby() -> void:
	calls.append(&"leave")


## Lobby ids this process has asked to be let into, in order. What REJOIN GAME
## *chose* is the testable part; whether Steam would have let us in is not.
var joined_lobbies: Array[int] = []

## What Steam says when asked to join. Empty means yes, and the lobby becomes
## the one this process is in. Anything else is a refusal, worded the way
## `SteamService._why_refused` words one.
var refuse_join_with: String = ""


## Lobbies asked about with `request_lobby_details`, in order.
var asked_about: Array[int] = []

## What Steam answers about them. `exists` false is a lobby everybody has left;
## `state` is the `KEY_STATE` value, so `STATE_OVER` is a finished match.
var details_exist: bool = true
var details_state: String = SteamService.STATE_PLAYING

## Set to make Steam never answer at all, which it is entitled to do and which
## the title screen has to survive without offering a button.
var details_never_arrive: bool = false


## Answers at once rather than after a frame. Both this and `join_lobby` do:
## what is being tested is the order `Main` does things in, not Steam's
## latency, and a test that needed the gap could emit the signal itself.
func request_lobby_details(lobby_id: int) -> void:
	asked_about.append(lobby_id)
	if details_never_arrive:
		return
	lobby_details.emit(lobby_id, details_exist, details_state)


## Answers the way the real one does: a lobby join is asynchronous, so the
## answer comes back on a signal rather than from the call.
func join_lobby(lobby_id: int) -> void:
	joined_lobbies.append(lobby_id)
	if not refuse_join_with.is_empty():
		lobby_failed.emit(refuse_join_with)
		return
	lobby = lobby_id
	lobby_joined.emit(lobby_id)
