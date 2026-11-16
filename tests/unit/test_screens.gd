extends GutTest
## Scene tests for the menu, the result screen, the loan panel, and the host that
## moves between them.

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")
const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")
const GameOverScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")
const OnlineGamesScene: PackedScene = preload(
	"res://src/ui/screens/online_games/online_games_screen.tscn"
)


func _settings(years: int = 10, loans: bool = true, seed_value: int = 555) -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = years
	settings.player_count = 1
	settings.loans_enabled = loans
	settings.rng_seed = seed_value
	return settings


# --------------------------------------------------- the root must fill the window
#
# These exist because of a bug that shipped: Main's root is a MarginContainer,
# and a container lays out its CHILDREN — but when it is itself the scene root
# its parent is the viewport, not another container, so it needs full-rect
# anchors of its own. Without them it shrink-wrapped to its minimum size and the
# game drew in a small box in the corner of the window.
#
# The earlier layout checks missed it because they set the screen's size by hand
# before measuring, which is precisely the step that was broken. These put the
# scene in a real viewport and let Godot size it.

## Puts a scene in a viewport of a known size and lets layout settle, which is
## the only way to test that a root actually fills its window.
func _in_viewport(scene: PackedScene, size: Vector2i) -> Array:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	add_child_autofree(viewport)
	var node: Control = scene.instantiate()
	viewport.add_child(node)
	await get_tree().process_frame
	await get_tree().process_frame
	return [viewport, node]


func test_the_scene_root_fills_its_viewport() -> void:
	var bits: Array = await _in_viewport(MainScene, Vector2i(1280, 720))
	var main: Control = bits[1]
	assert_eq(main.size, Vector2(1280, 720),
		"the root must fill the window, not shrink-wrap to its content")


func test_the_scene_root_fills_a_differently_shaped_window() -> void:
	var bits: Array = await _in_viewport(MainScene, Vector2i(1920, 1080))
	var main: Control = bits[1]
	assert_eq(main.size, Vector2(1920, 1080))


func test_the_root_has_the_anchors_that_make_that_work() -> void:
	# Asserting the mechanism as well as the result, so a failure says why.
	var main: Control = MainScene.instantiate()
	add_child_autofree(main)
	assert_eq(main.anchor_right, 1.0, "root needs a full-rect right anchor")
	assert_eq(main.anchor_bottom, 1.0, "root needs a full-rect bottom anchor")


func test_the_playing_screen_fills_the_window_through_the_host() -> void:
	# The whole chain: viewport -> Main -> gameplay screen.
	var bits: Array = await _in_viewport(MainScene, Vector2i(1280, 720))
	var main: Main = bits[1]
	main.start_match(_settings())
	await get_tree().process_frame
	await get_tree().process_frame

	var screen: Control = main.current_screen()
	assert_eq(screen.size, Vector2(1280, 720),
		"the playing screen should fill the window too")

	# And the board should therefore have room for all ten stalks.
	var list: VBoxContainer = screen.get_node("%StalkList")
	assert_eq(list.get_child_count(), 10)
	var scroll: ScrollContainer = screen.get_node("%StalkScroll")
	assert_gt(scroll.size.y, 300.0,
		"the market board should get real height, not a sliver")


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


func test_pressing_single_player_emits_the_chosen_settings() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	watch_signals(menu)
	(menu.get_node("%YearsSpin") as SpinBox).value = 7

	(menu.get_node("%SinglePlayerButton") as Button).pressed.emit()

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
	assert_eq(main.session().state().year, 0, "a match opens at year 0")


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

	# "You win" in a solo game, not "wins": the player is literally called
	# "You". The third-person wording is covered by its own test below.
	assert_eq(over.verdict_text(), "You win", "got: %s" % over.verdict_text())
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

## Starts a match and returns [host, screen, session].
##
## A match opens at Year 0 with trading closed, and loans only become available
## from Year 2, so `advance_to` readies up that many times.
func _playing(loans: bool = true, advance_to: int = 0) -> Array:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings(10, loans))
	var screen: Control = main.current_screen()
	while main.session().state().year < advance_to:
		(screen.get_node("%ReadyButton") as Button).pressed.emit()
	return [main, screen, main.session()]


