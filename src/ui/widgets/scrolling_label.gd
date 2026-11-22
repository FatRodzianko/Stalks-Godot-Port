class_name ScrollingLabel
extends RichTextLabel
## The year's special event, in the two lines the top strip gives it, ending in
## a "... MORE" the player can click when there is more of it.
##
## **The marker is part of the text, not a button beside it.** That was asked
## for three times and built wrong twice - as a column in a container, which
## narrowed every line, and as an overlay, which sat on top of them. Both failed
## for the same reason: a `Label` wraps every line to one width, so there is no
## way to say "leave room on the last line only". A marker *inside* the text has
## no alignment to get wrong, because it is on the same line, in the same font,
## on the same baseline as the words before it.
##
## **The wrapping is done here rather than by the engine**, which is what makes
## that possible. Terminus is fixed-width, so a line's capacity is a number of
## characters, and once this class decides where the lines break it can shorten
## the last one by exactly the width of the marker and put the marker there.
## `autowrap_mode` is off: these line breaks are the layout, so engine wrapping
## and this wrapping cannot disagree.
##
## **On hover it moves up a line at a time** until the last line is at the
## bottom, for a description too long for the strip (D100). Reported from play
## on 2026-11-22 as unreadable: it went too fast, "... MORE" jumped about
## because it followed the words, the words under it were never shown, and the
## last lines flashed by before it jumped back. Now (D175):
##
## - each line shows for `LINE_SECONDS`; the last lines hold for
##   `END_SECONDS` before it goes back to the top;
## - when the text overflows, every line that can ever sit on the bottom row
##   is wrapped short by the marker's width, so the marker never covers a word;
## - the marker is padded out to the same column every time, so it never moves.
##
## Moving a page at a time was tried and turned down: a three-line description
## showed its third line alone with a blank row under it.
##
## See docs/decisions.md D100, D102, D107a and D175.


## The player clicked the marker and wants the whole thing.
signal more_requested


## What the marker says, and what it costs in characters. The two must agree,
## so the visible text is measured rather than the markup.
const MARKER: String = "... MORE"

## The word that is clickable, picked out from the ellipsis before it.
const MARKER_WORD: String = "MORE"

## Seconds between line steps while hovered. Each step brings one new line of
## about sixty characters, roughly ten words.
const LINE_SECONDS: float = 3.0

## Seconds the last lines hold before it goes back to the top, so the end can
## be read rather than glimpsed.
const END_SECONDS: float = 5.0

## Seconds before the first step after the mouse arrives. Shorter, because the
## first lines have already been on screen to read, and a long wait after
## hovering looks like hovering does nothing (D100).
const FIRST_TURN_SECONDS: float = 1.6


## How many lines of the description the strip shows at once.
@export var max_lines_visible: int = 2


var _full: String = ""
var _lines: PackedStringArray = []
var _skipped: int = 0
var _timer: Timer


func _ready() -> void:
	bbcode_enabled = true
	scroll_active = false
	fit_content = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	mouse_filter = Control.MOUSE_FILTER_STOP

	_timer = Timer.new()
	_timer.wait_time = LINE_SECONDS
	_timer.timeout.connect(_step)
	add_child(_timer)

	meta_clicked.connect(_on_meta_clicked)
	resized.connect(_rewrap)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## Sets the text and returns to the top.
##
## Always use this rather than assigning `text`, which holds markup and only
## the lines currently on show.
func set_full_text(value: String) -> void:
	_full = value
	_skipped = 0
	_rewrap()


## The whole description, markup-free, whoever is asking.
func full_text() -> String:
	return _full


## Whether there is more of it than the strip can show.
func overflows() -> bool:
	return max_lines_visible > 0 and _lines.size() > max_lines_visible


## The furthest down it will go: the last line, sitting at the bottom.
func furthest_line() -> int:
	return maxi(0, _lines.size() - max_lines_visible)


## How many lines the description takes at this width. For tests.
func line_count() -> int:
	return _lines.size()


## Which line is at the top at the moment. For tests.
func lines_skipped() -> int:
	return _skipped


func is_scrolling() -> bool:
	return _timer != null and not _timer.is_stopped()


## The first step comes after `FIRST_TURN_SECONDS`; see `_step` for the rest.
func start_scrolling() -> void:
	if not overflows():
		return
	if _timer != null:
		_timer.start(FIRST_TURN_SECONDS)


func stop_scrolling() -> void:
	if _timer != null:
		_timer.stop()
	_skipped = 0
	_render()


## Moves on one line. Public so a test does not have to wait out the timer.
func step() -> void:
	_step()


# ------------------------------------------------------------------ the wrapping

