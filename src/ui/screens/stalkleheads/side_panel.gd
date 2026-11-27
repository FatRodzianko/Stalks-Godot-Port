class_name SidePanel
extends ScrollContainer
## The StalkleHeads tabs' right-hand panel: **HOLDINGS** (cash, net worth, any
## loan, and every company you hold, with a box and SELL), **RANKINGS**, and
## **THE DESK** (each NPC strategy's return, short interest, and each trader's
## chatter about last year, when it has any - phase S8). One page at a
## time; `MarketTabs` owns the three buttons that choose it, whether the panel
## shows at all, and the bright frame that sets it apart from the tab beneath
## (decisions.md D183, D184).
##
## Asked for after the first play test: HELD on the board alone made a player
## hunt for what they owned. The base game lists your stalks beside the board,
## and this does the same **with the base game's own row** (`HoldingRow`, made
## compact: ticker for name, no ALL), so it looks and sells the same way.


signal sell_requested(stalk_id: StringName, shares: int)

## A holding was clicked: open that company on the Company tab.
signal company_requested(stalk_id: StringName)


enum Page { HOLDINGS, RANKINGS, DESK }

## The buttons' captions, in their order on screen.
const CAPTIONS: Dictionary[Page, String] = {
	Page.HOLDINGS: "HOLDINGS",
	Page.RANKINGS: "RANKINGS",
	Page.DESK: "DESK",
}

## The panel's width in characters: a compact `HoldingRow` - ticker, count, box
## and SELL - with room for the scroll bar.
const WIDTH_CHARS: int = 26

## The two-column lines (cash, the desk, short interest), in characters.
const CAPTION_CHARS: int = 12
const VALUE_CHARS: int = 12

## The short interest list's ticker column: narrower than a caption, so the
## percent and its FLAGGED or SQUEEZED fit beside it.
const SHORT_TICKER_CHARS: int = 7

## The width chatter wraps at: the two columns above it.
const CHATTER_WIDTH: int = (CAPTION_CHARS + VALUE_CHARS) * CellRow.CELL_WIDTH

const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")
const HoldingRowScene: PackedScene = preload("res://src/ui/widgets/holding_row.tscn")
const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")


var _page: Page = Page.HOLDINGS
var _pages: Dictionary[Page, Control] = {}
var _holding_rows: Dictionary[StringName, HoldingRow] = {}
var _desk_rows: Array[CellRow] = []
var _context: TradeContext

@onready var _holdings_page: VBoxContainer = %HoldingsPage
@onready var _rankings_page: VBoxContainer = %RankingsPage
@onready var _desk_page: VBoxContainer = %DeskPage
@onready var _cash_row: CellRow = %CashRow
@onready var _net_row: CellRow = %NetRow
@onready var _loan_row: CellRow = %LoanRow
@onready var _holdings_header: HoldingRow = %HoldingsHeader
@onready var _holdings_list: VBoxContainer = %HoldingsList
@onready var _holdings_none: Label = %HoldingsNone
@onready var _ranking_list: VBoxContainer = %RankingList
@onready var _desk_title: Label = %DeskTitle
@onready var _desk_list: VBoxContainer = %DeskList
@onready var _short_title: Label = %ShortTitle
@onready var _short_none: Label = %ShortNone
@onready var _short_list: VBoxContainer = %ShortList
@onready var _chatter_title: Label = %ChatterTitle
@onready var _chatter_list: VBoxContainer = %ChatterList