func test_the_loan_button_is_hidden_when_loans_are_disabled() -> void:
	var bits: Array = _playing(false)
	var screen: Control = bits[1]
	# Visibility is set on the box that holds the button and the minimum
	# payment under it, so ask whether the button can actually be seen rather
	# than whether its own flag is set.
	assert_false((screen.get_node("%LoanButton") as Button).is_visible_in_tree())


func test_the_loan_button_invites_borrowing_before_any_loan() -> void:
	var bits: Array = _playing()
	var screen: Control = bits[1]
	var button: Button = screen.get_node("%LoanButton")
	assert_true(button.visible)
	assert_true(button.text.to_lower().contains("loan"), "got: %s" % button.text)


func test_borrowing_through_the_panel_pays_out_cash() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]

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
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]

	var player: PlayerState = session.state().player_by_id(&"p0")
	session.request_loan(&"p0", LoanRules.max_loan_for(player))

	# What is owed now sits under Your Stats, where the original kept the
	# player's figures. See docs/ui-reference.md.
	var owed: Label = screen.get_node("%LoanOwedLabel")
	assert_true(owed.visible, "an outstanding loan should be shown with your stats")
	assert_true(owed.text.contains(Palette.format_money(player.owes())),
		"got: %s" % owed.text)


func test_the_loan_button_becomes_a_payment_prompt_when_one_is_due() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	# A loan taken this year counts as paid; advance so a payment comes due.
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var button: Button = screen.get_node("%LoanButton")
	assert_true(button.text.to_lower().contains("pay"), "got: %s" % button.text)


func test_a_player_can_still_ready_up_with_a_payment_outstanding() -> void:
	# The prompt is advisory. The game must never take the choice away — it now
	# asks first (D53), but saying yes still goes through.
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var year_before: int = session.state().year
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	var confirm: ConfirmPanel = screen.confirm_panel()
	assert_true(confirm.is_open(), "it should ask before costing the player 10%")
	assert_eq(session.state().year, year_before, "and not advance until answered")

	(confirm.get_node("%ConfirmButton") as Button).pressed.emit()
	assert_eq(session.state().year, year_before + 1,
		"readying up with a payment due must be allowed")


func test_the_prompt_lets_a_player_go_back_and_pay() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var year_before: int = session.state().year
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	var confirm: ConfirmPanel = screen.confirm_panel()
	(confirm.get_node("%CancelButton") as Button).pressed.emit()

	assert_false(confirm.is_open(), "the prompt should close")
	assert_eq(session.state().year, year_before, "and nothing should have happened")
	assert_false(
		session.state().player_by_id(&"p0").is_ready,
		"the player should not be left readied",
	)


func test_the_prompt_names_what_it_will_cost() -> void:
	# "Are you sure?" without a consequence is noise.
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var message: String = screen.confirm_panel().get_node("%Message").text
	assert_string_contains(message, "10%", "the first miss costs 10%")


func test_readying_up_without_a_loan_asks_nothing() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]

	var year_before: int = session.state().year
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	assert_false(
		screen.confirm_panel().is_open(),
		"nothing is owed, so there is nothing to confirm",
	)
	# Solo, so readying is the only thing the year was waiting on and the flag
	# is cleared again by the advance.
	assert_eq(session.state().year, year_before + 1, "it should just go ahead")


func test_paying_the_minimum_through_the_panel_reduces_the_balance() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
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
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var panel: LoanPanel = screen.loan_panel()
	panel.show_panel()
	assert_true(panel.warning_text().contains("10%"),
		"the first miss costs 10%%; got: %s" % panel.warning_text())


# ------------------------------------------------- borrowing should not confuse
#
# Reported from play: "when you click borrow, you're immediately prompted about
# paying your loan. It's not clear if you need to pay it back that year."

func _with_a_fresh_loan() -> Array:
	var bits: Array = _playing(true, 2)
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	return bits


func test_a_brand_new_loan_says_nothing_is_due_yet() -> void:
	# The pay controls appear the moment you borrow, which reads as a demand for
	# money you have only just received.
	var bits: Array = _with_a_fresh_loan()
	var screen: Control = bits[1]
	screen.get_node("%LoanButton").pressed.emit()

	var warning: String = screen.loan_panel().get_node("%Warning").text
	assert_string_contains(warning.to_lower(), "next year")


