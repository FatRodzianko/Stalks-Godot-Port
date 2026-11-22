class_name ExchangeTab
extends HBoxContainer
## Tab 1 of a StalkleHeads match: the Stalk Exchange (docs/stalkleheads-design.md
## §7.2). The board on the left, grouped by industry; the rankings, the desk and
## short interest down the right.
##
## **Four things the design decided are what this file does:**
##
## - **Tickers** beside the full names: `StalkDefinition.ticker`, displayed at
##   last. The name still scrolls on hover.
## - **Collapsible industry groups.** Clicking an industry's header hides or
##   shows its members.
## - **Sorting within a group.** Clicking a column header sorts every group's
##   members by it; clicking again reverses. Never across groups, so a member's
##   P/E always sits under its industry's average.
## - **HELD on the board**, with one quantity field and Buy and Sell beside it,
##   so the base game's separate holdings list is not needed here. The base
##   board is unchanged (§14 q1).
##
## Collapse and sort are **presentation only**: they live in this node, never
## in `GameState`, so they cannot desync and nothing about them travels.
## There is no flatten-groups switch (§14 q12) and no cheap/expensive marker
## (§14 q9).
##
## Every figure comes from `MarketReadouts`; this lays out and forwards clicks.


signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)

## The player wants a company's details: the host opens the Company tab.
signal company_requested(stalk_id: StringName)


const CompanyRowScene: PackedScene = preload("res://src/ui/widgets/company_row.tscn")
const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")
const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")

## The group holding the two rows that are not companies. Its title is the
## design's (§7.2).
const INDEX_AND_BOND: StringName = &"index_and_bond"
const INDEX_AND_BOND_TITLE: String = "INDEX AND BOND"

## The right-hand strip's two-column rows, in characters: 24 wide in all.
const STRIP_CAPTION_CHARS: int = 12
const STRIP_VALUE_CHARS: int = 10


## Which groups are collapsed. Presentation only.
var _collapsed: Dictionary[StringName, bool] = {}

## The column the board is sorted by, or `&""` for board order.
var _sort_column: StringName = &""
var _sort_descending: bool = false

## Each group's header, and each group's member ids in board order.
var _group_rows: Dictionary[StringName, CompanyRow] = {}
var _group_members: Dictionary[StringName, Array] = {}
var _group_order: Array[StringName] = []
var _rows: Dictionary[StringName, CompanyRow] = {}

## The values each row sorts by, refreshed with the row.
var _sort_values: Dictionary[StringName, Dictionary] = {}

var _desk_rows: Array[CellRow] = []

@onready var _header_slot: MarginContainer = %HeaderSlot
@onready var _board_scroll: ScrollContainer = %BoardScroll
@onready var _board_list: VBoxContainer = %BoardList
@onready var _cash_row: CellRow = %CashRow
@onready var _net_row: CellRow = %NetRow
@onready var _loan_row: CellRow = %LoanRow
@onready var _ranking_list: VBoxContainer = %RankingList
@onready var _desk_list: VBoxContainer = %DeskList
@onready var _short_list: VBoxContainer = %ShortList
@onready var _short_none: Label = %ShortNone
@onready var _short_title: Label = %ShortTitle


