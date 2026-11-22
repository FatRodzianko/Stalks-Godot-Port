class_name IndustriesTab
extends ScrollContainer
## Tab 3 of a StalkleHeads match: Industries (docs/stalkleheads-design.md §7.4).
## Every industry's year, its three years, its standing, its average P/E and its
## share of the market's revenue; then, for the one selected, its moves by year
## and each member's share of the industry.
##
## **Market share is derived, not simulated** (§7.4): a company's revenue over
## its industry's. `MarketReadouts.market_share_percent` computes it.
##
## Click an industry's line to select it. The selection is presentation only,
## like the Exchange tab's collapse and sort. Each member has a trade box, and
## clicking its name opens it on the Company tab (decisions.md D183).


## A line was clicked. The host holds the state, so it redraws.
signal selection_changed(industry_id: StringName)

signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)

## A member's name was clicked.
signal company_requested(stalk_id: StringName)


const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")
const TradeLineScene: PackedScene = preload("res://src/ui/widgets/trade_line.tscn")

## What each heading means, by column (`TermTips`).
const HEADING_TIPS: Array[String] = [
	"", TermTips.INDUSTRY_MOVE, TermTips.THREE_YEARS, TermTips.STANDING,
	TermTips.INDUSTRY_PE, TermTips.INDUSTRY_SHARE, "", TermTips.COMPANIES,
]

## The table's columns, in characters, and how each lines up.
const WIDTHS: Array[int] = [19, 8, 7, 9, 8, 6, 11, 9]
const ALIGNS: Array[int] = [
	CellRow.LEFT, CellRow.RIGHT, CellRow.RIGHT, CellRow.RIGHT,
	CellRow.RIGHT, CellRow.RIGHT, CellRow.LEFT, CellRow.RIGHT,
]
const HEADINGS: PackedStringArray = [
	"INDUSTRY", "THIS YR", "3-YR", "STANDING", "AVG P/E", "SHARE", "", "COMPANIES",
]

## How many cells the revenue-share bar may take, at 100%.
const SHARE_BAR_CELLS: int = 10

## The by-year chart's size in cells (design §7.6): 22 wide, 5 tall - two rows
## above the axis, the axis, two below.
const CHART_WIDTH: int = 22
const CHART_HALF_HEIGHT: int = 2

const MEMBER_WIDTHS: Array[int] = [22, 6, 6]


var _selected: StringName = &""
var _rows: Dictionary[StringName, CellRow] = {}
var _member_lines: Dictionary[StringName, TradeLine] = {}
var _context: TradeContext

@onready var _header: CellRow = %Header
@onready var _list: VBoxContainer = %IndustryList
@onready var _chart: ChartWidget = %IndustryChart
@onready var _members_title: Label = %MembersTitle
@onready var _members_header: CellRow = %MembersHeader
@onready var _members: VBoxContainer = %Members


func _ready() -> void:
	_header.configure(WIDTHS, ALIGNS)
	_header.set_texts(HEADINGS)
	_header.set_row_variation(&"Faint")
	_header.set_framed(&"HeaderCard")
	for index: int in HEADING_TIPS.size():
		if not HEADING_TIPS[index].is_empty():
			_header.set_cell_tooltip(index, HEADING_TIPS[index])
	_members_header.configure(MEMBER_WIDTHS, [CellRow.LEFT, CellRow.RIGHT, CellRow.RIGHT])
	_members_header.set_texts(["COMPANY", "SHARE", "CHG"])
	_members_header.set_row_variation(&"Faint")
	_members_header.set_cell_tooltip(1, TermTips.MARKET_SHARE)
	_members_header.set_cell_tooltip(2, TermTips.MARKET_SHARE_CHANGE)


func refresh(context: TradeContext) -> void:
	_context = context
	var state: GameState = context.state
	if _selected.is_empty() and not state.market.industries.is_empty():
		_selected = state.market.industries[0].id
	for industry: IndustryState in state.market.industries:
		_refresh_industry(state, industry)
	_refresh_selected(state)


## Makes `industry_id` the one charted and broken down.
func select(industry_id: StringName, context: TradeContext) -> void:
	_selected = industry_id
	refresh(context)


func clear_amounts() -> void:
	for line: TradeLine in _member_lines.values():
		line.trade_box().clear_amount()


