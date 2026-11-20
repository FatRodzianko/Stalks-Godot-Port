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
const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")

## Ten players, host included — the most a match can hold. See game-rules.md §2.
const FULL_HOUSE: int = 10

## **The size the interface is laid out at, which is not the size of the
## window.** The whole game is drawn into a 640x360 `SubViewport` and that
## picture is then enlarged by a whole number to fill whatever window the
## player has (`src/ui/stage.gd`, decisions.md D40 and D96). So a screen is
## 640x360 however big the window is, and a test that lays one out at
## 1280x720 measures a screen with twice the room it really has - which is
## exactly how the title screen's message came to be tested in space that does
## not exist. See decisions.md D126.
const WINDOW: Vector2 = Vector2(640, 360)


## A row with a player in it. An empty `LobbyRow` is shorter than a real one -
## it has no name to set its height - so a test that fills the list with bare
## instances measures a lobby that cannot happen.
## Added to the list first, then filled: `display` writes to `@onready` nodes,
## which do not exist until the row is in the tree. The lobby screen seats them
## in that order for the same reason.
func _seat_row(list: VBoxContainer, index: int) -> void:
	var row: LobbyRow = LobbyRowScene.instantiate()
	list.add_child(row)
	row.display(
		PlayerState.new(StringName("p%d" % index), "Player %d" % index, 10000),
		index == 0,
		index == 0,
	)


## Puts a screen in the tree at the size the game would give it.
func _laid_out(screen: Control) -> void:
	add_child_autofree(screen)
	screen.size = WINDOW
	screen.position = Vector2.ZERO


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
	_laid_out(screen)
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
		card.size.y, WINDOW.y,
		"the card has to fit the picture the game is drawn into",
	)


# -------------------------------------------------------------- the lobby card

func _lobby_card(players: int, status: String) -> Control:
	var screen: Control = LobbyScene.instantiate()
	_laid_out(screen)
	var list: VBoxContainer = screen.get_node("%PlayerList")
	for index: int in players:
		_seat_row(list, index)
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

	assert_lt(card.size.y, WINDOW.y, "the card has to fit the picture the game is drawn into")


## **The list area is a fixed window on the roster, whatever is in it.** How
## many players that shows is not fixed - a row is taller once its Steam
## avatar arrives - which is exactly why the guarantee is the window rather
## than a row count, and why the scrollbar is what shows the rest. The owner
## chose that over a panel sized to nothing else on screen. See decisions.md
## D125.
func test_the_list_area_is_the_same_whoever_is_in_it() -> void:
	var empty: Control = await _lobby_scroll(0)
	var reserved: float = empty.size.y

	var full: Control = await _lobby_scroll(FULL_HOUSE)

	assert_eq(full.size.y, reserved, "the roster window does not resize")
	assert_gt(reserved, 0.0, "and it is a window, not nothing")


func _lobby_scroll(players: int) -> Control:
	var screen: Control = LobbyScene.instantiate()
	_laid_out(screen)
	var list: VBoxContainer = screen.get_node("%PlayerList")
	for index: int in players:
		_seat_row(list, index)
	await wait_frames(2)
	return list.get_parent()

# -------------------------------------------------- matching the title screen
#
# The lobby is the screen you arrive at from the title screen, and the two sat
# at noticeably different sizes. Reported from play on 2026-11-20 with the two
# marks that define it: the top of the heading text, and the bottom of the
# panel against the bottom of QUIT TO DESKTOP.
#
# **Within two pixels rather than exactly**, because a vertically centred card
# cannot hit both marks at once: the panel draws two pixels of padding above
# its heading, which puts the two targets a pixel either side of centre. One
# pixel at this size is a sixth of a character.

const ALIGNMENT_SLACK: float = 2.0


func _title_screen() -> Control:
	var menu: Control = MenuScene.instantiate()
	_laid_out(menu)
	await wait_frames(3)
	return menu


## The two marks the lobby is matched to: the top of the heading text, and the
## bottom of the quit button.
func _marks(menu: Control) -> Vector2:
	var heading: Control = menu.get_node("Centre/Shell/Title")
	var quit: Control = menu.get_node("Centre/Shell/QuitRow/QuitButton")
	return Vector2(heading.global_position.y, quit.global_position.y + quit.size.y)


func _title_screen_marks() -> Vector2:
	return _marks(await _title_screen())


func test_the_lobby_heading_starts_where_the_title_does() -> void:
	var marks: Vector2 = await _title_screen_marks()

	var card: Control = await _lobby_card(2, "Everybody is ready.")
	var heading: Control = card.get_node("Body/Title")

	assert_almost_eq(
		heading.global_position.y, marks.x, ALIGNMENT_SLACK,
		"the lobby heading should start where the title screen's does",
	)