func _ready() -> void:
	var header: CompanyRow = CompanyRowScene.instantiate()
	_header_slot.add_child(header)
	header.configure_as_header()
	header.sort_requested.connect(_on_header_sort_requested)
	# The list reserves its scrollbar's width whether or not it is showing
	# (decisions.md D174), and the header stands outside the list, so it is
	# inset by exactly that much to keep the columns over their rows.
	var bar: VScrollBar = _board_scroll.get_v_scroll_bar()
	if bar != null:
		_header_slot.add_theme_constant_override("margin_right", int(bar.get_combined_minimum_size().x))

	for row: CellRow in [_cash_row, _net_row, _loan_row]:
		row.configure([STRIP_CAPTION_CHARS, STRIP_VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
		row.set_cell_variation(0, &"Faint")
	_cash_row.set_cell(0, "CASH")
	_net_row.set_cell(0, "NET")
	_loan_row.set_cell(0, "LOAN")
	_loan_row.set_cell_variation(1, &"Bear")
	# From the rule itself, so the tooltip cannot disagree with the flag.
	_short_title.tooltip_text = (
		"Shares the desk has sold short. A company is flagged at %d%% of its shares."
		% roundi(ShortInterestRules.FLAG_AT_PERCENT)
	)


## Builds the board's rows for `state`'s market, once per match.
func build(state: GameState) -> void:
	for child: Node in _board_list.get_children():
		_board_list.remove_child(child)
		child.queue_free()
	_group_rows.clear()
	_group_members.clear()
	_group_order.clear()
	_rows.clear()

	for industry: IndustryState in state.market.industries:
		var members: Array[StringName] = []
		for company: CompanyState in MarketReadouts.industry_members(state, industry.id):
			members.append(company.id)
		_add_group(industry.id, members)
	var others: Array[StringName] = []
	for row: StalkState in state.stalks:
		if state.market.company_by_id(row.id) == null:
			others.append(row.id)
	_add_group(INDEX_AND_BOND, others)


## Redraws every figure. `ranking_order` is the standings, best first, as the
## screen around this already works them out; `trading` is whether this player
## may trade right now.
func refresh(
	state: GameState,
	player: PlayerState,
	trading: bool,
	ranking_order: Array[StringName],
	local_id: StringName,
	host_id: StringName,
) -> void:
	for group_id: StringName in _group_order:
		_refresh_group(state, group_id)
	for stalk_id: StringName in _rows:
		_refresh_company(state, player, stalk_id, trading)
	_arrange()
	_refresh_strip(state, player, ranking_order, local_id, host_id)


# ------------------------------------------------------------------ board

func _add_group(group_id: StringName, members: Array[StringName]) -> void:
	var header: CompanyRow = CompanyRowScene.instantiate()
	_board_list.add_child(header)
	header.configure_as_group(group_id)
	header.group_toggled.connect(_on_group_toggled)
	_group_rows[group_id] = header
	_group_members[group_id] = members
	_group_order.append(group_id)
	for stalk_id: StringName in members:
		var row: CompanyRow = CompanyRowScene.instantiate()
		_board_list.add_child(row)
		row.buy_requested.connect(_on_row_buy_requested)
		row.sell_requested.connect(_on_row_sell_requested)
		row.amount_changed.connect(_on_row_amount_changed)
		row.info_requested.connect(_on_row_info_requested)
		_rows[stalk_id] = row


func _refresh_group(state: GameState, group_id: StringName) -> void:
	var header: CompanyRow = _group_rows[group_id]
	var collapsed: bool = _collapsed.get(group_id, false)
	if group_id == INDEX_AND_BOND:
		header.display_group(INDEX_AND_BOND_TITLE, collapsed, MarketReadouts.NONE, MarketReadouts.NONE)
		return
	var industry: IndustryState = state.market.industry_by_id(group_id)
	var performance: float = MarketReadouts.NONE
	if state.year > 0:
		performance = MarketReadouts.industry_performance_in(state, group_id, state.year)
	header.display_group(
		industry.definition.display_name.to_upper(),
		collapsed,
		performance,
		MarketReadouts.industry_average_pe(state, group_id),
	)


func _refresh_company(state: GameState, player: PlayerState, stalk_id: StringName, trading: bool) -> void:
	var row: CompanyRow = _rows[stalk_id]
	var stalk: StalkState = state.stalk_by_id(stalk_id)
	var company: CompanyState = state.market.company_by_id(stalk_id)
	var eps: float = MarketReadouts.NONE
	var pe: float = MarketReadouts.NONE
	if company != null:
		eps = company.earnings_per_share()
		pe = MarketReadouts.company_pe(state, company)
	var held: int = player.shares_of(stalk_id) if player != null else 0
	var dividend: int = MarketReadouts.dividend_shown(state, stalk_id)
	row.display_row(stalk, String(stalk.definition.ticker), eps, pe, dividend, held, company != null)
	row.set_trading_open(trading)
	if player != null:
		row.set_affordable_hint(TradeRules.max_affordable(player, stalk))

	_sort_values[stalk_id] = {
		CompanyRow.SORT_TICKER: String(stalk.definition.ticker),
		CompanyRow.SORT_NAME: stalk.definition.display_name.to_lower(),
		CompanyRow.SORT_PRICE: float(stalk.price),
		CompanyRow.SORT_CHANGE: float(stalk.last_yearly_change),
		CompanyRow.SORT_EPS: eps,
		CompanyRow.SORT_PE: pe,
		CompanyRow.SORT_DIVIDEND: float(dividend),
		CompanyRow.SORT_HELD: float(held),
	}


## Puts every row in place: each group's header, then its members in the
## chosen order, hidden while the group is collapsed.
func _arrange() -> void:
	var at: int = 0
	for group_id: StringName in _group_order:
		_board_list.move_child(_group_rows[group_id], at)
		at += 1
		var collapsed: bool = _collapsed.get(group_id, false)
		for stalk_id: StringName in _sorted_members(group_id):
			var row: CompanyRow = _rows[stalk_id]
			_board_list.move_child(row, at)
			row.visible = not collapsed
			at += 1


func _sorted_members(group_id: StringName) -> Array[StringName]:
	var members: Array[StringName] = []
	members.assign(_group_members[group_id])
	if _sort_column.is_empty():
		return members
	members.sort_custom(_member_order)
	return members


## Ascending, or descending once reversed. A figure that does not exist (a P/E
## with no earnings) sorts last either way, and ties keep board order by id.
func _member_order(a: StringName, b: StringName) -> bool:
	var left: Variant = _sort_values.get(a, {}).get(_sort_column, null)
	var right: Variant = _sort_values.get(b, {}).get(_sort_column, null)
	var left_missing: bool = left == null or (left is float and is_nan(left))
	var right_missing: bool = right == null or (right is float and is_nan(right))
	if left_missing != right_missing:
		return right_missing
	if left_missing or left == right:
		return String(a) < String(b)
	if _sort_descending:
		return left > right
	return left < right


# ------------------------------------------------------------------ strip

func _refresh_strip(
	state: GameState,
	player: PlayerState,
	ranking_order: Array[StringName],
	local_id: StringName,
	host_id: StringName,
) -> void:
	if player != null:
		_cash_row.set_cell(1, Palette.format_money(player.cash))
		_net_row.set_cell(1, Palette.format_money(player.net_worth))
		_loan_row.visible = player.owes() > 0
		_loan_row.set_cell(1, Palette.format_money(player.owes()))

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

	_refresh_desk(state)
	_refresh_short_interest(state)


func _refresh_desk(state: GameState) -> void:
	var returns: Dictionary[NpcStrategy.Value, float] = MarketReadouts.desk_returns(state)
	var order: Array[NpcStrategy.Value] = MarketReadouts.strategies_by_return(state)
	while _desk_rows.size() < order.size():
		var row: CellRow = CellRowScene.instantiate()
		_desk_list.add_child(row)
		row.configure([STRIP_CAPTION_CHARS, STRIP_VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
		_desk_rows.append(row)
	for index: int in order.size():
		var strategy: NpcStrategy.Value = order[index]
		var row: CellRow = _desk_rows[index]
		row.set_texts([NpcStrategy.name_of(strategy).to_lower(), Palette.format_percent_change(returns[strategy])])
		row.set_cell_colour(1, Palette.for_percent(returns[strategy]))


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
		row.configure([STRIP_CAPTION_CHARS, STRIP_VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
		row.set_texts([String(stalk.definition.ticker), "%d shares" % entry[1]])


# ------------------------------------------------- the screen's hooks into rows

func row_for(stalk_id: StringName) -> CompanyRow:
	return _rows.get(stalk_id)


func group_row_for(group_id: StringName) -> CompanyRow:
	return _group_rows.get(group_id)


func clear_amounts() -> void:
	for row: CompanyRow in _rows.values():
		row.clear_amount()


## The board's rows from top to bottom, as ids: a group's id for its header,
## a stalk id for a member, members of a collapsed group left out. For tests.
func visible_order() -> Array[StringName]:
	var order: Array[StringName] = []
	for child: Node in _board_list.get_children():
		var row: CompanyRow = child as CompanyRow
		if row == null or not row.visible:
			continue
		if row.is_group():
			order.append(row.group_id())
		else:
			order.append(row.stalk_id())
	return order


func is_collapsed(group_id: StringName) -> bool:
	return _collapsed.get(group_id, false)


func sort_column() -> StringName:
	return _sort_column


func is_sorted_descending() -> bool:
	return _sort_descending


func ranking_row_count() -> int:
	return _ranking_list.get_child_count()


func desk_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for row: CellRow in _desk_rows:
		lines.append(row.line_text())
	return lines


func short_interest_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in _short_list.get_children():
		lines.append((child as CellRow).line_text())
	return lines


func cash_text() -> String:
	return _cash_row.cell_text(1)


# --------------------------------------------------------------- handlers

func _on_group_toggled(group_id: StringName) -> void:
	_collapsed[group_id] = not _collapsed.get(group_id, false)
	_group_rows[group_id].display_group_marker(_collapsed[group_id])
	_arrange()


## A first click sorts ascending; the same column again reverses it.
func _on_header_sort_requested(column: StringName) -> void:
	if _sort_column == column:
		_sort_descending = not _sort_descending
	else:
		_sort_column = column
		_sort_descending = false
	_arrange()


func _on_row_buy_requested(stalk_id: StringName, shares: int) -> void:
	buy_requested.emit(stalk_id, shares)


func _on_row_sell_requested(stalk_id: StringName, shares: int) -> void:
	sell_requested.emit(stalk_id, shares)


func _on_row_amount_changed(stalk_id: StringName, shares: int) -> void:
	amount_changed.emit(stalk_id, shares)


func _on_row_info_requested(stalk_id: StringName) -> void:
	company_requested.emit(stalk_id)
