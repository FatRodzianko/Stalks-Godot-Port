class_name CompanyTab
extends VBoxContainer
## Tab 4 of a StalkleHeads match: one company in depth
## (docs/stalkleheads-design.md §7.5). Opened by clicking its row on the
## Exchange, the gesture the base game's details panel already uses
## (decisions.md D103). `<` and `>` step through the companies in the match's
## own order, which does not follow the board's sort; **COMPANIES** opens a list
## of them all over the tab, to jump straight to one (decisions.md D184).
##
## What it shows:
##
## - the name, industry and **earnings regime, named** - "SLOWING, 2nd year"
##   (§14 q8) - and the description;
## - **five years of earnings**: revenue, expenses, profit, margin, earnings per
##   share, price and P/E, with a mark under a year it split;
## - **why the price moved** - the ledger widget, every point attributed;
## - its earnings yield against the risk-free rate;
## - **who holds it**: the players, by name only (D103), and the NPC traders who
##   traded it last year, **each by name** (§14 q11), with short interest.
##
## Beside the name line: how many shares you hold (HELD, as the board says
## it), and a trade box.
##
## **The title line is pinned**: COMPANIES, `<`, the name and `>` stay at the
## top while everything under them scrolls, so a long NPC table never hides
## which company it is about (decisions.md D185).
##
## The bond and the index are on the board but are not companies: for them this
## shows the name, description and investors only.


## `<` or `>` was pressed. The host holds the state, so it redraws.
signal company_changed(stalk_id: StringName)

## COMPANIES was pressed: show or hide the list of companies.
signal picker_requested

signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)


const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")

## The earnings table: a caption column, then one column per year.
const YEARS_SHOWN: int = 5
const CAPTION_CHARS: int = 16
const YEAR_CHARS: int = 7

const SPLIT_MARK: String = "^split"

enum Line { REVENUE, EXPENSES, PROFIT, MARGIN, EPS, PRICE, PE }

const LINE_CAPTIONS: Dictionary[Line, String] = {
	Line.REVENUE: "Revenue",
	Line.EXPENSES: "Expenses",
	Line.PROFIT: "Profit",
	Line.MARGIN: "Margin",
	Line.EPS: "Earnings/share",
	Line.PRICE: "Price",
	Line.PE: "P/E",
}

## NPC ACTIVITY's columns, in characters: the trader's name, what it did last
## year, and what it holds now. Fixed widths rather than a name column that
## takes the rest of the line, so the three sit together and read across
## (manual-testing.md G3). 30 holds the longest placeholder name; a longer one
## is clipped and shown whole in its tooltip.
const TRADER_CHARS: int = 30
const ACTION_CHARS: int = 10
const POSITION_CHARS: int = 10

## The line under the name: ticker, industry, then the regime phrase.
const IDENTITY_WIDTHS: Array[int] = [6, 20, 0]

## What each line of the earnings table means (`TermTips`).
const LINE_TIPS: Dictionary[Line, String] = {
	Line.REVENUE: TermTips.REVENUE,
	Line.EXPENSES: TermTips.EXPENSES,
	Line.PROFIT: TermTips.PROFIT,
	Line.MARGIN: TermTips.MARGIN,
	Line.EPS: TermTips.EPS,
	Line.PRICE: TermTips.PRICE,
	Line.PE: TermTips.PE,
}


## The board row on show. Presentation only.
var _stalk_id: StringName = &""
var _company_ids: Array[StringName] = []

var _year_row: CellRow
var _lines: Dictionary[Line, CellRow] = {}
var _split_row: CellRow
var _context: TradeContext

@onready var _pick: Button = %PickButton
@onready var _previous: Button = %PreviousButton
@onready var _next: Button = %NextButton
@onready var _name: Label = %CompanyName
@onready var _identity: CellRow = %Identity
@onready var _held_label: Label = %HeldLabel
@onready var _trade: TradeBox = %Trade
@onready var _description: Label = %Description
@onready var _earnings: VBoxContainer = %Earnings
@onready var _ledger: LedgerWidget = %Ledger
@onready var _yield: Label = %YieldLine
@onready var _investors: Label = %Investors
@onready var _activity: VBoxContainer = %Activity
@onready var _short_line: Label = %ShortLine


