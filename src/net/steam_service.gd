class_name SteamService
extends Node
## Talks to Steam. The only file in the project that knows the Steam API exists,
## apart from `SteamTransport`.
##
## **Created on demand, never an autoload.** Steam must not be touched unless a
## player actually asks for a Steam match: the port's whole point is that it
## runs with Steam closed (decisions.md D14), and the test suite must pass on a
## machine with no Steam client and no plugin. An autoload would initialise it
## for everybody, every run, including CI.
##
## **Why this is separate from `SteamTransport`.** Creating or joining a Steam
## lobby is *asynchronous* — `createLobby` returns nothing and the answer
## arrives on a signal — while handing back a `MultiplayerPeer` is immediate.
## Mixing the two would have forced the whole `Transport` interface to become
## asynchronous for the benefit of one implementation. Instead the waiting
## happens here, in the UI flow where a human is already waiting, and the
## transport is constructed once there is a lobby to point it at. See
## decisions.md D59.


## Steam is up and this process is signed in. Carries the player's own name so
## the lobby can use it without anybody else reaching for the Steam API.
signal ready_to_play(persona_name: String)

## Initialisation failed. `reason` is player-facing.
signal unavailable(reason: String)

## A lobby this process asked for now exists. The host joins it automatically.
signal lobby_created(lobby_id: int)

## Somebody left the lobby this process is in, or dropped out of it. Carries
## their Steam id; who that is and whether it matters is the caller's business.
signal lobby_member_left(steam_id: int)

## A lobby this process asked to join has been entered.
signal lobby_joined(lobby_id: int)

## A lobby create or join failed. `reason` is player-facing.
signal lobby_failed(reason: String)

## Results of `refresh_lobbies()`. Each entry is
## `{id: int, name: String, players: int, capacity: int}`.
signal lobby_list(lobbies: Array[Dictionary])

## The player accepted a Steam invite or clicked "Join game" on a friend. The
## screen host should take them straight into that lobby.
signal invited_to(lobby_id: int)


## The port's own App ID. See decisions.md D57.
const APP_ID: int = 1821800

## Lobby visibility. 2 is `k_ELobbyTypePublic`, which is what the in-game
## browser lists. 0 is `k_ELobbyTypePrivate`, which the browser never sees:
## the only way in is an invite.
const LOBBY_PUBLIC: int = 2
const LOBBY_PRIVATE: int = 0

## The command-line argument Steam appends when somebody accepts an invite to
## a game that is not running yet. Steam launches the game with it, which is
## the only way an invite can work from a cold start.
const CONNECT_LOBBY_ARG: String = "+connect_lobby"

## Why Steam refused to let us into a lobby — `EChatRoomEnterResponse`.
##
## Written as literals with their names beside them, like `LOBBY_PUBLIC`
## above, because this script has to load in a build with no Steam plugin at
## all (D14) and `Steam.CHAT_ROOM_ENTER_RESPONSE_*` would not exist there. The
## numbers were read off the installed plugin, not off a documentation page.
const ENTER_SUCCESS: int = 1
const ENTER_DOESNT_EXIST: int = 2
const ENTER_NOT_ALLOWED: int = 3
const ENTER_FULL: int = 4

## Lobby metadata keys. Steam lobbies carry arbitrary string pairs; these are
## what the browser reads to show a row without joining first.
const KEY_NAME: StringName = &"name"
const KEY_GAME: StringName = &"game"

## Whether the match in this lobby has begun. The browser lists only lobbies
## still reading `STATE_OPEN`.
##
## Without it, a lobby whose game was already under way stayed in the list,
## and joining it put the player through a lobby screen and back to the title
## a few seconds later when the host refused them. The refusal was correct;
## offering the game at all was not.
const KEY_STATE: StringName = &"state"
const STATE_OPEN: String = "open"
const STATE_PLAYING: String = "playing"

## The `EChatMemberStateChange` bits that mean a member is no longer in the
## lobby, from `lobby_chat_update`'s `chat_state`. Left is a deliberate exit
## and Disconnected is a drop without leaving first; for this game they have
## the same consequence, and so do being kicked or banned.
const CHAT_MEMBER_GONE: int = 0x0002 | 0x0004 | 0x0008 | 0x0010

## Written into every lobby this build creates, and required of every lobby the
## browser lists. Without it the browser would show lobbies from *any* app that
## happens to match the other filters.
const GAME_TAG: String = "stalks"


var _initialised: bool = false
var _lobby_id: int = 0

## What to call the lobby currently being created. See `create_lobby`.
var _pending_lobby_name: String = ""


