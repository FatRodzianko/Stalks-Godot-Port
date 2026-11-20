class_name CustomStalkStore
extends RefCounted
## The player's own stalks: a folder of JSON files, read and checked.
##
## One file is one company, with its special events inside it, matching the way
## a shipped stalk is one `.tres` (docs/decisions.md D29). Adding a stalk is
## adding a file; nothing else needs editing and the game need not be rebuilt.
##
## **JSON rather than `.tres`.** A `.tres` is a Godot resource, and loading one
## instantiates whatever script it names — which is the object-decoding hole
## that D41 closed deliberately for the network. A folder the player can drop
## files into is exactly as untrusted as a packet, so it gets the same answer:
## `JSON.parse_string` returns nothing but built-in types, and
## `StalkSchema` builds the definition field by field from there. See
## docs/decisions.md D120.
##
## **A bad file is skipped, never fatal.** Nine good files and one typo should
## give nine stalks and one message, not an empty picker. Every problem is
## collected in `problems` with the file's name on the front, which is what the
## Custom Stalks screen lists.
##
## The sibling job — checking a definition that arrived from another player — is
## the same `StalkSchema` with different handling. See `StateSync`.


## Where a player's stalks live. `user://` is the per-user writable directory;
## on Windows that is
## `%APPDATA%\Godot\app_userdata\Stalks Stalks Stalks\custom_stalks\`.
## It is outside the exported game, so an update cannot overwrite it.
const DIR: String = "user://custom_stalks"

## Written into the folder the first time it is made, so somebody who finds the
## folder is not left guessing at the format.
const GUIDE_NAME: String = "HOW-TO-WRITE-A-STALK.txt"


## Everything that loaded, sorted by id so the order is the same on every
## machine — the same reason `ContentLibrary` sorts.
var stalks: Array[StalkDefinition] = []

## One line per problem, each naming the file it came from. Empty when every
## file loaded.
var problems: Array[String] = []


## Reads every `.json` in `dir_path`.
##
## Always returns a store. A missing folder is not a problem — it is what a
## player who has never written a stalk looks like — so it is created, with the
## guide in it, and an empty store comes back.
static func load_from(dir_path: String = DIR) -> CustomStalkStore:
	var store: CustomStalkStore = CustomStalkStore.new()

	if not DirAccess.dir_exists_absolute(dir_path):
		store._create_folder(dir_path)
		return store

	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		store.problems.append("Cannot open %s." % dir_path)
		return store

	var names: PackedStringArray = []
	for file_name: String in dir.get_files():
		if file_name.to_lower().ends_with(".json"):
			names.append(file_name)
	# Directory order is not guaranteed and two machines must agree.
	names.sort()

	var seen: Dictionary[StringName, String] = {}
	for file_name: String in names:
		store._read_one("%s/%s" % [dir_path, file_name], file_name, seen)

	store.stalks.sort_custom(_by_id)
	return store


func is_empty() -> bool:
	return stalks.is_empty()


# ------------------------------------------------------------------- one file

func _read_one(path: String, file_name: String, seen: Dictionary[StringName, String]) -> void:
	var text: String = _read_text(path, file_name)
	if text.is_empty():
		return

	# **A JSON instance, not `JSON.parse_string`.** The static version reports a
	# bad file by pushing an engine error, which is both a console message the
	# player cannot act on and, in the suite, a failure. An instance hands back
	# the line and the reason instead, which is what an author actually needs.
	var reader: JSON = JSON.new()
	if reader.parse(text) != OK:
		problems.append(
			"%s: line %d: %s" % [file_name, reader.get_error_line(), reader.get_error_message()]
		)
		return

	var parsed: Variant = reader.data
	if not (parsed is Dictionary):
		problems.append("%s: should hold one stalk, written as a JSON object." % file_name)
		return

	var stem: String = file_name.get_basename()
	var schema: StalkSchema = StalkSchema.from_file_data(parsed, stem)
	if not schema.is_valid():
		for error: String in schema.errors:
			problems.append("%s: %s" % [file_name, error])
		return

	# Two files whose names slug to the same id, or one file naming the id
	# another already took. Both are the author's mistake and both need saying,
	# because the second file would otherwise simply vanish.
	var id: StringName = schema.definition.id
	if seen.has(id):
		problems.append(
			"%s: has the same id as %s. Rename one of them." % [file_name, seen[id]]
		)
		return
	seen[id] = file_name
	stalks.append(schema.definition)


