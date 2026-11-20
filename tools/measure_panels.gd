extends SceneTree
## Prints the laid-out height of the result card and the lobby card, so a
## fixed panel size can be chosen from measurements rather than guessed at.
##
## Run headless:
##   <godot> --headless --script res://tools/measure_panels.gd
##
## Godot computes layout without a window, so every number here is the one the
## game would use. Not part of the build.
##
## **Everything is measured at 640x360, not at the window size.** The game is
## drawn into a 640x360 `SubViewport` and that picture is enlarged by a whole
## number to fill the window (`src/ui/stage.gd`), so that is the only size a
## screen is ever laid out at.
##
## **It cannot measure the title screen.** Autoload names are resolved when a
## script is compiled, and a `--script` run has registered none, so the settings
## panel's reference to `Audio` fails to compile and takes the whole menu scene
## with it - after which this prints positions for a screen that never laid out.
## Standing an `Audio` node up by hand does not help, because the failure is at
## compile time. A screen that needs an autoload has to be measured from a GUT
## test, which starts the project properly; `tests/unit/test_panel_sizes.gd`
## does that and asserts the result rather than printing it. See decisions.md
## D126.


const GameOverScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")
const LobbyScene: PackedScene = preload("res://src/ui/screens/lobby/lobby_screen.tscn")
const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")
const HistoryRowScene: PackedScene = preload("res://src/ui/widgets/history_row.tscn")
const LobbyRowScene: PackedScene = preload("res://src/ui/widgets/lobby_row.tscn")


func _initialize() -> void:
	root.size = Vector2i(640, 360)
	await process_frame

	_measure_rows()
	await _measure_result_card(2)
	await _measure_result_card(10)
	await _measure_lobby(1)
	await _measure_lobby(10)

	quit()


## A screen added to the root keeps its own minimum size, not the window's,
## so every position read off it would be measured from the wrong origin.
func _laid_out(screen: Control) -> void:
	screen.size = Vector2(640, 360)
	screen.position = Vector2.ZERO


func _measure_rows() -> void:
	for entry: Array in [
		["ranking row", RankingRowScene],
		["history row", HistoryRowScene],
		["lobby row", LobbyRowScene],
	]:
		var row: Control = (entry[1] as PackedScene).instantiate()
		root.add_child(row)
		await process_frame
		print("%s: %.1f tall" % [entry[0], row.get_combined_minimum_size().y])
		row.queue_free()


func _measure_result_card(players: int) -> void:
	var screen: GameOverScreen = GameOverScene.instantiate()
	root.add_child(screen)
	_laid_out(screen)
	var state: GameState = _state_with(players)
	screen.display(state, &"p0")
	await process_frame
	await process_frame

	var card: Control = screen.get_node("Centre/Card")
	print("result card, %d players, standings: %.0f tall" % [players, card.size.y])

	(screen.get_node("%HistoryTab") as Button).pressed.emit()
	await process_frame
	await process_frame
	print("result card, %d players, year by year: %.0f tall" % [players, card.size.y])

	screen.queue_free()


func _measure_lobby(players: int) -> void:
	var screen: Control = LobbyScene.instantiate()
	root.add_child(screen)
	_laid_out(screen)
	await process_frame
	var list: VBoxContainer = screen.get_node("%PlayerList")
	for index: int in players:
		var row: Control = LobbyRowScene.instantiate()
		list.add_child(row)
	await process_frame
	await process_frame

	var card: Control = screen.get_node("Centre/Card")
	print("lobby card, %d players: %.0f tall, top %.0f, bottom %.0f" % [
		players, card.size.y, card.global_position.y, card.global_position.y + card.size.y,
	])
	var title: Control = screen.get_node("Centre/Card/Body/Title")
	print("  lobby title text top: %.0f" % title.global_position.y)

	# The status line is the other half of it: it wraps to a second line as
	# soon as it has a name in it, and the card used to grow with it.
	var status: Label = screen.get_node("%Status")
	status.text = "Nobody else has joined yet. You can start on your own."
	await process_frame
	await process_frame
	print("  with a one-line status: %.0f tall" % card.size.y)
	status.text = "Waiting on TheStalksEnjoyer. Remove them with X if they have gone."
	await process_frame
	await process_frame
	print("  with a two-line status: %.0f tall" % card.size.y)

	screen.queue_free()


func _state_with(players: int) -> GameState:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	var state: GameState = GameState.new(settings)
	for index: int in players:
		state.players.append(
			PlayerState.new(StringName("p%d" % index), "Player %d" % index, 10000)
		)
	state.is_over = true
	return state
