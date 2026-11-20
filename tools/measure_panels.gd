extends SceneTree
## Prints the laid-out height of the result card and the lobby card, so a
## fixed panel size can be chosen from measurements rather than guessed at.
##
## Run headless:
##   <godot> --headless --script res://tools/measure_panels.gd
##
## Godot computes layout without a window, so every number here is the one the
## game would use at 1280x720. Not part of the build.


const GameOverScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")
const LobbyScene: PackedScene = preload("res://src/ui/screens/lobby/lobby_screen.tscn")
const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")
const HistoryRowScene: PackedScene = preload("res://src/ui/widgets/history_row.tscn")
const LobbyRowScene: PackedScene = preload("res://src/ui/widgets/lobby_row.tscn")


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame

	_measure_rows()
	await _measure_result_card(2)
	await _measure_result_card(10)
	await _measure_lobby(1)
	await _measure_lobby(10)

	quit()


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
	await process_frame
	var list: VBoxContainer = screen.get_node("%PlayerList")
	for index: int in players:
		var row: Control = LobbyRowScene.instantiate()
		list.add_child(row)
	await process_frame
	await process_frame

	var card: Control = screen.get_node("Centre/Card")
	print("lobby card, %d players: %.0f tall" % [players, card.size.y])

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
