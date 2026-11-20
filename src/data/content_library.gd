class_name ContentLibrary
extends RefCounted
## Loads the authored stalk content from disk and validates it.
##
## Content is authored as one `.tres` per stalk in `src/data/stalks/`, each
## carrying its own special events (see docs/decisions.md D29). This class turns
## that directory into something the simulation can use, and refuses to hand back
## content it cannot vouch for.
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
