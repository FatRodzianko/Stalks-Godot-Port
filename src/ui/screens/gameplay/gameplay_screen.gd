extends Control
## The playing screen: the market board, the player's holdings, the standings,
## and the control that advances the year.
##
## Holds no rules. It reads state from a GameSession to render, and turns clicks
## into `request_*` calls. Every number shown is computed by the simulation —
## see docs/architecture.md §6.
##
## Tests inject a session with `setup()`. Run directly (as the project's main
## scene) it builds a default solo game so the screen is never empty.


const StalkRowScene: PackedScene = preload("res://src/ui/widgets/stalk_row.tscn")
const HoldingRowScene: PackedScene = preload("res://src/ui/widgets/holding_row.tscn")
const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")

## How long a rejection message stays on screen.
const MESSAGE_SECONDS: float = 4.0

@onready var _year_label: Label = %YearLabel
@onready var _mood_label: Label = %MoodLabel
@onready var _cash_label: Label = %CashLabel
@onready var _net_worth_label: Label = %NetWorthLabel
@onready var _event_panel: PanelContainer = %EventPanel
@onready var _event_flavour: Label = %EventFlavour
@onready var _event_effect: Label = %EventEffect
@onready var _stalk_list: VBoxContainer = %StalkList
@onready var _holding_list: VBoxContainer = %HoldingList
@onready var _holdings_empty: Label = %HoldingsEmpty
@onready var _ranking_list: VBoxContainer = %RankingList
@onready var _message_label: Label = %MessageLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _message_timer: Timer = %MessageTimer

var _session: GameSession
var _stalk_rows: Dictionary[StringName, StalkRow] = {}


func _ready() -> void:
	_ready_button.pressed.connect(_on_ready_pressed)
	_message_timer.timeout.connect(_clear_message)
	_message_timer.wait_time = MESSAGE_SECONDS
	_message_timer.one_shot = true

	if _session == null:
		_session = _build_default_session()
	_attach(_session)


## Injects a session. Call before the screen enters the tree, or immediately
## after; either order works.
func setup(session: GameSession) -> void:
	_session = session
	if is_node_ready():
		_attach(session)


func session() -> GameSession:
	return _session


func _build_default_session() -> GameSession:
	var library: ContentLibrary = ContentLibrary.load_from()
	if not library.is_valid():
		# Loud rather than silent: a content error means the game cannot be
		# trusted, and the validator already said exactly what is wrong.
		for error: String in library.errors:
			push_error("Content error: %s" % error)

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	# Loans stay off until the loan panel exists — better absent than present
	# and unreachable.
	settings.loans_enabled = false

	var session: LocalSession = LocalSession.create(settings, library)
	add_child(session)
	return session


func _attach(session: GameSession) -> void:
	if session == null:
		return
	if not session.year_resolved.is_connected(_on_year_resolved):
		session.year_resolved.connect(_on_year_resolved)
		session.player_changed.connect(_on_player_changed)
		session.action_rejected.connect(_on_action_rejected)
		session.game_over.connect(_on_game_over)

	_build_stalk_rows()
	_event_panel.visible = false
	refresh()


# ----------------------------------------------------------------- construction

## The market board is built once — ten rows that persist for the whole match —
## so a half-typed amount survives a refresh.
func _build_stalk_rows() -> void:
	_clear_children(_stalk_list)
	_stalk_rows.clear()

	for stalk: StalkState in _session.state().stalks:
		var row: StalkRow = StalkRowScene.instantiate()
		_stalk_list.add_child(row)
		row.display(stalk)
		row.buy_requested.connect(_on_buy_requested)
		row.amount_changed.connect(_on_buy_amount_changed)
		_stalk_rows[stalk.id] = row


## Empties a container **synchronously**.
##
## `queue_free()` alone is not enough: it defers until the end of the frame, so a
## freed row is still a child immediately afterwards. Anything that then counts
## or searches the container sees rows that are logically gone — a sold-out
## position would still appear on the board until the next frame. Removing from
## the tree first makes the container correct the instant this returns.
func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


# -------------------------------------------------------------------- rendering

## Redraws everything from current state. Cheap enough to call on any change.
func refresh() -> void:
	if _session == null or _session.state() == null:
		return

	var game: GameState = _session.state()
	var player: PlayerState = game.player_by_id(_session.local_player_id())
	if player == null:
		return

	_refresh_header(game, player)
	_refresh_board(game, player)
	_refresh_holdings(game, player)
	_refresh_standings(game)
	_refresh_ready_button(game)


func _refresh_header(game: GameState, player: PlayerState) -> void:
	_year_label.text = "Year %d of %d" % [game.year, game.settings.max_years]

	var latest: YearResult = game.latest_result()
	if latest != null:
		_mood_label.text = MarketMood.label(latest.mood)
		_mood_label.add_theme_color_override("font_color", Palette.for_mood(latest.mood))
	else:
		_mood_label.text = ""

	_cash_label.text = Palette.format_money(player.cash)
	_net_worth_label.text = Palette.format_money(player.net_worth)


func _refresh_board(game: GameState, player: PlayerState) -> void:
	for stalk: StalkState in game.stalks:
		var row: StalkRow = _stalk_rows.get(stalk.id)
		if row == null:
			continue
		row.display(stalk)
		row.set_affordable_hint(TradeRules.max_affordable(player, stalk))
		# Re-validate whatever is currently typed, so a figure that was
		# affordable last year and is not now turns red immediately.
		_validate_buy_row(row, row.shares_entered())


