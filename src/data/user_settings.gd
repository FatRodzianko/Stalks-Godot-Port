class_name UserSettings
extends RefCounted
## What this machine remembers between runs.
##
## Everything on Create Game except the seed, plus the player's name. Nothing
## here affects how the game plays: it is what you last typed, so a second
## session does not start from defaults and make you type it all again.
##
## **Not an autoload.** It is a file read once by the screen that owns those
## fields and written when that screen is used. An autoload would make it
## reachable from anywhere, which is the opposite of what a store this small
## needs. See the Autoloads note in CLAUDE.md.
##
## **Not game state.** It never reaches `GameSettings` except by filling in the
## controls a player can then change, so a remembered value can always be
## overruled by looking at the screen.
##
## Kept in `user://`, which is Godot's per-user writable directory and is never
## part of the exported game.


const PATH: String = "user://settings.cfg"

const SECTION_PLAYER: String = "player"
const SECTION_MATCH: String = "match"


var player_name: String = ""
var game_name: String = ""
var years: int = 10
var starting_cash: int = 10000
var loans_enabled: bool = true
var invite_only: bool = false


## Reads the file, or returns the defaults above if there is not one.
##
## A missing or corrupt file is not a failure: it is what the first run looks
## like. Godot's `ConfigFile.load` reports both the same way and both deserve
## the same answer, so neither is logged.
static func load_from(path: String = PATH) -> UserSettings:
	var settings: UserSettings = UserSettings.new()
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK:
		return settings

	settings.player_name = String(
		file.get_value(SECTION_PLAYER, "name", settings.player_name)
	)
	settings.game_name = String(
		file.get_value(SECTION_MATCH, "game_name", settings.game_name)
	)
	settings.years = int(file.get_value(SECTION_MATCH, "years", settings.years))
	settings.starting_cash = int(
		file.get_value(SECTION_MATCH, "starting_cash", settings.starting_cash)
	)
	settings.loans_enabled = bool(
		file.get_value(SECTION_MATCH, "loans_enabled", settings.loans_enabled)
	)
	settings.invite_only = bool(
		file.get_value(SECTION_MATCH, "invite_only", settings.invite_only)
	)
	return settings


## Writes the file. Silent on failure, because a player whose disk is full has
## larger problems than a forgotten year limit and nothing here is worth
## interrupting a game for.
func save_to(path: String = PATH) -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION_PLAYER, "name", player_name)
	file.set_value(SECTION_MATCH, "game_name", game_name)
	file.set_value(SECTION_MATCH, "years", years)
	file.set_value(SECTION_MATCH, "starting_cash", starting_cash)
	file.set_value(SECTION_MATCH, "loans_enabled", loans_enabled)
	file.set_value(SECTION_MATCH, "invite_only", invite_only)
	file.save(path)
