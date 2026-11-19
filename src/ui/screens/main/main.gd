class_name Main
extends MarginContainer
## The screen host: holds exactly one screen at a time and moves between them.
##
## This exists so screens stay ignorant of each other. The menu does not know
## about the playing screen, and the playing screen does not know what happens
## after a match — each emits intent and this decides.
##
## It also owns the session, so a session outlives the screen that displays it
## long enough for the result screen to read the finished state.


const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")
const GameplayScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")
const GameOverScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")
const LobbyScene: PackedScene = preload("res://src/ui/screens/lobby/lobby_screen.tscn")
const ConfirmPanelScene: PackedScene = preload("res://src/ui/widgets/confirm_panel.tscn")
const PauseMenuScene: PackedScene = preload("res://src/ui/widgets/pause_menu.tscn")
const DevOverlayScene: PackedScene = preload("res://src/ui/widgets/dev_overlay.tscn")
const SplashScene: PackedScene = preload("res://src/ui/screens/splash/splash_screen.tscn")

## Well above anything the game draws, so the development overlay is never
## underneath a screen. Godot sorts canvas layers by this number.
const DEV_OVERLAY_LAYER: int = 128

var _screen: Control

## The live session, whichever kind it is. Typed as the interface, not
## `LocalSession`, so hosting and joining need no second code path here.
var _session: GameSession

var _last_settings: GameSettings

## Kept so the lobby can tell the host what port to share.
var _listening_port: int = 0

## What this process was launched with, for the `--ready` / `--autostart`
## conveniences. MENU unless flags were given.
var _launch: LaunchArgs = LaunchArgs.new()

## The lobby `--ready` should press the button on. Held because the handler is
## a named method rather than a closure that could capture it.
var _automated_lobby: LobbyScreen

## Steam, created the first time somebody asks for it and kept for the life of
## the process. Never an autoload: a game played offline, and every test run,
## must never touch Steam at all. See docs/decisions.md D59.
var _steam: SteamService

## Set while Steam is being asked for a lobby to host in, and cleared when it
## answers. Held here because the menu that supplied them is swapped away
## before the answer arrives.
var _pending_host_settings: GameSettings

## The "leave the game?" overlay, built the first time Escape is pressed during
## a match and kept afterwards. Null until then, so a session that never asks
## never pays for it.
var _leave_prompt: ConfirmPanel

## The pause overlay, built the first time Escape is pressed during a match.
var _pause_menu: PauseMenu

## The direct-connection panel, in development builds only. Null otherwise.
var _dev_overlay: DevOverlay

## What this process was launched to do, held while the splash plays. Read
## once, by `_open_first_screen`.
var _pending_invite: int = 0
var _pending_launch: LaunchArgs = LaunchArgs.new()

## The layer it sits on, so it can be hidden away from the title screen.
var _dev_layer: CanvasLayer


func _ready() -> void:
	# Godot closes the window the moment it is asked unless told otherwise.
	# This game has a Steam lobby to shut and a peer to close first — see
	# `_notification` and docs/decisions.md D71.
	get_tree().auto_accept_quit = false

	apply_stored_display()
	add_dev_overlay_if_wanted()
	warm_up_steam()

	# An invite accepted while the game was closed launches it with
	# `+connect_lobby <id>`, and that has to work in a release build — which
	# is why it is not a `LaunchArgs` flag. See docs/decisions.md D69.
	_pending_invite = SteamService.lobby_from_command_line(OS.get_cmdline_args())
	_pending_launch = LaunchArgs.from_command_line()

	if _splash_is_wanted():
		show_splash()
		return
	_open_first_screen()


## Puts the saved resolution and fullscreen state onto the window.
##
## **Runs before anything is shown**, so a player never sees one frame of the
## default window before it jumps to their own size.
##
## `DisplayMode` does nothing under the headless display server, so a test
## that instantiates `Main` does not put the test runner fullscreen.
func apply_stored_display() -> void:
	var stored: UserSettings = UserSettings.load_from()
	DisplayMode.apply(get_window(), stored.resolution, stored.fullscreen)


## Whether to show the studio logo before anything else.
##
## **Not in a test or a headless run**, which have no display to show it on.
##
## **Not when the game was launched into something.** An accepted invite is a
## player asking for one particular lobby, and `--host` / `--join` are the
## development flags used to put two windows up in a hurry — several times a
## minute, on a bad afternoon. A logo in front of either is a toll.
func _splash_is_wanted() -> bool:
	if not DisplayMode.has_a_real_window():
		return false
	if _pending_invite != 0:
		return false
	return _pending_launch.mode == LaunchArgs.Mode.MENU


## Shows the studio logo. Public so it can be looked at without restarting the
## game.
func show_splash() -> void:
	var splash: SplashScreen = SplashScene.instantiate()
	splash.finished.connect(_on_splash_finished)
	_swap(splash)


func _on_splash_finished() -> void:
	_open_first_screen()


## Whatever the game was launched to do: join an invited lobby, obey a
## development flag, or show the menu.
func _open_first_screen() -> void:
	if _pending_invite != 0:
		var lobby: int = _pending_invite
		_pending_invite = 0
		join_online_game(lobby)
		return
	apply_launch_args(_pending_launch)


