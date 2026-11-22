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


## Buying through the board's own row: HELD goes up, the sell button appears.
func test_buying_through_a_row_fills_its_held_column() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _first_living_company()
	var row: CompanyRow = _exchange().row_for(company.id)
	assert_false(row.sell_is_shown(), "nothing to sell yet")

	row.type_amount("3")
	row.press_buy()

	assert_eq(_player().shares_of(company.id), 3)
	assert_eq(row.column_text(CompanyRow.SORT_HELD), "3")
	assert_true(row.sell_is_shown())


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
	assert_false(row.sell_is_shown())


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


# --------------------------------------------------------- the right strip

func test_the_strip_shows_cash_rankings_and_the_desk() -> void:
	_start(GameMode.Value.STALKLEHEADS, 3)
	assert_eq(_exchange().cash_text(), Palette.format_money(_player().cash))
	assert_eq(_exchange().ranking_row_count(), _state().players.size())
	var returns: Dictionary[NpcStrategy.Value, float] = MarketReadouts.desk_returns(_state())
	var lines: PackedStringArray = _exchange().desk_lines()
	assert_eq(lines.size(), returns.size())
	var best: NpcStrategy.Value = MarketReadouts.strategies_by_return(_state())[0]
	assert_eq(lines[0], "%s %s" % [
		NpcStrategy.name_of(best).to_lower(), Palette.format_percent_change(returns[best]),
	])


func test_the_strip_lists_short_interest() -> void:
	_start(GameMode.Value.STALKLEHEADS, 8)
	var expected: PackedStringArray = []
	for entry: Array in MarketReadouts.short_interest(_state()):
		expected.append("%s %d shares" % [_state().stalk_by_id(entry[0]).definition.ticker, entry[1]])
	assert_eq(_exchange().short_interest_lines(), expected)


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
	assert_eq(tab.years_line(), "EARNINGS yr2 yr3 yr4 yr5 yr6")
	var history: Array[CompanyState] = MarketReadouts.company_history(_state(), company.id, 5)
	var revenue: PackedStringArray = ["revenue"]
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
		assert_eq(lines[lines.size() - 1], "total %s" % Palette.format_change(stalk.last_yearly_change), String(company.id))
		assert_eq(lines[4], "this event %s" % Palette.format_change(ledger.this_years_event))


func test_the_arrows_walk_the_board_and_wrap() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var first: StringName = _state().stalks[0].id
	var last: StringName = _state().stalks[_state().stalks.size() - 1].id
	_tabs().show_company(first)
	_tabs().company_tab().get_node("%PreviousButton").pressed.emit()
	assert_eq(_tabs().company_tab().shown_id(), last)
	_tabs().company_tab().get_node("%NextButton").pressed.emit()
	assert_eq(_tabs().company_tab().shown_id(), first)


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
		assert_eq(lines.size(), activity.size())
		var trader: NpcTraderState = _state().market.desk.trader_by_id(activity[0][0])
		assert_string_contains(lines[0], trader.definition.display_name)
		named += 1
	assert_gt(named, 0, "some company should have desk activity")


func test_the_company_tab_lists_its_investors_by_name() -> void:
	_start(GameMode.Value.STALKLEHEADS, 1)
	var company: CompanyState = _first_living_company()
	_tabs().show_company(company.id)
	assert_eq(_tabs().company_tab().investors_text(), "none")
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


# ---------------------------------------------------------------- the digest

## §6.3: the year's fundamentals in one panel, at the year turn.
func test_the_year_digest_opens_with_the_years_news() -> void:
	_start(GameMode.Value.STALKLEHEADS, 0)
	_session.set_ready(&"p0", true)
	assert_true(_screen.news_panel().is_open())
	var digest: YearDigest = YearDigest.for_latest_year(_state())
	var lines: PackedStringArray = _screen.year_digest().lines_text()
	assert_eq(lines[0], "THE YEAR IN REVIEW year 1")
	assert_string_contains(lines[1], Palette.format_percent_change(digest.index_move_percent))
	assert_string_contains(lines[1], MarketMood.label(digest.mood))
	assert_true(_screen.year_digest().is_visible_in_tree())


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
	lines.append_array(tabs.exchange().desk_lines())
	lines.append_array(tabs.exchange().short_interest_lines())
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
