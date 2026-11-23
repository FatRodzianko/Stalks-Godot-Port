extends GutTest
## StalkleHeads phase S7, on screen: the real playing screen, a StalkleHeads
## match injected, driven through its controls (docs/stalkleheads-design.md §7,
## §11 S7; decisions.md D179-D182).
##
## The things a person would check by looking, checked by a machine instead:
## the tabs replace the boards and only in this mode; the board has tickers,
## groups that collapse, sorting that never crosses a group, and a HELD column
## that trades; the regime is named; the ledger's total is the board's change;
## the digest arrives with the year; a client's screen says what the host's
## does; and every tab fits the 640 x 360 picture.


const ScreenScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")
const TabsScene: PackedScene = preload("res://src/ui/screens/stalkleheads/market_tabs.tscn")

const SEED: int = 20261122

var _screen: GameplayScreen
var _session: LocalSession
var _saved_user: UserSettings


func before_each() -> void:
	_saved_user = UserSettings.load_from()
	var known: UserSettings = UserSettings.load_from()
	known.show_news = true
	known.save_to()


func after_each() -> void:
	_saved_user.save_to()


func _start(mode: GameMode.Value = GameMode.Value.STALKLEHEADS, years: int = 0) -> void:
	var settings: GameSettings = GameSettings.new()
	settings.mode = mode
	settings.max_years = 20
	settings.player_count = 1
	settings.loans_enabled = true
	settings.rng_seed = SEED
	_session = LocalSession.create(settings, MatchSetup.load_library(mode))
	_screen = ScreenScene.instantiate()
	_screen.setup(_session)
	add_child_autofree(_screen)
	add_child_autofree(_session)
	# Year 0 has trading closed; ready up to reach year 1, where it opens.
	for _year: int in years:
		_session.set_ready(&"p0", true)
	if _screen.news_panel() != null:
		_screen.news_panel().close()


func _state() -> GameState:
	return _session.state()


func _tabs() -> MarketTabs:
	return _screen.market_tabs()


func _exchange() -> ExchangeTab:
	return _tabs().exchange()


func _player() -> PlayerState:
	return _state().player_by_id(&"p0")


func _first_living_company() -> CompanyState:
	for company: CompanyState in _state().market.companies:
		if not _state().stalk_by_id(company.id).is_bankrupt:
			return company
	return null


## A click on a label that listens through its `gui_input` signal (a column
## heading), as the engine would deliver it.
func _click_label(label: Control) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	label.gui_input.emit(press)


func _click(control: Control) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	control._gui_input(press)


# ------------------------------------------------------------- which screen

## §14 q1: the base game's board is left alone. No tabs, no HELD column.
func test_a_base_game_match_keeps_its_three_boards() -> void:
	_start(GameMode.Value.BASE, 1)
	assert_null(_screen.market_tabs())
	assert_null(_screen.year_digest())
	assert_true(_screen.get_node("%Boards").visible)
	assert_false(_screen.get_node("%MarketSlot").visible)


func test_a_stalkleheads_match_shows_four_tabs_in_place_of_the_boards() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	assert_not_null(_tabs())
	assert_false(_screen.get_node("%Boards").visible)
	assert_true(_screen.get_node("%MarketSlot").visible)
	var captions: PackedStringArray = []
	for tab: MarketTabs.Tab in MarketTabs.CAPTIONS:
		captions.append(_tabs().tab_button(tab).text)
	assert_eq(captions, PackedStringArray(["EXCHANGE", "MARKET", "INDUSTRIES", "COMPANY"]))
	assert_eq(_tabs().current_tab(), MarketTabs.Tab.EXCHANGE)


func test_pressing_a_tab_shows_it_and_only_it() -> void:
	_start(GameMode.Value.STALKLEHEADS, 2)
	_tabs().tab_button(MarketTabs.Tab.INDUSTRIES).pressed.emit()
	assert_eq(_tabs().current_tab(), MarketTabs.Tab.INDUSTRIES)
	assert_true(_tabs().industries_tab().visible)
	assert_false(_exchange().visible)
	assert_false(_tabs().market_tab().visible)


# ---------------------------------------------------------------- the board

## Every row is on the board under a header, and every company row shows its
## ticker beside the full name.
func test_the_board_groups_every_row_under_its_industry() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var order: Array[StringName] = _exchange().visible_order()
	var group: StringName = &""
	var seen: int = 0
	for id: StringName in order:
		var header: CompanyRow = _exchange().group_row_for(id)
		if header != null:
			group = id
			continue
		seen += 1
		var company: CompanyState = _state().market.company_by_id(id)
		if company != null:
			assert_eq(group, company.profile.industry, "%s sits under its industry" % id)
		else:
			assert_eq(group, ExchangeTab.INDEX_AND_BOND, "%s sits with the index and the bond" % id)
		var row: StalkState = _state().stalk_by_id(id)
		assert_eq(_exchange().row_for(id).column_text(CompanyRow.SORT_TICKER), String(row.definition.ticker))
		assert_eq(_exchange().row_for(id).column_text(CompanyRow.SORT_NAME), row.definition.display_name)
	assert_eq(seen, _state().stalks.size(), "every board row once")


