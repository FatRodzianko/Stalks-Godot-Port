extends SceneTree
## Prints the invite-related parts of the installed GodotSteam API, so the
## invite work is built against what this plugin has rather than what a
## documentation page describes. Does not initialise Steam.

func _initialize() -> void:
	if not Engine.has_singleton("Steam"):
		print("no Steam singleton")
		quit()
		return
	var steam: Object = Engine.get_singleton("Steam")

	print("--- methods ---")
	var lines: PackedStringArray = []
	for entry: Dictionary in steam.get_method_list():
		var name: String = String(entry["name"])
		if not (name.to_lower().contains("invite") or name.to_lower().contains("overlay")):
			continue
		var args: PackedStringArray = []
		for arg: Dictionary in entry["args"]:
			args.append("%s: %s" % [arg["name"], type_string(int(arg["type"]))])
		lines.append("%s(%s)" % [name, ", ".join(args)])
	lines.sort()
	for line: String in lines:
		print(line)

	print("--- signals ---")
	var found: PackedStringArray = []
	for entry: Dictionary in steam.get_signal_list():
		var name: String = String(entry["name"])
		if not (name.contains("invite") or name.contains("join_requested")):
			continue
		var args: PackedStringArray = []
		for arg: Dictionary in entry["args"]:
			args.append("%s: %s" % [arg["name"], type_string(int(arg["type"]))])
		found.append("%s(%s)" % [name, ", ".join(args)])
	found.sort()
	for line: String in found:
		print(line)
	quit()
