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
## browser lists. Private lobbies are reachable by invite only.
const LOBBY_PUBLIC: int = 2

## Lobby metadata keys. Steam lobbies carry arbitrary string pairs; these are
## what the browser reads to show a row without joining first.
const KEY_NAME: StringName = &"name"
const KEY_GAME: StringName = &"game"

## Written into every lobby this build creates, and required of every lobby the
## browser lists. Without it the browser would show lobbies from *any* app that
## happens to match the other filters.
const GAME_TAG: String = "stalks"


var _initialised: bool = false
var _lobby_id: int = 0


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
	Steam.join_requested.connect(_on_join_requested)

	ready_to_play.emit(Steam.getPersonaName())
	return ""


func is_running() -> bool:
	return _initialised


## This player's Steam display name, or empty before `start()` succeeds.
func persona_name() -> String:
	return Steam.getPersonaName() if _initialised else ""


## The lobby this process is currently in, or 0.
func current_lobby() -> int:
	return _lobby_id


# ------------------------------------------------------------------- lobbies

## Asks Steam for a lobby. The answer arrives as `lobby_created` or
## `lobby_failed`; nothing is returned here because Steam does not answer
## immediately.
func create_lobby(max_players: int) -> void:
	if not _initialised:
		lobby_failed.emit("Steam is not running.")
		return
	Steam.createLobby(LOBBY_PUBLIC, max_players)


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
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.requestLobbyList()


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
	Steam.setLobbyData(lobby_id, String(KEY_NAME), "%s's game" % Steam.getPersonaName())
	lobby_created.emit(lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# 1 is `k_EChatRoomEnterResponseSuccess`. Everything else is a refusal with
	# its own meaning, but none of them are worth separate wording to a player.
	if response != 1:
		lobby_failed.emit("Could not join that game (code %d)." % response)
		return
	_lobby_id = lobby_id
	lobby_joined.emit(lobby_id)


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