## The industry header carries the members' average P/E and the year's move:
## the tier-2 comparison, two lines apart (§7.2).
func test_an_industry_header_shows_its_average_pe_and_its_year() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	for industry: IndustryState in _state().market.industries:
		var header: CompanyRow = _exchange().group_row_for(industry.id)
		assert_eq(
			header.column_text(CompanyRow.SORT_PE),
			Palette.format_decimal(MarketReadouts.industry_average_pe(_state(), industry.id), 1),
		)
		assert_eq(
			header.column_text(CompanyRow.SORT_CHANGE),
			Palette.format_percent_change(_state().latest_result().industry_performance[industry.id]),
		)


## A company row's figures are the readouts', and P/E is blank for the bond
## and the index.
func test_a_company_row_shows_its_derived_figures() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var company: CompanyState = _first_living_company()
	var row: CompanyRow = _exchange().row_for(company.id)
	var stalk: StalkState = _state().stalk_by_id(company.id)
	assert_eq(row.column_text(CompanyRow.SORT_PRICE), str(stalk.price))
	assert_eq(row.column_text(CompanyRow.SORT_CHANGE), Palette.format_change(stalk.last_yearly_change))
	assert_eq(row.column_text(CompanyRow.SORT_EPS), Palette.format_decimal(company.earnings_per_share(), 2))
	assert_eq(row.column_text(CompanyRow.SORT_PE), Palette.format_decimal(MarketReadouts.company_pe(_state(), company), 1))
	assert_eq(row.column_text(CompanyRow.SORT_DIVIDEND), str(MarketReadouts.dividend_shown(_state(), company.id)))
	for other_id: StringName in [EarningsMarket.BOND_ID, EarningsMarket.INDEX_ID]:
		assert_eq(_exchange().row_for(other_id).column_text(CompanyRow.SORT_PE), "", "%s has no P/E" % other_id)


## Buying through the board's own row: HELD goes up, S comes alive.
func test_buying_through_a_row_fills_its_held_column() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _first_living_company()
	var row: CompanyRow = _exchange().row_for(company.id)
	assert_true(row.sell_is_blocked(), "nothing to sell yet")

	row.type_amount("3")
	row.press_buy()

	assert_eq(_player().shares_of(company.id), 3)
	assert_eq(row.column_text(CompanyRow.SORT_HELD), "3")
	assert_false(row.sell_is_blocked())


func test_selling_through_a_row_empties_its_held_column() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _first_living_company()
	var row: CompanyRow = _exchange().row_for(company.id)
	row.type_amount("4")
	row.press_buy()
	row.type_amount("4")
	row.press_sell()
	assert_eq(_player().shares_of(company.id), 0)
	assert_eq(row.column_text(CompanyRow.SORT_HELD), "0")
	assert_true(row.sell_is_blocked())


## The quantity is checked as it is typed, from the authority's own rule.
func test_a_quantity_too_large_to_buy_greys_the_button() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var row: CompanyRow = _exchange().row_for(_first_living_company().id)
	row.type_amount("999999")
	assert_true(row.buy_is_blocked())
	row.type_amount("1")
	assert_false(row.buy_is_blocked())


func test_year_zero_and_readying_up_close_the_board() -> void:
	_start(GameMode.Value.STALKLEHEADS, 0)
	var row: CompanyRow = _exchange().row_for(_first_living_company().id)
	assert_true(row.buy_is_blocked(), "year 0 has trading closed")
	_session.set_ready(&"p0", true)
	assert_false(row.buy_is_blocked(), "year 1 is open")
	_player().is_ready = true
	_screen.refresh()
	assert_true(row.buy_is_blocked(), "and closed again once ready (D97)")


# ---------------------------------------------------- collapsing and sorting

func test_clicking_an_industry_header_collapses_and_expands_it() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var industry_id: StringName = _state().market.industries[0].id
	var header: CompanyRow = _exchange().group_row_for(industry_id)
	var member: StringName = MarketReadouts.industry_members(_state(), industry_id)[0].id

	_click(header)
	assert_true(_exchange().is_collapsed(industry_id))
	assert_false(_exchange().visible_order().has(member), "its members are hidden")
	assert_true(_exchange().visible_order().has(industry_id), "its header stays")
	assert_eq(header.line_text().left(1), CompanyRow.MARKER_CLOSED)

	_click(header)
	assert_false(_exchange().is_collapsed(industry_id))
	assert_true(_exchange().visible_order().has(member))


## §12.1: collapsing and sorting change nothing in `GameState`, so a player
## who collapses every group sends and receives what one who collapses none
## does.
func test_collapsing_and_sorting_change_nothing_in_the_match() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	var before: Dictionary = StateSync.encode_state(_state(), 0)
	for industry: IndustryState in _state().market.industries:
		_click(_exchange().group_row_for(industry.id))
	_exchange()._on_header_sort_requested(CompanyRow.SORT_PE)
	_exchange()._on_header_sort_requested(CompanyRow.SORT_PE)
	_screen.refresh()
	assert_eq(var_to_bytes(StateSync.encode_state(_state(), 0)), var_to_bytes(before))


## Sorting reorders the members of each group and never moves a row out of it.
func test_sorting_by_pe_orders_each_group_and_never_crosses_one() -> void:
	_start(GameMode.Value.STALKLEHEADS, 5)
	var groups_before: Array[StringName] = _groups_in(_exchange().visible_order())

	_exchange()._on_header_sort_requested(CompanyRow.SORT_PE)
	var ascending: Array[StringName] = _exchange().visible_order()
	assert_eq(_groups_in(ascending), groups_before, "the groups do not move")
	_assert_each_group_ordered_by_pe(ascending, false)

	_exchange()._on_header_sort_requested(CompanyRow.SORT_PE)
	assert_true(_exchange().is_sorted_descending(), "a second click reverses")
	_assert_each_group_ordered_by_pe(_exchange().visible_order(), true)


