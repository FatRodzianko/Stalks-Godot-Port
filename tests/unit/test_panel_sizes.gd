extends GutTest
## Panels that must not change size under the player.
##
## **Both of these were reported from play on the same day.** The result card
## grew and shrank as you switched between the standings and the year-by-year,
## and the lobby card jumped downwards when somebody joined. Neither is a wrong
## number on screen, which is why neither was caught: the panels were correct
## and simply would not hold still.
##
## A layout that depends on its contents is the normal Godot default, so this is
## the kind of rule that drifts back the moment somebody adds a row or a line of
## text. Hence a test rather than a note. See docs/decisions.md D125.


const GameOverScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")
const LobbyScene: PackedScene = preload("res://src/ui/screens/lobby/lobby_screen.tscn")
const LobbyRowScene: PackedScene = preload("res://src/ui/widgets/lobby_row.tscn")

## Ten players, host included — the most a match can hold. See game-rules.md §2.
const FULL_HOUSE: int = 10


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


func _result_card(players: int) -> Control:
	var screen: GameOverScreen = GameOverScene.instantiate()
	add_child_autofree(screen)
	screen.display(_state_with(players), &"p0")
	await wait_frames(2)
	return screen.get_node("Centre/Card")


# ------------------------------------------------------------- the result card

func test_the_result_card_is_the_same_size_on_either_tab() -> void:
	var card: Control = await _result_card(2)
	var standings: float = card.size.y

	(card.get_node("%HistoryTab") as Button).pressed.emit()
	await wait_frames(2)

	assert_eq(
		card.size.y, standings,
		"the card must not resize when the player changes tab",
	)


func test_the_result_card_is_the_same_size_however_many_played() -> void:
	var two: Control = await _result_card(2)
	var small: float = two.size.y

	var full: Control = await _result_card(FULL_HOUSE)

	assert_eq(full.size.y, small, "a full match's result card is the same size")


func test_a_full_result_card_still_fits_on_screen() -> void:
	var card: Control = await _result_card(FULL_HOUSE)

	assert_lt(
		card.size.y, 720.0,
		"the card has to fit the window the game runs in",
	)


# -------------------------------------------------------------- the lobby card

func _lobby_card(players: int, status: String) -> Control:
	var screen: Control = LobbyScene.instantiate()
	add_child_autofree(screen)
	var list: VBoxContainer = screen.get_node("%PlayerList")
	for index: int in players:
		list.add_child(LobbyRowScene.instantiate())
	(screen.get_node("%Status") as Label).text = status
	await wait_frames(2)
	return screen.get_node("Centre/Card")


func test_the_lobby_card_does_not_grow_when_somebody_joins() -> void:
	var alone: Control = await _lobby_card(1, "")
	var empty_lobby: float = alone.size.y

	var full: Control = await _lobby_card(FULL_HOUSE, "")

	assert_eq(full.size.y, empty_lobby, "a full lobby is the same size as an empty one")


## **The half that actually moved it.** The status line wraps as soon as it has
## a name in it, and a label that wraps is a panel that changes size.
func test_the_lobby_card_does_not_grow_when_the_status_wraps() -> void:
	var one_line: Control = await _lobby_card(2, "Everybody is ready.")
	var short_status: float = one_line.size.y

	var two_lines: Control = await _lobby_card(
		2, "Waiting on TheStalksEnjoyer. Remove them with X if they have gone."
	)

	assert_eq(two_lines.size.y, short_status, "a second line of status must not move it")


func test_a_full_lobby_fits_on_screen() -> void:
	var card: Control = await _lobby_card(FULL_HOUSE, "Everybody is ready.")

	assert_lt(card.size.y, 720.0, "the card has to fit the window the game runs in")


## Ten rows is what the list reserves, so a full lobby needs no scrolling. The
## scrollbar stays as the backstop for a row taller than it was measured at.
func test_a_full_lobby_needs_no_scrolling() -> void:
	var screen: Control = LobbyScene.instantiate()
	add_child_autofree(screen)
	var list: VBoxContainer = screen.get_node("%PlayerList")
	for index: int in FULL_HOUSE:
		list.add_child(LobbyRowScene.instantiate())
	await wait_frames(2)

	var scroll: ScrollContainer = screen.get_node("%PlayerList").get_parent()
	assert_lte(
		list.size.y, scroll.size.y,
		"all ten players should be visible without scrolling",
	)
