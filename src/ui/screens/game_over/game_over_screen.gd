class_name GameOverScreen
extends MarginContainer
## The result: who won, the final standings, and how the market ended up.
##
## Reads a finished GameState. Emits intent outward; it does not restart anything
## itself.


signal play_again_requested
signal menu_requested

## The host wants another game: reopen the lobby. Only the host's screen can
## emit this, because only the host can reopen a lobby.
signal rematch_offer_requested

## A client is asking the host for another game. Advisory — see D124.
signal rematch_ask_requested

## A client is taking up an offer the host has made.
signal rematch_join_requested

## Stand aside and let the player look at the board as it ended. The original
## did this by closing its winner panel; this screen has to step out of the
## way instead, because it replaced the board rather than sitting over it.
signal view_board_requested

const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")
const HistoryRowScene: PackedScene = preload("res://src/ui/widgets/history_row.tscn")

@onready var _verdict_label: Label = %Verdict
@onready var _detail_label: Label = %Detail
@onready var _ranking_list: VBoxContainer = %FinalRankings
@onready var _seed_label: Label = %SeedLabel
@onready var _again_button: Button = %PlayAgainButton
@onready var _rematch_button: Button = %RematchButton
@onready var _rematch_note: Label = %RematchNote
@onready var _menu_button: Button = %MenuButton
@onready var _board_button: Button = %ViewBoardButton
@onready var _standings_tab: Button = %StandingsTab
@onready var _history_tab: Button = %HistoryTab
@onready var _ranking_scroll: ScrollContainer = %RankingScroll
@onready var _history_box: VBoxContainer = %HistoryBox
@onready var _history_header_slot: MarginContainer = %HistoryHeaderSlot
@onready var _history_list: VBoxContainer = %HistoryList

var _state: GameState
var _local_player_id: StringName = &""

## The live session, so the rematch controls can read what is on offer and say
## so. Null in the tests that drive this screen from a bare state, and on every
## path that has no session to give it — the screen renders the standings
## either way and simply shows no rematch controls.
var _session: GameSession

## The same session under its two concrete types, because `match_started` is
## declared on each side rather than on the interface — the lobby screen holds
## them the same way and for the same reason.
var _host: HostSession
var _client: ClientSession

## Whether *Play again* is on this screen at all. Off for a networked match —
## see `offer_play_again`.
var _play_again_is_offered: bool = true

## Whether this player has already asked the host for another game. Local to
## this screen: the host is told, but nobody is told back, because an ask
## decides nothing and a client has no use for anybody else's.
var _has_asked: bool = false


func _ready() -> void:
	_again_button.pressed.connect(_on_again_button_pressed)
	_rematch_button.pressed.connect(_on_rematch_button_pressed)
	_menu_button.pressed.connect(_on_menu_button_pressed)
	_board_button.pressed.connect(_on_board_button_pressed)
	_standings_tab.pressed.connect(_on_standings_tab_pressed)
	_history_tab.pressed.connect(_on_history_tab_pressed)

	_again_button.visible = _play_again_is_offered

	var header: HistoryRow = HistoryRowScene.instantiate()
	_history_header_slot.add_child(header)
	header.configure_as_header()

	_attach()
	_refresh_rematch()

	if _state != null:
		_render()


## Stops listening the moment this screen leaves the tree.
##
## The same crash the lobby and the playing screen both had: `Main` swaps with
## `remove_child` plus a deferred `queue_free`, so without this a replaced
## screen still reacts to the next session signal and touches `@onready` nodes
## that are no longer in the tree. See decisions.md D61.
func _exit_tree() -> void:
	_detach()


func _attach() -> void:
	if _session == null:
		return
	if _session.rematch_offered.is_connected(_refresh_rematch):
		return
	_session.rematch_offered.connect(_refresh_rematch)
	_session.rematch_requested.connect(_on_rematch_requested)
	# **The result screen reacts to the match starting by putting its own
	# controls away, never by changing screen.** `start_match` broadcasts to
	# every peer, seated or not (`host_session.gd`), so this arrives at players
	# who declined the rematch as well as those who took it. Swapping them onto
	# a board would put them in a match they chose not to join; what they need
	# is for the way in to stop looking open. See decisions.md D124.
	if _host != null:
		_host.match_started.connect(_refresh_rematch)
	if _client != null:
		_client.match_started.connect(_refresh_rematch)


func _detach() -> void:
	if _session == null:
		return
	if not _session.rematch_offered.is_connected(_refresh_rematch):
		return
	_session.rematch_offered.disconnect(_refresh_rematch)
	_session.rematch_requested.disconnect(_on_rematch_requested)
	if _host != null:
		_host.match_started.disconnect(_refresh_rematch)
	if _client != null:
		_client.match_started.disconnect(_refresh_rematch)