func test_a_refresh_keeps_the_chosen_sort() -> void:
	_start(GameMode.Value.STALKLEHEADS, 2)
	_exchange()._on_header_sort_requested(CompanyRow.SORT_PRICE)
	var sorted: Array[StringName] = _exchange().visible_order()
	_screen.refresh()
	assert_eq(_exchange().visible_order(), sorted)


func _groups_in(order: Array[StringName]) -> Array[StringName]:
	var groups: Array[StringName] = []
	for id: StringName in order:
		if _exchange().group_row_for(id) != null:
			groups.append(id)
	return groups


## Within each group: every company with a P/E, in order, then every one
## without (a missing figure sorts last either way).
func _assert_each_group_ordered_by_pe(order: Array[StringName], descending: bool) -> void:
	var group_pes: Array[float] = []
	for id: StringName in order + [&"__end__"] as Array[StringName]:
		if id == &"__end__" or _exchange().group_row_for(id) != null:
			var seen_missing: bool = false
			for index: int in group_pes.size():
				if is_nan(group_pes[index]):
					seen_missing = true
					continue
				assert_false(seen_missing, "a P/E after a missing one, before %s" % id)
				if index > 0 and not is_nan(group_pes[index - 1]):
					if descending:
						assert_true(group_pes[index - 1] >= group_pes[index], "descending before %s" % id)
					else:
						assert_true(group_pes[index - 1] <= group_pes[index], "ascending before %s" % id)
			group_pes.clear()
			continue
		var company: CompanyState = _state().market.company_by_id(id)
		if company != null:
			group_pes.append(MarketReadouts.company_pe(_state(), company))


# --------------------------------------------------------- the side panel

func test_the_side_panel_shows_cash_rankings_and_the_desk() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var side: SidePanel = _tabs().side_panel()
	assert_eq(side.cash_text(), Palette.format_money(_player().cash))
	assert_eq(side.ranking_row_count(), _state().players.size())
	var returns: Dictionary[NpcStrategy.Value, float] = MarketReadouts.desk_returns(_state())
	var lines: PackedStringArray = side.desk_lines()
	assert_eq(lines.size(), returns.size())
	var best: NpcStrategy.Value = MarketReadouts.strategies_by_return(_state())[0]
	assert_eq(lines[0], "%s %s" % [
		Palette.sentence_case(NpcStrategy.name_of(best).to_lower()), Palette.format_percent_change(returns[best]),
	])


func test_the_side_panel_lists_short_interest() -> void:
	_start(GameMode.Value.STALKLEHEADS, 8)
	var expected: PackedStringArray = []
	for entry: Array in MarketReadouts.short_interest(_state()):
		expected.append("%s %d shares" % [_state().stalk_by_id(entry[0]).definition.ticker, entry[1]])
	assert_eq(_tabs().side_panel().short_interest_lines(), expected)


## D183: on the board the panel is always open; elsewhere it starts closed, a
## button opens it on its page, the same button closes it, a tab change closes it.
func test_the_side_panel_opens_and_closes_as_asked() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var tabs: MarketTabs = _tabs()
	assert_true(tabs.is_side_open(), "open on the board")
	tabs.side_button(SidePanel.Page.DESK).pressed.emit()
	assert_eq(tabs.side_panel().current_page(), SidePanel.Page.DESK)
	tabs.side_button(SidePanel.Page.DESK).pressed.emit()
	assert_true(tabs.is_side_open(), "the board's panel does not close")

	tabs.select_tab(MarketTabs.Tab.COMPANY)
	assert_false(tabs.is_side_open(), "closed on another tab")
	tabs.side_button(SidePanel.Page.HOLDINGS).pressed.emit()
	assert_true(tabs.is_side_open())
	assert_eq(tabs.side_panel().current_page(), SidePanel.Page.HOLDINGS)
	assert_true(tabs.side_button(SidePanel.Page.HOLDINGS).button_pressed)
	tabs.side_button(SidePanel.Page.HOLDINGS).pressed.emit()
	assert_false(tabs.is_side_open(), "the same button closes it")

	tabs.side_button(SidePanel.Page.RANKINGS).pressed.emit()
	tabs.select_tab(MarketTabs.Tab.INDUSTRIES)
	assert_false(tabs.is_side_open(), "a tab change closes it")
	tabs.select_tab(MarketTabs.Tab.EXCHANGE)
	assert_true(tabs.is_side_open())


## F1: opened on another tab, the panel lies over the tab like a window - the
## tab keeps its width - and on the board it has a column of its own.
func test_the_side_panel_lies_over_the_tabs_but_beside_the_board() -> void:
	_start(GameMode.Value.STALKLEHEADS, 2)
	_screen.size = Vector2(640, 360)
	var tabs: MarketTabs = _tabs()
	var frame: PanelContainer = tabs.get_node("%SideFrame")
	assert_eq(frame.theme_type_variation, &"OverlayFrame", "framed brightly")

	tabs.select_tab(MarketTabs.Tab.MARKET)
	await wait_physics_frames(2)
	var page: Control = tabs.market_tab()
	var width: float = page.size.x
	tabs.side_button(SidePanel.Page.HOLDINGS).pressed.emit()
	await wait_physics_frames(2)
	assert_eq(page.size.x, width, "the tab is not squeezed")
	assert_gt(page.get_global_rect().end.x, frame.global_position.x, "the panel covers its right-hand side")

	tabs.select_tab(MarketTabs.Tab.EXCHANGE)
	await wait_physics_frames(2)
	assert_true(tabs.exchange().get_global_rect().end.x <= frame.global_position.x, "the board is not covered")


