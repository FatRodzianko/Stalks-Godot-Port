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

## The layer it sits on, so it can be hidden away from the title screen.
var _dev_layer: CanvasLayer


func _ready() -> void:
	# Godot closes the window the moment it is asked unless told otherwise.
	# This game has a Steam lobby to shut and a peer to close first — see
	# `_notification` and docs/decisions.md D71.
	get_tree().auto_accept_quit = false

	apply_stored_display()
	add_dev_overlay_if_wanted()

	# An invite accepted while the game was closed launches it with
	# `+connect_lobby <id>`, and that has to work in a release build — which
	# is why it is not a `LaunchArgs` flag. See docs/decisions.md D69.
	var invited_lobby: int = SteamService.lobby_from_command_line(OS.get_cmdline_args())
	if invited_lobby != 0:
		join_online_game(invited_lobby)
		return
	apply_launch_args(LaunchArgs.from_command_line())


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
		SteamTransport.new(lobby_id), settings, library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: HostSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


func join_steam_match(lobby_id: int, owner_steam_id: int, player_name: String) -> String:
	_discard_session()
	_online_host_steam_id = owner_steam_id

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return BROKEN_CONTENT

	_is_online_match = true
	var result: Dictionary = ClientSession.join(
		SteamTransport.new(lobby_id, owner_steam_id), library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: ClientSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
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


## Somebody left the Steam lobby. Only the host leaving matters: this game has
## no host migration, so their departure ends the match for everybody.
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
	_on_connection_ended("The host left the game.")


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
	lobby.setup(_session, _listening_port)
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
	show_menu()
	# Says where they have ended up as well as why. Being dropped onto the title
	# screen with a bare "The host closed the game." reads as the game having
	# restarted itself.
	_report_to_menu("%s You are back at the title screen." % reason)


## The lobby is done with: show the board. The session is untouched — the match
## has already begun as far as the host is concerned.
func _on_play_requested() -> void:
	# A started game should stop appearing in the list of games to join. Only
	# the host can say so, and only the host owns the Steam lobby.
	if _session is HostSession and _steam != null and _steam.is_running():
		_steam.close_lobby_to_newcomers()
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
	# The state is read from the session, which this node owns, so it is still
	# alive after the playing screen goes away.
	var finished_state: GameState = _session.state()
	var local_id: StringName = _session.local_player_id()

	var over: GameOverScreen = GameOverScene.instantiate()
	over.play_again_requested.connect(_on_play_again)
	over.menu_requested.connect(show_menu)
	_swap(over)
	over.display(finished_state, local_id)


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
func _discard_session() -> void:
	if _session == null:
		return
	var networked: NetworkedSession = _session as NetworkedSession
	if networked != null:
		networked.close()
	# Leaving the match means leaving the Steam lobby too, or the browser would
	# keep listing a game nobody is in.
	#
	# A host shuts theirs to newcomers first. **Steam has no way to destroy a
	# lobby**: one exists until its last member leaves, and the owner leaving
	# simply promotes somebody else. Shutting it is the closest thing to
	# killing it that Steam offers, and it has to happen before leaving,
	# because afterwards this process no longer owns it. See decisions.md D68.
	if _steam != null and _steam.is_running():
		if _session is HostSession:
			_steam.close_lobby_to_newcomers()
		_steam.leave_lobby()
	_online_host_steam_id = 0
	remove_child(_session)
	_session.queue_free()
	_session = null
	_listening_port = 0
