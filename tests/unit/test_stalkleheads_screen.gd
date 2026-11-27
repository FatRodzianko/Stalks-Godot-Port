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


## A click on a board row's name, which is what opens the Company tab.
func _click_name(row: CompanyRow) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = row.name_cell().get_global_rect().get_center()
	row._gui_input(press)


# ------------------------------------------------------------- which screen

## §14 q1: the base game's board is left alone. No tabs, no HELD column.
func test_a_base_game_match_keeps_its_three_boards() -> void:
	_start(GameMode.Value.BASE, 1)
	assert_null(_screen.market_tabs())
	assert_null(_screen.year_digest())
	assert_true(_screen.get_node("%Boards").visible)
	assert_false(_screen.get_node("%MarketSlot").visible)


func test_a_stalkleheads_match_shows_its_tabs_in_place_of_the_boards() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	assert_not_null(_tabs())
	assert_false(_screen.get_node("%Boards").visible)
	assert_true(_screen.get_node("%MarketSlot").visible)
	var captions: PackedStringArray = []
	for tab: MarketTabs.Tab in MarketTabs.CAPTIONS:
		captions.append(_tabs().tab_button(tab).text)
	assert_eq(captions, PackedStringArray(["EXCHANGE", "MARKET", "INDUSTRIES", "COMPANY", "MESSAGES"]))
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
		expected.append("%s %s" % [
			_state().stalk_by_id(entry[0]).definition.ticker, SidePanel.short_interest_words(_state(), entry[0]),
		])
	assert_eq(_tabs().side_panel().short_interest_lines(), expected)
	for line: String in expected:
		assert_true(line.contains("%"), "a percent of the company, not a share count (D213)")


func test_short_interest_words_say_flagged_and_squeezed() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _state().market.company_by_id(&"stryker")
	var desk: NpcDesk = _state().market.desk
	for trader: NpcTraderState in desk.traders:
		trader.set_short(&"stryker", 0)
	desk.traders[0].set_short(&"stryker", roundi(float(company.shares_outstanding) * 0.2))
	assert_eq(SidePanel.short_interest_words(_state(), &"stryker"), "20% FLAGGED")
	company.squeeze_premium = 10
	company.squeeze_years_left = 1
	assert_eq(SidePanel.short_interest_words(_state(), &"stryker"), "20% SQUEEZED")
	desk.traders[0].set_short(&"stryker", 0)
	assert_eq(SidePanel.short_interest_words(_state(), &"stryker"), "0% SQUEEZED", "covered, the lift still in")


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

## Only the symbol and the name open the Company tab: a click on the HELD
## figure or the trade box, at the row's far end, leaves the board (D208).
func test_clicking_a_row_away_from_its_name_stays_on_the_exchange() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var row: CompanyRow = _exchange().row_for(_first_living_company().id)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = row.get_global_rect().end - Vector2(2, 2)
	assert_false(row.opens_company_at(press.global_position))
	row._gui_input(press)
	assert_eq(_tabs().current_tab(), MarketTabs.Tab.EXCHANGE)


## Clicking a row on the board opens that company on the Company tab (D103's
## gesture), with its regime named (§14 q8).
func test_clicking_a_row_opens_its_company_with_the_regime_named() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var company: CompanyState = _first_living_company()
	_click_name(_exchange().row_for(company.id))

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
		var mark: String = CompanyPicker.NOT_OWNED_MARK
		if _player().shares_of(company.id) > 0:
			mark = CompanyPicker.OWNED_MARK
		var expected: String = "%s %s%s" % [stalk.definition.ticker, mark, stalk.definition.display_name]
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
	var chart: DrawnChart = _tabs().market_tab().index_chart()
	assert_eq(chart.kind(), DrawnChart.Kind.LINES, "a line since D188")
	assert_eq(chart.series().size(), 1)
	assert_eq(chart.series()[0].size(), levels.size())
	for year: int in levels.size():
		assert_almost_eq(chart.series()[0][year], levels[year], 0.01)
	assert_eq(chart.captions()[0], "0")
	assert_eq(chart.size, MarketTab.CHART_SIZE)


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
	assert_string_contains(tab.industry_chart_title(), industry.definition.display_name.to_upper())
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
	lines.append_array(tabs.side_panel().chatter_lines())
	lines.append(tabs.market_tab().headline_text())
	lines.append_array(tabs.market_tab().whisper_texts())
	tabs.select_tab(MarketTabs.Tab.MARKET)
	lines.append(tabs.market_tab().index_chart().summary())
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
		lines.append_array(tab.chatter_lines())
		lines.append_array(tab.news_lines())
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
	assert_eq(picker.header_text(), "SYM^ NAME (* OWNED) NPC")
	var shown: Array[String] = []
	for id: StringName in picker.shown_order():
		shown.append(String(_state().stalk_by_id(id).definition.ticker))
	assert_eq(shown, tickers)
	picker.press_heading(2)
	picker.press_heading(2)
	assert_eq(picker.header_text(), "SYM NAME (* OWNED) NPCv")
	var counts: Array[int] = []
	for id: StringName in picker.shown_order():
		counts.append(MarketReadouts.npc_holder_count(_state(), id))
	for index: int in counts.size() - 1:
		assert_true(counts[index] >= counts[index + 1], "most held first")


