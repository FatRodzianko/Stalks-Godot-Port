extends GutTest
## A hostile host, aimed at the client that joined its game.
##
## **Why this file is separate from `test_custom_stalks.gd`.** That one checks
## the rules behave as written, with the kind of bad input an author produces
## by accident. This one assumes somebody is trying: it is the record of an
## attack on the receive path carried out on 2026-11-20, and every probe that
## found something is kept here so the finding cannot come back.
##
## **Two things it found**, both fixed in the same sitting and both guarded
## below:
##
##   * `NAN` passed the magnitude guard, because every comparison against NAN
##     is false. It reached `int(NAN)`, the most negative integer there is, and
##     was refused only by the range check that happened to follow - reporting
##     a number nobody had sent.
##   * A stalk carrying two hundred thousand bad events took a second and a
##     half to refuse, building an error string for each one. Ten of them would
##     have frozen a joining client for fifteen seconds. The same was true of a
##     dictionary stuffed with junk keys.
##
## See docs/decisions.md D124 and `docs/custom-stalks.md` §5.
##
## **What is deliberately NOT defended against.** A host sending a shipped
## company with invented numbers is a host rewriting its own simulation, which
## it can already do - it owns every price, dividend and ranking in the match.
## `test_a_host_may_serve_its_own_version_of_a_shipped_company` asserts that on
## purpose, so nobody later mistakes it for a hole.


## A character GDScript will not accept in a source literal.
##
## The parser refuses an invisible direction-control character outright and
## warns on a NUL, which is a small mercy in itself. Building them at runtime
## is how a test asks "what if this arrived from the network" — the only way
## they ever could.
func _character(code: int) -> String:
	return String.chr(code)


## A well-formed definition, as the honest host would send it, for each attack
## to bend in one direction.
func _honest() -> Dictionary:
	var schema: StalkSchema = StalkSchema.from_file_data({
		"name": "Victim Co",
		"bull_change": [0, 10],
		"bear_change": [0, 10],
		"bull_dividend": 2,
		"bear_dividend": 1,
	}, "victim")
	assert_true(schema.is_valid(), "the honest baseline must be valid")
	return StalkSchema.encode(schema.definition)


func _with(changes: Dictionary) -> Dictionary:
	var entry: Dictionary = _honest()
	for key: Variant in changes:
		entry[key] = changes[key]
	return entry


## Fires one definition at the client's decode path and returns the refusal, or
## an empty string if it was accepted.
func _refusal_for(entry: Dictionary) -> String:
	var out: Dictionary = StateSync.decode_content([entry])
	if out["library"] == null:
		return String(out["error"])
	return ""


func _assert_refused(entry: Dictionary, what: String) -> String:
	var reason: String = _refusal_for(entry)
	assert_ne(reason, "", "a hostile %s should be refused" % what)
	return reason


# -------------------------------------------------------------------- numbers

func test_nan_is_refused_as_not_a_number() -> void:
	# The finding. NAN defeats every comparison, so it has to be named.
	var reason: String = _assert_refused(_with({"bull_dividend": NAN}), "NAN dividend")
	assert_true(reason.contains("not a number"), reason)
	assert_false(
		reason.contains("9223372036854775808"),
		"the refusal should not quote a number nobody sent: %s" % reason,
	)


func test_nan_inside_a_range_is_refused() -> void:
	var reason: String = _assert_refused(_with({"bull_change": [NAN, NAN]}), "NAN range")
	assert_true(reason.contains("not a number"), reason)


func test_infinity_is_refused() -> void:
	assert_ne(_refusal_for(_with({"starting_price": INF})), "")
	assert_ne(_refusal_for(_with({"bear_dividend": -INF})), "")


func test_an_integer_too_large_to_represent_is_refused() -> void:
	assert_ne(_refusal_for(_with({"bull_dividend": 1.0e300})), "")


# ------------------------------------------------------------------- the work
#
# A refusal that takes fifteen seconds is still a denial of service. These
# assert the bound on effort, not just the outcome.

## Generous on purpose: the structural fix makes these return in about a
## millisecond, so a second of headroom cannot flake on a loaded machine while
## still catching a return to walking the whole list.
const GENEROUS_MILLISECONDS: int = 1000


