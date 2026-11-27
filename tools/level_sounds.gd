extends SceneTree
## Re-saves sound files as 16-bit WAV at the loudness of `bull2`, the clip the
## volume slider previews. See docs/decisions.md D221.
##
## Run headless, naming the files to level:
##   <godot> --headless --script res://tools/level_sounds.gd -- res://assets/audio/yeehaw.mp3
##
## Each file is decoded by Godot (so anything Godot can import will do), turned
## up or down so its loudest 300 ms matches `bull2`, and written beside the
## original with a `.wav` extension. The original is left for you to delete.
## Then run `--headless --import`, point the code at the new file, and check
## the result with `tools/measure_loudness.gd`.
##
## The reference is measured from `bull2.wav` the same way, so leveling a file
## twice changes nothing.

const REFERENCE: String = "res://assets/audio/bull2.wav"
const REFERENCE_FALLBACK: String = "res://assets/audio/bull2.mp3"
const WINDOW_SECONDS: float = 0.3


func _init() -> void:
	var rate: float = AudioServer.get_mix_rate()
	var reference_path: String = REFERENCE
	if not ResourceLoader.exists(reference_path):
		reference_path = REFERENCE_FALLBACK
	var target: float = _loudest(_decode(load(reference_path) as AudioStream, rate), rate)
	print("reference %s: %.1f dBFS, mix rate %d" % [reference_path, linear_to_db(target), rate])

	for path: String in OS.get_cmdline_user_args():
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			printerr("cannot load ", path)
			continue
		var frames: PackedVector2Array = _decode(stream, rate)
		var gain: float = target / _loudest(frames, rate)
		var out_path: String = path.get_basename() + ".wav"
		_save(frames, gain, rate, out_path)
		print("%s -> %s  gain %+.1f dB" % [path, out_path, linear_to_db(gain)])
	quit()


func _decode(stream: AudioStream, rate: float) -> PackedVector2Array:
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(0.0)
	var frames: PackedVector2Array = playback.mix_audio(1.0, int(stream.get_length() * rate) + 1)
	playback.stop()
	return frames


## The RMS of the loudest `WINDOW_SECONDS`, as a linear amplitude.
func _loudest(frames: PackedVector2Array, rate: float) -> float:
	var window: int = int(WINDOW_SECONDS * rate)
	var running: float = 0.0
	var loudest: float = 0.0
	for index: int in frames.size():
		running += frames[index].length_squared() / 2.0
		if index >= window:
			running -= frames[index - window].length_squared() / 2.0
		loudest = maxf(loudest, running / float(window))
	return sqrt(loudest)


func _save(frames: PackedVector2Array, gain: float, rate: float, path: String) -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames.size() * 4)
	for index: int in frames.size():
		var frame: Vector2 = frames[index] * gain
		data.encode_s16(index * 4, clampi(roundi(frame.x * 32767.0), -32768, 32767))
		data.encode_s16(index * 4 + 2, clampi(roundi(frame.y * 32767.0), -32768, 32767))

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(rate)
	wav.data = data
	var error: Error = wav.save_to_wav(ProjectSettings.globalize_path(path))
	if error != OK:
		printerr("could not write ", path, ": ", error_string(error))