## G1: captions and phrases in the year in review start with a capital.
func test_the_year_in_review_is_capitalised() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var lines: PackedStringArray = _screen.year_digest().lines_text()
	assert_string_contains(lines[1], "The Market:")
	assert_string_contains(lines[1], "Market P/E")
	for line: String in lines:
		assert_false(line.begins_with("biggest") or line.begins_with("dividend cut") or line.begins_with("the desk"), line)


## H2: the longest description is shown whole; the tab is the only place it is.
func test_the_company_description_is_never_cut() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var longest: StalkState = _state().stalks[0]
	for stalk: StalkState in _state().stalks:
		if stalk.definition.description.length() > longest.definition.description.length():
			longest = stalk
	_tabs().show_company(longest.id)
	await wait_process_frames(2)
	var description: Label = _tabs().company_tab().get_node("%Description")
	assert_eq(description.text, longest.definition.description)
	assert_eq(description.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING)
	assert_true(description.max_lines_visible < 0, "no line limit")
	assert_gt(description.get_line_count(), 2, "long enough to have been cut before")
	assert_eq(description.get_visible_line_count(), description.get_line_count())


## H3: a heading's caption keeps clear of the lines either side of it, and
## the widest heading still fits its column.
func test_headings_keep_clear_of_their_lines() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var header: CompanyRow = _exchange().get_node("%HeaderSlot").get_child(0)
	for node: String in ["Ticker", "Name", "Price", "Change", "Eps", "Pe", "Dividend", "Held"]:
		var label: Label = header.get_node("%" + node)
		var box: StyleBox = label.get_theme_stylebox("normal")
		assert_gte(box.get_margin(SIDE_LEFT), 1.0, node)
		assert_gte(box.get_margin(SIDE_RIGHT), 1.0, node)
	var price: Label = header.get_node("%Price")
	_click_label(price)
	assert_eq(price.size.x, price.custom_minimum_size.x, "PRICE^ fits without widening")


## The industry chart's bars are green above zero and red below; the scale,
## the axis and the captions are not coloured.
func test_a_signed_chart_colours_its_bars_by_sign() -> void:
	var plain: String = TextChart.signed_bars([10.0, -10.0], PackedStringArray(["Y1", "Y2"]), 6, 1)
	var lines: PackedStringArray = ChartWidget.coloured_signed(plain, 1).split("\n")
	var gain: String = "[color=#%s]" % Palette.BULL.to_html(false)
	var loss: String = "[color=#%s]" % Palette.BEAR.to_html(false)
	assert_string_contains(lines[0], gain + "██[/color]")
	assert_false(lines[0].contains(loss))
	assert_false(lines[1].contains("[color"), "the axis is not coloured")
	assert_string_contains(lines[2], loss + "██[/color]")
	assert_false(lines[2].contains(gain))
	assert_false(lines[3].contains("[color"), "the captions are not coloured")


## D208: the industry's moves are drawn bars, every year played while they
## fit, each captioned.
func test_the_industry_chart_draws_every_year_that_fits() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	_tabs().select_tab(MarketTabs.Tab.INDUSTRIES)
	var chart: DrawnChart = _tabs().industries_tab().industry_chart()
	assert_eq(chart.kind(), DrawnChart.Kind.BARS)
	assert_eq(chart.captions(), PackedStringArray(["1", "2", "3", "4"]))
	assert_eq(chart.years_shown(), 4)


