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
## The design's sketch also shows whispers and a market headline. Those are the
## news categories of phase S8 and are not built yet; until then this tab shows
## the year's event, which is what news there is.


const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")

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

const BULL_MARK: String = "B"
const BEAR_MARK: String = "b"
const UNPLAYED_MARK: String = "."

enum Line { INDEX, PE, MOOD, BREADTH, RISK_FREE }


var _lines: Dictionary[Line, CellRow] = {}

@onready var _stats: VBoxContainer = %Stats
@onready var _chart: DrawnChart = %IndexChart
@onready var _event_text: Label = %EventText
@onready var _event_effect: Label = %EventEffect
@onready var _mood_chart: Label = %MoodChart
@onready var _review: YearDigestPanel = %Review


func _ready() -> void:
	_chart.custom_minimum_size = CHART_SIZE
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


## `event_text` and `event_effect` are the two lines the top strip already
## shows, so the strip and this tab can never say different things.
func refresh(state: GameState, event_text: String, event_effect: String) -> void:
	_refresh_stats(state)
	_refresh_chart(state)
	_event_text.text = event_text
	_event_effect.text = event_effect
	_mood_chart.text = mood_chart_text(state)
	_refresh_review(state)


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


func review() -> YearDigestPanel:
	return _review


func index_chart() -> DrawnChart:
	return _chart


func stat_line(line: Line) -> String:
	return _lines[line].line_text()