## Whether the plugin is even present. False on a checkout that has not
## installed it, which must stay a normal, non-fatal condition.
static func is_plugin_available() -> bool:
	return ClassDB.class_exists("Steam")


## Starts Steam. Returns an error string, empty on success.
##
## Safe to call twice; the second call is a no-op.
func start() -> String:
	if _initialised:
		return ""
	if not is_plugin_available():
		return "Steam support is not installed in this build."

	# `embed_callbacks` off: this node polls `run_callbacks()` itself in
	# `_process`. Letting the plugin wire its own callbacks needs a scene tree
	# arrangement this project does not otherwise have, and polling explicitly
	# is the same choice the test harness makes for MultiplayerAPI.
	var result: Dictionary = Steam.steamInitEx(APP_ID, false)
	var status: int = int(result.get("status", -1))
	if status != 0:
		var verbal: String = String(result.get("verbal", ""))
		var reason: String = (
			verbal if not verbal.is_empty()
			else "Steam could not start (code %d). Is Steam running?" % status
		)
		unavailable.emit(reason)
		return reason

	_initialised = true
	# Required before Steam's relay can carry peer-to-peer traffic.
	Steam.initRelayNetworkAccess()

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.join_requested.connect(_on_join_requested)

	ready_to_play.emit(Steam.getPersonaName())
	return ""


func is_running() -> bool:
	return _initialised


## This player's Steam display name, or empty before `start()` succeeds.
func persona_name() -> String:
	return Steam.getPersonaName() if _initialised else ""


## Shuts this process's lobby to anybody else, by both means Steam offers.
##
## Called when the host starts the match, and again when the host leaves. A
## no-op when there is no lobby, so a local game can call it without asking
## whether Steam is involved, and only the lobby's owner can do either of
## these, so a client calling it changes nothing.
##
## **Two mechanisms, because they stop different things.** `setLobbyJoinable`
## is Steam's own switch and also blocks somebody holding an invite or a stale
## lobby id. The `state` key is what the browser's string filter reads, and a
## string filter on lobby data is the part of the documentation I could read
## verbatim. See docs/decisions.md D68.
func close_lobby_to_newcomers() -> void:
	if not _initialised or _lobby_id == 0:
		return
	Steam.setLobbyData(_lobby_id, String(KEY_STATE), STATE_PLAYING)
	Steam.setLobbyJoinable(_lobby_id, false)


## The lobby this process is currently in, or 0.
func current_lobby() -> int:
	return _lobby_id


# ------------------------------------------------------------------- lobbies

## Asks Steam for a lobby. The answer arrives as `lobby_created` or
## `lobby_failed`; nothing is returned here because Steam does not answer
## immediately.
## Asks Steam for a lobby. `lobby_name` is what the browser will show; blank
## names it after the signed-in player.
##
## The name is held until Steam answers, because it can only be written to a
## lobby that exists and Steam creates one asynchronously.
func create_lobby(
	max_players: int,
	lobby_name: String = "",
	invite_only: bool = false,
) -> void:
	if not _initialised:
		lobby_failed.emit("Steam is not running.")
		return
	_pending_lobby_name = lobby_name
	var lobby_type: int = LOBBY_PUBLIC
	if invite_only:
		lobby_type = LOBBY_PRIVATE
	Steam.createLobby(lobby_type, max_players)


func join_lobby(lobby_id: int) -> void:
	if not _initialised:
		lobby_failed.emit("Steam is not running.")
		return
	Steam.joinLobby(lobby_id)


func leave_lobby() -> void:
	if _initialised and _lobby_id != 0:
		Steam.leaveLobby(_lobby_id)
	_lobby_id = 0


## Asks for the list of joinable lobbies. Answers on `lobby_list`.
func refresh_lobbies() -> void:
	if not _initialised:
		lobby_list.emit([] as Array[Dictionary])
		return
	# Only this game's lobbies, and only ones with room left. Without the game
	# filter the browser would list lobbies from any app matching the rest.
	Steam.addRequestLobbyListStringFilter(String(KEY_GAME), GAME_TAG, 0)
	Steam.addRequestLobbyListStringFilter(String(KEY_STATE), STATE_OPEN, 0)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.requestLobbyList()


## Opens Steam's own friend picker for this lobby.
##
## Steam's dialog rather than a friend list of our own: it already knows who
## is online, who is playing this game, and how to word an invitation. The
## alternative is `inviteUserToLobby`, which needs a Steam id we would have to
## build a whole screen to collect.
func open_invite_overlay() -> void:
	if not _initialised or _lobby_id == 0:
		return
	Steam.activateGameOverlayInviteDialog(_lobby_id)


