extends GutTest
## Scene tests for the menu, the result screen, the loan panel, and the host that
## moves between them.

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")
const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")
const GameOverScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")


func _settings(years: int = 10, loans: bool = true, seed_value: int = 555) -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = years
	settings.player_count = 1
	settings.loans_enabled = loans
	settings.rng_seed = seed_value
	return settings


# ------------------------------------------------------------------- main menu

func test_the_menu_offers_the_documented_ranges() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)

	var years: SpinBox = menu.get_node("%YearsSpin")
	assert_eq(years.min_value, 2.0, "two years is the documented minimum")
	assert_eq(years.max_value, 99.0, "ninety-nine is the documented maximum")
	assert_eq(years.value, 10.0)


func test_the_menu_defaults_match_the_original_game() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)

	var settings: GameSettings = menu.chosen_settings()
	assert_eq(settings.max_years, 10)
	assert_eq(settings.starting_cash, 10000, "the original's default")
	assert_true(settings.loans_enabled)
	assert_eq(settings.player_count, 1)


func test_a_blank_seed_means_choose_one() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	assert_eq(menu.chosen_settings().rng_seed, 0,
		"zero tells the session to pick a seed and record it")


func test_a_typed_seed_is_used() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	(menu.get_node("%SeedField") as LineEdit).text = "4242"
	assert_eq(menu.chosen_settings().rng_seed, 4242)


func test_nonsense_in_the_seed_field_does_not_break_anything() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	(menu.get_node("%SeedField") as LineEdit).text = "not a number"
	assert_eq(menu.chosen_settings().rng_seed, 0)


func test_the_menu_settings_are_read_from_the_controls() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	(menu.get_node("%YearsSpin") as SpinBox).value = 25
	(menu.get_node("%CashSpin") as SpinBox).value = 5000
	(menu.get_node("%LoansCheck") as CheckBox).button_pressed = false

	var settings: GameSettings = menu.chosen_settings()
	assert_eq(settings.max_years, 25)
	assert_eq(settings.starting_cash, 5000)
	assert_false(settings.loans_enabled)


func test_pressing_start_emits_the_chosen_settings() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	watch_signals(menu)
	(menu.get_node("%YearsSpin") as SpinBox).value = 7

	(menu.get_node("%StartButton") as Button).pressed.emit()

	assert_signal_emitted(menu, "start_requested")
	var params: Array = get_signal_parameters(menu, "start_requested", 0)
	assert_eq((params[0] as GameSettings).max_years, 7)


# ------------------------------------------------------------ the screen host

func test_the_host_opens_on_the_menu() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	assert_true(main.current_screen() is MainMenu)


func test_starting_a_match_swaps_to_the_playing_screen() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	main.start_match(_settings())

	assert_false(main.current_screen() is MainMenu)
	assert_not_null(main.session())
	assert_eq(main.session().state().year, 1)


func test_only_one_screen_exists_at_a_time() -> void:
	# The old screen is removed from the tree immediately, not just queued, so
	# nothing ever sees two screens at once.
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	main.start_match(_settings())

	var screens: int = 0
	for child: Node in main.get_children():
		if child is MainMenu or child is GameOverScreen:
			screens += 1
		elif child.get_script() != null and child.has_method("stalk_row_for"):
			screens += 1
	assert_eq(screens, 1, "exactly one screen should be mounted")


func test_finishing_a_match_shows_the_result_screen() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings(2))

	var session: LocalSession = main.session()
	while not session.state().is_over:
		session.set_ready(&"p0", true)

	assert_true(main.current_screen() is GameOverScreen,
		"the result screen should take over when the match ends")


func test_returning_to_the_menu_discards_the_session() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings())
	assert_not_null(main.session())

	main.show_menu()

	assert_true(main.current_screen() is MainMenu)
	assert_null(main.session(), "a finished match should not linger")


func test_play_again_starts_a_fresh_market_rather_than_a_replay() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings(2, true, 999))
	var first_seed: int = main.session().seed_value()

	var session: LocalSession = main.session()
	while not session.state().is_over:
		session.set_ready(&"p0", true)

	var over: GameOverScreen = main.current_screen()
	(over.get_node("%PlayAgainButton") as Button).pressed.emit()

	assert_not_null(main.session())
	assert_ne(main.session().seed_value(), first_seed,
		"play again should be a new market, not the same one over")


# ------------------------------------------------------------- result screen

func _finished_state(years: int = 2) -> LocalSession:
	var session: LocalSession = LocalSession.create(
		_settings(years), ContentLibrary.load_from()
	)
	add_child_autofree(session)
	while not session.state().is_over:
		session.set_ready(&"p0", true)
	return session


