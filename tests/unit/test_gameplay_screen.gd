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

	# A match opens at Year 0 with trading closed. Ready up once so these tests
	# start where a player actually trades.
	_session.set_ready(&"p0", true)


## The board goes read-only once you have readied up.
##
## `TradeRules` is what actually refuses the trade; this is the other half,
## which stops a player being invited to press something that will be refused.
## A single-player game is the sharpest version of the test: readying ends the
## year immediately, so the only way to observe the state is to look at the
## controls on the way through. See decisions.md D97.
func test_readying_up_greys_out_the_board() -> void:
	# A fresh year, with the player not yet ready and a stalk worth buying.
	var stalk: StalkState = _first_tradable_stalk()
	assert_not_null(stalk, "the fixture should have something to trade")

	var row: StalkRow = _stalk_row_for(stalk.id)
	assert_not_null(row, "the board should have a row for it")
	assert_false(row.buy_is_blocked(), "buying is open before readying")

	_player().is_ready = true
	_screen.refresh()

	assert_true(row.buy_is_blocked(), "and closed once ready")


func _stalk_row_for(stalk_id: StringName) -> StalkRow:
	for node: Node in _screen.get_node("%StalkList").get_children():
		var row: StalkRow = node as StalkRow
		if row != null and row.stalk_id() == stalk_id:
			return row
	return null


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
	assert_eq((_screen.get_node("%YearLabel") as Label).text, "Year: 1/10")
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
	assert_eq((row.get_node("%Price") as Label).text, str(stalk.price))


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


func test_the_holdings_row_shows_how_many_are_owned() -> void:
	# Columns match the original: name and number owned. The price is not
	# repeated here — it is on the Available Stalks board. See ui-reference.md.
	var stalk: StalkState = _first_tradable_stalk()
	_buy_through_the_ui(_screen.stalk_row_for(stalk.id), "4")

	var row: HoldingRow = _screen.holding_row_for(stalk.id)
	assert_not_null(row)
	assert_eq((row.get_node("%Owned") as Label).text, "4")


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
	assert_eq((row.get_node("%Amount") as LineEdit).placeholder_text, str(expected),
		"just the number: the field is too narrow for \"max N\" plus digits")


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
	assert_eq((_screen.get_node("%YearLabel") as Label).text, "Year: 2/10")
	assert_false((_screen.get_node("%MoodLabel") as Label).text.is_empty(),
		"the year's mood should be on screen")


func test_the_event_panel_always_holds_its_space() -> void:
	# It stays visible whether or not an event fired, so the rest of the screen
	# does not jump down when one does. That jumping was a reported bug.
	var panel: PanelContainer = _screen.get_node("%EventPanel")
	assert_true(panel.visible, "the panel should be present before any advance")
	assert_false((_screen.get_node("%EventEffect") as Label).text.is_empty(),
		"it should say something rather than sit blank")

	for i: int in 3:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()
		assert_true(panel.visible, "the panel should never disappear")


func test_a_special_event_is_shown_when_one_fires() -> void:
	var flavour: Label = _screen.get_node("%EventFlavour")
	var effect: Label = _screen.get_node("%EventEffect")

	# With 45 events per pool one fires almost every year, but loop rather than
	# assume.
	var fired: bool = false
	var guard: int = 0
	while not fired and guard < 9:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()
		guard += 1
		fired = not flavour.text.is_empty()

	assert_true(fired, "an event should have fired within nine years")
	assert_true(effect.text.contains("by"),
		"the effect line should name the movement, got: %s" % effect.text)


func test_the_year_summary_reports_dividends_splits_and_bankruptcies() -> void:
	# These all happen in the simulation and used to be invisible, which made a
	# doubled share count look like a bug.
	var stalk: StalkState = _first_tradable_stalk()
	_buy_through_the_ui(_screen.stalk_row_for(stalk.id), "20")

	var mentioned: bool = false
	var guard: int = 0
	while not mentioned and guard < 10:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()
		guard += 1
		var summary: String = _screen.year_summary_text()
		mentioned = (
			summary.contains("Dividends")
			or summary.contains("Split")
			or summary.contains("Bankrupt")
		)

	assert_true(mentioned,
		"ten years with a position should have produced something to report")


