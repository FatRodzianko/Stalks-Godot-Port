extends SceneTree
## Prints the achievement and stat methods the installed GodotSteam exposes.
## Does not initialise Steam.

func _initialize() -> void:
	if not Engine.has_singleton("Steam"):
		print("no Steam singleton")
		quit()
		return
	var steam: Object = Engine.get_singleton("Steam")
	var lines: PackedStringArray = []
	for entry: Dictionary in steam.get_method_list():
		var name: String = String(entry["name"])
		var lower: String = name.to_lower()
		if not (lower.contains("achievement") or lower.contains("stat")):
			continue
		var args: PackedStringArray = []
		for arg: Dictionary in entry["args"]:
			args.append("%s: %s" % [arg["name"], type_string(int(arg["type"]))])
		lines.append("%s(%s) -> %s" % [
			name, ", ".join(args), type_string(int(entry["return"]["type"]))
		])
	lines.sort()
	for line: String in lines:
		print(line)
	quit()
