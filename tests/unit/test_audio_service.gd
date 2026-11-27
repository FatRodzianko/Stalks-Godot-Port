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
	assert_true(playing.has(AudioService.GLASS))
	assert_eq(_screams_in(playing).size(), 1, "exactly one scream")


## The screams among `streams`.
func _screams_in(streams: Array[AudioStream]) -> Array[AudioStream]:
	var found: Array[AudioStream] = []
	for clip: AudioStream in streams:
		if AudioService.SCREAMS.has(clip):
			found.append(clip)
	return found


func test_bankruptcies_take_turns_through_every_scream() -> void:
	# One per bankrupt year, each different, until all have been heard; then
	# round again in the same order. Starts wherever the shared autoload
	# happens to be, so it checks the cycle rather than which comes first.
	var heard: Array[AudioStream] = []
	for year: int in AudioService.SCREAMS.size() + 1:
		_silence()
		Audio.play_bankruptcy()
		var screams: Array[AudioStream] = _screams_in(_sounding())
		assert_eq(screams.size(), 1)
		heard.append(screams[0])

	var cycle: Array[AudioStream] = heard.slice(0, AudioService.SCREAMS.size())
	for clip: AudioStream in AudioService.SCREAMS:
		assert_eq(cycle.count(clip), 1, "every scream once per cycle")
	assert_eq(heard[-1], heard[0], "then round again from the start")


func test_no_scream_follows_itself() -> void:
	var previous: AudioStream = null
	for year: int in AudioService.SCREAMS.size() * 2:
		_silence()
		Audio.play_bankruptcy()
		var scream: AudioStream = _screams_in(_sounding())[0]
		assert_ne(scream, previous)
		previous = scream


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


# ---------------------------------------------- the volume preview, reported
#
# Dragging the slider used to stack previews on top of each other: the clip
# is longer than the gap between steps, so the old one was still sounding, at
# the old volume, underneath the new. Heard as an echo, and it made the
# control useless — only the tail of it was at the volume you had chosen.


func test_the_preview_has_a_voice_of_its_own() -> void:
	# Which is what lets a new preview stop the last one. Taking the next
	# voice in the round-robin could not: there would be two players holding
	# the clip and no way to know which to silence.
	assert_false(
		Audio.voices().has(Audio.preview_voice()),
		"the preview should not be one of the round-robin voices",
	)


func test_previewing_twice_leaves_one_clip_sounding_not_two() -> void:
	Audio.preview_voice().stop()

	Audio.play_volume_preview()
	Audio.play_volume_preview()

	assert_eq(Audio.preview_voice().stream, AudioService.BULL[1])
	assert_eq(_sounding().size(), 0, "a preview should not use up a game voice")