## Narrower than the years need, the chart keeps the latest ones.
func test_a_narrow_industry_chart_keeps_the_latest_years() -> void:
	var chart: DrawnChart = preload("res://src/ui/widgets/drawn_chart.tscn").instantiate()
	add_child_autofree(chart)
	var values: PackedFloat32Array = []
	var captions: PackedStringArray = []
	for year: int in range(1, 41):
		values.append(float(year % 7) - 3.0)
		captions.append(str(year))
	chart.size = Vector2(ChartGeometry.LABEL_CHARS * ChartGeometry.CELL_WIDTH + ChartGeometry.AXIS_GAP + 1 + 18 * 10, 96)
	chart.show_signed_bars(values, captions, captions)
	assert_eq(chart.years_shown(), 10)
	assert_eq(chart.captions()[9], "40", "the latest year is kept")


## D188: the earnings area opens on the table; each button swaps in its chart,
## the same size, over every year played.
func test_the_company_tab_charts_each_view() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	var company: CompanyState = _first_living_company()
	_tabs().show_company(company.id)
	_tabs().select_tab(MarketTabs.Tab.COMPANY)
	var tab: CompanyTab = _tabs().company_tab()
	var chart: DrawnChart = tab.company_chart()
	assert_eq(tab.shown_view(), CompanyTab.View.TABLE)
	assert_false(chart.visible)
	var kinds: Dictionary[CompanyTab.View, DrawnChart.Kind] = {
		CompanyTab.View.PRICE: DrawnChart.Kind.CANDLES,
		CompanyTab.View.SALES: DrawnChart.Kind.BARS,
		CompanyTab.View.MARGIN: DrawnChart.Kind.LINES,
		CompanyTab.View.PER_SHARE: DrawnChart.Kind.BARS,
		CompanyTab.View.PE: DrawnChart.Kind.LINES,
	}
	for view: CompanyTab.View in kinds:
		tab.select_view(view)
		assert_true(chart.visible, str(view))
		assert_false(tab.get_node("%Earnings").visible, "the table makes way")
		assert_eq(chart.kind(), kinds[view], str(view))
		assert_eq(chart.custom_minimum_size.x, float(CompanyTab.CHART_WIDTH))
		for each: CompanyTab.View in CompanyTab.View.values():
			var button: Button = tab.get_node("%Views").get_child(each)
			assert_eq(button.button_pressed, each == view, "one button lit")
	tab.select_view(CompanyTab.View.PRICE)
	assert_eq(chart.captions().size(), _state().year, "a candle a year, from year 1")
	tab.select_view(CompanyTab.View.SALES)
	assert_eq(chart.captions().size(), _state().year + 1, "from year 0")
	tab.select_view(CompanyTab.View.TABLE)
	assert_false(chart.visible)
	assert_true(tab.get_node("%Earnings").visible)


## D188: a candle opens where the year before closed, both restated on today's
## shares, so a split is not drawn as a crash.
func test_price_candles_join_up_and_are_split_adjusted() -> void:
	_start(GameMode.Value.STALKLEHEADS, 6)
	var company: CompanyState = _first_living_company()
	_tabs().show_company(company.id)
	_tabs().select_tab(MarketTabs.Tab.COMPANY)
	var tab: CompanyTab = _tabs().company_tab()
	tab.select_view(CompanyTab.View.PRICE)
	var opens: PackedFloat32Array = tab.company_chart().series()[0]
	var closes: PackedFloat32Array = tab.company_chart().series()[1]
	for index: int in range(1, opens.size()):
		assert_almost_eq(opens[index], closes[index - 1], 0.001, "year %d opens at last close" % (index + 1))
	var records: Array[CompanyState] = MarketReadouts.company_history(_state(), company.id, _state().year + 1)
	var last: CompanyState = records[records.size() - 1]
	assert_almost_eq(closes[closes.size() - 1], float(last.price), 0.001, "today's price is not restated")


