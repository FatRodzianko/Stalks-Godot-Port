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

## What `request_lobby_details` found out about one lobby this process is **not**
## in. `exists` is false when Steam has nothing for that id any more, which is
## what a lobby everybody has left looks like. `state` is the `KEY_STATE` value,
## so `STATE_OVER` means the lobby is alive but its match is not.
signal lobby_details(lobby_id: int, exists: bool, state: String)

## The player accepted a Steam invite or clicked "Join game" on a friend. The
## screen host should take them straight into that lobby.
signal invited_to(lobby_id: int)

## A player's Steam avatar has arrived. Asked for with `request_avatar`, which
## answers through this because Steam fetches it asynchronously — a portrait
## that is not cached yet takes a moment, and may arrive after the lobby row
## that wanted it already exists.
signal avatar_ready(steam_id: int, texture: Texture2D)


## The port's own App ID. See decisions.md D57.
const APP_ID: int = 1821800

## The supporter DLC's App ID, which is its own number and not the game's.
## Steam issues one per DLC; owning the game says nothing about owning this.
const SUPPORTER_DLC_APP_ID: int = 1856290

## Steam offers three portrait sizes: 32, 64 and 184 pixels square. The lobby
## draws on a 640x360 grid where a row is sixteen pixels tall, so the smallest
## is already larger than the space for it.
const AVATAR_SIZE: int = 1

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

## What the match is set up to be, published so a joiner can choose before
## committing. The original published the year limit and whether loans were on
## for exactly this purpose (audit 17.5).
##
## **Starting cash goes further than the original did.** It never published it,
## so a joiner could not tell a 10,000 game from a 150 one until they were
## already in the lobby, where there is nothing showing the settings either.
##
## Steam lobby data is strings. These are written as plain integers and read
## back with `to_int()`, which answers 0 for anything unparseable — including
## a lobby from an older build that never wrote them. 0 means "not published"
## and the row leaves that part out rather than showing a wrong number.
const KEY_YEARS: StringName = &"years"
const KEY_LOANS: StringName = &"loans"
const KEY_CASH: StringName = &"cash"

## Which game the lobby is: `GameMode.lobby_value`, a word rather than a
## number, so that a lobby from a build that never wrote it reads as empty
## rather than as `GameMode.Value.BASE` (docs/stalkleheads-design.md §9.4).
const KEY_MODE: StringName = &"mode"

## `KEY_LOANS` is a string like everything else in lobby data.
const LOANS_ON: String = "1"
const LOANS_OFF: String = "0"

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

## The match in this lobby has finished.
##
## **For somebody who was not there to see it end.** A match that is over does
## not take its lobby with it: the players are still in it, looking at the
## result screen, so the lobby is alive and reachable and a returning player
## would be let through the door and onto a dead board. This key is how the
## title screen knows not to offer that. See docs/decisions.md D115.
const STATE_OVER: String = "over"

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

## The match settings to publish once Steam has made the lobby. Held for the
## same reason the name is: lobby data can only be written to a lobby that
## exists, and Steam creates one asynchronously.
var _pending_settings: GameSettings = null

## Which lobby `request_lobby_details` is waiting to hear about, or 0.
##
## Needed because `lobby_data_update` fires for every lobby this process has
## data on - including the one it is in, every time anybody changes a key - and
## none of those are an answer to the question that was asked.
var _details_wanted_for: int = 0


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
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.join_requested.connect(_on_join_requested)
	Steam.avatar_loaded.connect(_on_avatar_loaded)

	ready_to_play.emit(Steam.getPersonaName())
	return ""


func is_running() -> bool:
	return _initialised


## This player's Steam display name, or empty before `start()` succeeds.
func persona_name() -> String:
	return Steam.getPersonaName() if _initialised else ""


## Whether this player owns the supporter DLC.
##
## **False whenever Steam is not running**, which includes every offline game
## and every test. A thank-you that appears because the question could not be
## asked would be worse than no thank-you.
##
## The original checked for a file called `support-dlc.txt` next to the
## executable, which anybody could create. Ownership is the real test; see
## decisions.md D91.
## This player's own Steam account, or 0 before `start()` succeeds.
func local_steam_id() -> int:
	return Steam.getSteamID() if _initialised else 0


## Asks Steam for somebody's avatar. Answers on `avatar_ready`.
##
## **Does nothing without Steam, and nothing for id 0**, which is what a player
## on a direct connection has. A lobby of such players simply shows no
## portraits, which is how every local game looks.
func request_avatar(steam_id: int) -> void:
	if not _initialised or steam_id == 0:
		return
	Steam.getPlayerAvatar(AVATAR_SIZE, steam_id)


func owns_supporter_dlc() -> bool:
	if not _initialised:
		return false
	# `isDLCInstalled`, not `isDlcInstalled`. GodotSteam capitalises the
	# acronym here and the wrong spelling is a *parse* error, not a runtime
	# one, so it takes the whole script down with it. Read off the plugin
	# binary on 2026-11-16 rather than guessed.
	return Steam.isDLCInstalled(SUPPORTER_DLC_APP_ID)


