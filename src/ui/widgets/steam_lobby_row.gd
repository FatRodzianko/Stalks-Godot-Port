class_name SteamLobbyRow
extends PanelContainer
## One joinable Steam game in the browser.
##
## Knows nothing about Steam beyond the numbers it is handed. The browser
## screen does the talking.


signal join_requested(lobby_id: int)


@onready var _name_label: Label = %Name
@onready var _players_label: Label = %Players
@onready var _join_button: Button = %JoinButton

var _lobby_id: int = 0


func _ready() -> void:
	_join_button.pressed.connect(func() -> void: join_requested.emit(_lobby_id))


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


func lobby_id() -> int:
	return _lobby_id