func test_the_bond_has_no_chart_buttons() -> void:
	_start(GameMode.Value.STALKLEHEADS, 2)
	_tabs().show_company(EarningsMarket.BOND_ID)
	_tabs().select_tab(MarketTabs.Tab.COMPANY)
	var tab: CompanyTab = _tabs().company_tab()
	assert_false(tab.get_node("%Views").visible)
	assert_false(tab.company_chart().visible)


func test_dividends_and_industry_pe_by_year() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	var company: CompanyState = _first_living_company()
	assert_eq(MarketReadouts.dividend_in(_state(), company.id, 0), 0, "year 0 paid none")
	var latest: EarningsYearResult = _state().latest_result() as EarningsYearResult
	assert_eq(MarketReadouts.dividend_in(_state(), company.id, _state().year), latest.dividend_per_share.get(company.id, 0))
	var pe: float = MarketReadouts.industry_average_pe_in(_state(), company.profile.industry, _state().year)
	assert_false(is_nan(pe))
	assert_gt(pe, 0.0)


## D188: a chart takes exactly the table's height, so switching moves nothing
## below it.
func test_a_chart_is_as_tall_as_the_table() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	_tabs().show_company(_first_living_company().id)
	_tabs().select_tab(MarketTabs.Tab.COMPANY)
	var tab: CompanyTab = _tabs().company_tab()
	await wait_process_frames(2)
	var table: Control = tab.get_node("%Earnings")
	var before: float = tab.get_node("%YieldLine").global_position.y
	tab.select_view(CompanyTab.View.PRICE)
	await wait_process_frames(2)
	assert_eq(tab.company_chart().size.y, table.get_combined_minimum_size().y)
	assert_eq(tab.get_node("%YieldLine").global_position.y, before, "nothing below moved")


## D189: the Market tab shows the year in review too, narrow, under the mood,
## on a right half that scrolls on its own. Same lines as the news panel's, laid
## out in two columns of industries and two-line outliers.
func test_the_market_tab_shows_the_year_in_review() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	var review: YearDigestPanel = _tabs().market_tab().review()
	assert_true(review.visible)
	var lines: PackedStringArray = review.lines_text()
	assert_string_contains(lines[0], "THE YEAR IN REVIEW")
	assert_string_contains(lines[0], "Year %d" % _state().year)
	assert_string_contains(lines[1], "The Market:")
	assert_string_contains(lines[2], "Market P/E")
	assert_eq(review.get_node("%Industries").columns, 2)
	var scroll: ScrollContainer = _tabs().market_tab().get_node("%RightScroll")
	assert_true(scroll.is_ancestor_of(review), "inside the right half's own scroll")


func test_year_zero_has_no_review_on_the_market_tab() -> void:
	_start(GameMode.Value.STALKLEHEADS, 0)
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	assert_false(_tabs().market_tab().review().visible)


## D191: the company list marks what you own with * and says so in its heading.
func test_the_company_list_stars_what_you_own() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var owned: CompanyState = _first_living_company()
	_session.request_buy(_session.local_player_id(), owned.id, 1)
	var tabs: MarketTabs = _tabs()
	tabs.select_tab(MarketTabs.Tab.COMPANY)
	tabs.company_tab().pick_button().pressed.emit()
	var picker: CompanyPicker = tabs.company_picker()
	assert_string_contains(picker.header_text(), "NAME (* OWNED)")
	var owned_name: String = _state().stalk_by_id(owned.id).definition.display_name
	var starred: int = 0
	for line: String in picker.lines_text():
		if line.contains("*" + owned_name):
			starred += 1
		elif line.contains("*"):
			fail_test("only owned companies are starred: %s" % line)
	assert_eq(starred, 1)


# --------------------------------------------------------------- the news

## Phase S8 (design §8): the year's news where S7 left room for it.
func test_the_market_tab_shows_the_headline_and_the_whispers() -> void:
	_start(GameMode.Value.STALKLEHEADS, 6)
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	var latest: EarningsYearResult = _state().latest_result() as EarningsYearResult
	assert_not_null(latest.market_news, "the shipped market news fits every mood and move")
	assert_eq(_tabs().market_tab().headline_text(), latest.market_news.headline)
	assert_eq(_tabs().market_tab().event_texts()[0], latest.market_news.headline, "first in THIS YEAR'S NEWS")
	var expected: PackedStringArray = []
	for whisper: WhisperRound.Line in NewsSelector.latest_whispers(_state()).lines:
		expected.append("%s | %s" % [WhisperRules.SOURCE_NAMES[whisper.source], whisper.text])
	assert_eq(expected.size(), NewsSelector.WHISPERS_PER_YEAR)
	assert_eq(_tabs().market_tab().whisper_texts(), expected)