func test_the_greyed_pay_minimum_button_says_why() -> void:
	# A disabled button with no reason given reads as broken.
	var bits: Array = _with_a_fresh_loan()
	var screen: Control = bits[1]
	screen.get_node("%LoanButton").pressed.emit()

	var button: Button = screen.loan_panel().get_node("%PayMinimumButton")
	assert_true(button.disabled, "nothing is owed yet")
	assert_string_contains(button.tooltip_text.to_lower(), "next year")


func test_paying_early_is_still_allowed_on_a_fresh_loan() -> void:
	# The minimum is already satisfied, but paying down the balance is not.
	# This is why the manual field stays usable while the button is greyed.
	var bits: Array = _with_a_fresh_loan()
	var session: LocalSession = bits[2]
	var loan: LoanState = session.state().player_by_id(&"p0").loan
	var owed_before: int = loan.balance

	# At least the minimum: partial payments are refused outright, which is why
	# the field says "min N" rather than accepting any figure.
	session.pay_loan(&"p0", loan.min_payment)

	assert_lt(
		session.state().player_by_id(&"p0").loan.balance, owed_before,
		"an early payment should still reduce the balance",
	)


func test_a_payment_below_the_minimum_is_refused_with_a_reason() -> void:
	# What the player sees if they type a small number into the field that stays
	# usable while "Pay minimum" is greyed.
	var bits: Array = _with_a_fresh_loan()
	var session: LocalSession = bits[2]
	var refusals: Array[String] = []
	session.action_rejected.connect(
		func(_id: StringName, reason: String) -> void: refusals.append(reason)
	)

	session.pay_loan(&"p0", 1)

	assert_eq(refusals.size(), 1)
	if refusals.size() == 1:
		assert_string_contains(refusals[0].to_lower(), "minimum")


# --------------------------------------------- the prompt should say where you are

func test_the_prompt_counts_the_misses_already_on_record() -> void:
	# A bare percentage does not tell a player whether this is a nuisance or the
	# end of their game.
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	var loan: LoanState = session.state().player_by_id(&"p0").loan
	loan.paid_this_year = false
	loan.missed_payments = 1

	screen.get_node("%ReadyButton").pressed.emit()

	var message: String = screen.confirm_panel().get_node("%Message").text
	assert_string_contains(message.to_lower(), "missed 1")
	assert_string_contains(message, "15%", "a second miss costs 15%")


func test_the_prompt_warns_when_the_next_miss_ends_the_game() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	var loan: LoanState = session.state().player_by_id(&"p0").loan
	loan.paid_this_year = false
	loan.missed_payments = 2

	screen.get_node("%ReadyButton").pressed.emit()

	var message: String = screen.confirm_panel().get_node("%Message").text.to_lower()
	assert_string_contains(message, "seized")


func test_choosing_to_pay_first_opens_the_loan_panel() -> void:
	# Closing the question and leaving the player to find the button themselves
	# is most of the way to not asking at all.
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	session.state().player_by_id(&"p0").loan.paid_this_year = false

	screen.get_node("%ReadyButton").pressed.emit()
	assert_true(screen.confirm_panel().is_open())
	(screen.confirm_panel().get_node("%CancelButton") as Button).pressed.emit()

	assert_true(screen.loan_panel().is_showing(), "it should take you there")


# ------------------------------------------- the loan panel is an errand, not a place

func test_borrowing_closes_the_panel() -> void:
	# It used to stay open and switch to its pay controls, which reads as being
	# asked for money you have just this moment received.
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	screen.get_node("%LoanButton").pressed.emit()
	assert_true(screen.loan_panel().is_showing())

	screen.loan_panel().borrow_requested.emit(
		LoanRules.max_loan_for(session.state().player_by_id(&"p0"))
	)

	assert_false(screen.loan_panel().is_showing(), "the errand is done")
	assert_string_contains(screen.current_message().to_lower(), "borrowed")


func test_the_board_says_when_the_first_payment_falls_due() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	screen.loan_panel().borrow_requested.emit(
		LoanRules.max_loan_for(session.state().player_by_id(&"p0"))
	)
	assert_string_contains(screen.current_message().to_lower(), "next year")


func test_paying_closes_the_panel_and_reports_what_is_left() -> void:
	var bits: Array = _with_a_fresh_loan()
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	screen.get_node("%LoanButton").pressed.emit()

	screen.loan_panel().payment_requested.emit(
		session.state().player_by_id(&"p0").loan.min_payment
	)

	assert_false(screen.loan_panel().is_showing())
	assert_string_contains(screen.current_message().to_lower(), "still owed")