## The file's text, or an empty string with the problem recorded.
##
## **The length is checked before the bytes are read.** Reading first and
## checking after is the version of this that runs out of memory on a file
## built to do exactly that; the check is worth nothing unless it happens
## first.
func _read_text(path: String, file_name: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("%s: could not be opened." % file_name)
		return ""

	var size: int = file.get_length()
	if size == 0:
		problems.append("%s: is empty." % file_name)
		return ""
	if size > StalkSchema.MAX_FILE_BYTES:
		problems.append(
			"%s: is %d bytes; the limit is %d."
			% [file_name, size, StalkSchema.MAX_FILE_BYTES]
		)
		return ""
	return file.get_as_text()


# -------------------------------------------------------------------- the folder

## Makes the folder and drops the guide in it.
##
## Done on a read rather than at startup so there is exactly one place that
## knows where custom stalks live, and so a player who deletes the folder gets
## it back by opening the picker.
func _create_folder(dir_path: String) -> void:
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
		problems.append("Cannot create %s." % dir_path)
		return
	var guide: FileAccess = FileAccess.open(
		"%s/%s" % [dir_path, GUIDE_NAME], FileAccess.WRITE
	)
	if guide != null:
		guide.store_string(guide_text())


## What the guide says. Separate from writing it so a test can read it without
## touching a disk, and so the limits in it come from the constants rather than
## from a copy of them that can drift.
static func guide_text() -> String:
	return """Custom stalks

One file is one company. Put a .json file in this folder and the company
appears in Create Game -> Custom Stalks, where you tick the ones a match
should use.

Required: name, bull_dividend, bear_dividend, bull_change, bear_change.
Everything else may be left out.

{
  "format": 1,
  "name": "Example Holdings",
  "description": "",
  "starting_price": 100,
  "bull_change": [0, 15],
  "bear_change": [5, 25],
  "bull_dividend": 3,
  "bear_dividend": 1,
  "events": [
    {"mood": "bull", "text": "Something good happened.", "price_change": 10},
    {"mood": "bear", "text": "Something bad happened.", "price_change": -15}
  ]
}

bull_change and bear_change are [smallest, largest] amounts the price moves in
a year. Both are written as positive numbers; a bear change is subtracted.

Events are optional. A company with none is never picked for a special event.
A bull event needs a positive price_change and a bear event a negative one.

Limits:
  name            up to {name} characters
  description     up to {description} characters
  event text      up to {flavour} characters
  starting_price  {min_price} to {max_price}
  dividends       0 to {dividend}
  change amounts  0 to {change}
  events          up to {events} bull and {events} bear
  file size       up to {bytes} bytes

Text may use plain ASCII only: letters, digits, spaces and ordinary
punctuation. Accented letters and emoji are rejected, because the game's font
cannot draw them.

The id a company is known by comes from the file's name, so two files cannot
share one unless they are named the same. You do not need to write an id.

If a file has a mistake in it, the Custom Stalks screen says which file and
what is wrong, and the rest still load.
""".format({
		"name": StalkSchema.MAX_NAME_LENGTH,
		"description": StalkSchema.MAX_DESCRIPTION_LENGTH,
		"flavour": StalkSchema.MAX_FLAVOUR_LENGTH,
		"min_price": StalkSchema.MIN_PRICE,
		"max_price": StalkSchema.MAX_PRICE,
		"dividend": StalkSchema.MAX_DIVIDEND,
		"change": StalkSchema.MAX_CHANGE,
		"events": StalkSchema.MAX_EVENTS_PER_MOOD,
		"bytes": StalkSchema.MAX_FILE_BYTES,
	})


static func _by_id(a: StalkDefinition, b: StalkDefinition) -> bool:
	return String(a.id) < String(b.id)