func _refresh_holdings(game: GameState, player: PlayerState) -> void:
	_clear_children(_holding_list)

	var held_any: bool = false
	for stalk: StalkState in game.stalks:
		var shares: int = player.shares_of(stalk.id)
		if shares <= 0:
			continue
		held_any = true
		var row: HoldingRow = HoldingRowScene.instantiate()
		_holding_list.add_child(row)
		row.display(stalk, shares)
		row.sell_requested.connect(_on_sell_requested)
		row.sell_all_requested.connect(_on_sell_all_requested)
		row.amount_changed.connect(_on_sell_amount_changed)

	_holdings_empty.visible = not held_any


func _refresh_standings(game: GameState) -> void:
	_clear_children(_ranking_list)

	var latest: YearResult = game.latest_result()
	var order: Array[StringName] = (
		latest.rankings if latest != null else TradeRules.rank(game.players)
	)

	for index: int in order.size():
		var player: PlayerState = game.player_by_id(order[index])
		if player == null:
			continue
		var row: RankingRow = RankingRowScene.instantiate()
		_ranking_list.add_child(row)
		row.display(index, player, player.id == _session.local_player_id())


func _refresh_ready_button(game: GameState) -> void:
	if game.is_over:
		_ready_button.text = "Game Over"
		_ready_button.disabled = true
		return

	_ready_button.disabled = false
	_ready_button.text = (
		"Finish Year %d" % game.settings.max_years
		if game.year >= game.settings.max_years
		else "Ready for New Year"
	)


# --------------------------------------------------------------- live validation

func _validate_buy_row(row: StalkRow, shares: int) -> void:
	if shares <= 0:
		# Nothing typed yet is not an error; do not shout at a blank field.
		row.set_buy_blocked("")
		return
	row.set_buy_blocked(
		_session.why_not_buy(_session.local_player_id(), row.stalk_id(), shares)
	)


# ------------------------------------------------------------------- UI handlers

func _on_buy_amount_changed(stalk_id: StringName, shares: int) -> void:
	var row: StalkRow = _stalk_rows.get(stalk_id)
	if row != null:
		_validate_buy_row(row, shares)


func _on_sell_amount_changed(stalk_id: StringName, shares: int) -> void:
	for child: Node in _holding_list.get_children():
		var row: HoldingRow = child as HoldingRow
		if row == null or row.stalk_id() != stalk_id:
			continue
		if shares <= 0:
			row.set_sell_blocked("")
		else:
			row.set_sell_blocked(
				_session.why_not_sell(_session.local_player_id(), stalk_id, shares)
			)


func _on_buy_requested(stalk_id: StringName, shares: int) -> void:
	if shares <= 0:
		_show_message("Enter how many shares to buy.")
		return
	_session.request_buy(_session.local_player_id(), stalk_id, shares)


func _on_sell_requested(stalk_id: StringName, shares: int) -> void:
	if shares <= 0:
		_show_message("Enter how many shares to sell.")
		return
	_session.request_sell(_session.local_player_id(), stalk_id, shares)


func _on_sell_all_requested(stalk_id: StringName) -> void:
	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	if player == null:
		return
	_session.request_sell(_session.local_player_id(), stalk_id, player.shares_of(stalk_id))


func _on_ready_pressed() -> void:
	_session.set_ready(_session.local_player_id(), true)


# -------------------------------------------------------------- session handlers

func _on_player_changed(_player_id: StringName) -> void:
	_clear_message()
	for row: StalkRow in _stalk_rows.values():
		row.clear_amount()
	refresh()


func _on_year_resolved(result: YearResult) -> void:
	_clear_message()
	_show_event(result)
	refresh()


func _on_action_rejected(_player_id: StringName, reason: String) -> void:
	_show_message(reason)


func _on_game_over(winners: Array[StringName]) -> void:
	var game: GameState = _session.state()
	var names: PackedStringArray = PackedStringArray()
	for winner_id: StringName in winners:
		var player: PlayerState = game.player_by_id(winner_id)
		if player != null:
			names.append(player.display_name)

	var text: String = (
		"Game over — %s wins!" % names[0]
		if names.size() == 1
		else "Game over — a tie between %s!" % ", ".join(names)
	)
	_message_label.text = text
	_message_label.theme_type_variation = &"Bull"
	_message_timer.stop()


# ------------------------------------------------------------------ presentation

func _show_event(result: YearResult) -> void:
	if result.event == null:
		_event_panel.visible = false
		return

	var target: StalkState = _session.state().stalk_by_id(result.event.target_stalk_id)
	var target_name: String = (
		target.definition.display_name if target != null else String(result.event.target_stalk_id)
	)

	_event_panel.visible = true
	_event_flavour.text = result.event.flavour_text
	_event_effect.text = "%s %s by %d" % [
		target_name,
		"rose" if result.event.price_change > 0 else "fell",
		absi(result.event.price_change),
	]
	_event_effect.add_theme_color_override(
		"font_color", Palette.for_change(result.event.price_change)
	)


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_label.theme_type_variation = &"Danger"
	_message_timer.start()


func _clear_message() -> void:
	_message_label.text = ""
	_message_timer.stop()


## For tests: whatever the player is currently being told.
func current_message() -> String:
	return _message_label.text


## For tests: the board row for a stalk, so a test can drive the real control
## rather than calling into the session directly.
func stalk_row_for(stalk_id: StringName) -> StalkRow:
	return _stalk_rows.get(stalk_id)


## For tests: the holdings row for a stalk, or null if nothing is held.
func holding_row_for(stalk_id: StringName) -> HoldingRow:
	for child: Node in _holding_list.get_children():
		var row: HoldingRow = child as HoldingRow
		if row != null and row.stalk_id() == stalk_id:
			return row
	return null


## For tests: how many positions the holdings board is showing.
func holding_row_count() -> int:
	var count: int = 0
	for child: Node in _holding_list.get_children():
		if child is HoldingRow:
			count += 1
	return count