func test_a_refused_borrow_keeps_the_panel_open_and_says_why_in_it() -> void:
	# The message line is covered while the panel is open, so a refusal reported
	# there would be invisible.
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	screen.get_node("%LoanButton").pressed.emit()

	# Far more than 25% of net worth.
	screen.loan_panel().borrow_requested.emit(999999)

	assert_true(screen.loan_panel().is_showing(), "it should stay open to be fixed")
	assert_ne(screen.loan_panel().warning_text(), "", "with the reason inside it")


func test_a_refused_payment_keeps_the_panel_open() -> void:
	var bits: Array = _with_a_fresh_loan()
	var screen: Control = bits[1]
	screen.get_node("%LoanButton").pressed.emit()

	screen.loan_panel().payment_requested.emit(1)

	assert_true(screen.loan_panel().is_showing())
	assert_string_contains(screen.loan_panel().warning_text().to_lower(), "minimum")


# ------------------------------------------- the bottom bar holds its height
#
# Reported from play: the bottom bar was taller in year 0 than afterwards,
# because of the amount of text. It should be static.
#
# The year-0 explanation wraps onto a second line and later messages fit on
# one, so the bar shrank after the first year and the boards above it jumped
# down to fill the gap. The fix reserves the tallest the bar can ever be.

## The bar, measured in the design resolution. A wider viewport gives the text
## room to fit on one line, which would make this test pass without proving
## anything — 640x360 is what the game actually runs at.
func _bar_height(screen: Control) -> float:
	return (screen.get_node("Root/BottomBar") as Control).size.y


## Walks a match through every state the bar has to survive and insists the
## height never changes. One screen throughout, so this is the player's own
## experience of it rather than a comparison between two separate games.
func test_the_bottom_bar_holds_one_height_for_a_whole_match() -> void:
	var bits: Array = await _in_viewport(MainScene, Vector2i(640, 360))
	var main: Main = bits[1]
	main.start_match(_settings())
	await get_tree().process_frame
	await get_tree().process_frame

	var screen: GameplayScreen = main.current_screen()
	var session: LocalSession = main.session()
	var ready_button: Button = screen.get_node("%ReadyButton")
	var settled: float = _bar_height(screen)
	assert_gt(settled, 0.0, "the bar should have a height to compare against")

	# Year 0 is the tall case: the opening explanation wraps onto two lines
	# where later messages fit on one.
	assert_string_contains(screen.info_text().to_lower(), "year 0",
		"the test needs the long opening text to be on screen")

	ready_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(_bar_height(screen), settled, "year 1 changed the bar's height")

	ready_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(_bar_height(screen), settled, "year 2 changed the bar's height")

	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	await get_tree().process_frame
	assert_eq(_bar_height(screen), settled, "borrowing changed the bar's height")

	ready_button.pressed.emit()
	await get_tree().process_frame
	assert_true(screen.loan_nag_visible(), "the test needs a payment to be due")
	assert_eq(_bar_height(screen), settled, "the loan reminder changed the bar's height")

	screen.show_message_for_testing("A refusal, which goes on its own line.")
	await get_tree().process_frame
	assert_eq(_bar_height(screen), settled, "a refusal changed the bar's height")

	# Paid off, so readying up stops asking about the outstanding payment and
	# the rest of the match can be pressed through.
	session.pay_loan(&"p0", session.state().player_by_id(&"p0").loan.balance)
	await get_tree().process_frame
	assert_false(screen.loan_nag_visible(), "the loan should be settled")
	assert_eq(_bar_height(screen), settled, "settling the loan changed the bar's height")

	# Stops one short of the end on purpose: the final year swaps this screen
	# out for the result screen, and there is no bar left to measure.
	while session.state().year < session.state().settings.max_years:
		ready_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(_bar_height(screen), settled, "the last year changed the bar's height")


# ------------------------------------------- the minimum payment, on the board
#
# Asked for after play: the minimum loan payment should be visible on the main
# board, under the LOAN button. It was only inside the loan panel before, so
# you had to open the panel to find out what you owed this year.

func test_there_is_no_minimum_shown_before_any_loan() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	assert_eq(screen.loan_minimum_text(), "", "nothing to pay, nothing to show")


