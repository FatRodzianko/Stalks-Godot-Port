class_name HistoryRow
extends PanelContainer
## One year of a finished match: which year, the mood, what the local player
## was worth at the end of it, and what happened.
##
## Dumb like every other row widget. It is handed four finished values and
## displays them; working out what a year amounted to is the screen's job,
## because that needs the stalk names and this does not know what a stalk is.
##
## The summary is the one thing here that can be longer than its column, so it
## is trimmed with an ellipsis and repeated in full on hover.


@onready var _year_label: Label = %Year
@onready var _mood_label: Label = %Mood
@onready var _net_worth_label: Label = %NetWorth
@onready var _summary_label: Label = %Summary

var _is_header: bool = false


## Turns this row into the column headings above the list, so the columns
## cannot drift apart from the rows beneath them. The same trick the board
## uses — see docs/decisions.md D36.
func configure_as_header() -> void:
	_is_header = true
	theme_type_variation = &"HeaderCard"
	_year_label.text = "YEAR"
	_mood_label.text = "MOOD"
	_net_worth_label.text = "NET WORTH"
	_summary_label.text = "WHAT HAPPENED"
	for label: Label in [_year_label, _mood_label, _net_worth_label]:
		label.theme_type_variation = &"Faint"


func display(year: int, mood: MarketMood.Value, net_worth: int, summary: String) -> void:
	if _is_header:
		return

	_year_label.text = "Y%d" % year
	_mood_label.text = MarketMood.label(mood)
	_mood_label.add_theme_color_override("font_color", Palette.for_mood(mood))
	_net_worth_label.text = Palette.format_money(net_worth)
	_summary_label.text = summary
	_summary_label.tooltip_text = summary
