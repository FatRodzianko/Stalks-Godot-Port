extends GutTest
## The sound effects, checked without listening to them.
##
## Headless runs use Godot's dummy audio driver, so "did it make a noise" is
## not a question a test can ask. What it can ask is which clip each player
## was handed, and that is where the two details inherited from the original
## actually live: a mood is **two** clips at once, and a bankruptcy is
## breaking glass **and** a scream. Both are easy to quietly reduce to one.
##
## `Audio` is an autoload, so these share one instance with the rest of the
## suite. Nothing here asserts a player is idle to begin with for that reason
## — only what changed.


func _silence() -> void:
	for player: AudioStreamPlayer in Audio.voices():
		player.stop()
		player.stream = null


func before_each() -> void:
	_silence()


## Which clips are loaded into players right now, in no particular order.
func _sounding() -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for player: AudioStreamPlayer in Audio.voices():
		if player.stream != null:
			streams.append(player.stream)
	return streams


func test_a_bull_year_plays_both_bull_clips() -> void:
	Audio.play_mood(MarketMood.Value.BULL)

	var playing: Array[AudioStream] = _sounding()
	assert_eq(playing.size(), 2, "layered, not one clip")
	for clip: AudioStream in AudioService.BULL:
		assert_true(playing.has(clip), "missing a bull clip")


func test_a_bear_year_plays_both_bear_clips() -> void:
	Audio.play_mood(MarketMood.Value.BEAR)

	var playing: Array[AudioStream] = _sounding()
	assert_eq(playing.size(), 2)
	for clip: AudioStream in AudioService.BEAR:
		assert_true(playing.has(clip), "missing a bear clip")


func test_a_bull_year_does_not_sound_like_a_bear_one() -> void:
	Audio.play_mood(MarketMood.Value.BULL)
	for clip: AudioStream in AudioService.BEAR:
		assert_false(_sounding().has(clip))


func test_a_bankruptcy_breaks_glass_and_screams() -> void:
	# Two clips again, and the scream is the half somebody would drop as
	# redundant.
	Audio.play_bankruptcy()

	var playing: Array[AudioStream] = _sounding()
	assert_eq(playing.size(), 2)
	for clip: AudioStream in AudioService.BANKRUPTCY:
		assert_true(playing.has(clip))


func test_a_yeehaw_is_one_clip() -> void:
	Audio.play_yeehaw()
	assert_eq(_sounding(), [AudioService.YEEHAW] as Array[AudioStream])


func test_there_are_enough_players_for_a_year_and_a_yeehaw_at_once() -> void:
	# A yeehaw can land in the same frame a year resolves. With too few
	# players the newer sound would cut off the older one.
	Audio.play_mood(MarketMood.Value.BEAR)
	Audio.play_bankruptcy()
	Audio.play_yeehaw()

	assert_eq(_sounding().size(), 5, "nothing should have been cut off")


# ------------------------------------------------------------------- volume

func test_volume_survives_being_set_and_read_back() -> void:
	var before: int = Audio.volume_percent()
	Audio.set_volume_percent(40)
	assert_almost_eq(Audio.volume_percent(), 40, 1)
	Audio.set_volume_percent(before)


func test_zero_is_silence_rather_than_quiet() -> void:
	# Decibels are logarithmic, so a naive conversion makes 0% merely faint.
	var before: int = Audio.volume_percent()
	Audio.set_volume_percent(0)
	assert_eq(Audio.volume_percent(), 0)
	Audio.set_volume_percent(before)


func test_a_volume_outside_the_range_is_clamped() -> void:
	var before: int = Audio.volume_percent()
	Audio.set_volume_percent(500)
	assert_eq(Audio.volume_percent(), 100)
	Audio.set_volume_percent(-20)
	assert_eq(Audio.volume_percent(), 0)
	Audio.set_volume_percent(before)


func test_the_effects_bus_exists() -> void:
	# Everything above is silently meaningless if the bus layout did not load:
	# the volume calls would no-op and still agree with each other.
	assert_gt(
		AudioServer.get_bus_index(String(AudioService.BUS)), 0,
		"an SFX bus should exist under Master",
	)