func test_a_stalk_with_absurdly_many_events_is_refused_without_walking_them() -> void:
	var events: Array = []
	for index: int in 50000:
		events.append({"mood": "bull", "text": "x", "price_change": 5})

	var started: int = Time.get_ticks_msec()
	var reason: String = _assert_refused(_with({"events": events}), "event flood")
	var took: int = Time.get_ticks_msec() - started

	assert_lt(took, GENEROUS_MILLISECONDS, "refusing took %dms" % took)
	assert_true(reason.contains("50000"), "it should say how many arrived: %s" % reason)


func test_a_stalk_stuffed_with_junk_fields_is_refused_by_its_shape() -> void:
	var entry: Dictionary = _honest()
	for index: int in 50000:
		entry["junk%d" % index] = 1

	var started: int = Time.get_ticks_msec()
	var reason: String = _assert_refused(entry, "field flood")
	var took: int = Time.get_ticks_msec() - started

	assert_lt(took, GENEROUS_MILLISECONDS, "refusing took %dms" % took)
	# Ties this to the shape check rather than to the error cap: with only the
	# cap, the first twenty junk keys would still be named one by one.
	assert_true(reason.contains("50013"), "it should say how many arrived: %s" % reason)
	assert_false(reason.contains("junk4999"), "it should not name them one by one")


func test_the_list_of_problems_cannot_be_made_to_grow_without_bound() -> void:
	# The invariant behind both tests above, asserted directly: whatever
	# arrives, one stalk produces a bounded number of complaints.
	# **Deliberately within the count bail**, which would otherwise refuse the
	# list by its length and never reach the per-event checks. Twenty events,
	# each wrong in two ways, is forty complaints from a list the game is
	# willing to walk. Written the other way first, with five hundred events,
	# and it passed with the cap removed because it never got that far.
	var entry: Dictionary = _honest()
	var events: Array = []
	for index: int in StalkSchema.MAX_EVENTS_PER_MOOD * 2:
		events.append({"mood": "bull", "text": "", "price_change": 0})
	entry["events"] = events

	var schema: StalkSchema = StalkSchema.from_wire(entry)
	assert_false(schema.is_valid())
	assert_lte(
		schema.errors.size(),
		StalkSchema.MAX_ERRORS_PER_STALK + 1,
		"errors grew to %d" % schema.errors.size(),
	)


func test_a_five_megabyte_string_is_refused_by_its_length() -> void:
	var started: int = Time.get_ticks_msec()
	assert_ne(_refusal_for(_with({"description": "A".repeat(5 * 1024 * 1024)})), "")
	assert_lt(Time.get_ticks_msec() - started, GENEROUS_MILLISECONDS)


func test_a_deeply_nested_value_is_refused_without_descending_into_it() -> void:
	# A thousand-deep structure where a string belongs. Nothing recurses into a
	# field it has already established is the wrong type.
	var deep: Dictionary = {}
	var cursor: Dictionary = deep
	for index: int in 1000:
		var child: Dictionary = {}
		cursor["name"] = child
		cursor = child

	assert_ne(_refusal_for(_with({"name": deep})), "")


# -------------------------------------------------------------------- the text

func test_a_control_character_cannot_reach_a_fixed_width_row() -> void:
	assert_ne(_refusal_for(_with({"name": "Evil%sName" % _character(0)})), "", "NUL")
	assert_ne(_refusal_for(_with({"name": "Col%summn" % _character(27)})), "", "escape")
	assert_ne(_refusal_for(_with({"name": "Two\nLines"})), "", "newline")


func test_a_direction_override_cannot_reach_a_label() -> void:
	# U+202E reverses everything after it, which can make a name read as
	# something else entirely. Outside printable ASCII, so already refused -
	# this says so by name, because it is the reason the rule is a whitelist
	# rather than a list of forbidden characters.
	assert_ne(_refusal_for(_with({"name": "Good%sEvil" % _character(0x202E)})), "")


