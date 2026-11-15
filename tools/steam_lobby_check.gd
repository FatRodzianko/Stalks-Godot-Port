extends SceneTree
## Exercises the whole Steam path on one machine: start Steam, create a real
## lobby, turn it into a peer, and leave again.
##
## Run it with **Steam running and signed in**, from the project root:
##
##     <godot> --headless --script res://tools/steam_lobby_check.gd
##
## This exists because the automated suite deliberately cannot do any of it.
## `tests/unit/test_steam_transport.gd` has to pass on a machine with no Steam
## and no plugin, so it covers argument handling and rendering only. Everything
## that actually talks to Steam is checked here, by hand, on demand.
##
## It leaves no mess: the lobby is left at the end. What it cannot prove is two
## *different* machines connecting to each other — that needs a second Steam
## account and a human. See docs/steam-integration.md section 6.


## Give Steam this many frames to answer before calling it a failure. Lobby
## creation is a round trip to Valve, so it is not instant.
const PATIENCE_FRAMES: int = 300


func _init() -> void:
	var service: SteamService = SteamService.new()
	root.add_child(service)

	var problem: String = service.start()
	if not problem.is_empty():
		print("FAILED to start Steam: ", problem)
		print("Is Steam running and signed in?")
		quit(1)
		return
	print("Steam started, signed in as: ", service.persona_name())

	var created: Array[int] = []
	var failed: Array[String] = []
	service.lobby_created.connect(func(id: int) -> void: created.append(id))
	service.lobby_failed.connect(func(reason: String) -> void: failed.append(reason))

	service.create_lobby(10)
	for frame: int in PATIENCE_FRAMES:
		await process_frame
		if not created.is_empty() or not failed.is_empty():
			break

	if not failed.is_empty():
		print("FAILED to create a lobby: ", failed[0])
		quit(1)
		return
	if created.is_empty():
		print("FAILED: Steam never answered the lobby request.")
		quit(1)
		return

	var lobby: int = created[0]
	print("Lobby created:        ", lobby)
	print("  owned by this user: ", service.lobby_owner(lobby) == Steam.getSteamID())
	print("  listed as:          ", Steam.getLobbyData(lobby, "name"))
	print("  tagged for filter:  ", Steam.getLobbyData(lobby, "game"))

	# The part that matters: a lobby has to become a usable peer.
	var opened: Dictionary = SteamTransport.new(lobby).open_server(9)
	var error: String = String(opened["error"])
	if not error.is_empty():
		print("FAILED to open a host peer: ", error)
		service.leave_lobby()
		quit(1)
		return

	var peer: MultiplayerPeer = opened["peer"]
	print("Host peer:            ", peer.get_class())
	print("  unique id:          ", peer.get_unique_id(), " (1 means server)")
	peer.close()

	service.leave_lobby()
	await process_frame
	print()
	print("All good. Two machines connecting still needs a second account.")
	quit()