func test_the_minimum_payment_is_shown_under_the_loan_button() -> void:
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	var player: PlayerState = session.state().player_by_id(&"p0")
	session.request_loan(&"p0", LoanRules.max_loan_for(player))

	assert_string_contains(
		screen.loan_minimum_text(),
		Palette.format_money(player.loan.min_payment),
	)


func test_the_minimum_keeps_up_with_what_is_actually_owed() -> void:
	# Derived from state rather than remembered, so interest and penalties
	# cannot leave a stale figure on the board.
	var bits: Array = _playing(true, 2)
	var screen: Control = bits[1]
	var session: LocalSession = bits[2]
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))
	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var player: PlayerState = session.state().player_by_id(&"p0")
	assert_string_contains(
		screen.loan_minimum_text(),
		Palette.format_money(player.loan.min_payment),
	)


# --------------------------------------------------------- escape, as a way out
#
# Asked for after play: there must be a way back to the title screen without
# restarting the game. There was none — closing the window was the only way
# out of a match.

func _press_escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	get_tree().root.push_input(event)
	await wait_process_frames(1)


func test_escape_during_a_match_asks_before_leaving() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings())
	await _press_escape()

	assert_true(main.leave_prompt() != null and main.leave_prompt().is_open(),
		"leaving a game in progress should ask first")
	assert_true(main.current_screen() is GameplayScreen,
		"and should not have left yet")


func test_saying_yes_to_that_question_goes_back_to_the_title_screen() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings())
	await _press_escape()
	if main.leave_prompt() == null:
		fail_test("no prompt to answer")
		return

	(main.leave_prompt().get_node("%ConfirmButton") as Button).pressed.emit()
	assert_true(main.current_screen() is MainMenu, "it should be back at the menu")
	assert_null(main.session(), "and the match should be gone")


func test_saying_no_keeps_the_match() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings())
	await _press_escape()
	if main.leave_prompt() == null:
		fail_test("no prompt to answer")
		return

	(main.leave_prompt().get_node("%CancelButton") as Button).pressed.emit()
	assert_true(main.current_screen() is GameplayScreen, "the match should still be there")
	assert_not_null(main.session())


func test_escape_on_the_title_screen_does_nothing() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	await _press_escape()

	assert_true(main.current_screen() is MainMenu)
	assert_null(main.leave_prompt(), "there is nothing to leave, so nothing to ask")


func test_escape_closes_the_loan_panel_rather_than_offering_to_leave() -> void:
	# The panel is a descendant of the playing screen, so it takes Escape first.
	# Without that, shutting a panel would put a "leave the game?" question on
	# the screen, which is a nasty thing to do to somebody reaching for Escape.
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(_settings())
	var screen: GameplayScreen = main.current_screen()
	screen.loan_panel().show_panel()

	await _press_escape()

	assert_false(screen.loan_panel().is_showing(), "the panel should have closed")
	assert_null(main.leave_prompt(), "and nothing should have asked about leaving")


# ----------------------------------------- the settings reach every game type
#
# Found in play: there was no way to enable loans for a Steam lobby, and the
# settings chosen on the title screen did not carry over to one.
#
# The first fix carried them across and showed a read-only summary on the
# Steam screen, which was the wrong shape: Steam is how the game is actually
# played, local hosting is for testing, and the settings were sitting on the
# testing path. There is now one Create Game panel and the kind of game is a
# choice on it. See decisions.md D65, which replaces D62.


func test_the_menu_offers_every_game_type_beside_the_settings() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)

	assert_true(menu.get_node("%Settings").is_visible_in_tree())
	assert_true(menu.get_node("%SinglePlayerButton").is_visible_in_tree())
	assert_true(menu.get_node("%HostOnlineButton").is_visible_in_tree())
	assert_true(menu.get_node("%HostLocalButton").is_visible_in_tree())


func test_hosting_online_carries_the_settings_straight_from_the_menu() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	(menu.get_node("%LoansCheck") as CheckBox).button_pressed = true
	(menu.get_node("%YearsSpin") as SpinBox).value = 25

	var carried: Array[GameSettings] = []
	menu.host_online_requested.connect(
		func(s: GameSettings) -> void: carried.append(s)
	)
	(menu.get_node("%HostOnlineButton") as Button).pressed.emit()

	assert_eq(carried.size(), 1)
	if carried.is_empty():
		return
	assert_true(carried[0].loans_enabled, "loans were ticked, so loans are on")
	assert_eq(carried[0].max_years, 25)


