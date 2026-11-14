extends GutTest
## Scene-tree tests driving the real gameplay screen.
##
## These instantiate the actual .tscn, inject a session, and interact through the
## real controls — typing into a LineEdit and pressing a Button — rather than
## calling the session directly. That is what makes them worth having: they prove
## the *wiring* works, which no amount of simulation testing can.
##
## See docs/testing.md.

const ScreenScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")

var _screen: Control
var _session: LocalSession


func before_each() -> void:
	var library: ContentLibrary = ContentLibrary.load_from()

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.rng_seed = 20261114
	_session = LocalSession.create(settings, library)

	_screen = ScreenScene.instantiate()
	_screen.setup(_session)
	add_child_autofree(_screen)
	add_child_autofree(_session)


func _player() -> PlayerState:
	return _session.state().player_by_id(&"p0")


func _first_tradable_stalk() -> StalkState:
	for stalk: StalkState in _session.state().stalks:
		if stalk.has_value():
			return stalk
	return null


## Types into a row's amount field and presses its Buy button, the way a player
## would. `text_changed` has to be emitted by hand because setting `text` in code
## deliberately does not fire it.
func _buy_through_the_ui(row: StalkRow, amount: String) -> void:
	var field: LineEdit = row.get_node("%Amount")
	field.text = amount
	field.text_changed.emit(amount)
	(row.get_node("%BuyButton") as Button).pressed.emit()


func _sell_through_the_ui(row: HoldingRow, amount: String) -> void:
	var field: LineEdit = row.get_node("%Amount")
	field.text = amount
	field.text_changed.emit(amount)
	(row.get_node("%SellButton") as Button).pressed.emit()


# ------------------------------------------------------------------ construction

func test_the_screen_builds_a_row_for_every_stalk() -> void:
	for stalk: StalkState in _session.state().stalks:
		assert_not_null(_screen.stalk_row_for(stalk.id), "no row for %s" % stalk.id)


func test_the_header_shows_the_year_and_the_players_money() -> void:
	assert_eq((_screen.get_node("%YearLabel") as Label).text, "Year 1 of 10")
	assert_eq((_screen.get_node("%CashLabel") as Label).text, "$10,000")
	assert_eq((_screen.get_node("%NetWorthLabel") as Label).text, "$10,000")


func test_holdings_start_empty_with_an_explanation() -> void:
	assert_eq(_screen.holding_row_count(), 0)
	assert_true((_screen.get_node("%HoldingsEmpty") as Label).visible,
		"an empty board should say what to do, not just be blank")


func test_the_standings_list_the_player() -> void:
	assert_eq((_screen.get_node("%RankingList") as VBoxContainer).get_child_count(), 1)


func test_the_board_shows_prices_from_the_simulation() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	var row: StalkRow = _screen.stalk_row_for(stalk.id)
	assert_eq((row.get_node("%Price") as Label).text, Palette.format_money(stalk.price))


# ------------------------------------------------------------------------ buying

func test_buying_through_the_ui_updates_holdings_and_cash() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	var price: int = stalk.price
	var row: StalkRow = _screen.stalk_row_for(stalk.id)

	_buy_through_the_ui(row, "5")

	assert_eq(_player().shares_of(stalk.id), 5, "the simulation should hold 5 shares")
	assert_eq(_screen.holding_row_count(), 1, "the holdings board should show the position")
	assert_eq((_screen.get_node("%CashLabel") as Label).text,
		Palette.format_money(10000 - price * 5),
		"the header should show the reduced cash")
	assert_false((_screen.get_node("%HoldingsEmpty") as Label).visible)


func test_the_holdings_row_shows_shares_and_value() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	_buy_through_the_ui(_screen.stalk_row_for(stalk.id), "4")

	var row: HoldingRow = _screen.holding_row_for(stalk.id)
	assert_not_null(row)
	assert_eq((row.get_node("%Shares") as Label).text, "4")
	assert_eq((row.get_node("%Value") as Label).text,
		Palette.format_money(stalk.price * 4))


func test_an_unaffordable_purchase_tells_the_player_why() -> void:
	# The original failed silently here. See docs/game-rules.md §11.
	var stalk: StalkState = _first_tradable_stalk()
	_buy_through_the_ui(_screen.stalk_row_for(stalk.id), "99999")

	assert_false(_screen.current_message().is_empty(),
		"a refused purchase must say something")
	assert_eq(_player().shares_of(stalk.id), 0)


func test_pressing_buy_with_an_empty_field_prompts_rather_than_failing_silently() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	(_screen.stalk_row_for(stalk.id).get_node("%BuyButton") as Button).pressed.emit()
	assert_false(_screen.current_message().is_empty())


func test_the_buy_button_disables_live_while_typing_an_unaffordable_amount() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	var row: StalkRow = _screen.stalk_row_for(stalk.id)
	var field: LineEdit = row.get_node("%Amount")
	var button: Button = row.get_node("%BuyButton")

	field.text = "5"
	field.text_changed.emit("5")
	assert_false(button.disabled, "an affordable amount should stay enabled")

	field.text = "99999"
	field.text_changed.emit("99999")
	assert_true(button.disabled, "an unaffordable amount should disable the control")
	assert_false(button.tooltip_text.is_empty(), "and explain itself on hover")

	field.text = ""
	field.text_changed.emit("")
	assert_false(button.disabled, "an empty field is not an error")


