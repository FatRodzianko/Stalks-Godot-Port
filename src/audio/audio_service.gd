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
const GLASS: AudioStream = preload("res://assets/audio/glass-shattering.mp3")

## The screams a bankruptcy takes turns through, one per bankrupt year, in this
## order and round again. The original had one Wilhelm scream; this has several
## so a long match does not play the same one every time.
##
## In turn rather than at random: the order is fixed, two in a row are never
## the same, and nothing here needs a random number generator.
##
## Five are cut from one Craig Smith archival reel of Wilhelm screams and two
## come from Sonniss GDC bundles; all were levelled to the same loudness. Where
## each came from, and its terms, is in NOTICE.md. See docs/decisions.md D217.
const SCREAMS: Array[AudioStream] = [
	preload("res://assets/audio/wilhelm-scream-1.wav"),
	preload("res://assets/audio/scream-sonniss-warrior.wav"),
	preload("res://assets/audio/wilhelm-scream-2.wav"),
	preload("res://assets/audio/wilhelm-scream-3.wav"),
	preload("res://assets/audio/scream-sonniss-female.wav"),
	preload("res://assets/audio/wilhelm-scream-4.wav"),
	preload("res://assets/audio/wilhelm-scream-5.wav"),
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

## The volume preview's own player, kept out of the round-robin above.
##
## It has to be a dedicated one so that a second preview can **stop** the
## first. Taking the next voice in the rotation would leave the old clip
## sounding underneath the new one, and the two together are heard as an echo
## — which makes it impossible to tell what volume you have just chosen,
## because only the tail of it is at the new level. Reported from play.
var _preview: AudioStreamPlayer = null

## The next player to use. Round-robin rather than searching for a free one:
## with six voices and clips this short, the oldest is always the best
## candidate and looking for an idle one just risks finding none.
var _next: int = 0

## Which of `SCREAMS` the next bankruptcy plays.
var _next_scream: int = 0


func _ready() -> void:
	_apply(UserSettings.load_from().volume_percent)
	for index: int in VOICES:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)

	_preview = AudioStreamPlayer.new()
	_preview.bus = BUS
	add_child(_preview)


## The year's mood, as two clips at once.
func play_mood(mood: MarketMood.Value) -> void:
	if mood == MarketMood.Value.BEAR:
		_play_together(BEAR)
	else:
		_play_together(BULL)


## Breaking glass and a scream, the next one in `SCREAMS`. Call once for a
## year, not once per stalk.
func play_bankruptcy() -> void:
	_play(GLASS)
	_play(SCREAMS[_next_scream])
	_next_scream = (_next_scream + 1) % SCREAMS.size()


func play_yeehaw() -> void:
	_play(YEEHAW)


## A single clip, so somebody moving the volume slider can hear the result.
##
## `bull2` because that is what the original's settings screen played. One
## clip rather than the layered pair: this is feedback, not a bull market.
##
## **Cuts off whatever the last preview was still playing.** Without that,
## previews overlap into an echo and the old clip is still sounding at the old
## volume, so you cannot hear what you just set. The menu also waits for the
## slider to be let go before asking for one — see `main_menu.gd`.
func play_volume_preview() -> void:
	if _preview == null:
		return
	_preview.stop()
	_preview.stream = BULL[1]
	_preview.play()


## Silences the last preview without starting another.
##
## A drag is supposed to be quiet, and moving the bus does not silence a clip
## that is already sounding — it rides the volume up and down with the slider,
## which is correct for a mixer and wrong for feedback. Reported from play.
##
## **Clears the stream as well as stopping.** Under the headless dummy audio
## driver `playing` is always false, so "is a preview sounding" is only
## answerable by looking at the clip the player holds. See
## `tests/unit/test_audio_service.gd`.
func stop_volume_preview() -> void:
	if _preview == null:
		return
	_preview.stop()
	_preview.stream = null


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

	# Read the file back before writing it. Building a fresh `UserSettings`
	# here would save this volume alongside the *defaults* for everything else
	# in the file, silently resetting the player's resolution and fullscreen
	# every time they touched the slider.
	var stored: UserSettings = UserSettings.load_from()
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


## The volume preview's player, which is **not** one of `voices()`. Public for
## the same reason: so a test can see whether a preview is sounding, and
## whether a second one replaced the first rather than joining it.
func preview_voice() -> AudioStreamPlayer:
	return _preview


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
