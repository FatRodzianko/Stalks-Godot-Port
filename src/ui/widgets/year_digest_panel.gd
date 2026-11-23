class_name YearDigestPanel
extends VBoxContainer
## The year in review: a StalkleHeads year's fundamentals in one panel, shown
## inside the year's news when the year turns (docs/stalkleheads-design.md
## §6.3).
##
## Shows a `YearDigest`, which `sim` builds; this only lays it out. The mood
## line reads in the order it was decided - the market's move first, the label
## after - because in this mode the label is a consequence, not a cause (§6.3).
##
## **A fixed shape.** The four outlier lines are always there; a year with no
## dividend cut has that line blank rather than missing (no filler text either:
## design §8.2 rule 3), so the panel is the same height every year
## (decisions.md D125).
##
## **Two layouts.** Wide, in the news panel when the year turns. **Narrow**
## (`set_narrow`), half the Market tab, where it is shown as well so the year
## can be read again without reopening the news (decisions.md D189): the market
## line becomes two, the industries two columns, and each outlier two lines,
## its caption above the company and the figure.
##
## The design's sketch also has an event headline and a whisper. Those are the
## news categories of phase S8 and are not built yet; the year's event itself
## is already in the news panel around this one.


const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")

## Captions for the outlier lines: the design's words (§6.3), which explain
## what each line is rather than give it a voice.
const SURPRISE: String = "Biggest earnings surprise"
const DISAPPOINTMENT: String = "Biggest disappointment"
const DIVIDEND_CUT: String = "Dividend cut"
const DESK_PICK: String = "The desk piled into"

const CAPTION_CHARS: int = 27
const COMPANY_CHARS: int = 26
const INDUSTRY_NAME_CHARS: int = 19
const INDUSTRY_MOVE_CHARS: int = 6

## Space after each industry's move, so the next name does not touch it.
const INDUSTRY_GAP_CHARS: int = 2

## The narrow layout's widths: an industry name and gap that put two columns in
## half the Market tab, and the indent under an outlier's caption.
const HALF_INDUSTRY_NAME_CHARS: int = 18
const HALF_INDUSTRY_GAP_CHARS: int = 1
const HALF_INDENT_CHARS: int = 2


@onready var _title: CellRow = %TitleRow
@onready var _market: CellRow = %MarketRow
@onready var _industries: GridContainer = %Industries
@onready var _outliers: VBoxContainer = %Outliers

var _industry_rows: Dictionary[StringName, CellRow] = {}
var _outlier_rows: Array[CellRow] = []

## The narrow layout's extra lines: the market's second line, and each
## outlier's line under its caption. Empty in the wide layout.
var _narrow: bool = false
var _market_second: CellRow
var _outlier_details: Array[CellRow] = []


func _ready() -> void:
	_title.configure([0, 8], [CellRow.LEFT, CellRow.RIGHT])
	_title.set_cell_variation(0, &"SubHeading")
	_market.configure([12, 6, 14, 17, 0])
	_market.set_cell_tooltip(3, TermTips.MARKET_PE)
	_market.set_cell_tooltip(4, TermTips.SENTIMENT)
	for caption: String in [SURPRISE, DISAPPOINTMENT, DIVIDEND_CUT, DESK_PICK]:
		var row: CellRow = CellRowScene.instantiate()
		_outliers.add_child(row)
		row.configure([CAPTION_CHARS, COMPANY_CHARS, 0])
		row.set_cell_variation(0, &"Faint")
		_outlier_rows.append(row)


## Switches to the narrow layout, for half the Market tab. Call once, before
## the first `show_digest`.
func set_narrow() -> void:
	if _narrow:
		return
	_narrow = true
	# Ordinary spacing rather than tight: half the tab is narrow, so the panel
	# is long, and tight lines run together (manual-testing.md L).
	theme_type_variation = &""
	_outliers.theme_type_variation = &""
	_market.configure([12, 6, 0])
	_market_second = CellRowScene.instantiate()
	add_child(_market_second)
	move_child(_market_second, _market.get_index() + 1)
	_market_second.configure([17, 0])
	_market_second.set_cell_tooltip(0, TermTips.MARKET_PE)
	_market_second.set_cell_tooltip(1, TermTips.SENTIMENT)
	_industries.columns = 2
	for index: int in _outlier_rows.size():
		var caption: CellRow = _outlier_rows[index]
		caption.configure([0])
		caption.set_cell_variation(0, &"Faint")
		var detail: CellRow = CellRowScene.instantiate()
		_outliers.add_child(detail)
		_outliers.move_child(detail, caption.get_index() + 1)
		detail.configure([HALF_INDENT_CHARS, COMPANY_CHARS, 0])
		_outlier_details.append(detail)