func _ready() -> void:
	custom_minimum_size.x = WIDTH_CHARS * CellRow.CELL_WIDTH
	_pages = {
		Page.HOLDINGS: _holdings_page,
		Page.RANKINGS: _rankings_page,
		Page.DESK: _desk_page,
	}
	for row: CellRow in [_cash_row, _net_row, _loan_row]:
		row.configure([CAPTION_CHARS, VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
		row.set_cell_variation(0, &"Faint")
	_cash_row.set_cell(0, "CASH")
	_net_row.set_cell(0, "NET")
	_net_row.set_cell_tooltip(0, TermTips.NET_WORTH)
	_loan_row.set_cell(0, "LOAN")
	_loan_row.set_cell_variation(1, &"Bear")
	_holdings_header.set_compact()
	_holdings_header.configure_as_header()
	_desk_title.tooltip_text = TermTips.fit(TermTips.DESK)
	_short_title.tooltip_text = TermTips.fit(TermTips.short_interest())
	_chatter_title.tooltip_text = TermTips.fit(TermTips.NPC_CHATTER)
	show_page(Page.HOLDINGS)


func show_page(page: Page) -> void:
	_page = page
	for each: Page in _pages:
		_pages[each].visible = each == page


func current_page() -> Page:
	return _page


## Redraws all three pages. `board_order` is the Exchange's row order, which
## the holdings follow.
func refresh(
	context: TradeContext,
	board_order: Array[StringName],
	ranking_order: Array[StringName],
	local_id: StringName,
	host_id: StringName,
) -> void:
	_context = context
	var state: GameState = context.state
	var player: PlayerState = context.player
	if player != null:
		_cash_row.set_cell(1, Palette.format_money(player.cash))
		_net_row.set_cell(1, Palette.format_money(player.net_worth))
		_loan_row.visible = player.owes() > 0
		_loan_row.set_cell(1, Palette.format_money(player.owes()))
	_refresh_holdings(state, board_order)
	_refresh_rankings(state, ranking_order, local_id, host_id)
	_refresh_desk(state)
	_refresh_short_interest(state)
	_refresh_chatter(state)


func clear_amounts() -> void:
	for row: HoldingRow in _holding_rows.values():
		row.clear_amount()


# ------------------------------------------------------------- holdings

func _refresh_holdings(state: GameState, board_order: Array[StringName]) -> void:
	var held_ids: Array[StringName] = []
	for stalk_id: StringName in board_order:
		if _context.held(stalk_id) > 0:
			held_ids.append(stalk_id)
	for stalk_id: StringName in _holding_rows.keys():
		if not held_ids.has(stalk_id):
			var gone: HoldingRow = _holding_rows[stalk_id]
			_holding_rows.erase(stalk_id)
			_holdings_list.remove_child(gone)
			gone.queue_free()
	for index: int in held_ids.size():
		var stalk_id: StringName = held_ids[index]
		var row: HoldingRow = _holding_rows.get(stalk_id)
		if row == null:
			row = HoldingRowScene.instantiate()
			_holdings_list.add_child(row)
			row.set_compact()
			row.sell_requested.connect(_on_row_sell_requested)
			row.amount_changed.connect(_on_row_amount_changed)
			row.info_requested.connect(_on_row_info_requested)
			_holding_rows[stalk_id] = row
		_holdings_list.move_child(row, index)
		row.display(state.stalk_by_id(stalk_id), _context.held(stalk_id))
		_context.prepare_holding(row, stalk_id)
	_holdings_none.visible = held_ids.is_empty()


# ------------------------------------------------------------- rankings

func _refresh_rankings(
	state: GameState,
	ranking_order: Array[StringName],
	local_id: StringName,
	host_id: StringName,
) -> void:
	for child: Node in _ranking_list.get_children():
		_ranking_list.remove_child(child)
		child.queue_free()
	for player_id: StringName in ranking_order:
		var ranked: PlayerState = state.player_by_id(player_id)
		if ranked == null:
			continue
		var row: RankingRow = RankingRowScene.instantiate()
		_ranking_list.add_child(row)
		row.display(ranked, ranked.id == local_id, ranked.is_ready, ranked.id == host_id)


# ----------------------------------------------------------------- desk

func _refresh_desk(state: GameState) -> void:
	var returns: Dictionary[NpcStrategy.Value, float] = MarketReadouts.desk_returns(state)
	var order: Array[NpcStrategy.Value] = MarketReadouts.strategies_by_return(state)
	while _desk_rows.size() < order.size():
		var row: CellRow = CellRowScene.instantiate()
		_desk_list.add_child(row)
		row.configure([CAPTION_CHARS, VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
		_desk_rows.append(row)
	for index: int in order.size():
		var strategy: NpcStrategy.Value = order[index]
		var row: CellRow = _desk_rows[index]
		row.set_texts([Palette.sentence_case(NpcStrategy.name_of(strategy).to_lower()), Palette.format_percent_change(returns[strategy])])
		row.set_cell_colour(1, Palette.for_percent(returns[strategy]))
		row.set_cell_tooltip(0, TermTips.strategy(strategy))


func _refresh_short_interest(state: GameState) -> void:
	for child: Node in _short_list.get_children():
		_short_list.remove_child(child)
		child.queue_free()
	var shorted: Array[Array] = MarketReadouts.short_interest(state)
	_short_none.visible = shorted.is_empty()
	for entry: Array in shorted:
		var stalk: StalkState = state.stalk_by_id(entry[0])
		var row: CellRow = CellRowScene.instantiate()
		_short_list.add_child(row)
		row.configure([SHORT_TICKER_CHARS, CAPTION_CHARS + VALUE_CHARS - SHORT_TICKER_CHARS], [CellRow.LEFT, CellRow.RIGHT])
		row.set_texts([String(stalk.definition.ticker), short_interest_words(state, entry[0])])
		row.set_cell_tooltip(0, stalk.definition.display_name)
		# Clicking the entry opens the company on the Company tab (D222).
		row.key = entry[0]
		row.set_clickable(true)
		row.pressed.connect(_on_short_row_pressed)
		row.set_cell_tooltip(1, "%d shares sold short" % entry[1])


## Each trader that said something about last year, in the order they acted:
## its name, faint, then the line, wrapped to the panel. No chatter, no
## heading: an empty slot shows nothing (design §8.2).
func _refresh_chatter(state: GameState) -> void:
	for child: Node in _chatter_list.get_children():
		_chatter_list.remove_child(child)
		child.queue_free()
	var news: YearNews = NewsSelector.latest(state)
	var latest: EarningsYearResult = state.latest_result() as EarningsYearResult
	if news != null and latest != null and latest.desk != null:
		for trader_id: StringName in latest.desk.trader_ids:
			if not news.chatter.has(trader_id):
				continue
			var trader: NpcTraderState = state.market.desk.trader_by_id(trader_id)
			var caption: Label = Label.new()
			caption.text = trader.definition.display_name
			caption.theme_type_variation = &"Faint"
			caption.clip_text = true
			caption.custom_minimum_size.x = CHATTER_WIDTH
			_chatter_list.add_child(caption)
			var line: Label = Label.new()
			line.text = news.chatter[trader_id]
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size.x = CHATTER_WIDTH
			_chatter_list.add_child(line)
	var any: bool = _chatter_list.get_child_count() > 0
	_chatter_title.visible = any
	_chatter_list.visible = any


# ------------------------------------------------------------ for tests

## The chatter as shown: name, line, name, line. Empty when hidden.
func chatter_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if not _chatter_list.visible:
		return lines
	for child: Node in _chatter_list.get_children():
		lines.append((child as Label).text)
	return lines


func holding_row(stalk_id: StringName) -> HoldingRow:
	return _holding_rows.get(stalk_id)


func holding_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for child: Node in _holdings_list.get_children():
		ids.append((child as HoldingRow).stalk_id())
	return ids


func ranking_row_count() -> int:
	return _ranking_list.get_child_count()


func desk_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for row: CellRow in _desk_rows:
		lines.append(row.line_text())
	return lines


## A company's short interest as the desk and the Company tab show it: the
## percent of its shares sold short, then FLAGGED or SQUEEZED (D213).
static func short_interest_words(state: GameState, company_id: StringName) -> String:
	var words: String = Palette.format_percent(MarketReadouts.short_interest_percent(state, company_id))
	match MarketReadouts.short_status(state, company_id):
		MarketReadouts.ShortStatus.FLAGGED:
			words += " FLAGGED"
		MarketReadouts.ShortStatus.SQUEEZED:
			words += " SQUEEZED"
	return words


func short_interest_rows() -> Array[CellRow]:
	var rows: Array[CellRow] = []
	for child: Node in _short_list.get_children():
		rows.append(child as CellRow)
	return rows


func short_interest_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in _short_list.get_children():
		lines.append((child as CellRow).line_text())
	return lines


func cash_text() -> String:
	return _cash_row.cell_text(1)


# ------------------------------------------------------------- handlers

func _on_row_sell_requested(stalk_id: StringName, shares: int) -> void:
	sell_requested.emit(stalk_id, shares)


func _on_row_amount_changed(stalk_id: StringName, _shares: int) -> void:
	var row: HoldingRow = _holding_rows.get(stalk_id)
	if row != null and _context != null:
		_context.check_holding(row, stalk_id)


func _on_row_info_requested(stalk_id: StringName) -> void:
	company_requested.emit(stalk_id)


func _on_short_row_pressed(stalk_id: StringName) -> void:
	company_requested.emit(stalk_id)
