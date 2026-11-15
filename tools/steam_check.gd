extends SceneTree
## Checks whether the GodotSteam GDExtension is installed and loading.
##
## Run it from the project root:
##
##     <godot> --headless --script res://tools/steam_check.gd
##
## This exists because **a GDExtension that loads correctly prints nothing**.
## There is no entry in Project Settings, no line in the Output panel, and no
## visible sign of any kind — so without something like this, a working install
## and a broken one look identical. See docs/steam-integration.md 3.2.
##
## It is a tool, not a test: the suite has to keep passing on a checkout with no
## Steam plugin at all, so this cannot live in tests/.


func _init() -> void:
	var present: bool = ClassDB.class_exists("Steam")
	print("Steam class registered: ", present)

	if not present:
		print()
		print("The extension is not loaded. Check that this file exists:")
		print("  addons/godotsteam/godotsteam.gdextension")
		print("See docs/steam-integration.md section 3.2.")
		quit(1)
		return

	print("  steamInit available:  ", ClassDB.class_has_method("Steam", "steamInit", true))
	# What SteamTransport will hand back in place of ENetMultiplayerPeer.
	print("  SteamMultiplayerPeer: ", ClassDB.class_exists("SteamMultiplayerPeer"))
	quit()
