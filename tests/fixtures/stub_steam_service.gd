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


func leave_lobby_as_host() -> void:
	calls.append(&"leave_as_host")


func leave_lobby() -> void:
	calls.append(&"leave")
