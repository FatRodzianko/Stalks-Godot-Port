class_name SteamLobbyRow
extends PanelContainer
## One joinable Steam game in the browser.
##
## Knows nothing about Steam beyond the numbers it is handed. The browser
## screen does the talking.


signal join_requested(lobby_id: int)


@onready var _name_label: Label = %Name
@onready var _detail_label: Label = %Detail
@onready var _players_label: Label = %Players
@onready var _join_button: Button = %JoinButton

var _lobby_id: int = 0


## Godot calls this once, when the row has been created and added to the
## screen. It only wires the button to its handler.
func _ready() -> void:
	_join_button.pressed.connect(_on_join_button_pressed)


## `lobby` is one entry from `SteamService.lobby_list`.
func display(lobby: Dictionary) -> void:
	_lobby_id = int(lobby.get("id", 0))
	_name_label.text = String(lobby.get("name", "Unnamed game"))

	var players: int = int(lobby.get("players", 0))
	var capacity: int = int(lobby.get("capacity", 0))
	_players_label.text = (
		"%d/%d" % [players, capacity] if capacity > 0 else str(players)
	)
	# A lobby reporting itself full should not offer a button that will fail.
	_join_button.disabled = capacity > 0 and players >= capacity

	_detail_label.text = _describe(lobby)


## The second line: what kind of match this is.
##
## The original's row showed `Years: N` and `Loans: Y/N`, published as lobby
## data for exactly this reason (audit 17.5). Starting cash is added because it
## changes how a game plays and the original left a joiner unable to tell a
## 10,000 game from a 150 one until they were already in the lobby.
##
## **Anything a lobby did not publish is left out rather than guessed.** A
## lobby made by an older build has none of these, and a row claiming ten years
## because that is the usual answer would be worse than a row that says
## nothing.
func _describe(lobby: Dictionary) -> String:
	var parts: Array[String] = []

	var years: int = int(lobby.get("years", 0))
	if years > 0:
		parts.append("%d years" % years)

	var cash: int = int(lobby.get("cash", 0))
	if cash > 0:
		parts.append("start %s" % Palette.format_money(cash))

	var loans: String = String(lobby.get("loans", ""))
	if loans == SteamService.LOANS_ON:
		parts.append("loans")
	elif loans == SteamService.LOANS_OFF:
		parts.append("no loans")

	return "  ".join(parts)


func lobby_id() -> int:
	return _lobby_id


## Somebody clicked JOIN on this row.
func _on_join_button_pressed() -> void:
	join_requested.emit(_lobby_id)