## Starts Steam now rather than the first time somebody opens Join Game.
##
## **The fault this fixes.** Initialising Steam takes long enough to see, and it
## was happening on the click that opens the lobby list, so the panel visibly
## stalled the first time it was opened in a session. Reported from play. At
## launch the same pause hides inside the time the window takes to appear.
##
## **Why it was not already done.** D59 ruled out making `SteamService` an
## autoload, because an autoload would initialise Steam for every run including
## every test. That is still right, and it ruled out slightly more than it
## needed to: the service can be started early in a real game without being an
## autoload.
##
## **Does nothing under the headless display server**, which is the whole test
## suite. The suite has to pass on a machine with no Steam client and no plugin
## (D14), so a run that instantiates `Main` must not reach for Steam.
##
## **The answer is deliberately thrown away.** Steam being closed is an
## ordinary thing, not a failure to report, and the player finds out when they
## go looking for a game — the browser already explains it there. Announcing it
## at launch would be reporting a problem nobody has yet.
func warm_up_steam() -> void:
	if not DisplayMode.has_a_real_window():
		return
	steam_service().start()


## Pins the direct-connection panel to the corner, in development builds only.
##
## `OS.is_debug_build()` is false in anything the `Windows Release` preset
## produces, so a player who bought the game never sees it.
##
## **It goes on a `CanvasLayer` of its own, and that matters twice.** The first
## version made it an ordinary child of this node, which is a
## `MarginContainer`, and it was unusable: a container lays out its `Control`
## children, so the panel was stretched to fill the screen instead of sitting
## where its offsets said, and every screen swap added the new screen *after*
## it, so the screen drew on top and swallowed the clicks. A `CanvasLayer` is
## not a `Control`, so no container touches it, and a high `layer` draws above
## everything regardless of child order. This is the same arrangement as the
## separate canvas such overlays get in Unity.
##
## **It shows on the title screen only**, like the Unity original that this
## follows: a session can only be started from there, and in a match it would
## be sitting over the board.
func add_dev_overlay_if_wanted() -> void:
	if not OS.is_debug_build():
		return

	_dev_layer = CanvasLayer.new()
	_dev_layer.layer = DEV_OVERLAY_LAYER
	add_child(_dev_layer)

	_dev_overlay = DevOverlayScene.instantiate()
	_dev_overlay.host_requested.connect(_on_dev_host_requested)
	_dev_overlay.join_requested.connect(_on_dev_join_requested)
	_dev_layer.add_child(_dev_overlay)


## The direct-connection panel, or null in a release build. For tests.
func dev_overlay() -> DevOverlay:
	return _dev_overlay


## Obeys `--host` / `--join` if they were given, otherwise shows the menu.
##
## Separate from `_ready` and taking its arguments explicitly so the behaviour can
## be tested without a command line. `from_command_line()` returns MENU in a
## release build, so a shipped game always lands here on the menu.
func apply_launch_args(launch: LaunchArgs) -> void:
	_launch = launch
	match launch.mode:
		LaunchArgs.Mode.HOST:
			_report_launch_problem(
				host_match(launch.host_settings(), launch.resolved_name(), launch.port)
			)
		LaunchArgs.Mode.JOIN:
			_report_launch_problem(
				join_match(launch.address, launch.port, launch.resolved_name())
			)
		_:
			show_menu()


## A failed auto-host or auto-join falls back to the menu with the reason on it.
## Leaving a blank screen would be a miserable way to discover that a port is
## busy.
func _report_launch_problem(problem: String) -> void:
	if problem.is_empty():
		return
	show_menu()
	_report_to_menu(problem)


# ------------------------------------------------------------------- escape
#
# Until this existed the only way out of a match was to close the window, which
# made every test of a second game a restart of the whole program.

## Escape means "back out of where I am".
##
## This lives on the screen host rather than on each screen because what to back
## out *to* is the host's business — the screens deliberately know nothing about
## one another.
##
## Overlays get first refusal. Godot delivers unhandled input from the deepest
## node upwards, so a confirmation or the loan panel, both of which are
## descendants of the current screen, takes Escape and marks it handled before
## it reaches here.
func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_ESCAPE:
		return
	if _screen == null or _screen is MainMenu:
		# Already as far back as there is. Left unhandled on purpose, so Escape
		# stays available to anything else that wants it on the title screen.
		return

	accept_event()
	if _session == null:
		# The Steam browser and the result screen hold nothing that can be lost,
		# so backing out of them needs no ceremony.
		show_menu()
		return
	show_pause_menu()


## Opens the pause overlay over a match.
##
## **Escape used to go straight to "leave the game?"**, which made the only key
## that does anything mid-match a key that offers to end your game. It now
## opens a menu, and leaving is one choice on it — behind the same
## confirmation as before.
func show_pause_menu() -> void:
	if _pause_menu == null:
		_pause_menu = PauseMenuScene.instantiate()
		add_child(_pause_menu)
		_pause_menu.leave_requested.connect(_ask_about_leaving)
		_pause_menu.quit_requested.connect(quit_to_desktop)
	# Each screen swap adds the new screen last, which would cover this.
	move_child(_pause_menu, -1)
	_pause_menu.open()


## Leaving a match in progress is not undoable — there is no reconnection yet —
## so it asks first.
func _ask_about_leaving() -> void:
	if _leave_prompt == null:
		_leave_prompt = ConfirmPanelScene.instantiate()
		add_child(_leave_prompt)
		_leave_prompt.confirmed.connect(_on_leave_confirmed)
	# Every screen swap adds the new screen as the last child, which would put
	# it over the top of this one. Raising it here keeps it on top without the
	# swap having to know the prompt exists.
	move_child(_leave_prompt, -1)
	_leave_prompt.ask(
		"Leave the game and go back to the title screen?",
		"Leave",
		"Keep playing",
	)


func _on_leave_confirmed() -> void:
	show_menu()


