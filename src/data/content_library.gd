class_name ContentLibrary
extends RefCounted
## A set of stalks the simulation can be run on, and the rules it must satisfy.
##
## Content is authored as one `.tres` per stalk in `src/data/stalks/`, each
## carrying its own special events (see docs/decisions.md D29). `load_from`
## turns that directory into something the simulation can use, and refuses to
## hand back content it cannot vouch for.
##
## **It is no longer only that directory.** A match may be played on a set the
## host chose — shipped stalks, the host's own custom ones, or both — so `of`
## builds a library over any list of definitions and `subset` narrows one to the
## chosen ids. Which library a match is running on is decided once, by the host,
## and travels to every client (see `StateSync`). See docs/decisions.md D121.
##
## Validation exists because the content is the easiest part of the project to get
## quietly wrong: ninety events referencing ten stalks by id, where a single typo
## in a target id would silently produce an event that can never fire. The
## original had exactly that class of bug.


const STALKS_DIR: String = "res://src/data/stalks"

## Loaded stalk definitions, sorted by id so the order is identical on every
## machine. Directory listing order is not guaranteed, and determinism matters
## here (docs/architecture.md §8). Display order on the board is a separate
## concern for the UI phase.
var stalks: Array[StalkDefinition] = []

## Problems found by `validate()`. Empty means the content is usable.
var errors: Array[String] = []


## Loads and validates every stalk resource in `dir_path`.
##
## Always returns a library; check `is_valid()` before using it. Loading never
## pushes an error or crashes, so a caller can report problems its own way.
static func load_from(dir_path: String = STALKS_DIR) -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.new()

	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		library.errors.append("Cannot open content directory: %s" % dir_path)
		return library

	var file_names: PackedStringArray = dir.get_files()
	var loaded_names: Array[String] = []
	for file_name: String in file_names:
		# Exported projects rename .tres to .res, so accept both.
		var usable: String = file_name.trim_suffix(".remap")
		if not (usable.ends_with(".tres") or usable.ends_with(".res")):
			continue
		loaded_names.append(usable)

	loaded_names.sort()
	for usable: String in loaded_names:
		var path: String = "%s/%s" % [dir_path, usable]
		var resource: Resource = load(path)
		if resource == null:
			library.errors.append("Failed to load %s" % path)
			continue
		var definition: StalkDefinition = resource as StalkDefinition
		if definition == null:
			library.errors.append(
				"%s is not a StalkDefinition (got %s)" % [path, resource.get_class()]
			)
			continue
		library.stalks.append(definition)

	library.stalks.sort_custom(_by_id)
	library.validate()
	return library


## A library over a set of definitions that came from somewhere other than the
## stalks directory.
##
## **This is what makes content per-match rather than per-install.** The shipped
## `.tres` files used to be the only content there was, so every machine could
## load its own copy and only ids needed to travel. Custom stalks end that: the
## content of a match is now chosen by its host, may include companies this
## machine has never seen, and arrives over the wire like any other match state.
## A library built here is that match's content.
##
## Validated like any other, so a set assembled from a file or a packet is held
## to the same rules as the authored one.
static func of(stalks: Array[StalkDefinition]) -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.new()
	library.stalks = stalks.duplicate()
	library.stalks.sort_custom(_by_id)
	library.validate()
	return library


## Everything this installation could play with: the shipped stalks and the
## player's own, in one library.
##
## What the Custom Stalks screen lists and what a match is chosen from. The
## per-file problems are *not* here — they belong to `CustomStalkStore`, which
## the picker reads separately so it can say which file was wrong.
static func available(
	stalks_dir: String = STALKS_DIR,
	custom_dir: String = CustomStalkStore.DIR,
) -> ContentLibrary:
	var shipped: ContentLibrary = ContentLibrary.load_from(stalks_dir)
	var combined: Array[StalkDefinition] = shipped.stalks.duplicate()
	combined.append_array(CustomStalkStore.load_from(custom_dir).stalks)

	var library: ContentLibrary = ContentLibrary.of(combined)
	# A broken shipped library stays broken through the combination; a custom
	# stalk cannot repair it and must not hide it.
	for error: String in shipped.errors:
		library.errors.append(error)
	return library


## The stalks with these ids, as a library of their own: one match's content.
##
## An empty `ids` means everything in this library. Callers choosing a match's
## content pass the shipped library in that case rather than this one — "no
## choice made" means the shipped ten, not every custom file on the machine.
##
## An id that is not here is reported rather than skipped: a match quietly
## missing a company somebody chose is worse than one that refuses to start.
##
## **The cap lives here**, so every route to a match library passes it — the
## picker, a settings object built by a test, and a launch flag alike.
func subset(ids: Array[StringName]) -> ContentLibrary:
	var picked: Array[StalkDefinition] = []
	var missing: Array[String] = []

	if ids.is_empty():
		picked = stalks.duplicate()
	else:
		for wanted: StringName in ids:
			var found: StalkDefinition = stalk_by_id(wanted)
			if found == null:
				missing.append(String(wanted))
				continue
			picked.append(found)

	var library: ContentLibrary = ContentLibrary.of(picked)
	for id: String in missing:
		library.errors.append("No stalk called '%s' is installed." % id)
	if picked.size() > StalkSchema.MAX_STALKS_PER_MATCH:
		library.errors.append(
			"A match may have %d stalks; this one has %d."
			% [StalkSchema.MAX_STALKS_PER_MATCH, picked.size()]
		)
	return library