func _refresh_industry(state: GameState, industry: IndustryState) -> void:
	var row: CellRow = _rows.get(industry.id)
	if row == null:
		row = CellRowScene.instantiate()
		_list.add_child(row)
		row.configure(WIDTHS, ALIGNS)
		row.key = industry.id
		row.set_clickable(true)
		row.pressed.connect(_on_industry_pressed)
		_rows[industry.id] = row

	var this_year: float = MarketReadouts.NONE
	var three_years: float = MarketReadouts.NONE
	if state.year > 0:
		this_year = MarketReadouts.industry_performance_in(state, industry.id, state.year)
		three_years = MarketReadouts.industry_compound_percent(state, industry.id, 3)
	var share: float = MarketReadouts.industry_revenue_share_percent(state, industry.id)
	row.set_texts([
		industry.definition.display_name,
		Palette.format_percent_change(this_year),
		Palette.format_percent_change(three_years),
		Palette.format_signed_decimal(industry.standing(), 2),
		Palette.format_decimal(MarketReadouts.industry_average_pe(state, industry.id), 1),
		Palette.format_percent(share),
		" " + TextChart.share_bar(share, SHARE_BAR_CELLS),
		str(MarketReadouts.living_members(state, industry.id).size()),
	])
	row.set_cell_colour(1, Palette.for_percent(this_year))
	row.set_cell_colour(2, Palette.for_percent(three_years))
	row.set_cell_variation(6, &"Chart")
	row.set_framed(&"Card" if industry.id == _selected else &"BareRow")


func _refresh_selected(state: GameState) -> void:
	var industry: IndustryState = state.market.industry_by_id(_selected)
	if industry == null:
		return
	var name: String = industry.definition.display_name
	var values: Array[float] = []
	var captions: PackedStringArray = []
	for year: int in range(1, state.year + 1):
		values.append(MarketReadouts.industry_performance_in(state, _selected, year))
		captions.append(str(year))
	_chart.show_signed_bars("BY YEAR: %s" % name.to_upper(), values, captions, CHART_WIDTH, CHART_HALF_HEIGHT)

	_members_title.text = "WITHIN THE INDUSTRY: %s" % name.to_upper()
	for child: Node in _members.get_children():
		_members.remove_child(child)
		child.queue_free()
	_member_lines.clear()
	for company: CompanyState in MarketReadouts.industry_members(state, _selected):
		var line: TradeLine = TradeLineScene.instantiate()
		_members.add_child(line)
		line.configure(MEMBER_WIDTHS, [CellRow.LEFT, CellRow.RIGHT, CellRow.RIGHT])
		line.stalk_id = company.id
		line.buy_requested.connect(_on_member_buy_requested)
		line.sell_requested.connect(_on_member_sell_requested)
		line.amount_changed.connect(_on_member_amount_changed)
		line.info_requested.connect(_on_member_info_requested)
		_member_lines[company.id] = line
		var share: float = MarketReadouts.market_share_percent(state, company)
		var change: float = MarketReadouts.market_share_change(state, company)
		var stalk: StalkState = state.stalk_by_id(company.id)
		line.cells().set_texts([
			stalk.definition.display_name,
			Palette.format_percent(share),
			Palette.format_percent_change(change),
		])
		line.cells().set_cell_colour(2, Palette.for_percent(change))
		_context.prepare(line.trade_box(), company.id)


func selected() -> StringName:
	return _selected


func line_for(industry_id: StringName) -> String:
	var row: CellRow = _rows.get(industry_id)
	return row.line_text() if row != null else ""


func member_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in _members.get_children():
		lines.append((child as TradeLine).line_text())
	return lines


func member_line(stalk_id: StringName) -> TradeLine:
	return _member_lines.get(stalk_id)


func industry_chart() -> ChartWidget:
	return _chart


func _on_industry_pressed(industry_id: StringName) -> void:
	_selected = industry_id
	selection_changed.emit(industry_id)


func _on_member_buy_requested(stalk_id: StringName, shares: int) -> void:
	buy_requested.emit(stalk_id, shares)


func _on_member_sell_requested(stalk_id: StringName, shares: int) -> void:
	sell_requested.emit(stalk_id, shares)


func _on_member_amount_changed(stalk_id: StringName, _shares: int) -> void:
	var line: TradeLine = _member_lines.get(stalk_id)
	if line != null and _context != null:
		_context.check(line.trade_box(), stalk_id)


func _on_member_info_requested(stalk_id: StringName) -> void:
	company_requested.emit(stalk_id)