## Whether to offer *Play again*. Off hides the button rather than disabling it:
## a greyed-out button is a question the screen cannot answer.
##
## **It is offered in a solo game and nowhere else.** *Play again* starts a
## single-player match from the finished settings, which is the only thing it
## has ever done — so in a networked match it took the player out of the game
## everybody else was still in, and on the host it tore the session down and
## sent the others off to find a new host. The original has no rematch at all:
## its result panel has `Quit Game` and a close box (audit §12), so a results
## screen with *Main menu* and *View board* is what the port is meant to be.
##
## Follows `LobbyScreen.offer_invites`: callable before this screen is in the
## tree, because the caller should not have to know when `@onready` ran. See
## docs/decisions.md D122.
func offer_play_again(offered: bool) -> void:
	_play_again_is_offered = offered
	if is_node_ready():
		_again_button.visible = offered


## Hands this screen the live session, so the rematch controls can say what is
## on offer. Optional: without one the screen is the standings and nothing else.
##
## Called before the screen is in the tree, like `LobbyScreen.setup`, so the
## wiring happens in `_ready` rather than here.
func setup(session: GameSession) -> void:
	_session = session
	_host = session as HostSession
	_client = session as ClientSession
	if is_node_ready():
		_attach()
		_refresh_rematch()


# ------------------------------------------------------------------ the rematch
#
# One button, which says a different thing depending on what this machine can
# do about a rematch: the host can reopen the lobby, a client can ask for one,
# and once the host has offered, a client can go and take a seat. Nobody is
# waited on — a player who never presses it is simply not in the next match.
# See docs/decisions.md D124.
#
# **The wording of all of it is placeholder.** Buttons and the line naming who
# asked are the owner's words to write.

## Re-reads the session and puts the button into whichever state fits. Connected
## to three signals and called on every one, because any of them can change the
## answer.
func _refresh_rematch() -> void:
	if _session == null:
		_rematch_button.visible = false
		_rematch_note.text = ""
		return

	_rematch_note.text = RematchNotice.for_session(_session)

	if _host != null:
		_rematch_button.visible = _session.can_offer_rematch()
		_rematch_button.text = "Return to lobby"
		return

	if _client == null:
		# A solo game. *Play again* is the rematch there, and it is a different
		# button.
		_rematch_button.visible = false
		_rematch_note.text = ""
		return

	# **The offer is said outright, not left to a button quietly changing its
	# label.** A player reading the standings is not watching the buttons, and
	# the host going back to the lobby is news: it is the moment the game is
	# waiting on them rather than the other way round. Reported from play on
	# 2026-11-20; the sentence itself is `RematchNotice`, which the final board
	# shows too.
	if _session.rematch_is_offered():
		_rematch_button.visible = true
		_rematch_button.disabled = false
		_rematch_button.text = "Return to lobby"
	else:
		# No offer: all a client can do is ask. Once asked, the button stays on
		# screen saying so rather than vanishing, because a control that
		# disappears when pressed reads as a misfire.
		_rematch_button.visible = true
		_rematch_button.disabled = _has_asked
		_rematch_button.text = "Rematch requested" if _has_asked else "Request rematch"


## What the rematch line currently says, for a test. Nothing in the game reads
## it back.
func rematch_note_for_testing() -> String:
	return _rematch_note.text


func _on_rematch_requested(_player_id: StringName) -> void:
	_refresh_rematch()


func _on_rematch_button_pressed() -> void:
	if _host != null:
		rematch_offer_requested.emit()
		return
	if _session != null and _session.rematch_is_offered():
		rematch_join_requested.emit()
		return
	_has_asked = true
	_refresh_rematch()
	rematch_ask_requested.emit()


## Shows the result of a finished match.
func display(state: GameState, local_player_id: StringName) -> void:
	_state = state
	_local_player_id = local_player_id
	if is_node_ready():
		_render()