func test_the_lobby_panel_ends_where_the_quit_button_does() -> void:
	var marks: Vector2 = await _title_screen_marks()

	var card: Control = await _lobby_card(2, "Everybody is ready.")

	assert_almost_eq(
		card.global_position.y + card.size.y, marks.y, ALIGNMENT_SLACK,
		"the lobby panel should end level with QUIT TO DESKTOP",
	)


# -------------------------------------------- the title screen's own message
#
# **Saying something on the title screen used to move the title screen.** The
# message label was the last row of the centred column, so showing a message
# made the column taller and `CenterContainer` pushed the title and the panel
# up and the quit button down. Reported from play on 2026-11-20: hosting an
# online game says "Creating a lobby..." and the screen jumped on the way out.
#
# It is now a sibling of the centred column rather than a row inside it, so it
# can be as long as it likes without taking any space from the column. See
# docs/decisions.md D126.

## Long enough to wrap at the full width of the window, which is the case that
## used to move the screen most.
const LONG_PROBLEM: String = (
	"Steam is not running. Start Steam and try again. "
	+ "Steam is not running. Start Steam and try again. "
	+ "Steam is not running. Start Steam and try again. "
	+ "Steam is not running. Start Steam and try again."
)


func test_a_status_message_does_not_move_the_title_screen() -> void:
	var menu: Control = await _title_screen()
	var before: Vector2 = _marks(menu)

	menu.show_status("Creating a lobby...")
	await wait_frames(2)

	assert_eq(_marks(menu), before, "saying something must not move the column")


func test_a_message_that_wraps_does_not_move_the_title_screen_either() -> void:
	var menu: Control = await _title_screen()
	var before: Vector2 = _marks(menu)

	menu.show_problem(LONG_PROBLEM)
	await wait_frames(2)

	assert_eq(_marks(menu), before, "a long message must not move it either")


func test_clearing_a_message_does_not_move_the_title_screen() -> void:
	var menu: Control = await _title_screen()
	menu.show_problem(LONG_PROBLEM)
	await wait_frames(2)
	var showing: Vector2 = _marks(menu)

	menu.show_problem("")
	await wait_frames(2)

	assert_eq(_marks(menu), showing, "and taking it away must not move it back")


## Not a message, but the same promise and the same screen: A8f steps 5-7 have
## asked a human to check this by eye since the title screen was rebuilt.
func test_switching_tabs_does_not_move_the_title_screen() -> void:
	var screen: Control = await _title_screen()
	var menu: MainMenu = screen as MainMenu
	var before: Vector2 = _marks(menu)

	for mode: int in [
		MainMenu.Mode.HOST, MainMenu.Mode.JOIN, MainMenu.Mode.SETTINGS,
	]:
		menu.show_mode(mode)
		await wait_frames(2)
		assert_eq(_marks(menu), before, "tab %d must not move the column" % mode)


## **The room down there is 33 pixels**, so this is the assertion that matters:
## the first version of this fix put the message at the foot of a 1280x720
## screen, which is twice the space the game actually has, and in play it
## landed straight on top of QUIT TO DESKTOP.
func test_the_message_sits_below_the_quit_button() -> void:
	var menu: Control = await _title_screen()
	menu.show_problem("Steam is not running.")
	await wait_frames(2)

	_assert_clear_of_the_column(menu)


func test_a_message_that_wraps_still_sits_below_the_quit_button() -> void:
	var menu: Control = await _title_screen()
	menu.show_problem(LONG_PROBLEM)
	await wait_frames(2)

	_assert_clear_of_the_column(menu)


## Not overlapping rather than comfortably clear, because there is nothing to
## be comfortable with: the gap below the quit button is 33 pixels, and two
## lines of the body font (27) plus the screen's bottom margin (6) come to
## exactly that. A one-line message - which is all but the longest of them at
## this width - sits 15 pixels below the button; a two-line one starts where
## the button ends.
## **A supporter's title screen is 13 pixels taller than everybody else's**,
## because the thank-you line is a row inside the centred column. That eats
## into the gap the message lives in - 20 pixels instead of 33 - so the screen
## the owner plays on is the tight case, and the one the first version of this
## fix was seen to break on. A one-line message still clears the button there,
## which is what this pins down. A message long enough to wrap does not, and
## cannot: see decisions.md D126.
func test_a_message_clears_the_quit_button_on_a_supporter_screen() -> void:
	var screen: Control = await _title_screen()
	var menu: MainMenu = screen as MainMenu
	menu.show_supporter_note(true)
	menu.show_problem("Steam is not running.")
	await wait_frames(2)

	_assert_clear_of_the_column(menu)


func _assert_clear_of_the_column(menu: Control) -> void:
	var message: Control = menu.get_node("%ContentWarning")

	assert_gte(
		message.global_position.y, _marks(menu).y,
		"the message must not land on the column",
	)
	assert_lte(
		message.global_position.y + message.size.y, WINDOW.y,
		"and must stay on screen",
	)
