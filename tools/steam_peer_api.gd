extends SceneTree
## Prints the GodotSteam constants this game needs to turn Steam's numeric
## answers into something a player can read. Checked against the installed
## plugin rather than against documentation for some other version.

func _initialize() -> void:
	if not Engine.has_singleton("Steam"):
		print("no Steam singleton")
		quit()
		return
	var steam: Object = Engine.get_singleton("Steam")
	var found: PackedStringArray = []
	for name: String in ClassDB.class_get_integer_constant_list(steam.get_class(), true):
		if not (name.contains("CHAT_ROOM") or name.contains("CHAT_MEMBER") \
				or name.contains("LOBBY_TYPE")):
			continue
		found.append("%s = %d" % [
			name, ClassDB.class_get_integer_constant(steam.get_class(), name)
		])
	found.sort()
	for line: String in found:
		print(line)
	if found.is_empty():
		print("no matching constants on class %s" % steam.get_class())
	quit()
