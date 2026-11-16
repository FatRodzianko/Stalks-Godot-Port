class_name GameOverScreen
extends MarginContainer
## The result: who won, the final standings, and how the market ended up.
##
## Reads a finished GameState. Emits intent outward; it does not restart anything
## itself.


signal play_again_requested
signal menu_requested

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


func _ready() -> void:
	_again_button.pressed.connect(_on_again_button_pressed)
	_menu_button.pressed.connect(_on_menu_button_pressed)
	_board_button.pressed.connect(_on_board_button_pressed)
	_standings_tab.pressed.connect(_on_standings_tab_pressed)
	_history_tab.pressed.connect(_on_history_tab_pressed)

	var header: HistoryRow = HistoryRowScene.instantiate()
	_history_header_slot.add_child(header)
	header.configure_as_header()

	if _state != null:
		_render()


## Shows the result of a finished match.
func display(state: GameState, local_player_id: StringName) -> void:
	_state = state
	_local_player_id = local_player_id
	if is_node_ready():
		_render()


func _render() -> void:
	var result: YearResult = _state.latest_result()
	var winners: Array[StringName] = result.winners if result != null else []

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

	if result.event != null:
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