## Hands the asking to Steam's own friend picker, which knows who is online.
func _on_invite_requested() -> void:
	if _steam != null and _steam.is_running():
		_steam.open_invite_overlay()


## The "leave the game?" overlay, or null if Escape has never been pressed
## during a match. For tests, and for anything that needs to know whether a
## question is already on screen.
func leave_prompt() -> ConfirmPanel:
	return _leave_prompt


## The pause overlay, or null if Escape has never been pressed during a match.
## For tests.
func pause_menu() -> PauseMenu:
	return _pause_menu


func show_menu() -> void:
	_discard_session()
	var menu: MainMenu = MenuScene.instantiate()
	menu.start_requested.connect(_on_start_requested)
	menu.host_online_requested.connect(_on_host_online_requested)
	menu.browse_online_requested.connect(_on_browse_online_requested)
	menu.join_online_requested.connect(join_online_game)
	menu.quit_requested.connect(quit_to_desktop)
	_swap(menu)
	# After the swap: the label is a child of the menu, which has to be in the
	# tree before its scene-unique names resolve.
	menu.show_supporter_note(_steam != null and _steam.owns_supporter_dlc())


## Starts a match. Public so a test can begin one without driving the menu.
func start_match(settings: GameSettings) -> void:
	_discard_session()
	_last_settings = settings

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return

	_mount_session(LocalSession.create(settings, library))
	_show_gameplay()


func current_screen() -> Control:
	return _screen


func session() -> GameSession:
	return _session


# -------------------------------------------------------------------- networked
#
# Hosting and joining both end in the same place: a session, mounted here, and
# the lobby screen watching it. What differs is only how the session is built.

