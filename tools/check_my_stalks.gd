extends SceneTree
## Reads the custom stalk files on THIS machine and says what the game makes of
## them, without starting the game.
##
## **Why this exists.** The Custom Stalks screen reports the same thing, but
## getting to it means launching the game, and a file with a typo in it is
## quicker to fix when the answer arrives in a terminal. Run it after editing a
## file:
##
##     <godot> --headless --script res://tools/check_my_stalks.gd
##
## It writes nothing and changes nothing.

func _init() -> void:
	var store: CustomStalkStore = CustomStalkStore.load_from()
	print("Folder: ", ProjectSettings.globalize_path(CustomStalkStore.DIR))

	if store.stalks.is_empty():
		print("No custom companies loaded.")
	for stalk: StalkDefinition in store.stalks:
		print("  OK  %s  id=%s  $%d  bull +%d %s  bear +%d %s  events %d bull / %d bear" % [
			stalk.display_name,
			stalk.id,
			stalk.starting_price,
			stalk.bull_dividend,
			stalk.bull_change,
			stalk.bear_dividend,
			stalk.bear_change,
			stalk.bull_events.size(),
			stalk.bear_events.size(),
		])

	for problem: String in store.problems:
		print("  BAD %s" % problem)

	# What a match could actually be built from, which is the pair of numbers
	# the picker shows.
	var available: ContentLibrary = ContentLibrary.available()
	print("Available to pick from: %d (cap per match: %d)" % [
		available.stalks.size(), StalkSchema.MAX_STALKS_PER_MATCH
	])
	quit()
