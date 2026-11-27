class_name WhisperRow
extends VBoxContainer
## One whisper as shown: its source, faint, then its words; and, in the
## whisper history once the year it was about has been played, what really
## came of it (docs/stalkleheads-design.md §8.4, decisions.md D205).
##
## A widget: it shows what it is given and knows nothing about the screen
## holding it. Used by the Market tab, its whisper history and the Company tab.


## What a whisper's outcome reads as on screen, once known.
const OUTCOME_WORDS: Dictionary[NewsBands.Surprise, String] = {
	NewsBands.Surprise.MUCH_WORSE: "much worse than expected",
	NewsBands.Surprise.WORSE: "worse than expected",
	NewsBands.Surprise.AS_EXPECTED: "as expected",
	NewsBands.Surprise.BETTER: "better than expected",
	NewsBands.Surprise.MUCH_BETTER: "much better than expected",
}

## The widest source name, plus a space, sets the source column's width, so
## every whisper's words start in the same place.
const WIDEST_SOURCE: String = "Questionable "


@onready var _source: Label = %Source
@onready var _text: Label = %Text
@onready var _outcome: Label = %Outcome


func _ready() -> void:
	var font: Font = _source.get_theme_font(&"font")
	var size: int = _source.get_theme_font_size(&"font_size")
	_source.custom_minimum_size.x = font.get_string_size(WIDEST_SOURCE, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_outcome.visible = false


## `text_width` is the least width the words wrap at, in pixels.
func show_whisper(line: WhisperRound.Line, text_width: float) -> void:
	_source.text = WhisperRules.SOURCE_NAMES.get(line.source, "")
	_text.text = line.text
	_text.custom_minimum_size.x = text_width


## Shows what really came of it, under the words.
func show_outcome(truth: NewsBands.Surprise) -> void:
	_outcome.text = "Outcome: %s" % OUTCOME_WORDS.get(truth, "")
	_outcome.visible = true


## What came of a squeeze or crash whisper: whether it happened (D214).
func show_squeeze_outcome(happened: bool) -> void:
	_outcome.text = "Outcome: it happened" if happened else "Outcome: it did not happen"
	_outcome.visible = true


## Says the outcome is not known yet: the year it is about is still to come.
func show_outcome_unknown() -> void:
	_outcome.text = "Outcome: not known yet"
	_outcome.visible = true


func source_text() -> String:
	return _source.text


func whisper_text() -> String:
	return _text.text


## Empty while hidden.
func outcome_text() -> String:
	return _outcome.text if _outcome.visible else ""