## Design §8.4: VIEW HISTORY opens every round so far over the right half,
## newest first, with each outcome once its year has been played, and leaving
## the tab closes it.
func test_view_history_lists_every_round_with_its_outcome() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	var tab: MarketTab = _tabs().market_tab()
	assert_false(tab.is_history_open())
	(tab.get_node("%HistoryButton") as Button).pressed.emit()
	assert_true(tab.is_history_open())
	var expected: PackedStringArray = []
	var rounds: Array[WhisperRound] = NewsSelector.whisper_history(_state())
	assert_eq(rounds.size(), 3, "heard after years 1, 2 and 3")
	rounds.reverse()
	for round: WhisperRound in rounds:
		expected.append("ABOUT YEAR %d" % round.about_year())
		for line: WhisperRound.Line in round.lines:
			var outcome: String = "Outcome: not known yet"
			if round.year < 3:
				outcome = "Outcome: %s" % WhisperRow.OUTCOME_WORDS[line.truth]
			expected.append("%s | %s | %s" % [WhisperRules.SOURCE_NAMES[line.source], line.text, outcome])
	assert_eq(tab.history_texts(), expected)
	(tab.get_node("%CloseHistoryButton") as Button).pressed.emit()
	assert_false(tab.is_history_open())
	(tab.get_node("%HistoryButton") as Button).pressed.emit()
	_tabs().select_tab(MarketTabs.Tab.EXCHANGE)
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	assert_false(tab.is_history_open(), "the tab opens on the current whispers")


## Nobody can trade in year 0, so no whispers then (decisions.md D207).
func test_no_whispers_before_trading_opens() -> void:
	_start(GameMode.Value.STALKLEHEADS, 0)
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	assert_eq(_tabs().market_tab().whisper_texts(), PackedStringArray())
	assert_false(_tabs().market_tab().get_node("%WhisperSection").visible)
	assert_eq(_tabs().market_tab().history_texts(), PackedStringArray())


func test_the_industries_tab_shows_the_selected_industrys_report() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	_tabs().select_tab(MarketTabs.Tab.INDUSTRIES)
	var tab: IndustriesTab = _tabs().industries_tab()
	var news: YearNews = NewsSelector.latest(_state())
	for industry: IndustryState in _state().market.industries:
		for child: Node in tab.get_node("%IndustryList").get_children():
			if (child as CellRow).key == industry.id:
				_click(child)
		assert_eq(tab.report_text(), news.industry_reports[industry.id])
		assert_eq(tab.outlook_text(), news.industry_report(industry.id), "the INDUSTRY REPORT (D212)")
		assert_false(tab.outlook_text().is_empty(), "the placeholders cover every band")


func test_the_industry_report_is_the_year_line_then_the_outlook() -> void:
	_start(GameMode.Value.STALKLEHEADS, 4)
	var news: YearNews = NewsSelector.latest(_state())
	for industry: IndustryState in _state().market.industries:
		assert_true(news.industry_years.has(industry.id), String(industry.id))
		assert_true(news.industry_outlooks.has(industry.id), String(industry.id))
		var report: String = news.industry_report(industry.id)
		assert_true(report.begins_with(news.industry_years[industry.id]), report)
		assert_true(report.ends_with(news.industry_outlooks[industry.id]), report)
		assert_true(report.contains(industry.definition.display_name), "the token is filled in")


