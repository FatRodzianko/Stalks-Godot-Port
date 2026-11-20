class_name StalkSchema
extends RefCounted
## Builds a StalkDefinition out of plain data, field by field, and refuses
## anything it cannot vouch for.
##
## **This is the security boundary for player-authored content.** Two different
## callers hand it the same shape and get the same checks:
##
##   * `CustomStalkStore` reads a JSON file the player wrote. A bad one is
##     listed in the picker and skipped.
##   * `StateSync` decodes a stalk definition that arrived from the host. A bad
##     one ends the connection with a reason.
##
## Those are different failures, not different rules, which is why the rules
## live in one place and the handling lives in the two callers. A rule that
## existed on only one of the paths would be the hole.
##
## **Nothing here decodes an object.** The input is a Dictionary of built-in
## types and every field is read by name off a whitelist; a key this class does
## not know about is an error rather than something copied across. That is D41's
## posture applied to content: see docs/decisions.md D41 and D119.
##
## See docs/game-rules.md §3 for what the fields mean and
## docs/custom-stalks.md for the file format.


# ------------------------------------------------------------------- the limits
#
# Every one of these is a real measurement of the shipped content, rounded up,
# rather than a round number picked for looking sensible. The shipped ten are
# the proof that the limits fit the game: `test_custom_stalks.gd` encodes them
# all and runs them back through this class.

## Longest display name. The longest shipped one is 41 characters ("My Pillow,
## Your Pillow, We're All Pillows!"). The board's name column is six characters
## wide and scrolls anything longer (`MarqueeLabel`), so this is a limit on the
## data rather than on the layout.
const MAX_NAME_LENGTH: int = 48

## Longest company description. The longest shipped one is 344 characters.
## `StalkPanel` wraps it into a dialog that grows, so the cap is about keeping
## the dialog on screen.
const MAX_DESCRIPTION_LENGTH: int = 600

## Longest special-event flavour text. The longest shipped one is 240
## characters. `ScrollingLabel` creeps a line at a time through anything that
## does not fit, so this is generous on purpose.
const MAX_FLAVOUR_LENGTH: int = 300

## Longest board symbol. Nothing displays one yet (see `StalkDefinition.ticker`)
## but it is accepted, so it is bounded.
const MAX_TICKER_LENGTH: int = 8

## Longest id. Long enough to be descriptive, short enough to sit in a log line.
const MAX_ID_LENGTH: int = 40

## Prices are whole numbers of dollars and a stalk above 150 splits in the same
## year (`YearResolver`), so a starting price above the split threshold means a
## stalk that halves before anybody has traded it.
const MIN_PRICE: int = 1
const MAX_PRICE: int = 150

## Dividends are paid per share every year and the board column is four
## characters. The largest shipped dividend is 8.
const MAX_DIVIDEND: int = 99

## Magnitude of a yearly change, stored positive. The largest shipped bound is
## 50 (strYker's bear range).
const MAX_CHANGE: int = 99

## Events per stalk, per mood. The shipped stalks carry five of each.
const MAX_EVENTS_PER_MOOD: int = 10

## Stalks in one match.
##
## **The one number to change.** Ten matches the board the game was designed
## around and the original's ten companies. Raising it is this constant and
## nothing else: the picker counts against it, the board scrolls
## (`gameplay_screen.tscn`), and the wire has no per-stalk assumption. Around
## fifty is the figure that has been discussed. See docs/decisions.md D122.
const MAX_STALKS_PER_MATCH: int = 10

## Largest custom stalk file that will be opened at all, checked before the
## bytes are read. 64 KB is about eighty times the largest shipped stalk.
const MAX_FILE_BYTES: int = 64 * 1024

## The format version a file declares. A file without one is assumed to be
## version 1, so the first generation of files need not carry it.
const CURRENT_FORMAT: int = 1