func _ready() -> void:
	_pick.pressed.connect(_on_pick_pressed)
	_previous.pressed.connect(_on_previous_pressed)
	_next.pressed.connect(_on_next_pressed)
	_identity.configure(IDENTITY_WIDTHS)
	_identity.set_cell_variation(0, &"Faint")
	_identity.set_cell_variation(1, &"Faint")
	_identity.set_cell_tooltip(2, TermTips.REGIME)
	_yield.mouse_filter = Control.MOUSE_FILTER_PASS
	_yield.tooltip_text = TermTips.fit(TermTips.EARNINGS_YIELD)
	_trade.buy_requested.connect(_on_trade_buy_requested)
	_trade.sell_requested.connect(_on_trade_sell_requested)
	_trade.amount_changed.connect(_on_trade_amount_changed)
	ReservedLines.reserve(_description)

	var widths: Array[int] = [CAPTION_CHARS]
	var aligns: Array[int] = [CellRow.LEFT]
	for _year: int in YEARS_SHOWN:
		widths.append(YEAR_CHARS)
		aligns.append(CellRow.RIGHT)
	_year_row = _add_earnings_row(widths, aligns)
	_year_row.set_cell(0, "EARNINGS")
	_year_row.set_row_variation(&"Faint")
	_year_row.set_cell_variation(0, &"SubHeading")
	for line: Line in LINE_CAPTIONS:
		var row: CellRow = _add_earnings_row(widths, aligns)
		row.set_cell(0, " " + LINE_CAPTIONS[line])
		row.set_cell_variation(0, &"Faint")
		row.set_cell_tooltip(0, LINE_TIPS[line])
		_lines[line] = row
	_split_row = _add_earnings_row(widths, aligns)
	_split_row.set_row_variation(&"Faint")


## The company to show, drawn at the next refresh.
func show_company(stalk_id: StringName) -> void:
	_stalk_id = stalk_id


func clear_amount() -> void:
	_trade.clear_amount()


func refresh(context: TradeContext) -> void:
	_context = context
	var state: GameState = context.state
	_company_ids.clear()
	for row: StalkState in state.stalks:
		_company_ids.append(row.id)
	if _stalk_id.is_empty() or not _company_ids.has(_stalk_id):
		if _company_ids.is_empty():
			return
		_stalk_id = _company_ids[0]

	var stalk: StalkState = state.stalk_by_id(_stalk_id)
	var company: CompanyState = state.market.company_by_id(_stalk_id)
	_name.text = stalk.definition.display_name
	_name.tooltip_text = stalk.definition.display_name
	_description.text = stalk.definition.description
	_held_label.text = "HELD %d " % context.held(_stalk_id)
	context.prepare(_trade, _stalk_id)

	if company == null:
		_identity.set_texts([String(stalk.definition.ticker), "", ""])
		_show_no_earnings()
		_ledger.show_nothing()
		_yield.text = ""
	else:
		var industry: IndustryState = state.market.industry_by_id(company.profile.industry)
		var industry_name: String = ""
		if industry != null:
			industry_name = industry.definition.display_name
		_identity.set_texts([
			String(stalk.definition.ticker),
			industry_name,
			MarketReadouts.regime_caption(state, company),
		])
		_show_earnings(state, company)
		var latest: EarningsYearResult = state.latest_result() as EarningsYearResult
		var ledger: PriceLedger = null
		if latest != null:
			ledger = latest.ledger_for(_stalk_id)
		_ledger.show_ledger(ledger)
		_yield.text = "Earnings yield %s  against risk-free %s" % [
			Palette.format_percent_decimal(MarketReadouts.earnings_yield_percent(state, company)),
			Palette.format_percent_decimal(MarketReadouts.risk_free_percent(state)),
		]

	_show_investors(state, stalk)
	_show_activity(state, company)


# ------------------------------------------------------------- earnings

func _add_earnings_row(widths: Array[int], aligns: Array[int]) -> CellRow:
	var row: CellRow = CellRowScene.instantiate()
	_earnings.add_child(row)
	row.configure(widths, aligns)
	return row


func _show_earnings(state: GameState, company: CompanyState) -> void:
	var records: Array[CompanyState] = MarketReadouts.company_history(state, company.id, YEARS_SHOWN)
	var years: Array[int] = MarketReadouts.history_years(state, YEARS_SHOWN)
	for column: int in YEARS_SHOWN:
		var cell: int = column + 1
		if column >= records.size():
			_year_row.set_cell(cell, "")
			for line: Line in _lines:
				_lines[line].set_cell(cell, "")
			_split_row.set_cell(cell, "")
			continue
		var record: CompanyState = records[column]
		_year_row.set_cell(cell, "Year %d" % years[column])
		_lines[Line.REVENUE].set_cell(cell, Palette.format_decimal(record.revenue, 0))
		_lines[Line.EXPENSES].set_cell(cell, Palette.format_decimal(MarketReadouts.expenses(record), 0))
		_lines[Line.PROFIT].set_cell(cell, Palette.format_decimal(record.profit, 0))
		_lines[Line.MARGIN].set_cell(cell, Palette.format_percent(record.margin_percent))
		_lines[Line.EPS].set_cell(cell, Palette.format_decimal(record.earnings_per_share(), 2))
		_lines[Line.PRICE].set_cell(cell, str(record.price))
		_lines[Line.PE].set_cell(cell, Palette.format_decimal(
			MarketReadouts.price_earnings(record.price, record.earnings_per_share()), 1
		))
		_split_row.set_cell(cell, SPLIT_MARK if record.did_split else "")


