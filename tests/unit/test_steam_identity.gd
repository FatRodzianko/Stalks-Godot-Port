extends GutTest
## Steam avatars and the supporter thank-you — the two gaps that needed a Steam
## account attached to a player.
##
## **Nothing here talks to Steam**, and could not: the suite has to pass on a
## machine with no Steam client and no plugin (D14). What it covers is
## everything around the Steam calls — that an account reaches the lobby list,
## that a row only claims a portrait that is its own, and that every path
## behaves itself when Steam is absent, which is the condition the suite runs
## in and also the condition a local game runs in.


const RowScene: PackedScene = preload("res://src/ui/widgets/lobby_row.tscn")
const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")


func _player(steam_id: int) -> PlayerState:
	var player: PlayerState = PlayerState.new(&"p0", "Murph", 10000)
	player.steam_id = steam_id
	return player


func _row(player: PlayerState) -> LobbyRow:
	var row: LobbyRow = RowScene.instantiate()
	add_child_autofree(row)
	row.display(player, false, false, false)
	return row


## Two seated players, the shape every lobby list is built from.
func _two_players() -> GameState:
	var state: GameState = StalksFixture.make_state(10, 2)
	state.players[0].id = &"p0"
	state.players[1].id = &"p1"
	return state


func _texture() -> Texture2D:
	var image: Image = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	return ImageTexture.create_from_image(image)


# --------------------------------------------------- the account on a player

func test_a_player_has_no_steam_account_by_default() -> void:
	# Which is every player in a local game, and every player in a test.
	assert_eq(PlayerState.new(&"p0", "Murph", 100).steam_id, 0)


## The lobby list is built from the synced roster, so an account that does not
## survive the snapshot reaches nobody but the host.
func test_a_steam_account_survives_the_snapshot() -> void:
	var state: GameState = _two_players()
	state.players[1].steam_id = 76561197960287930

	var encoded: Dictionary = StateSync.encode_state(state, &"p0")
	var received: GameState = StalksFixture.make_state(10, 2)
	StateSync.apply_state(received, encoded, ContentLibrary.load_from())

	assert_eq(received.players[1].steam_id, 76561197960287930)


## It is already visible to everyone in a Steam lobby through Steam itself, so
## hiding it from the snapshot would protect nothing and break the avatars.
func test_a_steam_account_is_not_redacted_from_rivals() -> void:
	var state: GameState = _two_players()
	state.players[1].steam_id = 7656119796028793

	var seen_by_murph: Dictionary = StateSync.encode_state(state, &"p0")
	var rival: Dictionary = seen_by_murph["players"][1]

	assert_eq(int(rival.get("steam_id", 0)), 7656119796028793)


# ------------------------------------------------------- the portrait itself

func test_a_row_shows_no_portrait_until_one_arrives() -> void:
	var row: LobbyRow = _row(_player(42))

	assert_false((row.get_node("%Avatar") as TextureRect).visible)


func test_a_row_takes_the_portrait_that_is_its_own() -> void:
	var row: LobbyRow = _row(_player(42))

	row.show_avatar(42, _texture())

	var avatar: TextureRect = row.get_node("%Avatar")
	assert_true(avatar.visible)
	assert_not_null(avatar.texture)


## The lobby screen hands every arriving portrait to every row rather than
## tracking which row asked for which, so refusing somebody else's is the row's
## job and the only thing stopping four players sharing one face.
func test_a_row_refuses_somebody_elses_portrait() -> void:
	var row: LobbyRow = _row(_player(42))

	row.show_avatar(99, _texture())

	assert_false((row.get_node("%Avatar") as TextureRect).visible)


func test_a_player_with_no_steam_account_never_shows_a_portrait() -> void:
	# Everybody on a direct connection. A lobby of them shows no portraits,
	# rather than a row of blank squares where portraits would be.
	var row: LobbyRow = _row(_player(0))

	row.show_avatar(0, _texture())

	assert_false((row.get_node("%Avatar") as TextureRect).visible)


# ---------------------------------------------------------- the thank-you

func test_the_supporter_note_is_hidden_unless_it_is_earned() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)

	assert_false((menu.get_node("%SupporterNote") as Label).visible)


func test_the_supporter_note_appears_for_somebody_who_owns_the_dlc() -> void:
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)

	menu.show_supporter_note(true)

	var note: Label = menu.get_node("%SupporterNote")
	assert_true(note.visible)
	assert_string_contains(note.text, "Supporting the Devs")


func test_the_note_can_be_taken_away_again() -> void:
	# The menu is rebuilt on every return to the title screen, but Steam may
	# have gone away since, and a thank-you that cannot be withdrawn would
	# outlive the answer it came from.
	var menu: MainMenu = MenuScene.instantiate()
	add_child_autofree(menu)
	menu.show_supporter_note(true)

	menu.show_supporter_note(false)

	assert_false((menu.get_node("%SupporterNote") as Label).visible)


# --------------------------------------------------------- without Steam

func test_nothing_steam_shaped_answers_yes_when_steam_is_absent() -> void:
	# The condition the whole suite runs in, and every local game. A thank-you
	# that appeared because the question could not be asked would be worse
	# than no thank-you.
	var service: SteamService = SteamService.new()
	add_child_autofree(service)

	assert_false(service.is_running())
	assert_false(service.owns_supporter_dlc())
	assert_eq(service.local_steam_id(), 0)


func test_asking_for_an_avatar_without_steam_does_nothing() -> void:
	var service: SteamService = SteamService.new()
	add_child_autofree(service)
	watch_signals(service)

	service.request_avatar(76561197960287930)

	assert_signal_not_emitted(service, "avatar_ready")
