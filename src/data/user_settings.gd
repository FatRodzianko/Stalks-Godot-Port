class_name UserSettings
extends RefCounted
## Preferences this machine keeps between runs. Godot's equivalent of Unity's
## PlayerPrefs, written as a named file rather than hidden in the registry.
##
## **Only things a player sets once and expects to stay set.** Right now that
## is the effect volume, the display size and mode, and whether the CRT effect
## is on, and whether the year's news panel appears. The bar for adding
## anything else is high.
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

const SECTION_DISPLAY: String = "display"

## Half volume on a first run, at the owner's instruction on 2026-11-17.
##
## It was full until then. The game's loudest moments - a bankruptcy plays
## breaking glass and a scream together - are startling at 100 on a machine
## whose system volume is already up, and a player who has not met the game
## yet has no reason to expect them. Starting halfway means the first thing
## anybody does with the slider is turn it up, which is a better first move
## than turning it down.
const DEFAULT_VOLUME: int = 50

## What a first run looks like: fullscreen, at whatever the monitor's own
## largest 16:9 size is. Written as a zero rather than a number because the
## answer depends on the monitor and this file does not know about monitors —
## `DisplayMode` resolves it. Every other game starts this way and a player
## who launches into a small window in the corner assumes something is wrong.
const USE_NATIVE: Vector2i = Vector2i.ZERO

const DEFAULT_FULLSCREEN: bool = true

## **Off until it is asked for.** The CRT effect is a taste, not an
## improvement: it warps the picture, softens the text and costs a little
## every frame. A player who has never heard of it should see the game the way
## it was drawn. See docs/decisions.md D94.
const DEFAULT_CRT_EFFECT: bool = false

## Section for things about how the game is played rather than how it looks.
const SECTION_GAME: String = "game"

## **On until a player turns it off.** The year's news panel is the point of
## having one - a player who has never seen it should see it. Anyone who tires
## of it can tick "Don't show again" on the panel itself, and turn it back on
## from Settings. See docs/decisions.md D102.
const DEFAULT_SHOW_NEWS: bool = true


var volume_percent: int = DEFAULT_VOLUME

## The size of the image the game renders, or `USE_NATIVE`. See
## `DisplaySettings` for what that means.
var resolution: Vector2i = USE_NATIVE

var fullscreen: bool = DEFAULT_FULLSCREEN

## Whether to draw the game through the CRT shader.
var crt_effect: bool = DEFAULT_CRT_EFFECT

## Whether the year's news comes up in a panel when the year turns.
var show_news: bool = DEFAULT_SHOW_NEWS


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
	settings.fullscreen = bool(
		file.get_value(SECTION_DISPLAY, "fullscreen", DEFAULT_FULLSCREEN)
	)
	settings.crt_effect = bool(
		file.get_value(SECTION_DISPLAY, "crt_effect", DEFAULT_CRT_EFFECT)
	)
	settings.show_news = bool(
		file.get_value(SECTION_GAME, "show_news", DEFAULT_SHOW_NEWS)
	)
	# Stored as two integers rather than a Vector2i so the file stays something
	# a person can read and correct by hand after a bad resolution has locked
	# them out of the settings screen.
	var width: int = int(file.get_value(SECTION_DISPLAY, "resolution_width", 0))
	var height: int = int(file.get_value(SECTION_DISPLAY, "resolution_height", 0))
	settings.resolution = Vector2i(maxi(width, 0), maxi(height, 0))
	return settings


## Writes the file. Silent on failure, because a player whose disk is full has
## larger problems than a forgotten volume and nothing here is worth
## interrupting a game for.
func save_to(path: String = PATH) -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION_AUDIO, "volume_percent", volume_percent)
	file.set_value(SECTION_DISPLAY, "fullscreen", fullscreen)
	file.set_value(SECTION_DISPLAY, "crt_effect", crt_effect)
	file.set_value(SECTION_GAME, "show_news", show_news)
	file.set_value(SECTION_DISPLAY, "resolution_width", resolution.x)
	file.set_value(SECTION_DISPLAY, "resolution_height", resolution.y)
	file.save(path)