## Re-measures and redraws. Called when the text changes and whenever the strip
## changes width, because a line's capacity is measured from that width.
func _rewrap() -> void:
	_lines = _wrapped(_full, false)
	if overflows():
		# Too long for the strip, so the marker will show: wrap again with
		# every line that can reach the bottom row left short by its width.
		_lines = _wrapped(_full, true)
	_skipped = mini(_skipped, furthest_line())
	_render()


## Greedy word wrap at a whole number of characters.
##
## Safe only because the font is fixed-width: a line's capacity is a count
## rather than a sum of glyph widths. A word longer than a whole line is broken
## rather than left to overflow, which no description does but a custom one
## might.
##
## With `leave_marker_room`, every line that can ever sit on the bottom row
## (all but the first `max_lines_visible - 1`) is `MARKER` shorter, so the
## marker always has its own space.
func _wrapped(value: String, leave_marker_room: bool) -> PackedStringArray:
	if characters_per_line() <= 0 or value.strip_edges().is_empty():
		return PackedStringArray([value]) if not value.is_empty() else PackedStringArray()

	var lines: PackedStringArray = []
	var line: String = ""
	for word: String in value.split(" ", false):
		var room: int = _room_on_line(lines.size(), leave_marker_room)
		while word.length() > room:
			if not line.is_empty():
				lines.append(line)
				line = ""
				room = _room_on_line(lines.size(), leave_marker_room)
			lines.append(word.substr(0, room))
			word = word.substr(room)
			room = _room_on_line(lines.size(), leave_marker_room)
		var candidate: String = word if line.is_empty() else "%s %s" % [line, word]
		if candidate.length() <= room:
			line = candidate
			continue
		lines.append(line)
		line = word
	if not line.is_empty():
		lines.append(line)
	return lines


## Characters allowed on line `index`: the whole width, or the width less the
## marker for a line that can reach the bottom row.
func _room_on_line(index: int, leave_marker_room: bool) -> int:
	var room: int = characters_per_line()
	if leave_marker_room and index >= max_lines_visible - 1:
		room -= MARKER.length()
	return maxi(room, 1)


## How many characters fit on one line at the current width.
func characters_per_line() -> int:
	var cell: float = _cell_width()
	if cell <= 0.0:
		return 0
	return floori(size.x / cell)


func _cell_width() -> float:
	var font: Font = get_theme_font("normal_font")
	if font == null:
		return 0.0
	return font.get_string_size(
		"M", HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("normal_font_size")
	).x


# ------------------------------------------------------------------ the drawing

## Puts the visible lines on screen. When the text overflows, the marker sits
## at the end of the bottom row, in the same column every time.
func _render() -> void:
	if _lines.is_empty():
		text = ""
		return

	if not overflows():
		var plain: PackedStringArray = []
		for line: String in _lines:
			plain.append(_escaped(line))
		text = "\n".join(plain)
		return

	var window: PackedStringArray = []
	for offset: int in max_lines_visible:
		var index: int = _skipped + offset
		var line: String = ""
		if index < _lines.size():
			line = _lines[index]
		if offset == max_lines_visible - 1:
			window.append(_with_marker(line))
		else:
			window.append(_escaped(line))
	text = "\n".join(window)


## A bottom line, padded to the marker's column, with the marker on the end.
## The wrapping already left this line short enough, so nothing is cut.
func _with_marker(line: String) -> String:
	var column: int = maxi(characters_per_line() - MARKER.length(), 0)
	var padding: String = " ".repeat(maxi(column - line.length(), 0))
	return _escaped(line) + padding + marker_markup()


## The marker as it is drawn: the whole of it, ellipsis included, in the
## ordinary text colour rather than the description's, so it reads as a thing
## to click rather than as the sentence trailing off.
##
## **The colour comes from the theme**, not from a literal here - it is the one
## every other label uses (CLAUDE.md: colours live in the theme).
func marker_markup() -> String:
	var colour: Color = get_theme_color("font_color", "Label")
	return "[url=more][color=#%s][u]%s[/u][/color][/url]" % [
		colour.to_html(false), MARKER
	]


## BBCode is on, so a `[` in a description would be read as markup. Nothing in
## the shipped content has one; a custom event might.
func _escaped(line: String) -> String:
	return line.replace("[", "[lb]")


# -------------------------------------------------------------------- the input

func _step() -> void:
	var furthest: int = furthest_line()
	if furthest == 0:
		stop_scrolling()
		return

	_skipped += 1
	if _skipped > furthest:
		_skipped = 0
	if _timer != null and not _timer.is_stopped():
		# The last lines hold longer, so the end can be read.
		if _skipped == furthest:
			_timer.start(END_SECONDS)
		else:
			_timer.start(LINE_SECONDS)
	_render()


func _on_mouse_entered() -> void:
	start_scrolling()


func _on_mouse_exited() -> void:
	stop_scrolling()


func _on_meta_clicked(meta: Variant) -> void:
	if String(meta) == "more":
		more_requested.emit()
