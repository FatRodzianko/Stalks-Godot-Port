class_name UserSettings
extends RefCounted
## Preferences this machine keeps between runs. Godot's equivalent of Unity's
## PlayerPrefs, written as a named file rather than hidden in the registry.
##
## **Only things a player sets once and expects to stay set.** Right now that
## is the effect volume, and the bar for adding anything else is high.
##
## **Match settings are not kept here, on purpose.** An earlier version
## remembered the Create Game fields — years, starting cash, loans, the game's
## name — so they came back next session. That was a convenience nobody asked
## for and it had a real cost: change the year limit once and the title screen
## stops showing the game's actual defaults, permanently, with nothing on
## screen to say why. The seed was excluded from that version for exactly this
## reason and the same reasoning applies to the rest of them. See
## docs/decisions.md D71.
##
## `user://` is the per-user writable directory and is never part of the
## exported game.


const PATH: String = "user://settings.cfg"

const SECTION_AUDIO: String = "audio"

## Full volume. A player who has never touched it hears the game as intended.
const DEFAULT_VOLUME: int = 100


var volume_percent: int = DEFAULT_VOLUME


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

	settings.volume_percent = clampi(
		int(file.get_value(SECTION_AUDIO, "volume_percent", DEFAULT_VOLUME)), 0, 100
	)
	return settings


## Writes the file. Silent on failure, because a player whose disk is full has
## larger problems than a forgotten volume and nothing here is worth
## interrupting a game for.
func save_to(path: String = PATH) -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION_AUDIO, "volume_percent", volume_percent)
	file.save(path)