## Your holdings, in board order, each the base game's row: a box and SELL.
func test_holdings_list_what_you_own_and_sell_from_there() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var side: SidePanel = _tabs().side_panel()
	assert_eq(side.holding_ids(), [] as Array[StringName])
	var first: StringName = _exchange().board_order()[0]
	var later: StringName = _exchange().board_order()[4]
	_session.request_buy(&"p0", later, 2)
	_session.request_buy(&"p0", first, 3)
	assert_eq(side.holding_ids(), [first, later] as Array[StringName], "board order")
	var row: HoldingRow = side.holding_row(first)
	assert_eq((row.get_node("%Name") as Label).text, String(_state().stalk_by_id(first).definition.ticker))
	assert_eq((row.get_node("%Owned") as Label).text, "3")
	assert_false((row.get_node("%SellAllButton") as Button).visible, "sell only, no ALL")

	var amount: LineEdit = row.get_node("%Amount")
	amount.text = "3"
	amount.text_changed.emit("3")
	(row.get_node("%SellButton") as Button).pressed.emit()
	assert_eq(_player().shares_of(first), 0)
	assert_eq(side.holding_ids(), [later] as Array[StringName], "sold out, gone from the list")


## The trade box never moves: SELL is greyed, not hidden, and every box is the
## same width on every row (manual-testing.md E, D183).
func test_the_trade_box_keeps_its_place() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	_screen.size = Vector2(640, 360)
	await wait_physics_frames(2)
	var company: CompanyState = _first_living_company()
	var box: TradeBox = _exchange().row_for(company.id).trade_box()
	var buy: Button = box.get_node("%BuyButton")
	var sell: Button = box.get_node("%SellButton")
	var before: float = buy.global_position.x
	assert_true(sell.visible)
	assert_true(sell.disabled)
	_session.request_buy(&"p0", company.id, 1)
	await wait_physics_frames(2)
	assert_eq(buy.text, "BUY")
	assert_eq(sell.text, "SELL")
	assert_eq(buy.global_position.x, before, "BUY did not move")
	assert_false(sell.disabled)
	assert_eq(box.size.x, float(TradeBox.WIDTH_CHARS * CellRow.CELL_WIDTH))


## Clicking a column heading marks it ^, again v, always after the caption.
func test_the_sorted_heading_shows_its_direction() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var header: CompanyRow = _exchange().get_node("%HeaderSlot").get_child(0)
	_click_label(header.get_node("%Pe"))
	assert_eq(header.column_text(CompanyRow.SORT_PE), "P/E^")
	_click_label(header.get_node("%Pe"))
	assert_eq(header.column_text(CompanyRow.SORT_PE), "P/Ev")
	_click_label(header.get_node("%Name"))
	assert_eq(header.column_text(CompanyRow.SORT_NAME), "NAME^")
	assert_eq(header.column_text(CompanyRow.SORT_PE), "P/E ")


# ---------------------------------------------------------- the company tab

## Clicking a row on the board opens that company on the Company tab (D103's
## gesture), with its regime named (§14 q8).
func test_clicking_a_row_opens_its_company_with_the_regime_named() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var company: CompanyState = _first_living_company()
	_click(_exchange().row_for(company.id))

	assert_eq(_tabs().current_tab(), MarketTabs.Tab.COMPANY)
	var tab: CompanyTab = _tabs().company_tab()
	assert_eq(tab.shown_id(), company.id)
	assert_string_contains(tab.identity_text(), MarketReadouts.regime_caption(_state(), company))
	assert_string_contains(tab.identity_text(), ", ")
	assert_string_contains(tab.identity_text(), " year")


func test_the_company_tab_shows_five_years_of_earnings() -> void:
	_start(GameMode.Value.STALKLEHEADS, 6)
	var company: CompanyState = _first_living_company()
	_tabs().show_company(company.id)
	var tab: CompanyTab = _tabs().company_tab()
	assert_eq(tab.years_line(), "EARNINGS Year 2 Year 3 Year 4 Year 5 Year 6")
	var history: Array[CompanyState] = MarketReadouts.company_history(_state(), company.id, 5)
	var revenue: PackedStringArray = ["Revenue"]
	for record: CompanyState in history:
		revenue.append(Palette.format_decimal(record.revenue, 0))
	assert_eq(tab.earnings_line(CompanyTab.Line.REVENUE), " ".join(revenue))


## D158 and §14 q7: Yearly Change includes the event, and the ledger breaks it
## down - so the ledger's total is the board's change, for every company.
func test_the_ledgers_total_is_the_boards_change() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	var latest: EarningsYearResult = _state().latest_result()
	for company: CompanyState in _state().market.companies:
		var ledger: PriceLedger = latest.ledger_for(company.id)
		if ledger == null or _state().stalk_by_id(company.id).is_bankrupt:
			continue
		_tabs().show_company(company.id)
		var lines: PackedStringArray = _tabs().company_tab().ledger().lines_text()
		var stalk: StalkState = _state().stalk_by_id(company.id)
		assert_eq(lines[lines.size() - 1], "Total %s" % Palette.format_change(stalk.last_yearly_change), String(company.id))
		assert_eq(lines[4], "This event %s" % Palette.format_change(ledger.this_years_event))