func _show_no_earnings() -> void:
	for column: int in YEARS_SHOWN:
		_year_row.set_cell(column + 1, "")
		for line: Line in _lines:
			_lines[line].set_cell(column + 1, "")
		_split_row.set_cell(column + 1, "")


# ------------------------------------------------------------ who holds it

## Names only, as the base game's details panel shows them (decisions.md D103).
func _show_investors(state: GameState, stalk: StalkState) -> void:
	var names: PackedStringArray = []
	for player: PlayerState in state.players:
		if player.invests_in(stalk.id):
			names.append(player.display_name)
	if stalk.definition.investors_are_anonymous and not names.is_empty():
		_investors.text = "(anonymous)"
	elif names.is_empty():
		_investors.text = "None"
	else:
		_investors.text = "\n".join(names)


## The traders who picked this company last year, by name (§14 q11), as a
## table: TRADER, what it did LAST YEAR, and what it holds NOW - a number of
## shares, or "short" and the shares it has sold short (decisions.md D184).
func _show_activity(state: GameState, company: CompanyState) -> void:
	for child: Node in _activity.get_children():
		_activity.remove_child(child)
		child.queue_free()
	_short_line.text = ""
	if company == null:
		return
	var entries: Array[Array] = MarketReadouts.desk_activity(state, company.id)
	if entries.is_empty():
		var nobody: CellRow = _add_activity_row()
		nobody.set_texts(["None"])
		return
	var heading: CellRow = _add_activity_row()
	heading.set_texts(["TRADER", "LAST YEAR", "NOW"])
	heading.set_row_variation(&"Faint")
	heading.set_framed(&"HeaderCard")
	heading.set_cell_tooltip(1, TermTips.NPC_LAST_YEAR)
	heading.set_cell_tooltip(2, TermTips.NPC_NOW)
	for entry: Array in entries:
		var trader: NpcTraderState = state.market.desk.trader_by_id(entry[0])
		var row: CellRow = _add_activity_row()
		row.set_texts([
			trader.definition.display_name,
			Palette.sentence_case(MarketReadouts.situation_word(entry[1])),
			Palette.sentence_case(MarketReadouts.position_caption(entry[2], entry[3])),
		])
		row.set_cell_tooltip(0, trader.definition.display_name)
		row.set_cell_variation(1, &"Faint")
	var shorted: int = state.market.desk.short_interest(company.id)
	_short_line.tooltip_text = TermTips.fit(TermTips.short_interest())
	if shorted > 0:
		_short_line.text = "Short interest %d shares" % shorted


func _add_activity_row() -> CellRow:
	var row: CellRow = CellRowScene.instantiate()
	_activity.add_child(row)
	row.configure([TRADER_CHARS, ACTION_CHARS, POSITION_CHARS], [CellRow.LEFT, CellRow.LEFT, CellRow.RIGHT])
	return row


# ---------------------------------------------------------------- for tests

func shown_id() -> StringName:
	return _stalk_id


func trade_box() -> TradeBox:
	return _trade


## How far down the list of companies starts: below the title line.
func title_height() -> float:
	return _pick.get_parent_control().get_combined_minimum_size().y


func pick_button() -> Button:
	return _pick


func held_text() -> String:
	return _held_label.text.strip_edges()


func identity_text() -> String:
	return _identity.line_text()


func earnings_line(line: Line) -> String:
	return _lines[line].line_text()


func years_line() -> String:
	return _year_row.line_text()


func split_line() -> String:
	return _split_row.line_text()


func ledger() -> LedgerWidget:
	return _ledger


func investors_text() -> String:
	return _investors.text


func activity_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in _activity.get_children():
		lines.append((child as CellRow).line_text())
	return lines


# --------------------------------------------------------------- handlers

func _on_pick_pressed() -> void:
	picker_requested.emit()


func _on_previous_pressed() -> void:
	_step(-1)


func _on_next_pressed() -> void:
	_step(1)


## Walks the companies, wrapping at either end. Asks the host to redraw,
## because the state is the host's to hand in.
func _step(by: int) -> void:
	if _company_ids.is_empty():
		return
	var at: int = maxi(0, _company_ids.find(_stalk_id))
	_stalk_id = _company_ids[posmod(at + by, _company_ids.size())]
	company_changed.emit(_stalk_id)


func _on_trade_buy_requested(shares: int) -> void:
	buy_requested.emit(_stalk_id, shares)


func _on_trade_sell_requested(shares: int) -> void:
	sell_requested.emit(_stalk_id, shares)


func _on_trade_amount_changed(_shares: int) -> void:
	if _context != null:
		_context.check(_trade, _stalk_id)