# -------------------------------------------------- what the browser is shown
#
# Two mechanisms, and they stop different things. The `state` key is what the
# browser's string filter reads, so it controls whether a lobby is *listed*.
# `setLobbyJoinable` is Steam's own switch and stops anybody getting in at all,
# invite or stale lobby id included.
#
# **They were used together until 2026-11-18 and are now separate**, because a
# match in progress wants to be unlisted but still reachable: a player whose
# connection dropped comes back through the same lobby, and the host decides
# whether they get their seat (D105). Slamming Steam's door shut made that
# impossible. The host is the gatekeeper now; Steam only decides who is
# advertised. See docs/decisions.md D68 and D106.
#
# Each is a no-op without a lobby, so a local game may call them without asking
# whether Steam is involved, and only the lobby's owner can write lobby data -
# a client calling one changes nothing.

## Takes the lobby out of the browser while leaving the door open.
##
## Called when the match starts, and by a new host taking over a match that was
## already under way. Nobody new may have a seat, but somebody coming back can
## still reach the lobby to ask for theirs.
func hide_lobby_from_the_browser() -> void:
	if not _initialised or _lobby_id == 0:
		return
	Steam.setLobbyData(_lobby_id, String(KEY_STATE), STATE_PLAYING)


## The match in this lobby has ended. Says so, so that a player who was away
## when it finished is not offered a game to go back into.
##
## **Only the lobby's owner can write this**, which is the host, and a client
## calling it changes nothing — the same as every other lobby-data call here.
## It is not guarded on that for the same reason none of them are.
func mark_lobby_finished() -> void:
	if not _initialised or _lobby_id == 0:
		return
	Steam.setLobbyData(_lobby_id, String(KEY_STATE), STATE_OVER)


## Puts the lobby back in the browser, joinable, with its settings fresh.
##
## For a new host taking over a **lobby** rather than a match. The player who
## left may have shut the lobby down on their way out - they had no way to know
## somebody else was about to own it - so this is what undoes that. Without it
## the migrated lobby works for the people already in it and is invisible and
## unjoinable to everybody else, which is exactly how it was first seen to
## fail.
func reopen_lobby_to_the_browser(settings: GameSettings = null) -> void:
	if not _initialised or _lobby_id == 0:
		return
	# `game` and `name` are rewritten too: this lobby is being advertised again
	# from scratch, and a key the departing owner cleared would otherwise leave
	# a row the browser filters out or cannot label.
	Steam.setLobbyData(_lobby_id, String(KEY_GAME), GAME_TAG)
	Steam.setLobbyData(_lobby_id, String(KEY_STATE), STATE_OPEN)
	Steam.setLobbyJoinable(_lobby_id, true)
	_pending_settings = settings
	_publish_settings(_lobby_id)


## The host leaving for good. Shuts the lobby down **only if nobody else is in
## it.**
##
## **Steam has no way to destroy a lobby**: one exists until its last member
## leaves, and the owner leaving simply promotes somebody else. So when the
## host is the last one out, closing the lobby by both means is the closest
## thing to killing it that Steam offers, and it has to happen before leaving,
## because afterwards this process no longer owns it (D68).
##
## **But when somebody else is still there, the lobby is not dying - it is
## changing hands** (D105), and shutting it down on the way out is sabotage.
## That is what made a migrated lobby unlistable, and this check is the fix:
## the lobby outlives this process either way, so the only question is whether
## it still has anybody in it.
## **Returns whether the lobby died with them**, which is the one case this
## process can be certain about without asking Steam anything later: nobody
## else was in it, so there is no game left to go back to. The caller uses that
## to throw the rejoin record away immediately rather than waiting to be told
## (D115).
func leave_lobby_as_host() -> bool:
	if not _initialised or _lobby_id == 0:
		leave_lobby()
		return false
	var last_one_out: bool = Steam.getNumLobbyMembers(_lobby_id) <= 1
	if last_one_out:
		Steam.setLobbyData(_lobby_id, String(KEY_STATE), STATE_PLAYING)
		Steam.setLobbyJoinable(_lobby_id, false)
	leave_lobby()
	return last_one_out


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
	settings: GameSettings = null,
) -> void:
	if not _initialised:
		lobby_failed.emit("Steam is not running.")
		return
	_pending_lobby_name = lobby_name
	_pending_settings = settings
	var lobby_type: int = LOBBY_PUBLIC
	if invite_only:
		lobby_type = LOBBY_PRIVATE
	Steam.createLobby(lobby_type, max_players)


func join_lobby(lobby_id: int) -> void:
	if not _initialised:
		lobby_failed.emit("Steam is not running.")
		return
	Steam.joinLobby(lobby_id)