func test_the_company_tab_shows_earnings_news_and_whispers() -> void:
	_start(GameMode.Value.STALKLEHEADS, 8)
	var news: YearNews = NewsSelector.latest(_state())
	var latest: EarningsYearResult = _state().latest_result() as EarningsYearResult
	for company: CompanyState in _state().market.companies:
		_tabs().show_company(company.id)
		var expected: PackedStringArray = []
		if news.earnings_surprise.has(company.id):
			expected.append("EARNINGS")
			expected.append(CompanyTab.earnings_news_line(latest.regimes[company.id], news.earnings_surprise[company.id]))
			if news.commentary.has(company.id):
				expected.append(news.commentary[company.id])
		if news.company_news.has(company.id):
			expected.append("IN THE NEWS")
			expected.append(news.company_news[company.id])
		var whispers: WhisperRound = NewsSelector.latest_whispers(_state())
		var about: Array[WhisperRound.Line] = whispers.lines_about(company.id)
		about.append_array(whispers.lines_about(company.profile.industry))
		if not about.is_empty():
			expected.append(CompanyTab.WHISPERS_HEADING)
		for whisper: WhisperRound.Line in about:
			expected.append("%s | %s" % [WhisperRules.SOURCE_NAMES[whisper.source], whisper.text])
		assert_eq(_tabs().company_tab().news_lines(), expected, String(company.id))


func test_the_earnings_line_names_the_regime_and_the_surprise() -> void:
	assert_eq(CompanyTab.earnings_news_line(EarningsRegime.Value.DISTRESS, NewsBands.Surprise.MUCH_WORSE),
		"Distress. Much worse than expected.")
	assert_eq(CompanyTab.earnings_news_line(EarningsRegime.Value.GROWTH, NewsBands.Surprise.AS_EXPECTED),
		"Growth. As expected.")


func test_a_living_company_has_its_own_news_every_year() -> void:
	# D211: the ported events and the general lines cover every move band.
	_start(GameMode.Value.STALKLEHEADS, 5)
	for year: int in range(1, 6):
		var news: YearNews = NewsSelector.news_for(_state(), year)
		var result: EarningsYearResult = MarketReadouts.result_for_year(_state(), year)
		for company_id: StringName in result.regimes:
			assert_true(news.company_news.has(company_id), "%s in year %d" % [company_id, year])


func test_chatter_sits_under_each_trader_and_on_the_desk_page() -> void:
	_start(GameMode.Value.STALKLEHEADS, 5)
	var news: YearNews = NewsSelector.latest(_state())
	var shown: int = 0
	for company: CompanyState in _state().market.companies:
		var activity: Array[Array] = MarketReadouts.desk_activity(_state(), company.id)
		_tabs().show_company(company.id)
		var expected: PackedStringArray = []
		for entry: Array in activity:
			expected.append(news.chatter[entry[0]])
		assert_eq(_tabs().company_tab().chatter_lines(), expected, String(company.id))
		shown += expected.size()
	assert_gt(shown, 0)

	var desk: PackedStringArray = []
	var latest: EarningsYearResult = _state().latest_result() as EarningsYearResult
	for trader_id: StringName in latest.desk.trader_ids:
		desk.append(_state().market.desk.trader_by_id(trader_id).definition.display_name)
		desk.append(news.chatter[trader_id])
	assert_eq(_tabs().side_panel().chatter_lines(), desk)


## §8.2 rule 3: a slot nothing fills shows nothing - not even its heading.
func test_news_nobody_has_written_shows_nothing() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	_state().market.news = NewsContent.new()
	_state().market.whisper_rounds.clear()
	_session.set_ready(&"p0", true)
	if _screen.news_panel() != null:
		_screen.news_panel().close()
	_tabs().select_tab(MarketTabs.Tab.MARKET)
	assert_eq(_tabs().market_tab().headline_text(), "")
	assert_eq(_tabs().market_tab().whisper_texts(), PackedStringArray())
	assert_false(_tabs().market_tab().get_node("%WhisperSection").visible)
	assert_eq(_tabs().market_tab().history_texts(), PackedStringArray())
	_tabs().select_tab(MarketTabs.Tab.INDUSTRIES)
	assert_eq(_tabs().industries_tab().report_text(), "")
	assert_false(_tabs().industries_tab().get_node("%ReportTitle").visible)
	_tabs().show_company(_first_living_company().id)
	# The EARNINGS line is worked out, not written, so it is all that is left.
	assert_eq(_tabs().company_tab().news_lines().size(), 2)
	assert_eq(_tabs().company_tab().news_lines()[0], "EARNINGS")
	assert_eq(_tabs().company_tab().chatter_lines(), PackedStringArray())
	assert_eq(_tabs().side_panel().chatter_lines(), PackedStringArray())
