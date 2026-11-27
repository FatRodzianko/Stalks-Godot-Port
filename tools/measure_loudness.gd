extends SceneTree
## Prints how loud each sound effect is, decoded by Godot itself.
##
## Run headless:
##   <godot> --headless --script res://tools/measure_loudness.gd
##
## For each clip in `assets/audio/` it reports the peak and the loudness of the
## loudest 300 ms (RMS), both in dBFS. Measuring through Godot means MP3 and
## WAV are compared on equal terms, after import, as the game hears them.
## Written because the screams were levelled against each other and not against
## the other effects, and came out far louder. See docs/decisions.md D217.

const DIR: String = "res://assets/audio/"
const RATE: float = 44100.0
const WINDOW_SECONDS: float = 0.3


func _init() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		if file.ends_with(".import"):
			continue
		var stream: AudioStream = load(DIR + file) as AudioStream
		if stream == null:
			continue
		_report(file, stream)
	quit()


func _report(file: String, stream: AudioStream) -> void:
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(0.0)
	var total: int = int(stream.get_length() * RATE) + 1
	var mixed: PackedVector2Array = playback.mix_audio(1.0, total)
	playback.stop()

	var squares: PackedFloat64Array = PackedFloat64Array()
	squares.resize(mixed.size())
	var peak: float = 0.0
	for index: int in mixed.size():
		var frame: Vector2 = mixed[index]
		var level: float = maxf(absf(frame.x), absf(frame.y))
		peak = maxf(peak, level)
		squares[index] = (frame.x * frame.x + frame.y * frame.y) / 2.0

	var window: int = int(WINDOW_SECONDS * RATE)
	var running: float = 0.0
	var loudest: float = 0.0
	for index: int in squares.size():
		running += squares[index]
		if index >= window:
			running -= squares[index - window]
		loudest = maxf(loudest, running / float(window))

	print("%-30s length %5.2f s  peak %6.1f dBFS  loudest-300ms %6.1f dBFS" % [
		file, stream.get_length(), linear_to_db(peak), linear_to_db(sqrt(loudest)),
	])