## Asks Steam what it knows about a lobby **without joining it**. Answers on
## `lobby_details`.
##
## `Steam.requestLobbyData` exists for exactly this case: you hold a lobby id
## and want to know what it is before committing to it. It is the only way to
## tell a match that is still being played from one that ended an hour ago,
## because the lobby browser cannot see either of them — a match in progress is
## deliberately unlisted (D106).
##
## **Silence is an answer the caller has to cope with.** Steam may never call
## back at all, so nothing here starts a clock: the caller asks again. See
## `Main._ask_whether_the_remembered_match_is_still_there`, which re-asks on a
## timer and treats "no answer yet" as "do not offer it yet".
func request_lobby_details(lobby_id: int) -> void:
	if not _initialised or lobby_id == 0:
		return
	_details_wanted_for = lobby_id
	if not Steam.requestLobbyData(lobby_id):
		# Steam refused to even ask - no connection, usually. Reported as "not
		# there", because an answer that cannot be obtained is not a yes.
		_details_wanted_for = 0
		lobby_details.emit(lobby_id, false, "")


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


# ------------------------------------------------- achievements and counters
#
# Thin by design: which achievements a match has earned is decided by
# `AchievementRules`, which is pure and has no idea Steam exists. These four
# are the only place the game tells Steam anything about a player.
#
# All are no-ops when Steam is not running, so a game played offline simply
# earns nothing rather than needing to ask first.

## Unlocks an achievement. Setting one that is already set is harmless, which
## is what lets the rules hand over everything earned rather than tracking
## what has been awarded before.
##
## Nothing is sent to Steam until `store_progress`.
func unlock(achievement_id: StringName) -> void:
	if not _initialised:
		return
	Steam.setAchievement(String(achievement_id))


## A lifetime counter, or 0 when Steam is not running.
func stat(stat_name: StringName) -> int:
	if not _initialised:
		return 0
	return Steam.getStatInt(String(stat_name))


func set_stat(stat_name: StringName, value: int) -> void:
	if not _initialised:
		return
	Steam.setStatInt(String(stat_name), value)


## Sends everything set since the last call. Steam batches, and an achievement
## that is never stored is never actually awarded.
func store_progress() -> void:
	if not _initialised:
		return
	Steam.storeStats()


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
	_publish_settings(lobby_id)
	lobby_created.emit(lobby_id)


## Writes the match settings a joiner should see before deciding.
##
## Cleared after use so a later lobby cannot inherit the last one's numbers.
## Nothing is written at all when no settings were supplied, which leaves the
## row showing only what it can stand behind.
func _publish_settings(lobby_id: int) -> void:
	var settings: GameSettings = _pending_settings
	_pending_settings = null
	if settings == null:
		return
	Steam.setLobbyData(lobby_id, String(KEY_MODE), GameMode.lobby_value(settings.mode))
	Steam.setLobbyData(lobby_id, String(KEY_YEARS), str(settings.max_years))
	Steam.setLobbyData(lobby_id, String(KEY_CASH), str(settings.starting_cash))
	var loans: String = LOANS_OFF
	if settings.loans_enabled:
		loans = LOANS_ON
	Steam.setLobbyData(lobby_id, String(KEY_LOANS), loans)


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


## Steam answered a `request_lobby_details`.
##
## `success` is Steam's `m_bSuccess`: false when it has nothing for that lobby
## id, which is what a lobby everybody has left looks like from outside.
##
## Updates for any other lobby - our own, most often, since every `setLobbyData`
## call in this file produces one - are dropped. Without that filter the first
## key anybody changed in the current lobby would be read as the answer to a
## question about a different one.
func _on_lobby_data_update(success: int, lobby_id: int, _member_id: int) -> void:
	if lobby_id != _details_wanted_for:
		return
	_details_wanted_for = 0
	if success == 0:
		lobby_details.emit(lobby_id, false, "")
		return
	lobby_details.emit(lobby_id, true, Steam.getLobbyData(lobby_id, String(KEY_STATE)))


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
			# 0 and "" both mean "this lobby did not say", which an older
			# build's lobby will not have.
			"mode": Steam.getLobbyData(id, String(KEY_MODE)),
			"years": Steam.getLobbyData(id, String(KEY_YEARS)).to_int(),
			"cash": Steam.getLobbyData(id, String(KEY_CASH)).to_int(),
			"loans": Steam.getLobbyData(id, String(KEY_LOANS)),
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


## Steam answered a `request_avatar`, with raw pixels rather than an image.
##
## `buffer` is RGBA8, `width` pixels square — Steam gives the size back rather
## than the caller assuming the one it asked for, because a portrait that was
## not cached can come back at whatever size Steam had.
##
## A zero-sized or short buffer means Steam had nothing: the account has no
## avatar, or it is still downloading. Dropped rather than reported, because
## a missing portrait is not a failure anybody can act on.
func _on_avatar_loaded(steam_id: int, width: int, buffer: PackedByteArray) -> void:
	if width <= 0 or buffer.size() < width * width * 4:
		return
	var image: Image = Image.create_from_data(
		width, width, false, Image.FORMAT_RGBA8, buffer
	)
	avatar_ready.emit(steam_id, ImageTexture.create_from_image(image))
