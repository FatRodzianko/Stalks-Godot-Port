class_name LastMatch
extends RefCounted
## The online match this machine was last playing, so the title screen can
## offer to go back into it.
##
## **A Steam lobby id and the name of the game in it, and nothing else.** The
## position a returning player gets back is the host's copy, not this one — the
## host kept their `PlayerState` the whole time (`host_session.gd`), and their
## seat is matched by Steam ID when they arrive. So there is nothing here worth
## forging: all this file does is remember a door number.
##
## **Deliberately not in `UserSettings`.** That file is for preferences a
## player sets once and expects to stay set, and D71 kept match state out of it
## on purpose. This is the opposite kind of thing: written when a match starts,
## forgotten when it ends, and meaningless a week later. Keeping it in its own
## file also means a stale rejoin record and somebody's volume setting cannot
## damage each other.
##
## `user://` is the per-user writable directory and is never part of the
## exported game.


const PATH: String = "user://last_match.cfg"

const SECTION: String = "match"


## The Steam lobby the match is in, or 0 for "nothing to go back to".
var lobby_id: int = 0

## What the match was called, for the line that says which game is being
## rejoined. Empty is allowed and simply means the sentence leaves it out.
var game_name: String = ""


## Whether there is a match to offer. A record with no lobby id is no record.
func exists() -> bool:
	return lobby_id != 0


## Reads the file, or returns an empty record if there is not one.
##
## A missing or unreadable file is the ordinary case — most runs have never
## played an online match — so neither is logged.
static func load_from(path: String = PATH) -> LastMatch:
	var remembered: LastMatch = LastMatch.new()
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK:
		return remembered
	remembered.lobby_id = int(file.get_value(SECTION, "lobby_id", 0))
	remembered.game_name = String(file.get_value(SECTION, "game_name", ""))
	return remembered


## Writes a lobby down as the match to come back to.
##
## Silent on failure, like `UserSettings.save_to`: a player whose disk is full
## has larger problems than a forgotten rejoin, and nothing here is worth
## interrupting a match for.
static func remember(lobby_id_to_keep: int, name_of_game: String, path: String = PATH) -> void:
	if lobby_id_to_keep == 0:
		return
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, "lobby_id", lobby_id_to_keep)
	file.set_value(SECTION, "game_name", name_of_game)
	file.save(path)


## Throws the record away, so the title screen stops offering a match that has
## finished.
##
## **Only when the match is actually over**, not when a rejoin fails. A Steam
## relay that is having a bad minute would otherwise destroy the only route
## back into a game that is still being played. A button that says "That game
## no longer exists." is a smaller problem than a seat nobody can return to.
static func forget(path: String = PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(path)