func _render() -> void:
	var result: YearResult = _state.latest_result()
	# Written as a block rather than `result.winners if result != null else []`,
	# which looked right and was not: the bare `[]` is an untyped `Array`, and
	# assigning one to an `Array[StringName]` fails at *run* time, so the
	# defensive branch took the screen down instead of saving it. Nothing in
	# play reaches it — a match that is over has a result — which is why it sat
	# there until a test drove this screen with no history. See D113.
	var winners: Array[StringName] = []
	if result != null:
		winners = result.winners

	var names: PackedStringArray = PackedStringArray()
	for winner_id: StringName in winners:
		var player: PlayerState = _state.player_by_id(winner_id)
		if player != null:
			names.append(player.display_name)

	if names.is_empty():
		_verdict_label.text = "No winner"
	elif names.size() == 1 and winners[0] == _local_player_id:
		# "You wins" otherwise, because a solo player is literally called
		# "You". Worth the branch: it is the first line of the screen and
		# every single-player game ends on it.
		_verdict_label.text = "You win"
	elif names.size() == 1:
		_verdict_label.text = "%s wins" % names[0]
	else:
		# All tied players win — see docs/game-rules.md §1.
		_verdict_label.text = "A tie: %s" % ", ".join(names)

	var me: PlayerState = _state.player_by_id(_local_player_id)
	if me != null:
		var started: int = _state.settings.starting_cash
		var change: int = me.net_worth - started
		_detail_label.text = "You finished on %s, %s from %s after %d years." % [
			Palette.format_money(me.net_worth),
			(
				"up %s" % Palette.format_money(change) if change >= 0
				else "down %s" % Palette.format_money(-change)
			),
			Palette.format_money(started),
			_state.settings.max_years,
		]
		_detail_label.add_theme_color_override("font_color", Palette.for_change(change))

	_seed_label.text = "seed %d — the same seed always plays out identically" % (
		_state.settings.rng_seed
	)

	for child: Node in _ranking_list.get_children():
		_ranking_list.remove_child(child)
		child.queue_free()

	var order: Array[StringName] = (
		result.rankings if result != null else TradeRules.rank(_state.players)
	)
	var host_id: StringName = _state.host_player_id()
	for index: int in order.size():
		var player: PlayerState = _state.player_by_id(order[index])
		if player == null:
			continue
		var row: RankingRow = RankingRowScene.instantiate()
		_ranking_list.add_child(row)
		row.display(player, player.id == _local_player_id, true, player.id == host_id)

	_build_history()


# ----------------------------------------------------------------- year by year
#
# The match's own history, which every machine already has: a client appends
# each year's result as it arrives and the host keeps its own. Nothing new
# crosses the wire for this.
#
# It shares the standings' space rather than being added below it. The card is
# 520x310 inside a 640x360 window and there was no room for a second list; a
# tab costs one row and the board is already dense enough elsewhere.

## One row per year: the year, its mood, what you were worth at the end of it,
## and what the market did.
func _build_history() -> void:
	for child: Node in _history_list.get_children():
		_history_list.remove_child(child)
		child.queue_free()

	for result: YearResult in _state.history:
		var row: HistoryRow = HistoryRowScene.instantiate()
		_history_list.add_child(row)
		row.display(
			result.year,
			result.mood,
			result.net_worths.get(_local_player_id, 0),
			_what_happened_in(result),
		)


## A year in a phrase.
##
## The event first, because it is the thing with a name; then splits and
## bankruptcies, which are rarer and worth knowing about. A quiet year says so
## rather than leaving the column blank, which reads as missing data.
func _what_happened_in(result: YearResult) -> String:
	var parts: PackedStringArray = PackedStringArray()

	if result is EarningsYearResult:
		var words: YearEventText = YearEventText.of(_state, result as EarningsYearResult)
		if not words.strip_effect().is_empty():
			parts.append(words.strip_effect())
	elif result.event != null:
		var target: StalkState = _state.stalk_by_id(result.event.target_stalk_id)
		var target_name: String = String(result.event.target_stalk_id)
		if target != null:
			target_name = target.definition.display_name
		var direction: String = "fell"
		if result.event.price_change > 0:
			direction = "rose"
		parts.append("%s %s %d" % [target_name, direction, absi(result.event.price_change)])

	var splits: Array[StringName] = result.split_ids()
	if not splits.is_empty():
		parts.append("split: %s" % ", ".join(_names_of(splits)))

	var bankruptcies: Array[StringName] = result.bankrupt_ids()
	if not bankruptcies.is_empty():
		parts.append("bankrupt: %s" % ", ".join(_names_of(bankruptcies)))

	if parts.is_empty():
		return "a quiet year"
	return " — ".join(parts)


func _names_of(stalk_ids: Array[StringName]) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for stalk_id: StringName in stalk_ids:
		var stalk: StalkState = _state.stalk_by_id(stalk_id)
		if stalk != null:
			names.append(stalk.definition.display_name)
		else:
			names.append(String(stalk_id))
	return names


func _on_standings_tab_pressed() -> void:
	show_standings()


func _on_history_tab_pressed() -> void:
	show_history()


## Public so a test can look at either list without clicking.
func show_standings() -> void:
	_ranking_scroll.visible = true
	_history_box.visible = false
	_standings_tab.button_pressed = true
	_history_tab.button_pressed = false


func show_history() -> void:
	_ranking_scroll.visible = false
	_history_box.visible = true
	_standings_tab.button_pressed = false
	_history_tab.button_pressed = true


# ------------------------------------------------------------------- for tests

## The year rows, for a test that wants to read them without the tree.
func history_rows() -> Array[Node]:
	return _history_list.get_children()

func verdict_text() -> String:
	return _verdict_label.text


func detail_text() -> String:
	return _detail_label.text


func ranking_count() -> int:
	return _ranking_list.get_child_count()


## "Play again" — a new match on a fresh seed, not a replay. See decisions.md
## D38. This screen only reports the click; Main decides what it means.
func _on_again_button_pressed() -> void:
	play_again_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()


## The player wants the finished board rather than the summary of it.
func _on_board_button_pressed() -> void:
	view_board_requested.emit()
