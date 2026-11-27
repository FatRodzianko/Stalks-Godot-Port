class_name MarketTab
extends MarginContainer
## Tab 2 of a StalkleHeads match: Market Analysis (docs/stalkleheads-design.md
## §7.3). The market as a whole - the index, its P/E, the mood and how often it
## has been bull, breadth, the risk-free rate - with the index charted by year
## and the moods by year beside it.
##
## **Two halves** (decisions.md D189): the market's figures and its chart on
## the left; on the right, scrolling on its own, the year's news, the mood by
## year, and the year in review the news panel showed when the year turned.
## The tab itself does not scroll, so the left half stays put. The right
## half's three sections are divided by bright rules (`SectionRule`), brighter
## than the faint lines inside the year in review, which divide its parts
## (manual-testing.md L, decisions.md D190).
##
## **Nothing here changes while anybody trades** (§6.2): every figure is last
## year's published data, so a player can read this while the others trade and
## lose nothing.
##
## **The news (phase S8, design §8).** At the top of the right half, the
## **whispers** heard at the end of the year just played (or at the match's
## start) about the year to come, each with its source (§8.4, decisions.md
## D205); and above the year's event, the **market headline**. Both are chosen
## by `NewsSelector`; when it chose none, the slot and its heading are not
## shown at all (§8.2: an empty slot shows nothing).
##
## **VIEW HISTORY** opens every round of whispers so far, newest first, over
## the right half, each with what really came of it once its year has been
## played. It closes with CLOSE, and whenever the tab is left, so the tab
## always opens on the current whispers.


const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")
const WhisperRowScene: PackedScene = preload("res://src/ui/widgets/whisper_row.tscn")

## The index chart's size in cells (design §7.6): the plot, plus the scale
## labels left of it and the year captions under it. A line since D188.
const CHART_WIDTH: int = 38
const CHART_HEIGHT: int = 7
const CHART_SIZE: Vector2 = Vector2(
	(CHART_WIDTH + ChartGeometry.LABEL_CHARS + 1) * ChartGeometry.CELL_WIDTH,
	(CHART_HEIGHT + 2) * ChartGeometry.LINE_HEIGHT,
)

## How many years the mood row shows.
const MOOD_YEARS: int = 10

## Characters per year on the mood row.
const MOOD_CELL: int = 3

## The width a whisper wraps at, as the event text does.
const WRAP_WIDTH: float = 240.0

## The least width a whisper's words wrap at, beside its source column.
const WHISPER_TEXT_WIDTH: float = 170.0

const BULL_MARK: String = "B"
const BEAR_MARK: String = "b"
const UNPLAYED_MARK: String = "."

enum Line { INDEX, PE, MOOD, BREADTH, RISK_FREE }


## What THIS YEAR'S NEWS says in a year with neither market news nor a squeeze,
## as the top strip says it.
const NO_EVENT: String = "No special event this year."


var _lines: Dictionary[Line, CellRow] = {}

@onready var _stats: VBoxContainer = %Stats
@onready var _chart: DrawnChart = %IndexChart
@onready var _headline: Label = %Headline
@onready var _whisper_section: VBoxContainer = %WhisperSection
@onready var _whispers_title: Label = %WhispersTitle
@onready var _whispers: VBoxContainer = %Whispers
@onready var _history_button: Button = %HistoryButton
@onready var _history_frame: PanelContainer = %HistoryFrame
@onready var _history_list: VBoxContainer = %HistoryList
@onready var _close_history_button: Button = %CloseHistoryButton
@onready var _event_text: Label = %EventText
@onready var _event_effect: Label = %EventEffect
@onready var _squeeze_text: Label = %SqueezeText
@onready var _squeeze_effect: Label = %SqueezeEffect
@onready var _mood_chart: Label = %MoodChart
@onready var _review: YearDigestPanel = %Review


func _ready() -> void:
	_chart.custom_minimum_size = CHART_SIZE
	_whispers_title.tooltip_text = TermTips.fit(TermTips.WHISPERS)
	_history_button.tooltip_text = TermTips.fit(TermTips.WHISPER_HISTORY)
	_history_button.pressed.connect(show_history)
	_close_history_button.pressed.connect(hide_history)
	visibility_changed.connect(_on_visibility_changed)
	_review.set_narrow()
	var captions: Dictionary[Line, String] = {
		Line.INDEX: "Index level",
		Line.PE: "Market P/E",
		Line.MOOD: "Mood",
		Line.BREADTH: "Breadth",
		Line.RISK_FREE: "Risk-free",
	}
	var tips: Dictionary[Line, String] = {
		Line.INDEX: TermTips.INDEX_LEVEL,
		Line.PE: TermTips.MARKET_PE,
		Line.MOOD: TermTips.MOOD,
		Line.BREADTH: TermTips.BREADTH,
		Line.RISK_FREE: TermTips.RISK_FREE,
	}
	for line: Line in captions:
		var row: CellRow = CellRowScene.instantiate()
		_stats.add_child(row)
		row.configure([12, 7, 6, 0], [CellRow.LEFT, CellRow.RIGHT, CellRow.RIGHT, CellRow.LEFT])
		row.set_cell(0, captions[line])
		row.set_cell_tooltip(0, tips[line])
		row.set_cell_variation(0, &"Faint")
		row.set_cell_variation(3, &"Faint")
		_lines[line] = row
	# No reserved height: the right half scrolls, so the event takes the lines
	# it needs and nothing below waits under a gap (decisions.md D189).


