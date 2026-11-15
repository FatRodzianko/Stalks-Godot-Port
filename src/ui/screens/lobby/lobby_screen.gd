class_name LobbyScreen
extends MarginContainer
## The waiting room: who is here, who is ready, and the host's Start button.
##
## Serves both sides. The difference is small and entirely about what you are
## allowed to do — only the host can start, and only the host knows the port
## worth sharing — so one screen with two modes beats two screens that would
## drift apart.
##
## Like every screen it emits intent and knows nothing about what happens next.
## It reads the session it is given and never mutates the match.


## The player asked to leave. The screen host decides whether that means closing
## a server or disconnecting a client.
signal leave_requested

## The connection ended without the player asking — the host closed the game, or
## removed this player from the lobby. Carries text to show them on the way out.
signal connection_ended(reason: String)

## The host pressed Start, or the client was told the match began. Either way the
## screen host swaps in the playing screen.
signal play_requested


const LobbyRowScene: PackedScene = preload("res://src/ui/widgets/lobby_row.tscn")


@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _status: Label = %Status

var _session: GameSession

## The same session, narrowed. Exactly one of these is non-null, and which one
## decides what this screen lets you do.
var _host: HostSession
var _client: ClientSession

## The port the host is listening on, shown so the host can tell people where to
## connect. Zero on a client, which has no use for it.
var _listening_port: int = 0


func _ready() -> void:
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(leave_requested.emit)
	if _session != null:
		_attach()


## Hands the screen its session. Call before adding it to the tree, or straight
## after — both work.
##
## The session is passed as a `GameSession` and narrowed here, so the screen host
## does not need two code paths for hosting and joining.
func setup(session: GameSession, listening_port: int = 0) -> void:
	_session = session
	_host = session as HostSession
	_client = session as ClientSession
	_listening_port = listening_port
	if is_node_ready():
		_attach()


func is_hosting() -> bool:
	return _host != null


## Public so a test can read the list without reaching into the tree.
func player_rows() -> Array[Node]:
	return _player_list.get_children()


func refresh() -> void:
	if _session == null or not is_inside_tree():
		# Belt and braces alongside `_detach`: building rows outside the tree
		# gives them no `_ready`, and every `@onready` in them stays null.
		return

	_title.text = "LOBBY" if is_hosting() else "JOINED"
	_subtitle.text = (
		"Others join on port %d" % _listening_port
		if is_hosting() and _listening_port > 0
		else "Waiting for the host to start"
	)

	_rebuild_list()

	# The host does not ready up. Pressing Start *is* their readiness, and a
	# second control that means the same thing but does nothing is worse than no
	# control at all — which is what it was.
	_ready_button.visible = not is_hosting()
	_start_button.visible = is_hosting()

	if is_hosting():
		_refresh_for_host()
	else:
		_refresh_for_guest()


## The host's view: Start, and an honest count of who is waiting.
##
## Start is never disabled by other players' readiness. A single idle player
## would otherwise hold the game shut with nothing the host could do about it,
## which is the deadlock this project has now walked into three times. The host
## is told what they are about to do instead of being stopped from doing it.
func _refresh_for_host() -> void:
	var waiting: PackedStringArray = _host.waiting_on()
	_start_button.disabled = not _host.why_not_start().is_empty()

	if _session.state().players.size() < 2:
		_status.text = "Nobody else has joined yet. You can start on your own."
	elif waiting.is_empty():
		_status.text = "Everybody is ready."
	else:
		# Named rather than counted, and paired with the way out: the host can
		# remove somebody who has wandered off rather than waiting indefinitely.
		_status.text = (
			"Waiting on %s. Remove them with X if they have gone."
			% Palette.list_names(waiting)
		)


func _refresh_for_guest() -> void:
	var local: PlayerState = _session.state().player_by_id(_session.local_player_id())
	var is_ready: bool = local != null and local.is_ready
	_ready_button.text = "NOT READY" if is_ready else "READY"
	_status.text = (
		"The host decides when to begin."
		if is_ready
		else "Tell the host you are ready."
	)




func _attach() -> void:
	if not _session.ready_state_changed.is_connected(_on_ready_state_changed):
		_session.ready_state_changed.connect(_on_ready_state_changed)
		_session.player_changed.connect(_on_player_changed)
		_session.action_rejected.connect(_on_action_rejected)

	if _host != null:
		_host.player_joined.connect(_on_roster_changed)
		_host.player_left.connect(_on_roster_changed)
		_host.match_started.connect(play_requested.emit)
	if _client != null:
		_client.match_started.connect(play_requested.emit)
		_client.connection_lost.connect(_on_connection_lost)

	refresh()