func test_the_result_screen_names_the_winner_and_the_outcome() -> void:
	var session: LocalSession = _finished_state()
	var over: GameOverScreen = GameOverScene.instantiate()
	add_child_autofree(over)
	over.display(session.state(), &"p0")

	assert_true(over.verdict_text().contains("wins"), "got: %s" % over.verdict_text())
	assert_true(over.detail_text().contains("finished on"), "got: %s" % over.detail_text())
	assert_eq(over.ranking_count(), 1)


func test_the_result_screen_shows_the_seed_for_reproducing_the_match() -> void:
	var session: LocalSession = _finished_state()
	var over: GameOverScreen = GameOverScene.instantiate()
	add_child_autofree(over)
	over.display(session.state(), &"p0")

	assert_true((over.get_node("%SeedLabel") as Label).text.contains("555"))


func test_the_result_screen_emits_rather_than_restarting_itself() -> void:
	var session: LocalSession = _finished_state()
	var over: GameOverScreen = GameOverScene.instantiate()
	add_child_autofree(over)
	over.display(session.state(), &"p0")
	watch_signals(over)

	(over.get_node("%PlayAgainButton") as Button).pressed.emit()
	assert_signal_emitted(over, "play_again_requested")

	(over.get_node("%MenuButton") as Button).pressed.emit()
	assert_signal_emitted(over, "menu_requested")


# ---------------------------------------------------------------- loan panel

func _playing(loans: bool = true) -> Array:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings(10, loans))
	return [main, main.current_screen(), main.session()]


func test_the_loan_button_is_hidden_when_loans_are_disabled() -> void:
	var bits: Array = _playing(false)
	var screen: Control = bits[1]
	assert_false((screen.get_node("%LoanButton") as Button).visible)


func test_the_loan_button_invites_borrowing_before_any_loan() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var button: Button = screen.get_node("%LoanButton")
	assert_true(button.visible)
	assert_true(button.text.contains("Take a loan"), "got: %s" % button.text)


func test_borrowing_through_the_panel_pays_out_cash() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	# Loans open in year 2.
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var panel: LoanPanel = screen.loan_panel()
	(screen.get_node("%LoanButton") as Button).pressed.emit()
	assert_true(panel.is_showing())

	var player: PlayerState = session.state().player_by_id(&"p0")
	var cash_before: int = player.cash
	(panel.get_node("%MaxButton") as Button).pressed.emit()
	(panel.get_node("%BorrowButton") as Button).pressed.emit()

	assert_true(player.has_outstanding_loan())
	assert_gt(player.cash, cash_before, "borrowing pays out immediately")


func test_the_panel_refuses_a_loan_before_year_two() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var panel: LoanPanel = screen.loan_panel()
	panel.show_panel()

	assert_false(panel.warning_text().is_empty(),
		"the panel should explain why borrowing is unavailable yet")


func test_the_header_shows_what_is_owed_once_borrowed() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var player: PlayerState = session.state().player_by_id(&"p0")
	session.request_loan(&"p0", LoanRules.max_loan_for(player))

	assert_true((screen.get_node("%LoanBox") as VBoxContainer).visible,
		"an outstanding loan should be visible in the header")
	assert_eq((screen.get_node("%LoanOwedLabel") as Label).text,
		Palette.format_money(player.owes()))


func test_the_loan_button_becomes_a_payment_prompt_when_one_is_due() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	# A loan taken this year counts as paid; advance so a payment comes due.
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var button: Button = screen.get_node("%LoanButton")
	assert_true(button.text.contains("payment due"), "got: %s" % button.text)


func test_a_player_can_still_ready_up_with_a_payment_outstanding() -> void:
	# The prompt is advisory. The game must never take the choice away.
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var year_before: int = session.state().year
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	assert_eq(session.state().year, year_before + 1,
		"readying up with a payment due must be allowed")


func test_paying_the_minimum_through_the_panel_reduces_the_balance() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var player: PlayerState = session.state().player_by_id(&"p0")
	var owed_before: int = player.owes()
	var panel: LoanPanel = screen.loan_panel()
	panel.show_panel()
	(panel.get_node("%PayMinimumButton") as Button).pressed.emit()

	assert_lt(player.owes(), owed_before)
	assert_true(player.loan.paid_this_year)


func test_the_panel_warns_about_the_consequence_of_missing_a_payment() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var panel: LoanPanel = screen.loan_panel()
	panel.show_panel()
	assert_true(panel.warning_text().contains("10%"),
		"the first miss costs 10%%; got: %s" % panel.warning_text())
