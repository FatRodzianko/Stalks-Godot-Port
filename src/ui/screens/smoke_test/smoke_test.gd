extends CenterContainer
## Throwaway scene that proves the toolchain works end to end: the project
## imports, a script parses, a scene loads, and a seeded RNG is reproducible.
##
## Delete this whole folder once the real main menu exists, and point
## `application/run/main_scene` in project.godot at the menu instead.

const DEMO_SEED: int = 12345
const DEMO_ROLLS: int = 5

@onready var _status: Label = %Status
@onready var _determinism: Label = %Determinism


func _ready() -> void:
	var version: String = str(Engine.get_version_info().get("string", "unknown"))
	_status.text = "Godot %s — toolchain OK" % version
	_determinism.text = "Seeded RNG (seed %d): %s" % [
		DEMO_SEED,
		_rng_fingerprint(DEMO_SEED, DEMO_ROLLS),
	]
	print(_status.text)
	print(_determinism.text)


## Draws `count` numbers from a generator seeded with `seed_value`.
## The same seed must always produce the same list. Every market test will
## depend on that property, so it is worth proving on day one.
func _rng_fingerprint(seed_value: int, count: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts: PackedStringArray = PackedStringArray()
	for _i in count:
		parts.append(str(rng.randi_range(1, 100)))
	return ", ".join(parts)