## The arrows walk the companies in the match's own order and wrap; sorting
## the board does not change it (F4 asked for this back, D184).
func test_the_arrows_walk_the_companies_and_wrap() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	_click_label(_exchange().get_node("%HeaderSlot").get_child(0).get_node("%Pe"))
	var order: Array[StringName] = []
	for stalk: StalkState in _state().stalks:
		order.append(stalk.id)
	_tabs().show_company(order[0])
	var tab: CompanyTab = _tabs().company_tab()
	tab.get_node("%NextButton").pressed.emit()
	assert_eq(tab.shown_id(), order[1])
	tab.get_node("%NextButton").pressed.emit()
	assert_eq(tab.shown_id(), order[2])
	tab.get_node("%PreviousButton").pressed.emit()
	tab.get_node("%PreviousButton").pressed.emit()
	tab.get_node("%PreviousButton").pressed.emit()
	assert_eq(tab.shown_id(), order[order.size() - 1], "wraps")


## Opening a company from a click lights COMPANY alone, not COMPANY and the
## tab the click came from.
## COMPANIES opens the list over the tab; a click picks a company and closes
## it; the NPC column counts the desk's holders.
func test_the_company_list_picks_a_company() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	_screen.size = Vector2(640, 360)
	var tabs: MarketTabs = _tabs()
	tabs.select_tab(MarketTabs.Tab.COMPANY)
	await wait_physics_frames(2)
	var tab: CompanyTab = tabs.company_tab()
	var width: float = tab.size.x
	tab.pick_button().pressed.emit()
	await wait_physics_frames(2)
	assert_true(tabs.is_picker_open())
	assert_eq(tab.size.x, width, "the tab is not squeezed")
	var picker: CompanyPicker = tabs.company_picker()
	assert_eq(picker.line_count(), _state().stalks.size())

	var counted: int = 0
	for company: CompanyState in _state().market.companies:
		var holders: int = MarketReadouts.npc_holder_count(_state(), company.id)
		var stalk: StalkState = _state().stalk_by_id(company.id)
		var expected: String = "%s %s" % [stalk.definition.ticker, stalk.definition.display_name]
		if holders > 0:
			expected += " %d" % holders
			counted += 1
		assert_eq(picker.line_text(company.id), expected)
	assert_gt(counted, 0, "by year 4 the desk holds something")

	var last: StringName = _state().stalks[_state().stalks.size() - 1].id
	picker.choose(last)
	assert_false(tabs.is_picker_open(), "closes on a pick")
	assert_eq(tab.shown_id(), last)
	tab.pick_button().pressed.emit()
	tab.pick_button().pressed.emit()
	assert_false(tabs.is_picker_open(), "the button closes it again")
	tab.pick_button().pressed.emit()
	tabs.select_tab(MarketTabs.Tab.MARKET)
	assert_false(tabs.is_picker_open(), "a tab change closes it")


func test_opening_a_company_lights_one_tab() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	_tabs().show_company(_first_living_company().id)
	for tab: MarketTabs.Tab in MarketTabs.CAPTIONS:
		assert_eq(_tabs().tab_button(tab).button_pressed, tab == MarketTabs.Tab.COMPANY, MarketTabs.CAPTIONS[tab])


## The Company tab says what you hold and trades from there.
func test_the_company_tab_trades_and_shows_what_you_hold() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _first_living_company()
	_tabs().show_company(company.id)
	var tab: CompanyTab = _tabs().company_tab()
	assert_eq(tab.held_text(), "HELD 0")
	tab.trade_box().type_amount("2")
	tab.trade_box().press_buy()
	assert_eq(_player().shares_of(company.id), 2)
	assert_eq(tab.held_text(), "HELD 2")


## E6 step 62: the industry has a column of its own, so the regime phrase
## never runs into it.
func test_the_identity_line_keeps_the_industry_whole() -> void:
	_start(GameMode.Value.STALKLEHEADS, 2)
	for company: CompanyState in _state().market.companies:
		_tabs().show_company(company.id)
		var cells: CellRow = _tabs().company_tab().get_node("%Identity")
		var name: String = _state().market.industry_by_id(company.profile.industry).definition.display_name
		assert_eq(cells.cell_text(1), name)
		assert_true(name.length() <= CompanyTab.IDENTITY_WIDTHS[1] - 1, "%s fits with a space" % name)


## The ledger's first line carries the year-on-year percentage.
func test_the_ledger_shows_the_year_on_year_move() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var company: CompanyState = _first_living_company()
	_tabs().show_company(company.id)
	var ledger: PriceLedger = (_state().latest_result() as EarningsYearResult).ledger_for(company.id)
	var expected: String = "%d -> %d %s" % [
		ledger.price_before, ledger.price_after,
		Palette.format_percent_change(MarketReadouts.percent_change(ledger.price_before, ledger.price_after)),
	]
	assert_eq(_tabs().company_tab().ledger().lines_text()[0], expected)


## §14 q11: the Company tab names each trader.
func test_the_company_tab_names_the_traders_who_traded_it() -> void:
	_start(GameMode.Value.STALKLEHEADS, 5)
	var named: int = 0
	for company: CompanyState in _state().market.companies:
		var activity: Array[Array] = MarketReadouts.desk_activity(_state(), company.id)
		if activity.is_empty():
			continue
		_tabs().show_company(company.id)
		var lines: PackedStringArray = _tabs().company_tab().activity_lines()
		assert_eq(lines.size(), activity.size() + 1, "a heading, then one line each")
		assert_eq(lines[0], "TRADER LAST YEAR NOW")
		var trader: NpcTraderState = _state().market.desk.trader_by_id(activity[0][0])
		var expected: String = "%s %s %s" % [
			trader.definition.display_name,
			Palette.sentence_case(MarketReadouts.situation_word(activity[0][1])),
			Palette.sentence_case(MarketReadouts.position_caption(activity[0][2], activity[0][3])),
		]
		assert_eq(lines[1], expected)
		named += 1
	assert_gt(named, 0, "some company should have desk activity")


