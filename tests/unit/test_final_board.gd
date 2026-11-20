extends GutTest
## Looking at the board after the match, and getting back to the result screen.
##
## The original let you close its winner panel and study the board as it ended
## — prices, your holdings, the rankings. The port replaced the board with a
## result screen rather than covering it, so that was lost (audit 17.9). This
## is the way back, and the way back from the way back.


const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")


func _finished_match() -> Main:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 2
	settings.rng_seed = 99
	main.start_match(settings)

	var session: GameSession = main.session()
	while not session.state().is_over:
		session.set_ready(session.local_player_id(), true)
	return main


func test_a_finished_match_shows_the_result_screen() -> void:
	var main: Main = _finished_match()

	assert_true(main.current_screen() is GameOverScreen)


func test_the_result_screen_offers_the_board() -> void:
	var main: Main = _finished_match()
	var over: GameOverScreen = main.current_screen() as GameOverScreen

	assert_not_null(over.get_node("%ViewBoardButton"))

	(over.get_node("%ViewBoardButton") as Button).pressed.emit()

	assert_true(main.current_screen() is GameplayScreen, "the board is back")


func test_the_board_shows_the_match_as_it_ended() -> void:
	# Not a fresh one. The session outlives the playing screen precisely so
	# this can be rebuilt from the state the match finished in.
	var main: Main = _finished_match()
	var ended_year: int = main.session().state().year
	main.show_final_board()

	var board: GameplayScreen = main.current_screen() as GameplayScreen
	assert_not_null(board)
	if board == null:
		return
	assert_same(board.session(), main.session())
	assert_eq(board.session().state().year, ended_year)
	assert_true(board.session().state().is_over)


## The original put a second Quit Game button in the bottom bar once its panel
## was dismissed, for the same reason: with the panel gone there has to be a
## way back out of the board.
func test_the_bottom_bar_becomes_the_way_back() -> void:
	var main: Main = _finished_match()
	main.show_final_board()
	var board: GameplayScreen = main.current_screen() as GameplayScreen

	var button: Button = board.get_node("%ReadyButton")
	assert_false(button.disabled, "it says Game Over and does nothing otherwise")
	assert_string_contains(button.text.to_lower(), "results")

	button.pressed.emit()

	assert_true(main.current_screen() is GameOverScreen, "and back again")


func test_a_board_still_being_played_is_not_a_way_back() -> void:
	# The same button readies up during a match, and must go on doing that.
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	main.start_match(GameSettings.new())

	var board: GameplayScreen = main.current_screen() as GameplayScreen
	var button: Button = board.get_node("%ReadyButton")
	assert_string_contains(button.text.to_lower(), "ready")

	button.pressed.emit()

	assert_true(main.current_screen() is GameplayScreen, "still playing")


func test_going_back_and_forth_keeps_working() -> void:
	var main: Main = _finished_match()

	for _pass: int in 3:
		main.show_final_board()
		assert_true(main.current_screen() is GameplayScreen)
		main.show_results()
		assert_true(main.current_screen() is GameOverScreen)


func test_the_board_cannot_be_asked_for_without_a_match() -> void:
	# Nothing to show. Falling through to the menu is the only sane answer.
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	main.show_final_board()

	assert_true(main.current_screen() is MainMenu)


## **Play again survives in a solo game**, which is the only place it ever
## worked: it starts a single-player match from the finished settings. Hidden in
## a networked one — see `test_main_migration.gd` and decisions.md D122.
func test_a_solo_result_screen_still_offers_play_again() -> void:
	var main: Main = _finished_match()
	var over: GameOverScreen = main.current_screen() as GameOverScreen

	assert_true(
		(over.get_node("%PlayAgainButton") as Button).visible,
		"a solo game is exactly what Play again is for",
	)