func test_prices_on_the_board_track_the_simulation_after_a_year() -> void:
	(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	for stalk: StalkState in _session.state().stalks:
		var row: StalkRow = _screen.stalk_row_for(stalk.id)
		var shown: String = (row.get_node("%Price") as Label).text
		var expected: String = (
			"BNKRT" if stalk.is_bankrupt else str(stalk.price)
		)
		assert_eq(shown, expected, "%s price on screen" % stalk.id)


func test_the_board_header_columns_line_up_with_the_rows() -> void:
	# A reported bug: the header was built by hand and had one fewer child than
	# the rows, so it lost less to separations and every column sat 20px off.
	# The header is now the row widget in header mode, and the scrollbar width is
	# compensated for. This test is what stops either regressing.
	_screen.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame

	var header: StalkRow = (_screen.get_node("%BoardHeaderSlot") as Node).get_child(0)
	var row: StalkRow = _screen.stalk_row_for(_session.state().stalks[0].id)
	var header_cols: Node = header.get_node("Row")
	var row_cols: Node = row.get_node("Row")

	assert_eq(header_cols.get_child_count(), row_cols.get_child_count(),
		"header and row must have the same columns")

	for i: int in header_cols.get_child_count():
		var h: Control = header_cols.get_child(i)
		var r: Control = row_cols.get_child(i)
		assert_almost_eq(h.position.x, r.position.x, 1.0,
			"column %s is horizontally offset" % h.name)
		assert_almost_eq(h.size.x, r.size.x, 1.0,
			"column %s is a different width" % h.name)


func test_long_stalk_names_are_not_hard_clipped() -> void:
	# "My Pillow, Your Pillow, We're All Pillows!" overflowed its column and was
	# simply cut. It now trims with an ellipsis and keeps the full name on hover.
	for stalk: StalkState in _session.state().stalks:
		var row: StalkRow = _screen.stalk_row_for(stalk.id)
		var label: Label = row.get_node("%Name")
		assert_eq(label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS,
			"%s name should ellipsize rather than clip" % stalk.id)
		assert_eq(label.tooltip_text, stalk.definition.display_name,
			"the full name should always be available on hover")


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
		# The controls stay in the tree so the columns keep their width, but the
		# price reads BANKRUPT and buying is refused.
		assert_eq((row.get_node("%Price") as Label).text, "BNKRT",
			"%s should be marked bankrupt" % stalk.id)
		assert_true((row.get_node("%BuyButton") as Button).disabled,
			"a bankrupt stalk must not be buyable")

	if not found_bankrupt:
		pass_test("no stalk went bankrupt in this seed; nothing to assert")


func test_the_screen_announces_the_finished_match_outward() -> void:
	# The screen no longer writes a game-over line itself; it tells whoever owns
	# it, which shows the result screen. Keeps the screens ignorant of each other.
	watch_signals(_screen)
	while not _session.state().is_over:
		(_screen.get_node("%ReadyButton") as Button).pressed.emit()

	assert_signal_emitted(_screen, "match_finished")
	var params: Array = get_signal_parameters(_screen, "match_finished", 0)
	assert_eq((params[0] as Array)[0], &"p0", "the only player wins")
	assert_true((_screen.get_node("%ReadyButton") as Button).disabled,
		"there is nothing left to ready up for")


func test_every_row_has_identical_column_geometry() -> void:
	# A LineEdit's minimum width grows with its placeholder text, so rows whose
	# "max N" hints differ in length were silently getting different column
	# widths — the board looked ragged for a reason nothing in the scene showed.
	# Pinned here because it is invisible in the scene files.
	_screen.size = Vector2(640, 360)
	await get_tree().process_frame
	await get_tree().process_frame

	var reference: Array = []
	for stalk: StalkState in _session.state().stalks:
		var columns: Node = _screen.stalk_row_for(stalk.id).get_node("Row")
		var widths: Array = []
		for child: Node in columns.get_children():
			widths.append(roundf((child as Control).size.x))
		if reference.is_empty():
			reference = widths
		else:
			assert_eq(widths, reference,
				"%s has different column widths from the first row" % stalk.id)


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
