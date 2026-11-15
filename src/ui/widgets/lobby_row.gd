class_name LobbyRow
extends PanelContainer
## One player in the lobby list: their name, whether they are you, and whether
## they are ready.
##
## Knows nothing about the session or the screen holding it — it displays what it
## is given. The lobby screen decides what each row means.


## The host asked to remove this player. The lobby screen decides what that
## means; the row only knows the button was pressed.
signal kick_requested(player_id: StringName)


@onready var _name_label: Label = %Name
@onready var _tag_label: Label = %Tag
@onready var _ready_label: Label = %Ready
@onready var _kick_button: Button = %Kick

var _player_id: StringName = &""


## Godot calls this once, when the row has been created and added to the
## screen. Nothing to do with a player "readying up" — that is the game's own
## word, and this is Godot's. All it does is wire the button to its handler.
func _ready() -> void:
	_kick_button.pressed.connect(_on_kick_button_pressed)


## `is_you` marks the local player, and `is_host` marks player 0. Both are shown
## because in a lobby "which one am I" is the first thing anybody looks for.
##
## There is no "disconnected" state here on purpose: a player who drops is taken
## out of the roster this list is built from, so there is nothing to show. If a
## vacated slot ever becomes visible — a bot playing it, or a rejoin — that is
## when this grows a third state. See porting-plan Phase 8.
## `can_kick` shows the remove button. Only the host passes true, and never for
## their own row.
func display(
	player: PlayerState,
	is_you: bool,
	is_host: bool,
	can_kick: bool = false,
) -> void:
	_player_id = player.id
	_kick_button.visible = can_kick
	_name_label.text = player.display_name

	var tags: PackedStringArray = []
	if is_host:
		tags.append("HOST")
	if is_you:
		tags.append("YOU")
	_tag_label.text = " ".join(tags)
	_tag_label.visible = not tags.is_empty()

	if player.is_ready:
		_ready_label.text = "READY"
		_ready_label.theme_type_variation = &"Bull"
	else:
		_ready_label.text = "WAITING"
		_ready_label.theme_type_variation = &"Faint"


func player_id() -> StringName:
	return _player_id


## The host clicked the X on this row. The row does not know what removing a
## player involves; it says who was clicked and the lobby screen decides.
func _on_kick_button_pressed() -> void:
	kick_requested.emit(_player_id)