func test_the_affordable_maximum_is_shown_as_a_hint() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	var row: StalkRow = _screen.stalk_row_for(stalk.id)
	var expected: int = TradeRules.max_affordable(_player(), stalk)
	assert_eq((row.get_node("%Amount") as LineEdit).placeholder_text, "max %d" % expected)


func test_the_amount_field_clears_after_a_successful_buy() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	var row: StalkRow = _screen.stalk_row_for(stalk.id)
	_buy_through_the_ui(row, "3")
	assert_eq((row.get_node("%Amount") as LineEdit).text, "",
		"a stale amount left in the field invites a double purchase")


# ----------------------------------------------------------------------- selling

func test_selling_through_the_ui_returns_cash() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	_buy_through_the_ui(_screen.stalk_row_for(stalk.id), "6")
	var cash_after_buy: int = _player().cash

	_sell_through_the_ui(_screen.holding_row_for(stalk.id), "6")

	assert_eq(_player().shares_of(stalk.id), 0)
	assert_gt(_player().cash, cash_after_buy)
	assert_eq(_screen.holding_row_count(), 0, "a closed position should leave the board")


func test_sell_all_closes_the_whole_position() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	_buy_through_the_ui(_screen.stalk_row_for(stalk.id), "7")

	var row: HoldingRow = _screen.holding_row_for(stalk.id)
	(row.get_node("%SellAllButton") as Button).pressed.emit()

	assert_eq(_player().shares_of(stalk.id), 0)
	assert_eq(_screen.holding_row_count(), 0)


func test_overselling_is_refused_with_a_message() -> void:
	var stalk: StalkState = _first_tradable_stalk()
	_buy_through_the_ui(_screen.stalk_row_for(stalk.id), "2")
	_sell_through_the_ui(_screen.holding_row_for(stalk.id), "10")

	assert_false(_screen.current_message().is_empty())
	assert_eq(_player().shares_of(stalk.id), 2, "the position should be untouched")


# ---------------------------------------------------------------- advancing time

func test_the_ready_button_advances_the_year_and_redraws() -> void:
	(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	assert_eq(_session.state().year, 2)
	assert_eq((_screen.get_node("%YearLabel") as Label).text, "Year 2 of 10")
	assert_false((_screen.get_node("%MoodLabel") as Label).text.is_empty(),
		"the year's mood should be on screen")


func test_a_special_event_is_shown_when_one_fires() -> void:
	var panel: PanelContainer = _screen.get_node("%EventPanel")
	assert_false(panel.visible, "no event before the first advance")

	# Advance until an event fires; with 45 events per pool this is immediate in
	# practice, but loop rather than assume.
	var guard: int = 0
	while not panel.visible and guard < 9:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()
		guard += 1

	assert_true(panel.visible, "an event should have fired within nine years")
	assert_false((_screen.get_node("%EventFlavour") as Label).text.is_empty())
	assert_false((_screen.get_node("%EventEffect") as Label).text.is_empty())
	assert_true((_screen.get_node("%EventEffect") as Label).text.contains("by"),
		"the effect line should name the movement")


func test_prices_on_the_board_track_the_simulation_after_a_year() -> void:
	(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	for stalk: StalkState in _session.state().stalks:
		var row: StalkRow = _screen.stalk_row_for(stalk.id)
		var shown: String = (row.get_node("%Price") as Label).text
		var expected: String = "—" if stalk.is_bankrupt else Palette.format_money(stalk.price)
		assert_eq(shown, expected, "%s price on screen" % stalk.id)


func test_a_bankrupt_stalk_is_marked_and_cannot_be_bought() -> void:
	# Play out a full match and check any stalk that failed is presented as such.
	while not _session.state().is_over:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	var found_bankrupt: bool = false
	for stalk: StalkState in _session.state().stalks:
		if not stalk.is_bankrupt:
			continue
		found_bankrupt = true
		var row: StalkRow = _screen.stalk_row_for(stalk.id)
		assert_true((row.get_node("%BankruptBanner") as Label).visible,
			"%s should show the bankrupt banner" % stalk.id)
		assert_false((row.get_node("%BuyButton") as Button).visible,
			"a bankrupt stalk should not offer a buy control")

	if not found_bankrupt:
		pass_test("no stalk went bankrupt in this seed; nothing to assert")


func test_the_game_over_message_names_the_winner() -> void:
	while not _session.state().is_over:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	assert_true(_screen.current_message().contains("Game over"),
		"got: %s" % _screen.current_message())
	assert_true((_screen.get_node("%ReadyButton") as Button).disabled,
		"there is nothing left to ready up for")


func test_the_final_year_button_says_what_it_does() -> void:
	while _session.state().year < _session.state().settings.max_years:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	assert_eq((_screen.get_node("%ReadyButton") as Button).text, "Finish Year 10",
		"the last advance is different and should say so")


func test_what_is_on_screen_matches_a_headless_simulation_of_the_same_seed() -> void:
	# The Phase 4 acceptance criterion: the UI invents nothing.
	while not _session.state().is_over:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	var library: ContentLibrary = ContentLibrary.load_from()
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.rng_seed = 20261114
	var headless: LocalSession = LocalSession.create(settings, library)
	add_child_autofree(headless)
	while not headless.state().is_over:
		headless.set_ready(&"p0", true)

	assert_eq(
		_session.state().player_by_id(&"p0").net_worth,
		headless.state().player_by_id(&"p0").net_worth,
		"the same seed played through the UI and headlessly must agree"
	)
	for stalk: StalkState in _session.state().stalks:
		assert_eq(stalk.price, headless.state().stalk_by_id(stalk.id).price,
			"%s price should match the headless run" % stalk.id)