func test_markup_pointing_at_a_resource_is_refused() -> void:
	# `[img]res://...[/img]` in event text would be markup in the event strip
	# if it were ever rendered unescaped. It is escaped there - and refused
	# here as well, because content may not name a path.
	var entry: Dictionary = _with({"events": [
		{"mood": "bull", "text": "[img]res://icon.svg[/img]", "price_change": 5},
	]})
	assert_ne(_refusal_for(entry), "")


func test_markup_that_is_merely_markup_is_allowed_and_escaped_later() -> void:
	# A bracket on its own is ordinary punctuation and must not be refused;
	# `ScrollingLabel` is what makes it safe to draw. The escaping itself is
	# asserted in test_custom_stalks.gd.
	var entry: Dictionary = _with({"events": [
		{"mood": "bull", "text": "[color=red]a good year[/color]", "price_change": 5},
	]})
	assert_eq(_refusal_for(entry), "", "a bracket is punctuation, not an attack")


# ------------------------------------------------------------------- the types

func test_an_object_cannot_arrive_as_a_field() -> void:
	# Object decoding is off, so one cannot really cross the wire (D41). This
	# asserts the validator does not depend on that being true.
	assert_ne(_refusal_for(_with({"name": RefCounted.new()})), "")


func test_an_object_cannot_arrive_as_an_event() -> void:
	assert_ne(_refusal_for(_with({"events": [Resource.new()]})), "")


func test_a_field_name_that_is_not_text_is_refused() -> void:
	var entry: Dictionary = _honest()
	entry[42] = "x"
	assert_ne(_refusal_for(entry), "")


# ---------------------------------------------------------------- the identity

func test_two_stalks_cannot_share_an_event_id() -> void:
	# Events are looked up by id to resolve a year's news. Two with one id
	# would make which text appears a matter of ordering.
	var first: Dictionary = _with({"events": [
		{"id": "shared", "mood": "bull", "text": "a", "price_change": 5},
	]})
	var second: Dictionary = _with({"id": "custom:other", "events": [
		{"id": "shared", "mood": "bull", "text": "b", "price_change": 5},
	]})
	var out: Dictionary = StateSync.decode_content([first, second])
	assert_null(out["library"])
	assert_true(String(out["error"]).contains("shared"), String(out["error"]))


func test_a_host_may_serve_its_own_version_of_a_shipped_company() -> void:
	# **Deliberately accepted.** A host that sends BERRY BONDS with different
	# numbers is rewriting its own simulation, which it can do anyway - it owns
	# every price and payout in the match. Pinned so that nobody later reads
	# this as a hole and "fixes" it by having clients prefer their own files,
	# which would reintroduce exactly the content mismatch D121 removed.
	var entry: Dictionary = _with({"id": "berry_bonds", "name": "Not Really Berry Bonds"})
	assert_eq(_refusal_for(entry), "", "the host decides its own match's content")


func test_a_refusal_is_safe_to_put_on_a_screen() -> void:
	# The reason is drawn to the player, so untrusted text inside it must not
	# carry control characters or newlines into a fixed-width UI.
	var entry: Dictionary = _with({"id": "evil%s
id" % _character(7)})
	var reason: String = _assert_refused(entry, "id")
	assert_false(reason.contains("\n"), reason)
	assert_false(reason.contains(_character(7)), "a bell character was echoed back")


# ------------------------------------------------------------- the whole thing

func test_a_client_told_nonsense_leaves_with_a_reason_rather_than_a_board() -> void:
	# The end-to-end property all of the above exists to protect: whatever the
	# host sends, the client either plays a match it can vouch for or leaves
	# saying why. It never renders a board built from values it rejected.
	var session: ClientSession = ClientSession.new()
	session.name = NetworkedSession.NODE_NAME
	session._state = GameState.new(null)
	session._library = ContentLibrary.load_from()
	add_child_autofree(session)

	var reasons: Array[String] = []
	session.connection_lost.connect(func(reason: String) -> void: reasons.append(reason))

	session._on_welcomed(
		&"p1", {"stalks": [], "players": []}, [], [_with({"bull_dividend": NAN})]
	)

	assert_eq(reasons.size(), 1, "the player should be told exactly once")
	assert_false(reasons[0].is_empty())
	assert_false(session.has_joined(), "and must not be seated in the match")
	assert_eq(session.state().stalks.size(), 0, "nothing should have been built")