## Lays out `digest`. `state` is what names the companies and industries.
func show_digest(digest: YearDigest, state: GameState) -> void:
	_title.set_texts(["THE YEAR IN REVIEW", "Year %d" % digest.year])

	var move: String = Palette.format_percent_change(digest.index_move_percent)
	var mood: String = "-> %s" % MarketMood.label(digest.mood)
	var pe: String = "Market P/E %s" % Palette.format_decimal(digest.market_pe, 1)
	var sentiment: String = "Year %d sentiment %s" % [digest.year + 1, Palette.format_percent_change(digest.next_sentiment)]
	_market.set_cell_colour(1, Palette.for_percent(digest.index_move_percent))
	_market.set_cell_colour(2, Palette.for_mood(digest.mood))
	if _narrow:
		_market.set_texts(["The Market:", move, mood])
		_market_second.set_texts([pe, sentiment])
		_market_second.set_cell_colour(1, Palette.for_percent(digest.next_sentiment))
	else:
		_market.set_texts(["The Market:", move, mood, pe, sentiment])
		_market.set_cell_colour(4, Palette.for_percent(digest.next_sentiment))

	_show_industries(digest)

	_show_outlier(0, digest.surprise_id, state,
		"Profit %s" % Palette.format_percent_change(digest.surprise_profit_percent))
	_show_outlier(1, digest.disappointment_id, state, "Margin %s -> %s" % [
		Palette.format_percent(digest.disappointment_margin_before),
		Palette.format_percent(digest.disappointment_margin_after),
	])
	var cut: String = "%d -> %d" % [digest.dividend_before, digest.dividend_after]
	if digest.dividend_cut_in_distress:
		cut += ", now in distress"
	_show_outlier(2, digest.dividend_cut_id, state, cut)
	_show_outlier(3, digest.desk_pick_id, state, _desk_detail(digest))


func _show_industries(digest: YearDigest) -> void:
	for entry: Array in digest.industries:
		var industry_id: StringName = entry[0]
		var row: CellRow = _industry_rows.get(industry_id)
		if row == null:
			row = CellRowScene.instantiate()
			_industries.add_child(row)
			var name_chars: int = INDUSTRY_NAME_CHARS
			var gap_chars: int = INDUSTRY_GAP_CHARS
			if _narrow:
				name_chars = HALF_INDUSTRY_NAME_CHARS
				gap_chars = HALF_INDUSTRY_GAP_CHARS
			row.configure([name_chars, INDUSTRY_MOVE_CHARS, gap_chars], [CellRow.LEFT, CellRow.RIGHT])
			_industry_rows[industry_id] = row
		var move: float = entry[2]
		row.set_texts([entry[1], Palette.format_percent_change(move)])
		row.set_cell_colour(1, Palette.for_percent(move))


func _show_outlier(index: int, stalk_id: StringName, state: GameState, detail: String) -> void:
	var row: CellRow = _outlier_rows[index]
	var captions: Array[String] = [SURPRISE, DISAPPOINTMENT, DIVIDEND_CUT, DESK_PICK]
	var name: String = String(stalk_id)
	var stalk: StalkState = state.stalk_by_id(stalk_id)
	if stalk != null:
		name = stalk.definition.display_name
	if _narrow:
		# The caption stays even in a year with nothing to show, so the panel
		# keeps one shape; only the line under it is blank.
		row.set_texts([captions[index]])
		if stalk_id.is_empty():
			_outlier_details[index].set_texts(["", "", ""])
		else:
			_outlier_details[index].set_texts(["", name, detail])
		return
	if stalk_id.is_empty():
		row.set_texts(["", "", ""])
		return
	row.set_texts([captions[index], name, detail])


func _desk_detail(digest: YearDigest) -> String:
	var names: PackedStringArray = []
	for strategy: NpcStrategy.Value in digest.desk_pick_strategies:
		names.append(NpcStrategy.name_of(strategy).to_lower())
	if names.is_empty():
		return "%d shares net" % digest.desk_pick_shares
	return Palette.sentence_case("%s buying" % Palette.list_names(names))


## Every line, for tests.
func lines_text() -> PackedStringArray:
	var lines: PackedStringArray = [_title.line_text(), _market.line_text()]
	if _narrow:
		lines.append(_market_second.line_text())
	for row: Node in _industries.get_children():
		lines.append((row as CellRow).line_text())
	for row: Node in _outliers.get_children():
		lines.append((row as CellRow).line_text())
	return lines