func is_valid() -> bool:
	return errors.is_empty()


## Re-runs validation, replacing `errors`. Returns the error list.
##
## Collects every problem rather than stopping at the first, so one run reports
## everything an author needs to fix.
func validate() -> Array[String]:
	errors = []

	if stalks.is_empty():
		errors.append("No stalks were loaded.")
		return errors

	var seen_stalk_ids: Dictionary[StringName, bool] = {}
	var seen_event_ids: Dictionary[StringName, bool] = {}

	for stalk: StalkDefinition in stalks:
		var label: String = str(stalk.id) if stalk.id != &"" else "<missing id>"

		if stalk.id == &"":
			errors.append("A stalk has no id (display name %s)." % stalk.display_name)
		elif seen_stalk_ids.has(stalk.id):
			errors.append("Duplicate stalk id: %s" % label)
		else:
			seen_stalk_ids[stalk.id] = true

		if stalk.display_name.is_empty():
			errors.append("Stalk %s has no display name." % label)
		if stalk.starting_price <= 0:
			errors.append("Stalk %s has a starting price of %d." % [label, stalk.starting_price])

		_validate_range(stalk, label, stalk.bear_change, "bear_change")
		_validate_range(stalk, label, stalk.bull_change, "bull_change")

		if stalk.is_price_static and not stalk.all_events().is_empty():
			errors.append(
				"Stalk %s is static-price but carries %d events, which can never fire."
				% [label, stalk.all_events().size()]
			)

		_validate_events(stalk, label, stalk.bull_events, MarketMood.Value.BULL, seen_event_ids)
		_validate_events(stalk, label, stalk.bear_events, MarketMood.Value.BEAR, seen_event_ids)

	return errors


func _validate_range(
	_stalk: StalkDefinition,
	label: String,
	bounds: Vector2i,
	field: String,
) -> void:
	if bounds.x < 0 or bounds.y < 0:
		errors.append("Stalk %s has a negative %s %s; magnitudes are stored positive."
			% [label, field, str(bounds)])
	if bounds.x > bounds.y:
		errors.append("Stalk %s has %s with min above max %s."
			% [label, field, str(bounds)])


func _validate_events(
	stalk: StalkDefinition,
	label: String,
	events: Array[SpecialEventDefinition],
	expected_mood: MarketMood.Value,
	seen_event_ids: Dictionary[StringName, bool],
) -> void:
	for event: SpecialEventDefinition in events:
		if event == null:
			errors.append("Stalk %s has an empty slot in its %s event list."
				% [label, MarketMood.label(expected_mood)])
			continue

		var event_label: String = str(event.id) if event.id != &"" else "<missing id>"

		if event.id == &"":
			errors.append("Stalk %s has an event with no id." % label)
		elif seen_event_ids.has(event.id):
			errors.append("Duplicate event id: %s" % event_label)
		else:
			seen_event_ids[event.id] = true

		# The whole point of validating: an event whose target does not match the
		# stalk it lives on would never fire, silently.
		if event.target_stalk_id != stalk.id:
			errors.append("Event %s lives on stalk %s but targets %s."
				% [event_label, label, str(event.target_stalk_id)])

		if event.mood != expected_mood:
			errors.append("Event %s is in the %s list but is marked %s."
				% [event_label, MarketMood.label(expected_mood), MarketMood.label(event.mood)])

		if event.price_change == 0:
			errors.append("Event %s has a price change of 0 and would do nothing."
				% event_label)

		if event.flavour_text.is_empty():
			errors.append("Event %s has no flavour text." % event_label)


# ------------------------------------------------------------------- accessors

func stalk_by_id(stalk_id: StringName) -> StalkDefinition:
	for stalk: StalkDefinition in stalks:
		if stalk.id == stalk_id:
			return stalk
	return null


## One event by id, or null. Needed to rebuild a YearResult on a client: only the
## event's id crosses the wire, and the client reads the flavour text from its own
## copy of the content. See StateSync.
func event_by_id(event_id: StringName) -> SpecialEventDefinition:
	for event: SpecialEventDefinition in all_events():
		if event.id == event_id:
			return event
	return null


func all_events() -> Array[SpecialEventDefinition]:
	var combined: Array[SpecialEventDefinition] = []
	for stalk: StalkDefinition in stalks:
		combined.append_array(stalk.all_events())
	return combined


func events_for_mood(mood: MarketMood.Value) -> Array[SpecialEventDefinition]:
	var selected: Array[SpecialEventDefinition] = []
	for stalk: StalkDefinition in stalks:
		selected.append_array(
			stalk.bull_events if mood == MarketMood.Value.BULL else stalk.bear_events
		)
	return selected


# -------------------------------------------------------------------- factories

## A fresh set of StalkStates for a new match.
func build_stalk_states() -> Array[StalkState]:
	var states: Array[StalkState] = []
	for stalk: StalkDefinition in stalks:
		states.append(StalkState.new(stalk))
	return states


## An EventPool holding every authored event.
func build_event_pool() -> EventPool:
	return EventPool.new(all_events())


static func _by_id(a: StalkDefinition, b: StalkDefinition) -> bool:
	return String(a.id) < String(b.id)


func _to_string() -> String:
	return "ContentLibrary(%d stalks, %d events, %s)" % [
		stalks.size(),
		all_events().size(),
		"valid" if is_valid() else "%d errors" % errors.size(),
	]