func test_the_company_tab_lists_its_investors_by_name() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _first_living_company()
	_tabs().show_company(company.id)
	assert_eq(_tabs().company_tab().investors_text(), "None")
	_session.request_buy(&"p0", company.id, 1)
	_tabs().show_company(company.id)
	assert_eq(_tabs().company_tab().investors_text(), _player().display_name)


# ----------------------------------------------- the market and industries

func test_the_market_tab_charts_the_index_by_year() -> void:
	_start(GameMode.Value.STALKLEHEADS, 6)
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	var levels: Array[float] = MarketReadouts.index_levels(_state())
	var captions: PackedStringArray = []
	for year: int in levels.size():
		captions.append(str(year))
	assert_eq(
		_tabs().market_tab().index_chart().chart_text(),
		TextChart.bars(levels, captions, MarketTab.CHART_WIDTH, MarketTab.CHART_HEIGHT),
	)


func test_the_market_tabs_mood_row_marks_each_year() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var marks: PackedStringArray = []
	for result: YearResult in _state().history:
		marks.append("B" if result.mood == MarketMood.Value.BULL else "b")
	var lines: PackedStringArray = MarketTab.mood_chart_text(_state()).split("\n")
	assert_eq(lines[0], "1  2  3  4  5  6  7  8  9  10")
	assert_eq(lines[1], "%s  %s  %s  .  .  .  .  .  .  ." % [marks[0], marks[1], marks[2]])


func test_clicking_an_industry_selects_it_for_the_chart_and_the_breakdown() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	_tabs().select_tab(MarketTabs.Tab.INDUSTRIES)
	var tab: IndustriesTab = _tabs().industries_tab()
	var industry: IndustryState = _state().market.industries[2]
	var row: CellRow = null
	for child: Node in tab.get_node("%IndustryList").get_children():
		if (child as CellRow).key == industry.id:
			row = child
	_click(row)
	assert_eq(tab.selected(), industry.id)
	assert_string_contains(tab.industry_chart().title_text(), industry.definition.display_name.to_upper())
	assert_eq(tab.member_lines().size(), MarketReadouts.industry_members(_state(), industry.id).size())


## D183: a company shown on its own can be bought where it is shown.
func test_an_industrys_members_can_be_bought_from_the_breakdown() -> void:
	_start(GameMode.Value.STALKLEHEADS, 2)
	_tabs().select_tab(MarketTabs.Tab.INDUSTRIES)
	var tab: IndustriesTab = _tabs().industries_tab()
	var company: CompanyState = _first_living_company()
	var row: CellRow = null
	for child: Node in tab.get_node("%IndustryList").get_children():
		if (child as CellRow).key == company.profile.industry:
			row = child
	_click(row)
	var line: TradeLine = tab.member_line(company.id)
	line.trade_box().type_amount("4")
	line.trade_box().press_buy()
	assert_eq(_player().shares_of(company.id), 4)


# ---------------------------------------------------------------- the digest

## §6.3: the year's fundamentals in one panel, at the year turn.
func test_the_year_digest_opens_with_the_years_news() -> void:
	_start(GameMode.Value.STALKLEHEADS, 0)
	_session.set_ready(&"p0", true)
	assert_true(_screen.news_panel().is_open())
	var digest: YearDigest = YearDigest.for_latest_year(_state())
	var lines: PackedStringArray = _screen.year_digest().lines_text()
	assert_eq(lines[0], "THE YEAR IN REVIEW Year 1")
	assert_string_contains(lines[1], Palette.format_percent_change(digest.index_move_percent))
	assert_string_contains(lines[1], MarketMood.label(digest.mood))
	assert_true(_screen.year_digest().is_visible_in_tree())


## D183: with the news panel turned off, clicking the year's event still
## opens it, with the year in review, long event or short.
func test_clicking_the_event_opens_the_year_in_review() -> void:
	var stored: UserSettings = UserSettings.load_from()
	stored.show_news = false
	stored.save_to()
	_start(GameMode.Value.STALKLEHEADS, 2)
	assert_false(_screen.news_panel().is_open(), "turned off, so it did not open by itself")
	_click_label(_screen.get_node("%EventPanel"))
	assert_true(_screen.news_panel().is_open())
	assert_eq(_screen.year_digest().lines_text()[0], "THE YEAR IN REVIEW Year 2")
	assert_true(_screen.news_panel().dont_show_again_box().button_pressed, "shows the setting")


## The sentiment line says what it is: next year's sentiment, as a move.
func test_the_digest_names_next_years_sentiment() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var digest: YearDigest = YearDigest.for_latest_year(_state())
	_screen.news_panel().close()
	_click_label(_screen.get_node("%EventPanel"))
	assert_string_contains(
		_screen.year_digest().lines_text()[1],
		"Year 4 sentiment %s" % Palette.format_percent_change(digest.next_sentiment),
	)
	assert_eq(digest.next_sentiment, _state().market.sentiment)