## The online list with no Steam behind it at all.
##
## Deliberately not driven through `Main`, which would start Steam for real:
## no test may touch Steam (decisions.md D59), and on a machine where Steam
## happens to be running one that did would initialise it twice and fail.
## A null service is the build-without-the-plugin case, which this screen is
## required to survive anyway.
func _online_list() -> OnlineGamesScreen:
	var browser: OnlineGamesScreen = OnlineGamesScene.instantiate()
	add_child_autofree(browser)
	browser.setup(null)
	return browser


func test_the_online_list_does_not_offer_to_create_a_game() -> void:
	# It used to have a HOST button and a read-only summary of settings chosen
	# on another screen. Creating a game belongs under Create Game.
	var browser: OnlineGamesScreen = _online_list()
	assert_false(browser.has_node("%HostButton"), "hosting does not belong here")
	assert_false(browser.has_node("%HostingSummary"),
		"nor does a copy of settings owned somewhere else")


func test_the_online_list_still_comes_up_with_no_steam_at_all() -> void:
	var browser: OnlineGamesScreen = _online_list()
	assert_false((browser.get_node("%Status") as Label).text.is_empty(),
		"it should explain itself rather than sit there empty")


# ------------------------------------------------------------ who is hosting
#
# Asked for after play: the rankings named everybody the same way, so there
# was no telling whose machine the game was running on. Said in a word — the
# first attempt used a leading `*` explained only by a tooltip, which left
# the sole on-screen clue a punctuation mark.

func test_the_host_is_marked_in_the_rankings() -> void:
	var bits: Array = _playing()
	var screen: GameplayScreen = bits[1]

	var rows: Array[Node] = screen.get_node("%RankingList").get_children()
	assert_eq(rows.size(), 1, "a solo game has one player, who is hosting it")
	if rows.is_empty():
		return
	assert_string_contains((rows[0].get_node("%Name") as Label).text, "(Host)")


func test_the_tooltip_says_everything_the_row_says() -> void:
	# The row is cut short at this width, so hovering has to tell you at least
	# as much as the row does, not less.
	var bits: Array = _playing()
	var screen: GameplayScreen = bits[1]
	var rows: Array[Node] = screen.get_node("%RankingList").get_children()
	if rows.is_empty():
		return
	var label: Label = rows[0].get_node("%Name")
	assert_eq(label.tooltip_text, label.text)
	assert_string_contains(label.tooltip_text, "(Host)")


func test_the_first_player_is_the_host() -> void:
	# The rule the marker rests on, asserted where it lives rather than being
	# re-derived as `players[0]` by every screen that needs it.
	var state: GameState = StalksFixture.make_state(10, 3)
	assert_eq(state.host_player_id(), state.players[0].id)


func test_an_empty_match_has_no_host_rather_than_crashing() -> void:
	var state: GameState = GameState.new(null)
	assert_eq(state.host_player_id(), &"")


func test_a_player_called_you_is_not_labelled_you_twice() -> void:
	# A solo player is called "You", so appending "(you)" read "You (you)".
	var bits: Array = _playing()
	var screen: GameplayScreen = bits[1]
	var rows: Array[Node] = screen.get_node("%RankingList").get_children()
	if rows.is_empty():
		return
	var shown: String = (rows[0].get_node("%Name") as Label).text.to_lower()
	assert_false(shown.contains("(you)"), "got: %s" % shown)


# ------------------------------------------------------- the board makes noise
#
# The service has its own tests; these prove the board actually calls it. A
# correct service nobody calls sounds exactly like no service at all.

func _clips_sounding() -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for player: AudioStreamPlayer in Audio.voices():
		if player.stream != null:
			streams.append(player.stream)
	return streams


func _hush() -> void:
	for player: AudioStreamPlayer in Audio.voices():
		player.stop()
		player.stream = null


func test_advancing_a_year_plays_the_mood() -> void:
	var bits: Array = _playing()
	var screen: GameplayScreen = bits[1]
	_hush()

	(screen.get_node("%ReadyButton") as Button).pressed.emit()

	var sounding: Array[AudioStream] = _clips_sounding()
	assert_eq(sounding.size(), 2, "a mood is two clips")
	var mood_clips: Array[AudioStream] = AudioService.BULL
	if bits[2].state().latest_result().mood == MarketMood.Value.BEAR:
		mood_clips = AudioService.BEAR
	for clip: AudioStream in mood_clips:
		assert_true(sounding.has(clip), "the year resolved without its own sound")