## Stops listening the moment this screen leaves the tree.
##
## **This is not tidiness, it is a crash fix.** `Main` swaps screens with
## `remove_child` plus `queue_free`, and `queue_free` is deferred — so without
## this, a screen that has already been replaced is still connected to the
## session and still reacts to the next signal. It then rebuilds its rows while
## detached from the tree, where `_ready` never runs on them, and every
## `@onready` node in a new row is null.
##
## That is exactly what happened when the host pressed Start: the client swapped
## to the board on `match_started`, then the state broadcast that follows
## immediately after reached the dead lobby and took the client down with it.
func _detach() -> void:
	if _session == null:
		return
	if _session.ready_state_changed.is_connected(_on_ready_state_changed):
		_session.ready_state_changed.disconnect(_on_ready_state_changed)
		_session.player_changed.disconnect(_on_player_changed)
		_session.action_rejected.disconnect(_on_action_rejected)
	if _host != null:
		_host.player_joined.disconnect(_on_roster_changed)
		_host.player_left.disconnect(_on_roster_changed)
		_host.match_started.disconnect(play_requested.emit)
	if _client != null:
		_client.match_started.disconnect(play_requested.emit)
		_client.connection_lost.disconnect(_on_connection_lost)


func _exit_tree() -> void:
	_detach()


## One row per player, rebuilt wholesale.
##
## Rebuilding rather than diffing because a lobby list is at most ten rows and
## changes a handful of times; the simplest correct thing is the right thing here.
func _rebuild_list() -> void:
	_clear_list()
	var players: Array[PlayerState] = _session.state().players
	for index: int in players.size():
		var player: PlayerState = players[index]
		var row: LobbyRow = LobbyRowScene.instantiate()
		_player_list.add_child(row)
		var is_you: bool = player.id == _session.local_player_id()
		row.display(player, is_you, index == 0, is_hosting() and not is_you)
		row.kick_requested.connect(_on_kick_requested)


## Removes rows immediately rather than only queueing them. `queue_free()` is
## deferred to the end of the frame, so a rebuild that only queued would briefly
## show every row twice — the trap documented in architecture.md §6 and already
## caught once on the holdings board.
func _clear_list() -> void:
	for child: Node in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()


## Presses the ready button as a player would. Only for the `--ready` launch
## flag: a scripted run that called the session directly would miss anything
## wrong with the button itself.
func press_ready_for_testing() -> void:
	_ready_button.pressed.emit()


## Only a guest reaches this — the host's button is hidden.
func _on_ready_pressed() -> void:
	var local: PlayerState = _session.state().player_by_id(_session.local_player_id())
	var now_ready: bool = local == null or not local.is_ready
	_session.set_ready(_session.local_player_id(), now_ready)
	# A client's own flag is confirmed by the host, so the button settles when
	# `ready_state_changed` comes back rather than guessing here.
	refresh()


func _on_start_pressed() -> void:
	if _host == null:
		return
	var problem: String = _host.why_not_start()
	if problem.is_empty():
		_host.start_match()
	else:
		# The button is disabled in this state, so this is belt and braces — but
		# silence would be the wrong answer if it is ever reached.
		_status.text = problem


func _on_kick_requested(player_id: StringName) -> void:
	if _host == null:
		return
	var problem: String = _host.kick_player(player_id)
	if not problem.is_empty():
		_status.text = problem


func _on_ready_state_changed(_player_id: StringName, _is_ready: bool) -> void:
	refresh()


func _on_player_changed(_player_id: StringName) -> void:
	refresh()


func _on_roster_changed(_player_id: StringName) -> void:
	refresh()


func _on_action_rejected(_player_id: StringName, reason: String) -> void:
	_status.text = reason


## Being removed, or the host quitting, ends this screen rather than annotating
## it. Leaving a kicked player sitting in a lobby they are no longer part of —
## which is what this used to do — is worse than no message at all, because the
## list keeps showing players they cannot see any more.
func _on_connection_lost(reason: String) -> void:
	_status.text = reason
	_ready_button.disabled = true
	connection_ended.emit(reason)
