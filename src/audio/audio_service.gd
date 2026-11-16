class_name AudioService
extends Node
## The game's sound effects. Registered as the `Audio` autoload.
##
## One of the few services CLAUDE.md sanctions as an autoload, and it earns it:
## sound is triggered from several screens and belongs to none of them.
## Deliberately thin — it owns players and a volume, and holds no game rules.
##
## **The clips and what they play over came from the original**, read out of
## `GameplayManager.RpcPlayBearOrBullSounds`. Two details there are easy to
## lose and are the whole character of the thing:
##
## - A mood plays **two clips at once**, not one. `bear1` and `bear2` together,
##   `bull1` and `bull2` together. Layered, not alternated.
## - A bankruptcy plays breaking glass **and** a scream, together, and **once
##   per year** however many stalks went under.
##
## There is no sound for a split, and none for buying or selling. That is the
## original's choice, not an omission here.


## Where the clips live. Named for what they are rather than what they sound
## like, except where the file name is already the joke.
const BULL: Array[AudioStream] = [
	preload("res://assets/audio/bull1.mp3"),
	preload("res://assets/audio/bull2.mp3"),
]
const BEAR: Array[AudioStream] = [
	preload("res://assets/audio/bear1.mp3"),
	preload("res://assets/audio/bear2.mp3"),
]
const BANKRUPTCY: Array[AudioStream] = [
	preload("res://assets/audio/glass-shattering.mp3"),
	preload("res://assets/audio/wilhelm-scream.mp3"),
]
const YEEHAW: AudioStream = preload("res://assets/audio/yeehaw.mp3")

## The bus every effect goes to, so one volume governs all of them and the
## Master bus is left alone for music, should any ever arrive.
const BUS: StringName = &"SFX"

## Enough players for the loudest moment the game has: a bankruptcy is two
## clips, and a yeehaw can land in the same frame as a year resolving.
const VOICES: int = 6

## Silence, in decibels. Godot's volume is logarithmic, so a volume of zero
## percent is not 0 dB — it is as far down as the mixer goes.
const SILENCE_DB: float = -80.0


var _players: Array[AudioStreamPlayer] = []

## The next player to use. Round-robin rather than searching for a free one:
## with six voices and clips this short, the oldest is always the best
## candidate and looking for an idle one just risks finding none.
var _next: int = 0


func _ready() -> void:
	_apply(UserSettings.load_from().volume_percent)
	for index: int in VOICES:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)


## The year's mood, as two clips at once.
func play_mood(mood: MarketMood.Value) -> void:
	if mood == MarketMood.Value.BEAR:
		_play_together(BEAR)
	else:
		_play_together(BULL)


## Breaking glass and a scream. Call once for a year, not once per stalk.
func play_bankruptcy() -> void:
	_play_together(BANKRUPTCY)


func play_yeehaw() -> void:
	_play(YEEHAW)


## A single clip, so somebody moving the volume slider can hear the result.
##
## `bull2` because that is what the original's settings screen played. One
## clip rather than the layered pair: this is feedback, not a bull market.
func play_volume_preview() -> void:
	_play(BULL[1])


# ------------------------------------------------------------------- volume

## 0 to 100. Anything outside that is clamped rather than refused, because a
## volume is not somewhere to be strict with a caller.
##
## **Saves as well as applies.** A slider should call this when it is let go
## rather than on every frame of a drag, or the file is rewritten a hundred
## times for one adjustment.
func set_volume_percent(percent: int) -> void:
	var safe: int = clampi(percent, 0, 100)
	_apply(safe)

	var stored: UserSettings = UserSettings.new()
	stored.volume_percent = safe
	stored.save_to()


## Moves the mixer without touching the file. The stored value is applied
## through here at startup, where writing it straight back would be pointless.
func _apply(percent: int) -> void:
	var bus_index: int = AudioServer.get_bus_index(String(BUS))
	if bus_index < 0:
		return
	if percent <= 0:
		AudioServer.set_bus_volume_db(bus_index, SILENCE_DB)
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(percent / 100.0))


## What `set_volume_percent` was last given, read back from the mixer rather
## than remembered separately so the two cannot disagree.
func volume_percent() -> int:
	var bus_index: int = AudioServer.get_bus_index(String(BUS))
	if bus_index < 0:
		return 100
	var db: float = AudioServer.get_bus_volume_db(bus_index)
	if db <= SILENCE_DB:
		return 0
	return clampi(int(round(db_to_linear(db) * 100.0)), 0, 100)


## The players this service owns, in order. Public so a test can see what is
## sounding without reaching into the node tree by path.
func voices() -> Array[AudioStreamPlayer]:
	return _players


# ----------------------------------------------------------------- internals

func _play_together(streams: Array[AudioStream]) -> void:
	for stream: AudioStream in streams:
		_play(stream)


func _play(stream: AudioStream) -> void:
	if stream == null or _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.play()