## Opens a lobby and shows it. Returns an error string, empty on success.
func host_match(settings: GameSettings, player_name: String, port: int) -> String:
	_discard_session()
	_name_the_match(settings, player_name)
	_last_settings = settings

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return BROKEN_CONTENT

	_is_online_match = false
	var result: Dictionary = HostSession.host(
		EnetTransport.new(port), settings, library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = port
	var session: HostSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


## Connects to somebody else's lobby. An empty return means the socket opened —
## the connection itself is asynchronous and reported by the lobby screen.
func join_match(address: String, port: int, player_name: String) -> String:
	_discard_session()

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return BROKEN_CONTENT

	_is_online_match = false
	var result: Dictionary = ClientSession.join(
		EnetTransport.new(port, address), library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: ClientSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


## Steam, started on first use. Public so a test can see whether anything has
## touched it.
func steam_service() -> SteamService:
	if _steam == null:
		_steam = SteamService.new()
		_steam.name = "SteamService"
		add_child(_steam)
	return _steam


## This player's Steam account, or 0 when Steam is not running.
##
## Carried into an online match so the lobby can show avatars (audit 17.7).
## Nothing else reads it, and a direct connection never has one.
func local_steam_id() -> int:
	if _steam == null or not _steam.is_running():
		return 0
	return _steam.local_steam_id()


## Hands the title screen's lobby list a Steam service.
##
## **The list lives on the title screen now**, under Join Game, rather than on
## a screen of its own reached by a button. Steam is still started here,
## because it is initialised once per process and outlives any screen, and the
## browser has to come up and explain itself on a machine with no Steam at all
## (D14) rather than be refused by the menu.
func show_online_games() -> void:
	var menu: MainMenu = _screen as MainMenu
	if menu == null:
		return
	var service: SteamService = steam_service()
	_watch_the_service(service)
	menu.show_online_games(service)


## Hosts inside a Steam lobby that already exists. Whoever asked for the lobby
## waited for Steam to answer, so by here there is nothing left to wait for.
func host_steam_match(lobby_id: int, settings: GameSettings, player_name: String) -> String:
	_discard_session()
	_name_the_match(settings, player_name)
	_last_settings = settings

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return BROKEN_CONTENT

	_is_online_match = true
	var result: Dictionary = HostSession.host(
		_steam_transports.host_in(lobby_id),
		settings,
		library,
		player_name,
		local_steam_id(),
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: HostSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


## Joins a Steam host, whether this is a first join or a reconnection after the
## host changed.
##
## `during_migration` means this is one attempt among several at reaching a
## host that has just taken over, and changes two things. The Steam lobby is
## **kept**, because it is the lobby the new host is in rather than one being
## left behind. And no screen is swapped: whatever is on screen stays, stale,
## until a welcome actually arrives, because a half-built session would
## otherwise put an empty lobby or an empty market up on every attempt.
## `Main` watches for the welcome in `_process` and shows the right screen then.
func join_steam_match(
	lobby_id: int,
	owner_steam_id: int,
	player_name: String,
	during_migration: bool = false,
) -> String:
	_discard_session(during_migration)
	_online_host_steam_id = owner_steam_id

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return BROKEN_CONTENT

	_is_online_match = true
	var result: Dictionary = ClientSession.join(
		_steam_transports.client_to(lobby_id, owner_steam_id),
		library,
		player_name,
		local_steam_id(),
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: ClientSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	if during_migration:
		return ""
	_show_lobby()
	return ""


# ------------------------------------------------------------- hosting online
#
# Creating a Steam lobby is asynchronous: ask, then wait for Steam to call
# back with an id. That wait lives here rather than in the Transport (D59),
# and it lives in `Main` rather than on a screen because the screen it was
# asked from is gone by the time the answer arrives.

## Host a game other people reach through Steam, with the settings from Create
## Game. The lobby does not exist yet, so this asks for one and continues in
## `_on_steam_lobby_created`.
func _on_host_online_requested(settings: GameSettings) -> void:
	_pending_host_settings = settings

	var service: SteamService = steam_service()
	if not service.is_running():
		var problem: String = service.start()
		if not problem.is_empty():
			_report_to_menu(problem)
			return

	if not service.lobby_created.is_connected(_on_steam_lobby_created):
		service.lobby_created.connect(_on_steam_lobby_created)
		service.lobby_failed.connect(_on_steam_lobby_failed)
	_watch_the_service(service)

	# Steam takes a moment, and a button that does nothing visible reads as
	# broken.
	var menu: MainMenu = _screen as MainMenu
	if menu != null:
		menu.show_status("Creating a lobby...")

	# Ten players including the host, matching the match limit. The lobby
	# carries the host's chosen name so the browser can show it.
	# The host's chosen limit, clamped to what a match can actually hold. The
	# port used to pass the maximum unconditionally, so a host who wanted a
	# three-player game could not stop a fourth joining (audit 17.4).
	service.create_lobby(
		clampi(settings.player_count, 1, HostSession.MAX_PLAYERS),
		settings.game_name,
		settings.invite_only,
		settings,
	)


## Listens to the Steam service. Connected once, from wherever Steam is first
## needed, because these answers can arrive when no screen is expecting them:
## an invite accepted mid-menu, a host leaving mid-lobby.
func _watch_the_service(service: SteamService) -> void:
	if service.lobby_member_left.is_connected(_on_steam_lobby_member_left):
		return
	service.lobby_member_left.connect(_on_steam_lobby_member_left)
	service.lobby_joined.connect(_on_steam_lobby_joined)
	service.invited_to.connect(_on_steam_invited_to)


## Somebody left the Steam lobby. Only the host leaving matters, and it now
## starts a migration rather than ending the game. See docs/decisions.md D105.
##
## **This is the only thing that reports it over Steam.** A direct connection
## raises `server_disconnected` and the session acts on that; Steam's
## peer-to-peer session just goes quiet. Without this a client sat on a lobby
## or a board that had silently stopped being connected to anything, which is
## what `ClientSession`'s join timeout was written to catch — that timeout is
## now a backstop rather than the mechanism. See docs/decisions.md D68.
func _on_steam_lobby_member_left(steam_id: int) -> void:
	if steam_id == 0 or steam_id != _online_host_steam_id:
		return
	if _session == null or _session is HostSession:
		return
	_online_host_steam_id = 0
	_begin_migration(steam_id)


# ------------------------------------------------------------- host migration
#
# The host walked out. Steam hands the lobby to one of the remaining members
# on its own, so nobody votes and nobody has to agree: every client asks Steam
# the same question until it answers, then either starts hosting or joins
# whoever Steam picked. `LobbyMigration` is that decision, tested on its own in
# test_lobby_migration.gd; this is the plumbing round it.
#
# See docs/decisions.md D105.

## Holds on to the match and starts asking Steam who owns the lobby now.
##
## **The match is kept, not re-fetched.** This client already holds a complete
## copy of it (`state_sync.gd`), which is the whole reason migration is
## possible: if this process turns out to be the new host, it promotes what it
## has rather than asking anybody for it.
func _begin_migration(departed_steam_id: int) -> void:
	var client: ClientSession = _session as ClientSession
	var lobby_id: int = _steam.current_lobby() if _steam != null else 0
	if client == null or lobby_id == 0 or local_steam_id() == 0:
		# No Steam lobby to be handed on, or no account to be handed it. A
		# direct connection ends here, as it always did.
		_on_connection_ended("The host left the game.")
		return

	_migrating_in_match = _screen is GameplayScreen
	_migrating_state = client.state()
	_migrating_rng_state = client.rng_state()
	_migrating_player_id = client.local_player_id()
	_migration = LobbyMigration.new(local_steam_id(), departed_steam_id)
	_reconnect_attempted = false
	print(MIGRATION_LOG, "host %d left lobby %d. Asking Steam who owns it now." % [
		departed_steam_id, lobby_id
	])
	print(MIGRATION_LOG, "this player is %d, in a %s." % [
		local_steam_id(), "match" if _migrating_in_match else "lobby"
	])
	_since_last_poll = MIGRATION_POLL_SECONDS


func _process(delta: float) -> void:
	if _migration == null:
		return

	# Already decided to host, and waiting for the old peer to let go of the
	# port before putting a new one on it.
	if _hosting_in >= 0.0:
		_hosting_in -= delta
		if _hosting_in <= 0.0:
			_hosting_in = -1.0
			_start_hosting_the_moved_lobby()
		return

	_migration.wait(delta)
	_since_last_poll += delta
	if _since_last_poll < MIGRATION_POLL_SECONDS:
		return
	_since_last_poll = 0.0

	# An attempt that has landed ends the migration, so a connection made a
	# moment ago is not torn down to make another. Only an attempt made *by
	# this migration* counts: the session left over from the departed host is
	# also "joined", and taking that as success is the fault D108 was.
	if _reconnect_attempted:
		var client: ClientSession = _session as ClientSession
		if client != null and client.has_joined():
			_settle_in_behind_the_new_host()
			return

	var lobby_id: int = _steam.current_lobby() if _steam != null else 0
	var owner: int = _steam.lobby_owner(lobby_id) if lobby_id != 0 else 0
	var step: LobbyMigration.Step = _migration.next_step(owner)
	if step == LobbyMigration.Step.BECOME_HOST:
		_stand_down_to_host(lobby_id)
	elif step == LobbyMigration.Step.JOIN_NEW_HOST:
		_try_the_new_host(lobby_id, owner)
	elif step == LobbyMigration.Step.GAVE_UP:
		_give_up_on_migration("The host left the game.")


## Steam made this player the owner, so this process carries the match on.
## Closes the old connection and starts the clock on hosting.
##
## **The two halves are deliberately not in the same frame.** See
## `NEW_HOST_START_SECONDS`: a listen socket opened while the old peer is still
## letting go of the port comes up dead, and a dead listen socket looks exactly
## like a working game to the player holding it.
func _stand_down_to_host(lobby_id: int) -> void:
	print(MIGRATION_LOG, "Steam made this player the owner. Taking over.")
	_hosting_lobby = lobby_id
	_hosting_in = NEW_HOST_START_SECONDS
	# Keeps the Steam lobby: it is the thing being taken over, and leaving it
	# would be leaving the game this is trying to save.
	_discard_session(true)


func _start_hosting_the_moved_lobby() -> void:
	var lobby_id: int = _hosting_lobby
	_hosting_lobby = 0

	var library: ContentLibrary = _loaded_library()
	if library == null:
		_give_up_on_migration(BROKEN_CONTENT)
		return

	var in_match: bool = _migrating_in_match
	var state: GameState = _migrating_state
	var rng_state: int = _migrating_rng_state
	var my_player_id: StringName = _migrating_player_id
	_end_migration()

	_is_online_match = true

	var result: Dictionary = {}
	if in_match:
		print(MIGRATION_LOG, "continuing the match from this client's own copy.")
		result = HostSession.take_over(
			_steam_transports.host_in(lobby_id),
			state,
			library,
			my_player_id,
			rng_state,
		)
	else:
		# **A lobby is re-hosted, not taken over.** Nobody has a position yet,
		# so there is nothing to preserve and the others can simply rejoin as
		# they would any new game. The settings are the ones they were already
		# looking at, so the lobby they come back to is the same game.
		var settings: GameSettings = GameSettings.new()
		if state != null and state.settings != null:
			settings = state.settings
		# A lobby that somehow arrived unnamed would otherwise be headed
		# "LOBBY", which is the lobby screen's last resort rather than a name.
		_name_the_match(settings, _steam_name())
		_last_settings = settings
		result = HostSession.host(
			_steam_transports.host_in(lobby_id),
			settings,
			library,
			_steam_name(),
			local_steam_id(),
		)

	if not String(result["error"]).is_empty():
		_give_up_on_migration(String(result["error"]))
		return

	_listening_port = 0
	var session: HostSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	print(MIGRATION_LOG, "now hosting the moved %s as %s." % [
		"match" if in_match else "lobby", my_player_id
	])

	# **Now that this process owns the lobby, it has to say what the lobby
	# is.** The player who left may have shut it down on the way out, so a
	# migrated lobby has to be advertised again or nobody can find it - the
	# first fault reported from play (D106). A match that was already under way
	# wants the opposite: unlisted, but still reachable by somebody coming back
	# for their seat.
	if _steam != null and _steam.is_running():
		if in_match:
			_steam.hide_lobby_from_the_browser()
		else:
			_steam.reopen_lobby_to_the_browser(_last_settings)

	if in_match:
		_show_gameplay()
	else:
		_show_lobby()


## Steam picked somebody else, so this process reconnects to them.
## Tries the new host, and will try again.
##
## **One attempt is not enough**, which is the other half of the fault reported
## from play. Steam needs a moment to route to a host that has only just
## started listening, and an attempt that lands too early fails for good - the
## client sits on "connecting" until its own join timeout gives up. So every
## poll makes another attempt, until one connects or the twenty seconds run
## out. The owner's Unity game does the same, calling `JoinSteamHost` once a
## second for the whole of its reconnect window.
##
## A failure here is not the end of the migration: the next poll tries again.
func _try_the_new_host(lobby_id: int, owner_steam_id: int) -> void:
	# No screen change and the Steam lobby is kept, because this may be one of
	# several attempts and the lobby is where the new host is.
	_reconnect_attempted = true
	print(MIGRATION_LOG, "Steam says %d hosts now. Trying to reach them." % owner_steam_id)
	join_steam_match(lobby_id, owner_steam_id, _steam_name(), true)


## An attempt landed: the new host has welcomed this client back.
func _settle_in_behind_the_new_host() -> void:
	print(MIGRATION_LOG, "reconnected to the new host.")
	var in_match: bool = _migrating_in_match
	_end_migration()
	if in_match:
		_show_gameplay()
	else:
		_show_lobby()


## Steam never named an owner, or the new session could not be built. Either
## way the game is over for this player, which is what used to happen the
## moment the host left.
func _give_up_on_migration(reason: String) -> void:
	print(MIGRATION_LOG, "giving up: %s" % reason)
	_end_migration()
	_on_connection_ended(reason)


func _end_migration() -> void:
	_migration = null
	_hosting_in = -1.0
	_hosting_lobby = 0
	_reconnect_attempted = false
	_migrating_state = null
	_migrating_rng_state = 0
	_migrating_player_id = &""
	_migrating_in_match = false


## Steam has made the lobby. Now there is something to host in.
func _on_steam_lobby_created(lobby_id: int) -> void:
	if _pending_host_settings == null:
		return
	var settings: GameSettings = _pending_host_settings
	_pending_host_settings = null

	var problem: String = host_steam_match(lobby_id, settings, _steam_name())
	if problem.is_empty():
		return
	show_menu()
	_report_to_menu(problem)


func _on_steam_lobby_failed(reason: String) -> void:
	_pending_host_settings = null
	if _screen is MainMenu:
		_report_to_menu(reason)
		return
	show_menu()
	_report_to_menu(reason)


func _on_browse_online_requested() -> void:
	show_online_games()


## Who this process connected to when joining an online game, so that Steam
## reporting them leaving can be recognised as the host going away.
##
## Recorded rather than read back from `getLobbyOwner`: when a lobby's owner
## leaves, **Steam promotes another member to owner automatically**, so by the
## time the departure is reported the lobby already belongs to somebody else.
## Steam lobby ownership and being this game's host are different things, and
## only the second one matters here. See docs/decisions.md D68.
var _online_host_steam_id: int = 0

## Where a Steam match's transport comes from. Replaced in tests, which must
## never reach the Steam API - see `SteamTransportSource`.
var _steam_transports: SteamTransportSource = SteamTransportSource.new()

## A host migration under way, or null when there is none.
##
## Everything below it is the match as it stood when the host left, held on to
## while Steam decides who takes over. A `GameState` is RefCounted, so keeping
## this reference is what stops the departing session taking the match with it.
## See docs/decisions.md D105.
var _migration: LobbyMigration = null
var _migrating_state: GameState = null
var _migrating_rng_state: int = 0
var _migrating_player_id: StringName = &""

## Whether the match had actually started. A lobby has no position to preserve,
## so it migrates by re-hosting; a match in progress is taken over.
var _migrating_in_match: bool = false

## Steam is asked who owns the lobby on a timer rather than every frame, and
## every ask is also another attempt to reconnect. One second, the owner's
## Unity game's `ReconnectRetrySeconds`.
const MIGRATION_POLL_SECONDS: float = 1.0
var _since_last_poll: float = 0.0

## How long to let the old connection die before opening a listen socket in its
## place. Half a second, the owner's Unity game's `NewHostStartDelaySeconds`.
##
## **This is not politeness, it is the fault reported from play.** Closing a
## Steam peer and hosting in the same frame produced a host that reported no
## error, played perfectly well by itself, and accepted no connections at all -
## the virtual port was still held by the peer that was on its way out. The
## Unity game carries the same constant for the same reason.
const NEW_HOST_START_SECONDS: float = 0.5

## Prefix on the migration's own log lines.
##
## **Migration is the one thing in this game that cannot be watched.** It
## happens on somebody else's machine, in the seconds after a host walks out,
## and every visible symptom of it going wrong looks like a symptom of
## something else - a board that stops updating, a player who cannot connect, a
## game that carries on single-handed. Three faults were diagnosed from
## guesswork before this existed. These lines land in the log file (see
## development.md §10), which is the only account of what actually happened.
const MIGRATION_LOG: String = "[migration] "


## Counting down to opening that listen socket, or negative when not.
var _hosting_in: float = -1.0
var _hosting_lobby: int = 0

## Whether this migration has actually tried to reconnect yet.
##
## **Without this the migration ends the instant it starts.** The session still
## mounted when the host leaves is a client that has joined - it joined the
## host who just left - so "is the client connected?" answers yes before
## anything has been attempted, and the migration congratulates itself and
## stops. The symptom is a lobby that never migrates, still showing the
## departed player as host, until the dead connection finally times out. See
## docs/decisions.md D108.
var _reconnect_attempted: bool = false

## Whether the match on screen is being carried by Steam. Decides whether a
## lobby offers to invite anybody: there is nothing to invite through on a
## local game.
var _is_online_match: bool = false

## The Steam lobby we have asked to be let into, or 0. Held because the answer
## arrives on a signal with no memory of who asked.
var _pending_join_lobby: int = 0

## Reports what the local player earns in the match on screen. Replaced with
## each new match, so it never reports against a session that has ended.
var _achievements: AchievementReporter


## The player's Steam display name.
##
## **An online game names you from your Steam account**, never from the title
## screen's name field. That field exists for local games, where there is no
## account to ask. The rebuilt menu briefly used it for both, so a Steam game
## showed everybody as "Player" — or as whatever had been typed for an earlier
## local game, which was worse, because it looked deliberate. See
## docs/decisions.md D66.
func _steam_name() -> String:
	var persona: String = ""
	if _steam != null:
		persona = _steam.persona_name().strip_edges()
	if persona.is_empty():
		return "Player"
	return persona


## Gets into a Steam lobby and then into the match inside it.
##
## Public and taking only a lobby id, because there are three ways to arrive
## here and only one of them has a screen attached: picking a game from the
## list, accepting an invite while the game is running, and being launched by
## an invite from cold. See docs/decisions.md D69.
##
## Joining is asynchronous — the owner cannot be read until Steam says we are
## in — so this asks and continues in `_on_steam_lobby_joined`.
func join_online_game(lobby_id: int) -> void:
	if lobby_id == 0:
		return
	_pending_join_lobby = lobby_id

	var service: SteamService = steam_service()
	if not service.is_running():
		var problem: String = service.start()
		if not problem.is_empty():
			_pending_join_lobby = 0
			show_menu()
			_report_to_menu(problem)
			return

	_watch_the_service(service)
	service.join_lobby(lobby_id)


## Steam has let us into the lobby. Now there is an owner to connect to.
func _on_steam_lobby_joined(lobby_id: int) -> void:
	if _pending_join_lobby != lobby_id:
		return
	_pending_join_lobby = 0

	var problem: String = join_steam_match(
		lobby_id, _steam.lobby_owner(lobby_id), _steam_name()
	)
	if problem.is_empty():
		return
	show_menu()
	_report_to_menu(problem)


## Somebody accepted an invitation while the game was already running.
func _on_steam_invited_to(lobby_id: int) -> void:
	join_online_game(lobby_id)


func _show_lobby() -> void:
	var lobby: LobbyScreen = LobbyScene.instantiate()
	lobby.leave_requested.connect(show_menu)
	lobby.play_requested.connect(_on_play_requested)
	lobby.connection_ended.connect(_on_connection_ended)
	lobby.invite_requested.connect(_on_invite_requested)
	if _is_online_match:
		lobby.offer_invites()
	_swap(lobby)
	# After the swap, so the screen is in the tree and its @onready nodes exist.
	lobby.setup(_session, _listening_port, _steam)
	_apply_lobby_automation(lobby)


## The `--ready` / `--autostart` development conveniences. Does nothing unless
## those flags were given, which they never are outside a debug build.
##
## `--ready` presses the lobby's own button rather than calling the session, so
## that a scripted two-process run exercises the same path a player does. An
## automation that takes a shortcut past the UI cannot reproduce a UI bug.
func _apply_lobby_automation(lobby: LobbyScreen) -> void:
	if _launch.auto_ready:
		var client: ClientSession = _session as ClientSession
		if client != null:
			_automated_lobby = lobby
			client.joined.connect(_on_automation_joined)

	if _launch.auto_start:
		var host: HostSession = _session as HostSession
		if host != null:
			host.ready_state_changed.connect(_on_automation_ready_changed)


## `--ready`: press the lobby's own button as soon as this client is seated.
func _on_automation_joined(_player_id: StringName) -> void:
	if _automated_lobby != null:
		_automated_lobby.press_ready_for_testing()


## `--autostart`: begin as soon as the gate allows it. Readiness is the only
## thing the gate waits on once somebody has joined, so this is the only moment
## worth re-checking.
func _on_automation_ready_changed(_player_id: StringName, _is_ready: bool) -> void:
	var host: HostSession = _session as HostSession
	if host == null:
		return
	if host.why_not_start().is_empty() and host.state().players.size() > 1:
		host.start_match()


## Kicked, or the host quit. Back to the menu, carrying the reason: a player
## left sitting in a lobby they are no longer part of has no idea what happened.
func _on_connection_ended(reason: String) -> void:
	if _migration != null:
		# **A migration already has this covered.** The same departure reaches
		# here twice: once from Steam, which starts the migration, and again
		# from the session when its connection to the departed host finally
		# gives out. Acting on the second would drop the player onto the title
		# screen while a new host was being found for them.
		return
	show_menu()
	# Says where they have ended up as well as why. Being dropped onto the title
	# screen with a bare "The host closed the game." reads as the game having
	# restarted itself.
	_report_to_menu("%s You are back at the title screen." % reason)


## The lobby is done with: show the board. The session is untouched — the match
## has already begun as far as the host is concerned.
func _on_play_requested() -> void:
	# A started game should stop appearing in the list of games to join. Only
	# the host can say so, and only the host owns the Steam lobby. It stays
	# *joinable* - a player who drops comes back through this lobby and the
	# host decides whether they get their seat (D105).
	if _session is HostSession and _steam != null and _steam.is_running():
		_steam.hide_lobby_from_the_browser()
	_show_gameplay()


## Builds and shows the playing screen.
##
## Solo and networked play both come through here, so a connection made for one
## cannot be missed by the other - which is how the playing screen came to be
## the only screen that did not notice the host leaving.
func _show_gameplay() -> void:
	var gameplay: GameplayScreen = GameplayScene.instantiate()
	gameplay.setup(_session)
	gameplay.match_finished.connect(_on_match_finished)
	gameplay.connection_ended.connect(_on_connection_ended)
	_swap(gameplay)


## Fills in a blank game name, so that by the time anybody is looking at a
## lobby it always has a heading. Done here rather than on the title screen
## because an online game is named after the Steam account, which the title
## screen has not asked Steam about.
func _name_the_match(settings: GameSettings, host_name: String) -> void:
	if not settings.game_name.strip_edges().is_empty():
		return
	settings.game_name = "%s's game" % host_name


## A session must be in the tree before `attach_peer`, because `multiplayer`
## resolves by node path — see architecture.md §5.2.
func _mount_session(session: GameSession) -> void:
	_session = session
	add_child(_session)
	_watch_for_achievements()


## Starts reporting the local player's achievements for this match.
##
## Created for every match, including a solo one: achievements are earned by
## playing, not by playing online. It does nothing when Steam is not running,
## which is why there is no condition here — one path rather than two.
func _watch_for_achievements() -> void:
	if _achievements != null:
		remove_child(_achievements)
		_achievements.queue_free()
	_achievements = AchievementReporter.new()
	_achievements.name = "Achievements"
	add_child(_achievements)
	_achievements.setup(_session, _steam)


## A busy port or an unreachable host is a normal thing for a player to run into,
## not a fault in the game, so it goes on the screen rather than into the log.
## `push_error` is reserved for things that mean the build is broken — bad
## content, say.
func _on_dev_host_requested(port: int, player_name: String) -> void:
	var problem: String = host_match(GameSettings.new(), player_name, port)
	if not problem.is_empty():
		_report_to_menu(problem)


func _on_dev_join_requested(address: String, port: int, player_name: String) -> void:
	var problem: String = join_match(address, port, player_name)
	if not problem.is_empty():
		_report_to_menu(problem)


## Puts a failure back on the menu, where the player still is. Nothing has been
## swapped at this point, so the menu is still the current screen.
func _report_to_menu(problem: String) -> void:
	var menu: MainMenu = _screen as MainMenu
	if menu != null:
		menu.show_problem(problem)


func _on_start_requested(settings: GameSettings) -> void:
	start_match(settings)


func _on_match_finished(_winners: Array[StringName]) -> void:
	show_results()


## Shows the result screen for the finished match.
##
## Public and separate from `_on_match_finished` because the player can leave
## it to look at the board and come back, so this is reached twice.
##
## The state is read from the session, which this node owns, so it is still
## alive after the playing screen goes away.
func show_results() -> void:
	if _session == null:
		show_menu()
		return

	var over: GameOverScreen = GameOverScene.instantiate()
	over.play_again_requested.connect(_on_play_again)
	over.menu_requested.connect(show_menu)
	over.view_board_requested.connect(show_final_board)
	_swap(over)
	over.display(_session.state(), _session.local_player_id())


## Puts the finished board back on screen, to be looked over rather than
## played.
##
## The original let you close its winner panel and study the board underneath;
## the port's result screen replaced the board instead of covering it, so
## getting back to it means rebuilding it (audit 17.9, D81). The session is
## still alive, so the board renders the match exactly as it ended.
func show_final_board() -> void:
	if _session == null:
		show_menu()
		return

	var gameplay: GameplayScreen = GameplayScene.instantiate()
	gameplay.setup(_session)
	gameplay.results_requested.connect(show_results)
	gameplay.connection_ended.connect(_on_connection_ended)
	_swap(gameplay)
	gameplay.show_as_final_board()


func _on_play_again() -> void:
	if _last_settings == null:
		show_menu()
		return
	# A fresh seed, so "play again" is a new market rather than a replay. The
	# chosen seed, if the player typed one, is deliberately not reused.
	var settings: GameSettings = _last_settings.duplicate() as GameSettings
	settings.rng_seed = 0
	start_match(settings)


## The window was closed, or the OS asked the game to stop.
##
## **Does not ask.** Clicking the X is not a keystroke somebody hits by
## accident, and a confirmation in front of a window that is already going
## away is an argument with a player who has finished. Escape asks because it
## is reversible; this is not.
##
## What it does do is leave properly. Before this, closing the window skipped
## `_discard_session` entirely, so a host's Steam lobby was never marked shut
## and its peer was never closed — the lobby survived until Steam noticed it
## was empty. See docs/decisions.md D71.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	quit_to_desktop()


## Shuts the game down the way closing the window does.
##
## **A button for this is not optional.** Fullscreen has no window to close, so
## without one the only way out is Alt+F4 — which a player should never have to
## discover. The original had `Quit to Desktop` on the title screen and
## `Exit to Desktop` in the pause menu, and this is both of them.
##
## Goes through `_discard_session` for the same reason the close handler does:
## a host that vanishes without shutting its Steam lobby leaves that lobby
## standing until Steam notices it is empty. See docs/decisions.md D71.
func quit_to_desktop() -> void:
	_discard_session()
	get_tree().quit()


## Replaces the current screen. Removes the old one from the tree immediately
## rather than only queueing it, so nothing briefly sees two screens at once —
## the same deferred-free trap described in docs/architecture.md §6.
func _swap(next: Control) -> void:
	# A pause overlay belongs to the match under it. Leaving one open across a
	# swap would put it over the title screen, where none of its buttons mean
	# anything.
	if _pause_menu != null:
		_pause_menu.close()
	# The development overlay can only start a session, so it belongs on the
	# screen a session is started from and nowhere else.
	if _dev_layer != null:
		_dev_layer.visible = next is MainMenu
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
	_screen = next
	add_child(next)


## What to tell a player whose install is damaged.
##
## It used to say "see the log", which is advice a player cannot take: there
## is no log window, and the file is somewhere they have never been told
## about. The detail still goes to the log for whoever is debugging; the
## sentence on screen is the one thing they can actually do about it.
const BROKEN_CONTENT: String = (
	"The game's content files are missing or damaged. "
	+ "Verifying or reinstalling the game should fix it."
)


## The validated content, or null with the problems already logged.
func _loaded_library() -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.load_from()
	if library.is_valid():
		return library
	for error: String in library.errors:
		push_error("Content error: %s" % error)
	return null


## Closes any transport before freeing the session, so a lobby left behind does
## not hold its socket open and block the next attempt on the same port.
## Closes the live session.
##
## `keep_lobby` holds on to the Steam lobby, for the one case that needs it: a
## migration is a new session inside the *same* lobby, so leaving it would be
## leaving the game this is trying to rescue.
func _discard_session(keep_lobby: bool = false) -> void:
	if _session == null:
		return
	var networked: NetworkedSession = _session as NetworkedSession
	if networked != null:
		networked.close()
	# Leaving the match means leaving the Steam lobby too, or the browser would
	# keep listing a game nobody is in.
	#
	# **A host leaving is two different events** and `leave_lobby_as_host`
	# tells them apart: the last player out is a lobby dying, and should be
	# shut down as far as Steam allows (D68), while a host leaving other
	# players behind is a lobby changing hands, which must be left alone for
	# them to migrate into (D106).
	if _steam != null and _steam.is_running() and not keep_lobby:
		if _session is HostSession:
			_steam.leave_lobby_as_host()
		else:
			_steam.leave_lobby()
	_online_host_steam_id = 0
	remove_child(_session)
	_session.queue_free()
	_session = null
	_listening_port = 0
