extends SceneTree
## What a host should tell other machines on the network.
##
##     <godot> --headless --script res://tools/lan_check.gd
##
## Direct (non-Steam) play is the fast path for testing: no accounts, no store,
## no second Steam install, and it is what the automated suite uses. This
## prints the address to type into the other machine's Join field.
##
## It prints *every* candidate because the first one is a guess. A developer
## machine is usually on several networks at once and most of them are virtual.
## If the top one does not work, try the next. See docs/development.md 6b.


func _init() -> void:
	var candidates: PackedStringArray = EnetTransport.local_addresses()

	if candidates.is_empty():
		print("No usable network address found.")
		print("Only this machine can reach the game. Check the network cable or Wi-Fi.")
		quit(1)
		return

	print("Type this into the other machine's Join field:")
	print("  ", candidates[0])
	print()
	print("The lobby will tell the host: ", EnetTransport.new(42420).joining_hint())

	if candidates.size() > 1:
		print()
		print("If that one does not work, try these in order:")
		for i: int in range(1, candidates.size()):
			print("  ", candidates[i])
	quit()