func test_the_mood_line_carries_the_index_move() -> void:
	_start(GameMode.Value.STALKLEHEADS, 2)
	var latest: EarningsYearResult = _state().latest_result()
	assert_eq(
		_screen.get_node("%MoodLabel").text,
		"%s %s" % [MarketMood.label(latest.mood), Palette.format_percent_change(latest.index_move_percent)],
	)


# --------------------------------------------------------- what a client sees

## Everything a client shows is derived from what the wire sends (design §9.1):
## tabs built on a welcomed replica say exactly what the host's say.
func test_a_clients_tabs_say_what_the_hosts_do() -> void:
	var played: WireMatch = WireMatch.start(90210, 3, 30)
	played.play(9)
	var library: ContentLibrary = ContentLibrary.load_from()
	var replica: GameState = GameState.new(GameSettings.new())
	assert_eq(StateSync.apply_state(replica, StateSync.encode_state(played.state, 0), library), "")
	assert_eq(StateSync.apply_history(replica, StateSync.encode_history(played.state), library), "")

	var host_lines: PackedStringArray = _everything_shown(played.state)
	var client_lines: PackedStringArray = _everything_shown(replica)
	assert_eq(WireMatch.first_difference(host_lines, client_lines), "")
	assert_gt(host_lines.size(), 40)


func _everything_shown(state: GameState) -> PackedStringArray:
	var tabs: MarketTabs = TabsScene.instantiate()
	add_child_autofree(tabs)
	tabs.build(state)
	var player: PlayerState = state.players[0]
	tabs.refresh(state, player, true, state.latest_result().rankings, player.id, &"")
	var lines: PackedStringArray = []
	for stalk: StalkState in state.stalks:
		lines.append(tabs.exchange().row_for(stalk.id).line_text())
	for industry: IndustryState in state.market.industries:
		lines.append(tabs.exchange().group_row_for(industry.id).line_text())
	lines.append_array(tabs.side_panel().desk_lines())
	lines.append_array(tabs.side_panel().short_interest_lines())
	tabs.select_tab(MarketTabs.Tab.MARKET)
	lines.append(tabs.market_tab().index_chart().chart_text())
	for line: MarketTab.Line in MarketTab.Line.values():
		lines.append(tabs.market_tab().stat_line(line))
	tabs.select_tab(MarketTabs.Tab.INDUSTRIES)
	for industry: IndustryState in state.market.industries:
		lines.append(tabs.industries_tab().line_for(industry.id))
	for company: CompanyState in state.market.companies:
		tabs.show_company(company.id)
		var tab: CompanyTab = tabs.company_tab()
		lines.append(tab.identity_text())
		for line: CompanyTab.Line in CompanyTab.Line.values():
			lines.append(tab.earnings_line(line))
		lines.append_array(tab.ledger().lines_text())
		lines.append_array(tab.activity_lines())
	var digest: YearDigest = YearDigest.for_latest_year(state)
	lines.append("%s %s %s %s %s" % [
		digest.surprise_id, digest.disappointment_id, digest.dividend_cut_id,
		digest.desk_pick_id, digest.desk_pick_shares,
	])
	return lines


# ------------------------------------------------------------------- layout

## Every tab fits the 640 x 360 picture (design §7.1, §12.1): measured, not
## read. The screen is laid out at the game's size and nothing may ask for
## more width than it has.
func test_every_tab_fits_the_picture() -> void:
	_start(GameMode.Value.STALKLEHEADS, 6)
	_screen.size = Vector2(640, 360)
	for tab: MarketTabs.Tab in MarketTabs.CAPTIONS:
		_tabs().select_tab(tab)
		await wait_physics_frames(2)
		var needed: Vector2 = _screen.get_combined_minimum_size()
		assert_true(needed.x <= 640.0, "%s needs %d px across" % [MarketTabs.CAPTIONS[tab], needed.x])
		assert_true(needed.y <= 360.0, "%s needs %d px down" % [MarketTabs.CAPTIONS[tab], needed.y])
		# And with the side panel open over it (D184).
		if tab != MarketTabs.Tab.EXCHANGE:
			_tabs().side_button(SidePanel.Page.HOLDINGS).pressed.emit()
			await wait_physics_frames(2)
			needed = _screen.get_combined_minimum_size()
			assert_true(needed.x <= 640.0, "%s with the panel needs %d px across" % [MarketTabs.CAPTIONS[tab], needed.x])


## The board's columns are the design's widths (§7.2), so a header and a row
## line up: every column of the header starts where the row's does.
func test_the_header_lines_up_with_the_rows() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	_screen.size = Vector2(640, 360)
	await wait_physics_frames(2)
	var header: CompanyRow = _exchange().get_node("%HeaderSlot").get_child(0)
	var row: CompanyRow = _exchange().row_for(_first_living_company().id)
	for name: String in ["Price", "Change", "Eps", "Pe", "Dividend", "Held"]:
		var top: Control = header.get_node("%" + name)
		var below: Control = row.get_node("%" + name)
		assert_eq(top.global_position.x, below.global_position.x, "%s column" % name)
		assert_eq(top.size.x, below.size.x, "%s width" % name)