func test_a_year_with_nothing_going_bankrupt_does_not_break_glass() -> void:
	var bits: Array = _playing()
	var screen: GameplayScreen = bits[1]
	_hush()

	(screen.get_node("%ReadyButton") as Button).pressed.emit()
	assert_eq(bits[2].state().latest_result().bankrupt_ids().size(), 0,
		"this seed should not bankrupt anything in year 1")

	for clip: AudioStream in AudioService.BANKRUPTCY:
		assert_false(_clips_sounding().has(clip))


# ----------------------------------------------------- the year-by-year history
#
# The match keeps every year's result already — a client appends each one as
# it arrives and the host keeps its own — and until now there was no way to
# look at any of it after the fact. The original had no such view; this is a
# port addition. See decisions.md D73.

func _finished_screen(years: int = 10) -> GameOverScreen:
	var session: LocalSession = _finished_state(years)
	var over: GameOverScreen = GameOverScene.instantiate()
	add_child_autofree(over)
	over.display(session.state(), &"p0")
	return over


func test_the_result_screen_opens_on_the_standings() -> void:
	var over: GameOverScreen = _finished_screen()
	assert_true((over.get_node("%RankingScroll") as Control).visible)
	assert_false((over.get_node("%HistoryBox") as Control).visible)


func test_the_history_tab_swaps_the_two_lists() -> void:
	# They share the space rather than stacking: the card is 520x310 inside a
	# 640x360 window and a second list does not fit.
	var over: GameOverScreen = _finished_screen()

	(over.get_node("%HistoryTab") as Button).pressed.emit()
	assert_false((over.get_node("%RankingScroll") as Control).visible)
	assert_true((over.get_node("%HistoryBox") as Control).visible)

	(over.get_node("%StandingsTab") as Button).pressed.emit()
	assert_true((over.get_node("%RankingScroll") as Control).visible)
	assert_false((over.get_node("%HistoryBox") as Control).visible)


func test_there_is_a_row_for_every_year_played() -> void:
	# Eleven, not ten. A ten-year match settles once more and ends at year
	# eleven — that final settlement moves prices and decides the winner, so
	# it is a year like any other and belongs in the list. See
	# test_year_resolver.gd, which pins the same thing from the other end.
	var over: GameOverScreen = _finished_screen(10)
	assert_eq(over.history_rows().size(), 11)


func test_each_row_names_its_year_and_what_you_were_worth() -> void:
	var over: GameOverScreen = _finished_screen()
	var rows: Array[Node] = over.history_rows()
	if rows.is_empty():
		return

	assert_eq((rows[0].get_node("%Year") as Label).text, "Y1")
	assert_ne((rows[0].get_node("%NetWorth") as Label).text, "",
		"what you were worth at the end of that year")
	assert_ne((rows[0].get_node("%Mood") as Label).text, "")


func test_a_year_always_says_something_happened() -> void:
	# A blank column reads as missing data rather than as a quiet year.
	var over: GameOverScreen = _finished_screen()
	for row: Node in over.history_rows():
		assert_false((row.get_node("%Summary") as Label).text.strip_edges().is_empty())


func test_the_summary_is_repeated_on_hover_because_the_column_is_narrow() -> void:
	var over: GameOverScreen = _finished_screen()
	var rows: Array[Node] = over.history_rows()
	if rows.is_empty():
		return
	var summary: Label = rows[0].get_node("%Summary")
	assert_eq(summary.tooltip_text, summary.text)


func test_a_solo_winner_is_told_they_win_not_that_they_wins() -> void:
	# The solo player is called "You", and the verdict used to read
	# "You wins". It is the first line of the screen and the last thing every
	# single-player game shows.
	var over: GameOverScreen = _finished_screen()
	assert_eq(over.verdict_text(), "You win")


func test_somebody_else_winning_still_reads_in_the_third_person() -> void:
	var session: LocalSession = _finished_state(10)
	# Given a name, and shown to somebody who is not them. Renaming rather
	# than standing up a second player because the wording is all that is
	# under test, and "You wins" would still contain "You win".
	session.state().players[0].display_name = "Bob"

	var over: GameOverScreen = GameOverScene.instantiate()
	add_child_autofree(over)
	over.display(session.state(), &"p9")

	assert_eq(over.verdict_text(), "Bob wins")