## What every custom id begins with, so a custom stalk can never collide with
## or shadow a shipped one whatever its file says. See docs/decisions.md D120.
const CUSTOM_PREFIX: String = "custom:"

## Separates a stalk id from the event index within it, for the event ids this
## class derives. Not legal in an authored id, so a derived event id cannot
## collide with an authored one.
const EVENT_SEPARATOR: String = "#"

## What a mood is called in a file and on the wire.
##
## **Not `MarketMood.label`**, which returns "BULL!!!" and "bear..." — those are
## the original game's display strings and belong on screen, not in data. A
## stored value that doubles as a label is a value that cannot be reworded.
const MOOD_BULL: String = "bull"
const MOOD_BEAR: String = "bear"


## Every key a stalk may carry. Anything else is an error rather than something
## quietly ignored: a misspelled `bull_dividends` would otherwise become a
## silent zero, which is exactly the class of content bug `ContentLibrary`
## exists to catch.
const STALK_KEYS: PackedStringArray = [
	"format",
	"id",
	"name",
	"description",
	"ticker",
	"starting_price",
	"bull_change",
	"bear_change",
	"bull_dividend",
	"bear_dividend",
	"is_price_static",
	"investors_are_anonymous",
	"events",
]

const EVENT_KEYS: PackedStringArray = [
	"id",
	"mood",
	"text",
	"price_change",
]


## The stalk that was built, or null when `errors` is not empty.
var definition: StalkDefinition = null

## Everything wrong with the data, in the order it was found. Collects every
## problem rather than stopping at the first, so one run tells an author
## everything to fix.
var errors: Array[String] = []


func is_valid() -> bool:
	return errors.is_empty() and definition != null


# ----------------------------------------------------------------- the two doors

## Builds from a file the player wrote.
##
## `file_stem` is the file's name without its extension, used as the id when the
## file does not name one. The id is prefixed either way, so nothing a file says
## can produce a built-in's id.
static func from_file_data(data: Dictionary, file_stem: String) -> StalkSchema:
	var schema: StalkSchema = StalkSchema.new()

	var requested: String = file_stem
	if data.has("id"):
		if not (data["id"] is String):
			schema.errors.append("'id' must be text.")
			return schema
		requested = String(data["id"])

	var slug: String = _slug_of(requested)
	if slug.is_empty():
		schema.errors.append(
			"Cannot make an id from '%s'. Use letters, digits, - or _." % requested
		)
		return schema

	schema._build(data, StringName(CUSTOM_PREFIX + slug))
	return schema


## Builds from a definition that arrived over the wire.
##
## **Treat it as hostile.** The id is taken from the data rather than derived,
## because a built-in stalk keeps its own id across the wire and the receiver
## has to be able to match it — so the id is checked instead, for shape and for
## length, like every other field.
static func from_wire(data: Dictionary) -> StalkSchema:
	var schema: StalkSchema = StalkSchema.new()

	if not data.has("id") or not (data["id"] is String):
		schema.errors.append("A stalk arrived with no id.")
		return schema

	var raw: String = String(data["id"])
	if not _is_well_formed_id(raw):
		schema.errors.append("Stalk id '%s' is not a usable id." % _for_display(raw))
		return schema

	schema._build(data, StringName(raw))
	return schema


# -------------------------------------------------------------------- encoding

## One stalk as plain data, for the wire. The mirror of `from_wire`.
##
## Built-in and custom stalks encode identically: the receiver rebuilds the
## whole match's content from this and never consults its own files, so there
## is no second path for a built-in to arrive by. See docs/decisions.md D121.
static func encode(stalk: StalkDefinition) -> Dictionary:
	return {
		"format": CURRENT_FORMAT,
		"id": String(stalk.id),
		"name": stalk.display_name,
		"description": stalk.description,
		"ticker": String(stalk.ticker),
		"starting_price": stalk.starting_price,
		"bull_change": [stalk.bull_change.x, stalk.bull_change.y],
		"bear_change": [stalk.bear_change.x, stalk.bear_change.y],
		"bull_dividend": stalk.bull_dividend,
		"bear_dividend": stalk.bear_dividend,
		"is_price_static": stalk.is_price_static,
		"investors_are_anonymous": stalk.investors_are_anonymous,
		"events": _encoded_events(stalk),
	}