## A bankrupt row's word is wider than a price: the change column gives up its
## width, so "BANKRUPT" is whole and every later column stays put.
func test_a_bankrupt_row_shows_the_whole_word_and_keeps_its_columns() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _first_living_company()
	_state().stalk_by_id(company.id).is_bankrupt = true
	_screen.refresh()
	_screen.size = Vector2(640, 360)
	await wait_physics_frames(2)
	var row: CompanyRow = _exchange().row_for(company.id)
	var price: Label = row.get_node("%Price")
	var font: Font = price.get_theme_font("font")
	var font_size: int = price.get_theme_font_size("font_size")
	var needed: float = font.get_string_size("BANKRUPT", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	assert_eq(price.text, "BANKRUPT")
	assert_true(price.size.x >= needed, "BANKRUPT needs %d px, has %d" % [needed, price.size.x])
	var header: CompanyRow = _exchange().get_node("%HeaderSlot").get_child(0)
	for name: String in ["Eps", "Pe", "Dividend", "Held"]:
		assert_eq(
			header.get_node("%" + name).global_position.x,
			row.get_node("%" + name).global_position.x,
			"%s column" % name,
		)


## F5: no tooltip on the tabs is wider than TermTips.MAX_CHARS, so it stays by
## the pointer. A scrolling name's tooltip is the name itself and is exempt.
func test_every_tooltip_on_the_tabs_is_wrapped() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	var tabs: MarketTabs = _tabs()
	var checked: int = 0
	for tab: MarketTabs.Tab in MarketTabs.CAPTIONS:
		tabs.select_tab(tab)
		for node: Node in tabs.find_children("*", "Control", true, false):
			var control: Control = node as Control
			if control is MarqueeLabel or control.tooltip_text.is_empty() or not control.is_visible_in_tree():
				continue
			for line: String in control.tooltip_text.split("\n"):
				assert_true(
					line.length() <= TermTips.MAX_CHARS or not line.contains(" "),
					"%s: %s" % [control.name, line],
				)
			checked += 1
	assert_gt(checked, 20)


func test_fit_wraps_at_the_limit_and_keeps_line_breaks() -> void:
	var text: String = "one two three four five six seven eight nine ten eleven\nshort"
	var lines: PackedStringArray = TermTips.fit(text).split("\n")
	assert_eq(lines[lines.size() - 1], "short")
	for line: String in lines:
		assert_true(line.length() <= TermTips.MAX_CHARS, line)
	assert_eq(TermTips.fit(text).replace("\n", " "), text.replace("\n", " "))


## G4: marking the sorted column moves no heading - a right-aligned caption
## keeps its mark's space - and each heading is drawn as a cell.
func test_sorting_moves_no_heading() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var header: CompanyRow = _exchange().get_node("%HeaderSlot").get_child(0)
	var pe: Label = header.get_node("%Pe")
	assert_eq(pe.theme_type_variation, &"HeaderCell")
	var before: int = pe.text.length()
	_click_label(pe)
	assert_eq(pe.text.length(), before, "same length, so nothing shifts")
	assert_eq(pe.theme_type_variation, &"HeaderCellLit")
	pe.mouse_entered.emit()
	assert_eq(pe.theme_type_variation, &"HeaderCellHover", "lit under the mouse")
	pe.mouse_exited.emit()
	assert_eq(pe.theme_type_variation, &"HeaderCellLit")
	assert_string_contains(header.get_node("%Name").tooltip_text, "Click to sort")


## G4: an industry's header does not repeat its name as a tooltip.
func test_an_industry_header_has_no_name_tooltip() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	for child: Node in _exchange().find_children("*", "CompanyRow", true, false):
		var row: CompanyRow = child as CompanyRow
		if row.get_node("%Ticker").visible:
			continue
		assert_eq((row.get_node("%Name") as Control).tooltip_text, "")


## G2: the Company tab's title line stays put while the rest scrolls.
func test_the_company_title_line_is_pinned() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var tab: CompanyTab = _tabs().company_tab()
	var scroll: ScrollContainer = tab.get_node("Scroll")
	assert_false(scroll.is_ancestor_of(tab.pick_button()), "outside the scrolling part")
	assert_true(scroll.is_ancestor_of(tab.get_node("%Activity")))


## G2: the company list sorts by a heading, again reversed, ties in match order.
func test_the_company_list_sorts_by_its_headings() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	var tabs: MarketTabs = _tabs()
	tabs.select_tab(MarketTabs.Tab.COMPANY)
	tabs.company_tab().pick_button().pressed.emit()
	var picker: CompanyPicker = tabs.company_picker()
	var tickers: Array[String] = []
	for stalk: StalkState in _state().stalks:
		tickers.append(String(stalk.definition.ticker))
	tickers.sort()
	picker.press_heading(0)
	assert_eq(picker.header_text(), "SYM^ NAME NPC")
	var shown: Array[String] = []
	for id: StringName in picker.shown_order():
		shown.append(String(_state().stalk_by_id(id).definition.ticker))
	assert_eq(shown, tickers)
	picker.press_heading(2)
	picker.press_heading(2)
	assert_eq(picker.header_text(), "SYM NAME NPCv")
	var counts: Array[int] = []
	for id: StringName in picker.shown_order():
		counts.append(MarketReadouts.npc_holder_count(_state(), id))
	for index: int in counts.size() - 1:
		assert_true(counts[index] >= counts[index + 1], "most held first")


## G1: captions and phrases in the year in review start with a capital.
func test_the_year_in_review_is_capitalised() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var lines: PackedStringArray = _screen.year_digest().lines_text()
	assert_string_contains(lines[1], "The market")
	assert_string_contains(lines[1], "Market P/E")
	for line: String in lines:
		assert_false(line.begins_with("biggest") or line.begins_with("dividend cut") or line.begins_with("the desk"), line)
