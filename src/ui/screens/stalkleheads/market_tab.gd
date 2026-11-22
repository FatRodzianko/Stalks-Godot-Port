class_name MarketTab
extends ScrollContainer
## Tab 2 of a StalkleHeads match: Market Analysis (docs/stalkleheads-design.md
## §7.3). The market as a whole - the index, its P/E, the mood and how often it
## has been bull, breadth, the risk-free rate - with the index charted by year
## and the moods by year beside it.
##
## **Nothing here changes while anybody trades** (§6.2): every figure is last
## year's published data, so a player can read this while the others trade and
## lose nothing.
##
## The design's sketch also shows whispers and a market headline. Those are the
## news categories of phase S8 and are not built yet; until then this tab shows
## the year's event, which is what news there is.


const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")

## The index chart's size in cells (design §7.6).
const CHART_WIDTH: int = 38
const CHART_HEIGHT: int = 7

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
@onready var _chart: ChartWidget = %IndexChart
@onready var _event_text: Label = %EventText
@onready var _event_effect: Label = %EventEffect
@onready var _mood_chart: Label = %MoodChart


func _ready() -> void:
	var captions: Dictionary[Line, String] = {
		Line.INDEX: "index level",
		Line.PE: "market P/E",
		Line.MOOD: "mood",
		Line.BREADTH: "breadth",
		Line.RISK_FREE: "risk-free",
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
		row.configure([14, 8, 6, 0], [CellRow.LEFT, CellRow.RIGHT, CellRow.RIGHT, CellRow.LEFT])
		row.set_cell(0, captions[line])
		row.set_cell_tooltip(0, tips[line])
		row.set_cell_variation(0, &"Faint")
		row.set_cell_variation(3, &"Faint")
		_lines[line] = row
	ReservedLines.reserve(_event_text)


## `event_text` and `event_effect` are the two lines the top strip already
## shows, so the strip and this tab can never say different things.
func refresh(state: GameState, event_text: String, event_effect: String) -> void:
	_refresh_stats(state)
	_refresh_chart(state)
	_event_text.text = event_text
	_event_effect.text = event_effect
	_mood_chart.text = mood_chart_text(state)


func _refresh_stats(state: GameState) -> void:
	var index: StalkState = state.stalk_by_id(EarningsMarket.INDEX_ID)
	var latest: EarningsYearResult = state.latest_result() as EarningsYearResult
	if index != null:
		var move: String = ""
		if latest != null:
			move = Palette.format_percent_change(latest.index_move_percent)
		_lines[Line.INDEX].set_texts(["index level", str(index.price), Palette.format_change(index.last_yearly_change), "  " + move])
		_lines[Line.INDEX].set_cell_colour(2, Palette.for_change(index.last_yearly_change))

	_lines[Line.PE].set_cell(1, Palette.format_decimal(MarketReadouts.market_pe(state), 1))

	var bulls: Vector2i = MarketReadouts.bull_years(state, MOOD_YEARS)
	if latest != null:
		_lines[Line.MOOD].set_cell(1, MarketMood.label(latest.mood))
		_lines[Line.MOOD].set_cell_colour(1, Palette.for_mood(latest.mood))
		_lines[Line.MOOD].set_cell(3, "  %d of last %d bull" % [bulls.x, bulls.y])
	else:
		_lines[Line.MOOD].set_texts(["mood", "", "", ""])

	var breadth: Vector2i = MarketReadouts.breadth(state)
	if breadth.y > 0:
		_lines[Line.BREADTH].set_cell(1, "%d/%d" % [breadth.x, breadth.y])
		_lines[Line.BREADTH].set_cell(3, "  rose this year")
	else:
		_lines[Line.BREADTH].set_texts(["breadth", "", "", ""])

	var bond: StalkState = state.stalk_by_id(EarningsMarket.BOND_ID)
	_lines[Line.RISK_FREE].set_cell(1, Palette.format_percent_decimal(MarketReadouts.risk_free_percent(state)))
	if bond != null:
		_lines[Line.RISK_FREE].set_cell(3, "  " + bond.definition.display_name)


func _refresh_chart(state: GameState) -> void:
	var levels: Array[float] = MarketReadouts.index_levels(state)
	var captions: PackedStringArray = []
	for year: int in levels.size():
		captions.append(str(year))
	_chart.show_bars("INDEX, BY YEAR", levels, captions, CHART_WIDTH, CHART_HEIGHT)


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


func index_chart() -> ChartWidget:
	return _chart


func stat_line(line: Line) -> String:
	return _lines[line].line_text()