static func _encoded_events(stalk: StalkDefinition) -> Array:
	var out: Array = []
	for event: SpecialEventDefinition in stalk.all_events():
		if event == null:
			continue
		out.append({
			"id": String(event.id),
			"mood": mood_token(event.mood),
			"text": event.flavour_text,
			"price_change": event.price_change,
		})
	return out


# --------------------------------------------------------------- building it up

## The one builder both doors reach. Every field is assigned by name; the
## dictionary is never copied across wholesale.
func _build(data: Dictionary, stalk_id: StringName) -> void:
	_reject_unknown_keys(data, STALK_KEYS, "stalk")
	_check_format(data)

	var built: StalkDefinition = StalkDefinition.new()
	built.id = stalk_id
	built.display_name = _text(data, "name", MAX_NAME_LENGTH, true)
	built.description = _text(data, "description", MAX_DESCRIPTION_LENGTH, false)
	built.ticker = StringName(_identifier(data, "ticker", MAX_TICKER_LENGTH))
	built.starting_price = _whole(data, "starting_price", MIN_PRICE, MAX_PRICE, 100)
	built.bull_change = _range(data, "bull_change")
	built.bear_change = _range(data, "bear_change")
	built.bull_dividend = _whole(data, "bull_dividend", 0, MAX_DIVIDEND, 0)
	built.bear_dividend = _whole(data, "bear_dividend", 0, MAX_DIVIDEND, 0)
	built.is_price_static = _flag(data, "is_price_static")
	built.investors_are_anonymous = _flag(data, "investors_are_anonymous")

	_build_events(data, built)

	# A static-price stalk cannot be moved by anything, so an event on one could
	# never fire. `ContentLibrary` says the same about the shipped content.
	if built.is_price_static and not built.all_events().is_empty():
		errors.append(
			"Stalk '%s' never moves, so its %d events could never happen."
			% [stalk_id, built.all_events().size()]
		)

	if errors.is_empty():
		definition = built


## **Events are optional, and a stalk with none is simply never picked for a
## special event.** `EventPool` draws from whatever it is given, so a stalk that
## contributes nothing to the pool cannot be drawn. No rule is needed for it.
func _build_events(data: Dictionary, built: StalkDefinition) -> void:
	if not data.has("events"):
		return
	if not (data["events"] is Array):
		errors.append("'events' must be a list.")
		return

	var entries: Array = data["events"]
	var bull_count: int = 0
	var bear_count: int = 0

	for index: int in entries.size():
		if not (entries[index] is Dictionary):
			errors.append("Event %d is not a set of fields." % (index + 1))
			continue
		var entry: Dictionary = entries[index]
		_reject_unknown_keys(entry, EVENT_KEYS, "event %d" % (index + 1))

		var mood: int = _mood(entry, index)
		if mood < 0:
			continue

		var is_bull: bool = mood == MarketMood.Value.BULL
		var position: int = bull_count if is_bull else bear_count
		if position >= MAX_EVENTS_PER_MOOD:
			errors.append(
				"More than %d %s events; a stalk may have %d of each."
				% [MAX_EVENTS_PER_MOOD, mood_token(mood as MarketMood.Value), MAX_EVENTS_PER_MOOD]
			)
			continue

		var event: SpecialEventDefinition = _build_event(entry, built, mood, index, position)
		if event == null:
			continue

		if is_bull:
			built.bull_events.append(event)
			bull_count += 1
		else:
			built.bear_events.append(event)
			bear_count += 1