## The lobby Steam was told to join on the command line, or 0.
##
## Accepting an invite to a game that is not running launches it with
## `+connect_lobby <id>`. Parsed here rather than in `LaunchArgs`, which
## deliberately ignores everything in a release build — this has to work in
## the shipped game, because that is the only build an invite will ever
## launch.
static func lobby_from_command_line(arguments: PackedStringArray) -> int:
	for index: int in arguments.size():
		if arguments[index] != CONNECT_LOBBY_ARG:
			continue
		if index + 1 >= arguments.size():
			return 0
		var value: String = arguments[index + 1]
		if not value.is_valid_int():
			return 0
		return value.to_int()
	return 0


## Who owns a lobby. A client needs this: it connects to the owner, not to the
## lobby itself.
func lobby_owner(lobby_id: int) -> int:
	return Steam.getLobbyOwner(lobby_id) if _initialised else 0


# ------------------------------------------------------------------ internals

func _on_lobby_created(connect_result: int, lobby_id: int) -> void:
	if connect_result != 1:
		lobby_failed.emit("Steam could not create the lobby.")
		return
	_lobby_id = lobby_id
	# So the browser can show a name and filter to this game.
	Steam.setLobbyData(lobby_id, String(KEY_GAME), GAME_TAG)
	Steam.setLobbyData(lobby_id, String(KEY_STATE), STATE_OPEN)
	Steam.setLobbyData(lobby_id, String(KEY_NAME), _lobby_name_or_default())
	lobby_created.emit(lobby_id)


## The host's chosen name, or one made from their Steam name. Cleared after
## use so a later lobby does not inherit it.
func _lobby_name_or_default() -> String:
	var chosen: String = _pending_lobby_name.strip_edges()
	_pending_lobby_name = ""
	if not chosen.is_empty():
		return chosen
	return "%s's game" % Steam.getPersonaName()


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != ENTER_SUCCESS:
		lobby_failed.emit(_why_refused(response))
		return
	_lobby_id = lobby_id
	lobby_joined.emit(lobby_id)


## Somebody's membership of our lobby changed.
##
## Only departures are passed on. An arrival is already visible through the
## game's own networking — a player who has joined introduces themselves —
## whereas a departure over Steam is otherwise silent: the peer-to-peer
## session simply stops carrying traffic, which is how a client whose host
## left could sit on the lobby for ever. See docs/decisions.md D68.
func _on_lobby_chat_update(
	lobby_id: int,
	changed_id: int,
	_making_change_id: int,
	chat_state: int,
) -> void:
	if lobby_id != _lobby_id:
		return
	if chat_state & CHAT_MEMBER_GONE == 0:
		return
	lobby_member_left.emit(changed_id)


## Steam's refusal, in words.
##
## It used to read "Could not join that game (code 3)", on the grounds that no
## refusal was worth separate wording. That was wrong, and the owner met the
## proof: code 3 is what a player gets for clicking a game in a list they have
## not refreshed since it started, which is the commonest refusal there is and
## the one most deserving of a sentence.
##
## The unlisted codes — bans, blocks, rate limits — keep the number, because
## a player hitting one needs something to report rather than a guess.
func _why_refused(response: int) -> String:
	if response == ENTER_DOESNT_EXIST:
		return "That game no longer exists."
	if response == ENTER_NOT_ALLOWED:
		# Covers a game already under way and, once it exists, an invite-only
		# lobby. Worded to be true of both rather than guessing which.
		return "That game is not open to new players."
	if response == ENTER_FULL:
		return "That game is full."
	return "Could not join that game (code %d)." % response


func _on_lobby_match_list(lobbies: Array) -> void:
	var rows: Array[Dictionary] = []
	for id: int in lobbies:
		var name: String = Steam.getLobbyData(id, String(KEY_NAME))
		rows.append({
			"id": id,
			"name": name if not name.is_empty() else "Unnamed game",
			"players": Steam.getNumLobbyMembers(id),
			"capacity": Steam.getLobbyMemberLimit(id),
		})
	lobby_list.emit(rows)


## A Steam invite accepted, or "Join game" from the friends list.
func _on_join_requested(lobby_id: int, _steam_id: int) -> void:
	invited_to.emit(lobby_id)


## Steam's callbacks are pumped by hand because `start()` disables the embedded
## ones. Without this, no lobby signal ever fires.
func _process(_delta: float) -> void:
	if _initialised:
		Steam.run_callbacks()
