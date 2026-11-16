extends SceneTree
## Prints the parts of the GodotSteam API this game's lobby handling depends
## on, so a claim about what Steam offers can be checked against the plugin
## actually installed rather than against documentation for some other version.
##
## Does NOT initialise Steam: it only loads the extension and reads the
## singleton's method and signal lists, so it is safe with Steam closed.

func _initialize() -> void:
	if not Engine.has_singleton("Steam"):
		print("no Steam singleton")
		quit()
		return
	var steam: Object = Engine.get_singleton("Steam")

	print("--- lobby methods ---")
	var methods: PackedStringArray = []
	for entry: Dictionary in steam.get_method_list():
		var name: String = String(entry["name"])
		if not name.to_lower().contains("lobby"):
			continue
		var args: PackedStringArray = []
		for arg: Dictionary in entry["args"]:
			args.append("%s: %s" % [arg["name"], type_string(int(arg["type"]))])
		methods.append("%s(%s) -> %s" % [
			name, ", ".join(args), type_string(int(entry["return"]["type"]))
		])
	methods.sort()
	for line: String in methods:
		print(line)

	print("--- lobby signals ---")
	var signals: PackedStringArray = []
	for entry: Dictionary in steam.get_signal_list():
		var name: String = String(entry["name"])
		if not name.contains("lobby"):
			continue
		var args: PackedStringArray = []
		for arg: Dictionary in entry["args"]:
			args.append("%s: %s" % [arg["name"], type_string(int(arg["type"]))])
		signals.append("%s(%s)" % [name, ", ".join(args)])
	signals.sort()
	for line: String in signals:
		print(line)

	quit()
