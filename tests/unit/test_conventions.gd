extends GutTest
## Readability rules, enforced by a machine instead of by memory.
##
## **Why this file exists.** This project has two kinds of rule. Static typing
## is enforced in `project.godot` (`untyped_declaration=2` makes untyped code a
## hard parse error) and has never once drifted. The naming and readability
## rules in `CLAUDE.md` were enforced by nothing, and drifted badly — eighteen
## signal connections were written in a style the same document forbids, over
## weeks, without anybody noticing.
##
## Same project, same author, opposite outcomes. The difference was purely
## whether a machine checked. So the rules that matter now get checked.
##
## These scan the source as text. That is crude, and it is the point: a crude
## check that runs every time beats a precise rule nobody runs.
##
## **If one of these fails**, the fix is almost always to give the thing a name.
## Do not add an exception without reading `CLAUDE.md` and deciding the rule
## itself is wrong.


## Where the game's own code lives. `addons/` is third-party and `tools/` is
## developer scripts; neither is ours to style.
const SOURCE_DIR: String = "res://src"

## The documentation, which is a release gate in this project and so is held to
## the placeholder rule as well. See `test_no_document_has_a_leftover_placeholder`.
const DOCS_DIR: String = "res://docs"


func _gd_files(dir_path: String) -> PackedStringArray:
	return _files_under(dir_path, ".gd")


func _files_under(dir_path: String, suffix: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		var full: String = "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			found.append_array(_files_under(full, suffix))
		elif name.ends_with(suffix):
			found.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return found


func _lines_of(path: String) -> PackedStringArray:
	return FileAccess.get_file_as_string(path).split("\n")


## Every offending `file:line  text`, so a failure says exactly where to look
## rather than just that something is wrong somewhere.
func _offenders(matcher: Callable) -> PackedStringArray:
	return _offenders_in(_gd_files(SOURCE_DIR), matcher)


func _offenders_in(paths: PackedStringArray, matcher: Callable) -> PackedStringArray:
	var found: PackedStringArray = []
	for path: String in paths:
		var lines: PackedStringArray = _lines_of(path)
		for index: int in lines.size():
			var line: String = lines[index]
			if matcher.call(line):
				found.append("%s:%d  %s" % [path, index + 1, line.strip_edges()])
	return found


# --------------------------------------------------------------- the rules

func test_no_inline_function_is_connected_to_a_signal() -> void:
	# `connect(func() -> void: thing.emit(x))` is the style that prompted this
	# file. It reads as nonsense to anyone who has not met a lambda, it buries
	# behaviour inside wiring, and it cannot be found by searching for a name.
	# Give it a name: `connect(_on_kick_button_pressed)`.
	var offenders: PackedStringArray = _offenders(
		func(line: String) -> bool: return line.contains(".connect(func")
	)
	assert_eq(offenders, PackedStringArray(), "inline functions connected to signals")


func test_no_signal_is_connected_straight_to_another_signals_emit() -> void:
	# `connect(play_requested.emit)` works, but passing one signal's `emit` as
	# a callable is a Godot idiom rather than something readable. A named
	# method that emits is one more line and says what it is for.
	var offenders: PackedStringArray = _offenders(
		func(line: String) -> bool:
			var at: int = line.find(".connect(")
			if at == -1:
				return false
			return line.substr(at + 9).contains(".emit)")
	)
	assert_eq(offenders, PackedStringArray(), "signals connected to another signal's emit")


func test_every_connection_target_has_a_name() -> void:
	# The general form of both rules above: whatever is connected must be
	# something a reader can go and look up.
	var offenders: PackedStringArray = _offenders(
		func(line: String) -> bool:
			var at: int = line.find(".connect(")
			if at == -1:
				return false
			var target: String = line.substr(at + 9).strip_edges()
			# A connection split across lines puts the target on the next one;
			# that is caught by the inline-function rule instead.
			if target.is_empty():
				return false
			return target.begins_with("func")
	)
	assert_eq(offenders, PackedStringArray(), "connections to something unnamed")


func test_no_conditional_expression_is_split_across_lines() -> void:
	# GDScript allows `value_if_true if condition else value_if_false`, and on
	# one short line it reads fine. Split across three lines it puts the
	# condition in the middle, after the answer, which is backwards for anyone
	# reading top to bottom. An if/else block says the same thing in the order
	# a person thinks it.
	#
	# Matches a line that is only a condition: `if x > 3` with no colon, which
	# can only be the middle of a split conditional expression.
	var offenders: PackedStringArray = _offenders(
		func(line: String) -> bool:
			var trimmed: String = line.strip_edges()
			if not trimmed.begins_with("if "):
				return false
			return not trimmed.ends_with(":")
	)
	assert_eq(offenders, PackedStringArray(), "conditional expressions split over lines")


func test_no_source_file_has_a_leftover_placeholder() -> void:
	# A substitution that did not happen. Thirteen literal "DASH" markers once
	# shipped in doc comments this way.
	var offenders: PackedStringArray = _offenders(
		func(line: String) -> bool:
			return line.contains("DASH") or line.contains("{WARN}") or line.contains("ARROW")
	)
	assert_eq(offenders, PackedStringArray(), "unsubstituted placeholders")


func test_no_source_file_has_a_debugging_trace_left_in() -> void:
	# `print()` in shipped code is either a leftover trace or output that
	# belongs on screen. Tools and tests print freely; `src/` should not.
	var offenders: PackedStringArray = _offenders(
		func(line: String) -> bool:
			var trimmed: String = line.strip_edges()
			if trimmed.begins_with("#"):
				return false
			return trimmed.begins_with("print(") or trimmed.contains("[TRACE]")
	)
	assert_eq(offenders, PackedStringArray(), "stray print statements")


## The same placeholder rule, applied to `docs/`.
##
## Documentation is a release gate here, not an afterthought: a successor with
## no access to anyone who worked on this has to be able to read it. A literal
## "DASH" in the middle of a sentence is a straightforward failure of that.
##
## **This check was added because it immediately found five.** The source was
## scanned for placeholders from the day that rule existed; `docs/` was not, and
## five had been sitting in `exporting.md`, `porting-plan.md` and
## `steam-integration.md` since the scripts that wrote them substituted a
## marker and never put the character back.
func test_no_document_has_a_leftover_placeholder() -> void:
	var offenders: PackedStringArray = _offenders_in(
		_files_under(DOCS_DIR, ".md"),
		func(line: String) -> bool:
			# "DASH" as a word, so prose that legitimately contains the letters
			# inside a longer word is left alone.
			if line.contains(" DASH ") or line.contains("{WARN}"):
				return true
			return line.begins_with("DASH ") or line.ends_with(" DASH")
	)
	assert_eq(offenders, PackedStringArray(), "unsubstituted placeholders in docs")


func test_the_scan_actually_reaches_the_source() -> void:
	# Guards every test above: a broken path would make them all pass by
	# scanning nothing at all, which is the classic way a lint quietly dies.
	var files: PackedStringArray = _gd_files(SOURCE_DIR)
	assert_gt(files.size(), 30, "expected to find the project's source files")
	assert_true(
		"%s/net/host_session.gd" % SOURCE_DIR in files,
		"a known file should be among those scanned",
	)

	var documents: PackedStringArray = _files_under(DOCS_DIR, ".md")
	assert_gt(documents.size(), 5, "expected to find the project's documentation")
	assert_true(
		"%s/decisions.md" % DOCS_DIR in documents,
		"a known document should be among those scanned",
	)
