class_name GameOverScreen
extends MarginContainer
## The result: who won, the final standings, and how the market ended up.
##
## Reads a finished GameState. Emits intent outward; it does not restart anything
## itself.


signal play_again_requested
signal menu_requested

const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")

@onready var _verdict_label: Label = %Verdict
@onready var _detail_label: Label = %Detail
@onready var _ranking_list: VBoxContainer = %FinalRankings
@onready var _seed_label: Label = %SeedLabel
@onready var _again_button: Button = %PlayAgainButton
@onready var _menu_button: Button = %MenuButton

var _state: GameState
var _local_player_id: StringName = &""


func _ready() -> void:
	_again_button.pressed.connect(func() -> void: play_again_requested.emit())
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())
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
	for index: int in order.size():
		var player: PlayerState = _state.player_by_id(order[index])
		if player == null:
			continue
		var row: RankingRow = RankingRowScene.instantiate()
		_ranking_list.add_child(row)
		row.display(index, player, player.id == _local_player_id)


# ------------------------------------------------------------------- for tests

func verdict_text() -> String:
	return _verdict_label.text


func detail_text() -> String:
	return _detail_label.text


func ranking_count() -> int:
	return _ranking_list.get_child_count()