func _build_event(
	entry: Dictionary,
	built: StalkDefinition,
	mood: int,
	index: int,
	position: int,
) -> SpecialEventDefinition:
	var label: String = "Event %d" % (index + 1)

	var text: String = _text(entry, "text", MAX_FLAVOUR_LENGTH, true, label)
	# A change of zero is an event that happens and does nothing, which reads to
	# a player as the game being broken.
	var change: int = _whole(entry, "price_change", -MAX_CHANGE, MAX_CHANGE, 0, label)
	if change == 0:
		errors.append("%s changes the price by 0, so nothing would happen." % label)

	var event: SpecialEventDefinition = SpecialEventDefinition.new()
	event.id = _event_id(entry, built.id, mood, position)
	event.target_stalk_id = built.id
	event.mood = mood as MarketMood.Value
	event.flavour_text = text
	event.price_change = change
	return event


## An event's id: the one it arrived with, or one derived from where it sits.
##
## **A file does not name its events.** An author writing a stalk should not
## have to invent ten unique keys, and every duplicate-id problem disappears
## when the ids are positions rather than names. An id that *does* arrive — from
## the wire, where the shipped events keep the ids their `.tres` files gave them
## — is checked and kept, because the year result names its event by id and both
## sides must agree on it.
func _event_id(
	entry: Dictionary, stalk_id: StringName, mood: int, position: int
) -> StringName:
	var derived: StringName = StringName(
		"%s%s%s%d"
		% [stalk_id, EVENT_SEPARATOR, mood_token(mood as MarketMood.Value), position]
	)
	if not entry.has("id"):
		return derived
	if not (entry["id"] is String):
		errors.append("An event id must be text.")
		return derived

	var raw: String = String(entry["id"])
	if not _is_well_formed_id(raw):
		errors.append("Event id '%s' is not a usable id." % _for_display(raw))
		return derived
	return StringName(raw)


# ----------------------------------------------------------------- field readers
#
# One reader per kind of field. Each reports its own problem and returns
# something harmless, so a single bad field does not stop the rest being
# checked and the author gets the whole list at once.

## A line of player-visible text.
##
## **Printable ASCII only** (space to `~`). The owner's instruction was
## "alphanumeric", which would reject the game's own `PG&Enron`, `strYker!!!`
## and `My Pillow, Your Pillow, We're All Pillows!`, so the rule is the widest
## one the game can actually draw: Terminus is a fixed-width bitmap font whose
## columns are measured in characters, and anything outside this range is either
## a missing glyph or a control character that corrupts a row. All ten shipped
## stalks pass it. See docs/decisions.md D119.
func _text(
	data: Dictionary,
	key: String,
	limit: int,
	required: bool,
	owner_label: String = "",
) -> String:
	var where: String = key if owner_label.is_empty() else "%s '%s'" % [owner_label, key]

	if not data.has(key):
		if required:
			errors.append("Missing '%s'." % where)
		return ""
	if not (data[key] is String):
		errors.append("'%s' must be text." % where)
		return ""

	var value: String = String(data[key])
	if required and value.strip_edges().is_empty():
		errors.append("'%s' is empty." % where)
		return ""
	if value.length() > limit:
		errors.append(
			"'%s' is %d characters; the limit is %d." % [where, value.length(), limit]
		)
		return ""
	if not _is_printable_ascii(value):
		errors.append(
			"'%s' contains characters the game cannot draw. Use plain ASCII." % where
		)
		return ""
	if value.contains("://"):
		# Content is data, never somewhere to load from. Nothing in the game
		# treats this text as a path or fetches anything named in it, and this
		# is what keeps it that way. No shipped description or event text
		# contains a scheme.
		#
		# **Traversal is not checked here, deliberately.** `..` is ordinary
		# prose — the shipped "You're not my mutual..." would fail on it, and
		# it did while this rule was first written. The fields that *are* ever
		# treated as names, ids and tickers, go through `_is_plain_token`
		# instead, which permits no dot, slash or colon at all. Traversal is
		# impossible there by construction rather than by a blacklist.
		errors.append("'%s' may not contain a link." % where)
		return ""
	return value