func refresh(state: GameState) -> void:
	_refresh_stats(state)
	_refresh_chart(state)
	_refresh_events(state)
	_mood_chart.text = mood_chart_text(state)
	_refresh_news(state)
	_refresh_review(state)


## THIS YEAR'S NEWS: the market news - headline, event text, what it did - and
## then the short squeeze, if one fired or ended, as its own item (D209, D213).
## The same words as the top strip, from the same helper.
func _refresh_events(state: GameState) -> void:
	var words: YearEventText = YearEventText.of(state, state.latest_result() as EarningsYearResult)
	_show_line(_headline, words.headline)
	_show_line(_event_text, words.body)
	_show_line(_event_effect, words.effect)
	if not words.effect.is_empty():
		_event_effect.add_theme_color_override("font_color", Palette.for_change(words.effect_change))
	_show_line(_squeeze_text, words.squeeze_text)
	_show_line(_squeeze_effect, "\n".join(words.squeeze_effects))
	if not words.squeeze_effects.is_empty():
		_squeeze_effect.add_theme_color_override("font_color", Palette.for_change(words.squeeze_change))
	if words.is_empty() and state.year > 0:
		_show_line(_event_effect, NO_EVENT)
		_event_effect.remove_theme_color_override("font_color")


static func _show_line(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()


## The whispers, or nothing where none was heard.
func _refresh_news(state: GameState) -> void:
	_clear(_whispers)
	var current: WhisperRound = NewsSelector.latest_whispers(state)
	if current != null:
		for line: WhisperRound.Line in current.lines:
			_add_whisper(_whispers, line)
	_refresh_history(state)
	# The section shows while there is anything to read, now or before, and
	# the button with it: the history holds the current round too.
	var heard_any: bool = _history_list.get_child_count() > 0
	_whisper_section.visible = _whispers.get_child_count() > 0 or heard_any
	_history_button.visible = heard_any


## Every round heard so far, newest first, with its outcomes once known.
## Rounds in which nothing was heard are left out.
func _refresh_history(state: GameState) -> void:
	_clear(_history_list)
	var rounds: Array[WhisperRound] = NewsSelector.whisper_history(state)
	rounds.reverse()
	for round: WhisperRound in rounds:
		if round.lines.is_empty():
			continue
		var heading: Label = Label.new()
		heading.theme_type_variation = &"SubHeading"
		heading.text = "ABOUT YEAR %d" % round.about_year()
		_history_list.add_child(heading)
		for line: WhisperRound.Line in round.lines:
			var row: WhisperRow = _add_whisper(_history_list, line)
			if not round.is_settled(state):
				row.show_outcome_unknown()
			elif line.is_about_squeeze():
				row.show_squeeze_outcome(NewsSelector.squeeze_whisper_came_true(state, round, line))
			else:
				row.show_outcome(line.truth)


func _add_whisper(parent: VBoxContainer, line: WhisperRound.Line) -> WhisperRow:
	var row: WhisperRow = WhisperRowScene.instantiate()
	parent.add_child(row)
	row.show_whisper(line, WHISPER_TEXT_WIDTH)
	return row


func _clear(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


## Opens the whisper history over the right half.
func show_history() -> void:
	_history_frame.visible = true


func hide_history() -> void:
	_history_frame.visible = false


func is_history_open() -> bool:
	return _history_frame.visible


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		hide_history()


func _refresh_stats(state: GameState) -> void:
	var index: StalkState = state.stalk_by_id(EarningsMarket.INDEX_ID)
	var latest: EarningsYearResult = state.latest_result() as EarningsYearResult
	if index != null:
		var move: String = ""
		if latest != null:
			move = Palette.format_percent_change(latest.index_move_percent)
		_lines[Line.INDEX].set_texts(["Index level", str(index.price), Palette.format_change(index.last_yearly_change), "  " + move])
		_lines[Line.INDEX].set_cell_colour(2, Palette.for_change(index.last_yearly_change))

	_lines[Line.PE].set_cell(1, Palette.format_decimal(MarketReadouts.market_pe(state), 1))

	var bulls: Vector2i = MarketReadouts.bull_years(state, MOOD_YEARS)
	if latest != null:
		_lines[Line.MOOD].set_cell(1, MarketMood.label(latest.mood))
		_lines[Line.MOOD].set_cell_colour(1, Palette.for_mood(latest.mood))
		_lines[Line.MOOD].set_cell(3, "  %d of last %d bull" % [bulls.x, bulls.y])
	else:
		_lines[Line.MOOD].set_texts(["Mood", "", "", ""])

	var breadth: Vector2i = MarketReadouts.breadth(state)
	if breadth.y > 0:
		_lines[Line.BREADTH].set_cell(1, "%d/%d" % [breadth.x, breadth.y])
		_lines[Line.BREADTH].set_cell(3, "  Rose this year")
	else:
		_lines[Line.BREADTH].set_texts(["Breadth", "", "", ""])

	var bond: StalkState = state.stalk_by_id(EarningsMarket.BOND_ID)
	_lines[Line.RISK_FREE].set_cell(1, Palette.format_percent_decimal(MarketReadouts.risk_free_percent(state)))
	if bond != null:
		_lines[Line.RISK_FREE].set_cell(3, "  " + bond.definition.display_name)


## The index level each year as a line: a level is read for its path, not
## compared bar against bar (decisions.md D188).
func _refresh_chart(state: GameState) -> void:
	var levels: Array[float] = MarketReadouts.index_levels(state)
	var values: PackedFloat32Array = []
	var captions: PackedStringArray = []
	var tips: PackedStringArray = []
	for year: int in levels.size():
		values.append(levels[year])
		captions.append(str(year))
		tips.append("Year %d\nIndex %d" % [year, roundi(levels[year])])
	var series: Array[PackedFloat32Array] = [values]
	_chart.show_lines(series, PackedStringArray(["Index"]), captions, tips)


## Two lines: the latest ten year numbers, and under each the mood it was -
## `B` bull, `b` bear, `.` not played yet. A string, so a test asserts it.
static func mood_chart_text(state: GameState) -> String:
	var first: int = maxi(1, state.year - MOOD_YEARS + 1)
	var numbers: String = ""
	var marks: String = ""
	for year: int in range(first, first + MOOD_YEARS):
		if year > state.settings.max_years:
			break
		numbers += str(year).rpad(MOOD_CELL)
		var mark: String = UNPLAYED_MARK
		var result: YearResult = MarketReadouts.result_for_year(state, year)
		if result != null:
			mark = BULL_MARK if result.mood == MarketMood.Value.BULL else BEAR_MARK
		marks += mark.rpad(MOOD_CELL)
	return "%s\n%s" % [numbers.rstrip(" "), marks.rstrip(" ")]


## The year in review, as the news panel shows it when the year turns, kept
## here under the mood so it can be read again (decisions.md D189). Hidden in
## year 0, which has no year to review.
func _refresh_review(state: GameState) -> void:
	var digest: YearDigest = YearDigest.for_latest_year(state)
	_review.visible = digest != null
	if digest != null:
		_review.show_digest(digest, state)


func headline_text() -> String:
	return _headline.text if _headline.visible else ""


## THIS YEAR'S NEWS as shown, one entry per visible line, top to bottom.
func event_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for label: Label in [_headline, _event_text, _event_effect, _squeeze_text, _squeeze_effect]:
		if label.visible and not label.text.is_empty():
			out.append(label.text)
	return out


## The current whispers as shown, `source | words` per line; empty when the
## section is hidden.
func whisper_texts() -> PackedStringArray:
	return _row_texts(_whispers if _whisper_section.visible else null)


## The whisper history as listed: each round's heading, then each whisper as
## `source | words | outcome`.
func history_texts() -> PackedStringArray:
	return _row_texts(_history_list)


func _row_texts(container: VBoxContainer) -> PackedStringArray:
	var texts: PackedStringArray = []
	if container == null:
		return texts
	for child: Node in container.get_children():
		if child is WhisperRow:
			var row: WhisperRow = child
			var parts: PackedStringArray = [row.source_text(), row.whisper_text()]
			if not row.outcome_text().is_empty():
				parts.append(row.outcome_text())
			texts.append(" | ".join(parts))
		elif child is Label:
			texts.append((child as Label).text)
	return texts


func review() -> YearDigestPanel:
	return _review


func index_chart() -> DrawnChart:
	return _chart


func stat_line(line: Line) -> String:
	return _lines[line].line_text()
