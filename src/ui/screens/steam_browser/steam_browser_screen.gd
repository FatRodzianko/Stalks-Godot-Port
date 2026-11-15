class_name SteamBrowserScreen
extends MarginContainer
## Find a Steam game to join, or start one.
##
## The only screen that touches `SteamService`, and even then only through its
## signals. It emits intent outward like every other screen and decides
## nothing: `Main` owns the service and turns a chosen lobby into a session.
##
## **It must survive Steam being absent.** A checkout without the plugin, or a
## machine with Steam closed, has to reach this screen and be told why it is
## empty rather than crash. That is the same requirement as D14 — the game runs
## without Steam — applied to the one screen that cannot.


## Host a new Steam game in this lobby.
signal host_requested(lobby_id: int)

## Join somebody else's. `owner_steam_id` is who to connect to.
signal join_requested(lobby_id: int, owner_steam_id: int)

signal back_requested


const LobbyRowScene: PackedScene = preload("res://src/ui/widgets/steam_lobby_row.tscn")


@onready var _status: Label = %Status
@onready var _persona: Label = %Persona
@onready var _hosting_summary: Label = %HostingSummary
@onready var _list: VBoxContainer = %LobbyList
@onready var _empty: Label = %EmptyNote
@onready var _host_button: Button = %HostButton
@onready var _refresh_button: Button = %RefreshButton
@onready var _back_button: Button = %BackButton

var _service: SteamService

## What HOST would start a game with. This screen has no settings controls of
## its own — they live on the title screen, which is the only place a match is
## configured — so all it does is say what they currently are. Showing them
## matters because they used to be silently discarded on the way here: a Steam
## game was always ten years with loans off. See docs/decisions.md D62.
var _settings: GameSettings

## Whether `setup` has been called. Not `_service != null`, because a null
## service is a real answer — it means a build with no Steam plugin — and
## that case still has to reach `_attach` and be reported.
var _was_set_up: bool = false

## What the player last asked for, so the right signal goes out when Steam
## answers. Steam does not tell us which request a result belongs to.
var _pending: StringName = &""
var _pending_lobby: int = 0


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)
	if _was_set_up:
		_attach()


## Hands the screen the service and the settings a hosted game would use.
## `Main` owns both: Steam is initialised once per process and outlives any one
## screen, and the settings belong to the title screen the player came from.
func setup(service: SteamService, settings: GameSettings) -> void:
	_service = service
	_settings = settings
	_was_set_up = true
	if is_node_ready():
		_attach()


func _attach() -> void:
	# What hosting would start is the one thing on this screen that has nothing
	# to do with Steam, so it is shown before anything can go wrong with Steam.
	_show_hosting_summary()

	# No service at all is the extreme case of Steam being unavailable: a build
	# without the plugin. The screen still has to come up and say so.
	if _service == null:
		_show_unavailable("Steam is not available in this build.")
		return

	_service.lobby_created.connect(_on_lobby_created)
	_service.lobby_joined.connect(_on_lobby_joined)
	_service.lobby_failed.connect(_on_lobby_failed)
	_service.lobby_list.connect(_on_lobby_list)

	if not _service.is_running():
		var problem: String = _service.start()
		if not problem.is_empty():
			_show_unavailable(problem)
			return

	_persona.text = "Signed in as %s" % _service.persona_name()
	_status.text = "Looking for games..."
	_service.refresh_lobbies()


## Spells out what HOST would start, and where to go to change it.
##
## A joiner does not need this — the host owns the settings and sends them with
## the opening state — but it is shown to everybody, because which of the two
## you are about to be is not decided until you press a button.
func _show_hosting_summary() -> void:
	if _settings == null:
		_hosting_summary.text = ""
		return
	_hosting_summary.text = "HOST starts: %d years, %s each, loans %s. Change on the title screen." % [
		_settings.max_years,
		Palette.format_money(_settings.starting_cash),
		"on" if _settings.loans_enabled else "off",
	]


## Stops listening on the way out. The same deferred-`queue_free` trap as every
## other screen — see decisions.md D50.
func _detach() -> void:
	if _service == null:
		return
	if _service.lobby_created.is_connected(_on_lobby_created):
		_service.lobby_created.disconnect(_on_lobby_created)
		_service.lobby_joined.disconnect(_on_lobby_joined)
		_service.lobby_failed.disconnect(_on_lobby_failed)
		_service.lobby_list.disconnect(_on_lobby_list)


func _exit_tree() -> void:
	_detach()


## Public so a test can read the list without reaching into the tree.
func lobby_rows() -> Array[Node]:
	return _list.get_children()


func _show_unavailable(reason: String) -> void:
	_persona.text = ""
	_status.text = reason
	_host_button.disabled = true
	_refresh_button.disabled = true
	_empty.visible = false
	_clear_list()


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _on_host_pressed() -> void:
	if _service == null or not _service.is_running():
		return
	_pending = &"host"
	_status.text = "Creating a lobby..."
	_host_button.disabled = true
	# Ten players including the host, matching the match limit.
	_service.create_lobby(NetworkedSession.MAX_CLIENTS + 1)


func _on_refresh_pressed() -> void:
	if _service == null or not _service.is_running():
		return
	_status.text = "Looking for games..."
	_service.refresh_lobbies()


func _on_row_join_requested(lobby_id: int) -> void:
	_pending = &"join"
	_pending_lobby = lobby_id
	_status.text = "Joining..."
	_service.join_lobby(lobby_id)


# ------------------------------------------------------------- what Steam says

func _on_lobby_created(lobby_id: int) -> void:
	# Steam reports creating and joining separately, and the host gets both.
	# Only the create matters here; the join that follows is our own.
	if _pending != &"host":
		return
	_pending = &""
	host_requested.emit(lobby_id)


func _on_lobby_joined(lobby_id: int) -> void:
	if _pending != &"join":
		return
	_pending = &""
	# A client connects to the lobby's *owner*, not to the lobby.
	join_requested.emit(lobby_id, _service.lobby_owner(lobby_id))


func _on_lobby_failed(reason: String) -> void:
	_pending = &""
	_status.text = reason
	_host_button.disabled = false


func _on_lobby_list(lobbies: Array[Dictionary]) -> void:
	_clear_list()

	for lobby: Dictionary in lobbies:
		var row: SteamLobbyRow = LobbyRowScene.instantiate()
		_list.add_child(row)
		row.display(lobby)
		row.join_requested.connect(_on_row_join_requested)

	_empty.visible = lobbies.is_empty()
	_status.text = (
		"No games right now. Start one." if lobbies.is_empty()
		else "%d game%s available" % [lobbies.size(), "" if lobbies.size() == 1 else "s"]
	)


## Removes rows immediately rather than only queueing them, so a refresh never
## briefly shows every lobby twice. See decisions.md D50.
func _clear_list() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