## A short machine-ish string: a ticker. Optional everywhere it is used.
func _identifier(data: Dictionary, key: String, limit: int) -> String:
	if not data.has(key):
		return ""
	if not (data[key] is String):
		errors.append("'%s' must be text." % key)
		return ""

	var value: String = String(data[key])
	if value.is_empty():
		return ""
	if value.length() > limit:
		errors.append("'%s' is longer than %d characters." % [key, limit])
		return ""
	if not _is_plain_token(value):
		errors.append("'%s' may only hold letters, digits, - and _." % key)
		return ""
	return value


## A whole number within bounds.
##
## **Rejected, not clamped.** Every one of these feeds integer money or a
## fixed-width column, and a host sending 2^40 for a dividend is not somebody
## whose value should be quietly corrected — it is somebody whose content should
## not load. JSON has no integer type, so a value with a fractional part is
## refused rather than truncated.
func _whole(
	data: Dictionary,
	key: String,
	low: int,
	high: int,
	fallback: int,
	owner_label: String = "",
) -> int:
	var where: String = key if owner_label.is_empty() else "%s '%s'" % [owner_label, key]

	if not data.has(key):
		return fallback

	var raw: Variant = data[key]
	if raw is bool or not (raw is int or raw is float):
		errors.append("'%s' must be a whole number." % where)
		return fallback
	if raw is float and absf(float(raw) - roundf(float(raw))) > 0.0:
		errors.append("'%s' must be a whole number, not %s." % [where, raw])
		return fallback

	var value: float = float(raw)
	# Outside this, `int()` does not represent the value at all, so the bounds
	# check below would be comparing something other than what was sent.
	if absf(value) > 9.0e15:
		errors.append("'%s' is far outside what the game can hold." % where)
		return fallback

	var whole: int = int(value)
	if whole < low or whole > high:
		errors.append("'%s' is %d; it must be between %d and %d." % [where, whole, low, high])
		return fallback
	return whole


## A `(min, max)` magnitude pair, written as a two-element list.
func _range(data: Dictionary, key: String) -> Vector2i:
	if not data.has(key):
		return Vector2i.ZERO
	if not (data[key] is Array):
		errors.append("'%s' must be a list of two whole numbers." % key)
		return Vector2i.ZERO

	var entries: Array = data[key]
	if entries.size() != 2:
		errors.append("'%s' must hold exactly two numbers, not %d." % [key, entries.size()])
		return Vector2i.ZERO

	var pair: Dictionary = {"low": entries[0], "high": entries[1]}
	# Magnitudes are stored positive and applied in the direction of the mood,
	# so a negative bound here means a bear year that raises the price.
	var low: int = _whole(pair, "low", 0, MAX_CHANGE, 0, key)
	var high: int = _whole(pair, "high", 0, MAX_CHANGE, 0, key)
	if low > high:
		errors.append("'%s' has its smallest value above its largest." % key)
		return Vector2i.ZERO
	return Vector2i(low, high)


## Which pool an event belongs to, or -1 when it does not say usably.
##
## Returned as a plain int rather than a `MarketMood.Value` precisely so there
## is a value meaning "no answer": an enum has no room for one, and defaulting
## a bad mood to BULL would silently move an event into the wrong pool.
func _mood(entry: Dictionary, index: int) -> int:
	var label: String = "Event %d" % (index + 1)
	if not entry.has("mood"):
		errors.append("%s does not say whether it is a %s or %s event."
			% [label, MOOD_BULL, MOOD_BEAR])
		return -1
	if not (entry["mood"] is String):
		errors.append("%s has a 'mood' that is not text." % label)
		return -1

	var raw: String = String(entry["mood"]).strip_edges().to_lower()
	if raw == MOOD_BULL:
		return MarketMood.Value.BULL
	if raw == MOOD_BEAR:
		return MarketMood.Value.BEAR

	errors.append("%s has a mood of '%s'; it must be '%s' or '%s'."
		% [label, _for_display(raw), MOOD_BULL, MOOD_BEAR])
	return -1


