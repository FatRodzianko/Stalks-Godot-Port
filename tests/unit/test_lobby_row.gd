extends GutTest
## What a game in the browser tells you before you commit to it.
##
## The original published the year limit and whether loans were on as Steam
## lobby data for exactly this purpose, and the port's row showed neither
## (audit 17.5). Starting cash is published too, which the original never did —
## a joiner could not tell a 10,000 game from a 150 one until they were already
## in the lobby, where nothing shows the settings either.


const RowScene: PackedScene = preload("res://src/ui/widgets/steam_lobby_row.tscn")


func _row(lobby: Dictionary) -> SteamLobbyRow:
	var row: SteamLobbyRow = RowScene.instantiate()
	add_child_autofree(row)
	row.display(lobby)
	return row


func _detail(lobby: Dictionary) -> String:
	return (_row(lobby).get_node("%Detail") as Label).text


func _full_lobby() -> Dictionary:
	return {
		"id": 7,
		"name": "Friday night",
		"players": 2,
		"capacity": 4,
		"years": 25,
		"cash": 10000,
		"loans": SteamService.LOANS_ON,
	}


func test_a_row_says_how_long_the_match_is() -> void:
	assert_string_contains(_detail(_full_lobby()), "25 years")


func test_a_row_says_what_you_start_with() -> void:
	assert_string_contains(_detail(_full_lobby()), "10,000")


func test_a_row_says_loans_are_on() -> void:
	assert_string_contains(_detail(_full_lobby()), "loans")


func test_a_row_says_loans_are_off() -> void:
	var lobby: Dictionary = _full_lobby()
	lobby["loans"] = SteamService.LOANS_OFF

	assert_string_contains(_detail(lobby), "no loans")


func test_the_name_and_the_count_are_still_there() -> void:
	var row: SteamLobbyRow = _row(_full_lobby())

	assert_eq((row.get_node("%Name") as Label).text, "Friday night")
	assert_eq((row.get_node("%Players") as Label).text, "2/4")


## A lobby made by a build that predates this publishes none of it. A row that
## claimed ten years because that is the usual answer would be worse than a row
## that says nothing.
func test_a_lobby_that_published_nothing_claims_nothing() -> void:
	var lobby: Dictionary = {
		"id": 7, "name": "Older build", "players": 1, "capacity": 4,
	}

	assert_eq(_detail(lobby), "")


func test_a_lobby_that_published_only_some_of_it_shows_only_that() -> void:
	var lobby: Dictionary = {
		"id": 7, "name": "Half a lobby", "players": 1, "capacity": 4, "years": 12,
	}
	var detail: String = _detail(lobby)

	assert_string_contains(detail, "12 years")
	assert_false(detail.contains("loans"), "nothing was said about loans")
	assert_false(detail.contains("start"), "nor about starting cash")


func test_a_full_game_cannot_be_joined() -> void:
	var lobby: Dictionary = _full_lobby()
	lobby["players"] = 4

	assert_true((_row(lobby).get_node("%JoinButton") as Button).disabled)
