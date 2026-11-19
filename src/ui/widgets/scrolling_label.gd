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
## **It still creeps a line at a time on hover**, for a description too long for
## two lines - the reason it was written (D100). Three of the game's ninety
## descriptions run past three lines and twenty past two, and `overflows()` is
## false for the rest, which never start their timer.
##
## See docs/decisions.md D100, D102 and D107a.


## The player clicked the marker and wants the whole thing.
signal more_requested


## What the marker says, and what it costs in characters. The two must agree,
## so the visible text is measured rather than the markup.
const MARKER: String = "... MORE"

## The word that is clickable, picked out from the ellipsis before it.
const MARKER_WORD: String = "MORE"

## Seconds between line steps. Much slower than the name marquee's 0.2, because
## a line of prose takes longer to read than a few more characters of a name.
const STEP_SECONDS: float = 1.6

## Steps to wait at the top and bottom, so the first and last lines can be read
## rather than glimpsed.
const HOLD_STEPS: int = 2


## How many lines of the description the strip shows at once.
@export var max_lines_visible: int = 2


var _full: String = ""
var _lines: PackedStringArray = []
var _skipped: int = 0
var _hold: int = 0
var _timer: Timer


func _ready() -> void:
	bbcode_enabled = true
	scroll_active = false
	fit_content = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	mouse_filter = Control.MOUSE_FILTER_STOP

	_timer = Timer.new()
	_timer.wait_time = STEP_SECONDS
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
	_hold = 0
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


## **No hold on the way in.** The pause exists so the first lines are not
## whisked away before they can be read - but a player who has just put the
## mouse on the text has been reading it, and three steps of nothing (nearly
## five seconds) looks exactly like hovering doing nothing at all. Reported
## that way. The hold is kept for the wrap-around, where it earns its keep.
func start_scrolling() -> void:
	if not overflows():
		return
	_hold = 0
	if _timer != null:
		_timer.start()


func stop_scrolling() -> void:
	if _timer != null:
		_timer.stop()
	_skipped = 0
	_hold = 0
	_render()


## Moves on one line. Public so a test does not have to wait out the timer.
func step() -> void:
	_step()


# ------------------------------------------------------------------ the wrapping

## Re-measures and redraws. Called when the text changes and whenever the strip
## changes width, because a line's capacity is measured from that width.
func _rewrap() -> void:
	_lines = _wrapped(_full)
	_skipped = mini(_skipped, furthest_line())
	_render()


## Greedy word wrap at a whole number of characters.
##
## Safe only because the font is fixed-width: a line's capacity is a count
## rather than a sum of glyph widths. A word longer than a whole line is broken
## rather than left to overflow, which no description does but a custom one
## might.
func _wrapped(value: String) -> PackedStringArray:
	var room: int = characters_per_line()
	if room <= 0 or value.strip_edges().is_empty():
		return PackedStringArray([value]) if not value.is_empty() else PackedStringArray()

	var lines: PackedStringArray = []
	var line: String = ""
	for word: String in value.split(" ", false):
		while word.length() > room:
			if not line.is_empty():
				lines.append(line)
				line = ""
			lines.append(word.substr(0, room))
			word = word.substr(room)
		var candidate: String = word if line.is_empty() else "%s %s" % [line, word]
		if candidate.length() <= room:
			line = candidate
			continue
		lines.append(line)
		line = word
	if not line.is_empty():
		lines.append(line)
	return lines


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

## Puts the visible window on screen, with the marker on the end of its last
## line when there is more to read.
func _render() -> void:
	var window: PackedStringArray = []
	for offset: int in max_lines_visible:
		var index: int = _skipped + offset
		if index >= _lines.size():
			break
		window.append(_escaped(_lines[index]))

	if window.is_empty():
		text = ""
		return

	if overflows():
		var last: int = window.size() - 1
		window[last] = _with_marker(_lines[_skipped + last])

	text = "\n".join(window)


## One line, shortened by exactly the marker's width so the two together still
## fit, with the marker on the end.
##
## A line already shorter than that is left alone, so the marker follows the
## words rather than being pushed out to the margin.
func _with_marker(line: String) -> String:
	var room: int = maxi(characters_per_line() - MARKER.length(), 0)
	var kept: String = line if line.length() <= room else line.substr(0, room)
	return _escaped(kept) + marker_markup()


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
	if _hold > 0:
		_hold -= 1
		return

	var furthest: int = furthest_line()
	if furthest == 0:
		stop_scrolling()
		return

	_skipped += 1
	if _skipped > furthest:
		# Back to the top, and pause there before setting off again.
		_skipped = 0
		_hold = HOLD_STEPS
	_render()


func _on_mouse_entered() -> void:
	start_scrolling()


func _on_mouse_exited() -> void:
	stop_scrolling()


func _on_meta_clicked(meta: Variant) -> void:
	if String(meta) == "more":
		more_requested.emit()