## What a mood is called in data. See `MOOD_BULL`.
static func mood_token(mood: MarketMood.Value) -> String:
	return MOOD_BEAR if mood == MarketMood.Value.BEAR else MOOD_BULL


func _flag(data: Dictionary, key: String) -> bool:
	if not data.has(key):
		return false
	if not (data[key] is bool):
		errors.append("'%s' must be true or false." % key)
		return false
	return bool(data[key])


func _check_format(data: Dictionary) -> void:
	if not data.has("format"):
		return
	var raw: Variant = data["format"]
	if raw is bool or not (raw is int or raw is float):
		errors.append("'format' must be a whole number.")
		return
	if int(raw) != CURRENT_FORMAT:
		errors.append(
			"This file says format %d; this version of the game reads format %d."
			% [int(raw), CURRENT_FORMAT]
		)


## Anything not on the whitelist, named so a typo is obvious.
func _reject_unknown_keys(data: Dictionary, allowed: PackedStringArray, what: String) -> void:
	for key: Variant in data:
		if not (key is String):
			errors.append("A field name in the %s is not text." % what)
			continue
		if String(key) in allowed:
			continue
		errors.append("The %s has a field called '%s', which is not one of its fields."
			% [what, _for_display(String(key))])


# ------------------------------------------------------------------- characters

## Space (32) through tilde (126). See `_text` for why this and not narrower.
static func _is_printable_ascii(value: String) -> bool:
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if code < 32 or code > 126:
			return false
	return true


## Letters, digits, hyphen and underscore, and at least one character.
static func _is_plain_token(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		if not _is_token_character(value.unicode_at(index)):
			return false
	return true


static func _is_token_character(code: int) -> bool:
	if code >= 48 and code <= 57:
		return true
	if code >= 65 and code <= 90:
		return true
	if code >= 97 and code <= 122:
		return true
	return code == 45 or code == 95


## Whether an id that arrived from somewhere else is one this game could have
## produced: a plain token, optionally behind the custom prefix, optionally with
## one derived event suffix on the end.
##
## Being strict here is what keeps an id out of every other job a string can be
## given — there is no separator, no traversal and no scheme that could survive
## this check.
static func _is_well_formed_id(raw: String) -> bool:
	if raw.is_empty() or raw.length() > MAX_ID_LENGTH:
		return false

	var body: String = raw
	if body.begins_with(CUSTOM_PREFIX):
		body = body.substr(CUSTOM_PREFIX.length())

	var parts: PackedStringArray = body.split(EVENT_SEPARATOR)
	if parts.size() > 2:
		return false
	for part: String in parts:
		if not _is_plain_token(part):
			return false
	return true


## A filename or a requested id turned into a token. Anything that is not a
## token character becomes an underscore, runs of them collapse, and the result
## is lowercased — so two files cannot differ by case alone.
static func _slug_of(raw: String) -> String:
	var out: String = ""
	for index: int in raw.length():
		var code: int = raw.unicode_at(index)
		if _is_token_character(code):
			out += raw[index]
			continue
		if not out.ends_with("_"):
			out += "_"
	out = out.strip_edges().lstrip("_").rstrip("_").to_lower()
	return out.substr(0, MAX_ID_LENGTH - CUSTOM_PREFIX.length())


## Untrusted text on its way into an error message, which is itself drawn on
## screen. Stripped of anything unprintable and cut short, so a hostile id
## cannot use the complaint about it as a way in.
static func _for_display(raw: String) -> String:
	var out: String = ""
	for index: int in mini(raw.length(), 32):
		var code: int = raw.unicode_at(index)
		out += raw[index] if code >= 32 and code <= 126 else "?"
	return out
