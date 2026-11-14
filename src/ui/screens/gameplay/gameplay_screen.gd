extends MarginContainer
## The playing screen: the market board, the player's holdings, the standings,
## and the control that advances the year.
##
## Holds no rules. It reads state from a GameSession to render, and turns clicks
## into `request_*` calls. Every number shown is computed by the simulation —
## see docs/architecture.md §6.
##
## The root is a MarginContainer rather than an anchored Control, so every piece
## of this screen is laid out by a container and there are no anchors to get
## wrong. An earlier version anchored a Control and produced dead space at the
## top and bottom of the window; see docs/decisions.md D35.
##
## Tests inject a session with `setup()`. Run directly it builds a default solo
## game, so the screen is never empty.


const StalkRowScene: PackedScene = preload("res://src/ui/widgets/stalk_row.tscn")
const HoldingRowScene: PackedScene = preload("res://src/ui/widgets/holding_row.tscn")
const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")
const LoanPanelScene: PackedScene = preload("res://src/ui/widgets/loan_panel.tscn")

## How long a rejection message stays on screen.
const MESSAGE_SECONDS: float = 4.0

## Emitted when the match ends, so whoever owns this screen can move on.
signal match_finished(winners: Array[StringName])

@onready var _year_label: Label = %YearLabel
@onready var _mood_label: Label = %MoodLabel
@onready var _seed_label: Label = %SeedLabel
@onready var _cash_label: Label = %CashLabel
@onready var _net_worth_label: Label = %NetWorthLabel
@onready var _loan_box: VBoxContainer = %LoanBox
@onready var _loan_owed_label: Label = %LoanOwedLabel
@onready var _event_panel: PanelContainer = %EventPanel
@onready var _event_flavour: Label = %EventFlavour
@onready var _event_effect: Label = %EventEffect
@onready var _year_summary: Label = %YearSummary
@onready var _board_header_slot: MarginContainer = %BoardHeaderSlot
@onready var _holdings_header_slot: MarginContainer = %HoldingsHeaderSlot
@onready var _stalk_scroll: ScrollContainer = %StalkScroll
@onready var _holding_scroll: ScrollContainer = %HoldingScroll
@onready var _stalk_list: VBoxContainer = %StalkList
@onready var _holding_list: VBoxContainer = %HoldingList
@onready var _holdings_empty: Label = %HoldingsEmpty
@onready var _ranking_list: VBoxContainer = %RankingList
@onready var _message_label: Label = %MessageLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _loan_button: Button = %LoanButton
@onready var _message_timer: Timer = %MessageTimer

var _session: GameSession
var _stalk_rows: Dictionary[StringName, StalkRow] = {}
var _loan_panel: LoanPanel


func _ready() -> void:
	_ready_button.pressed.connect(_on_ready_pressed)
	_loan_button.pressed.connect(_on_loan_button_pressed)
	_message_timer.timeout.connect(_clear_message)
	_message_timer.wait_time = MESSAGE_SECONDS
	_message_timer.one_shot = true

	_build_headers()

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
		for error: String in library.errors:
			push_error("Content error: %s" % error)

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.loans_enabled = true

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
	_build_loan_panel()
	_reset_year_panel()
	refresh()


# ----------------------------------------------------------------- construction

## The column headers are the row widgets themselves, in header mode. A
## separately built header drifts out of alignment the moment a column changes —
## which it did. See StalkRow.
func _build_headers() -> void:
	var stalk_header: StalkRow = StalkRowScene.instantiate()
	_board_header_slot.add_child(stalk_header)
	stalk_header.configure_as_header()

	var holding_header: HoldingRow = HoldingRowScene.instantiate()
	_holdings_header_slot.add_child(holding_header)
	holding_header.configure_as_header()

	# The headers sit OUTSIDE their scroll containers so they stay put while the
	# list scrolls — which means they are also not narrowed by the scrollbar the
	# list reserves. Left alone, every column sat 8px off whenever a scrollbar
	# was present, and lined up only when it was not. Both scrolls therefore show
	# their vertical bar permanently, and each header is inset by exactly that
	# width.
	_inset_header_for_scrollbar(_board_header_slot, _stalk_scroll)
	_inset_header_for_scrollbar(_holdings_header_slot, _holding_scroll)


func _inset_header_for_scrollbar(slot: MarginContainer, scroll: ScrollContainer) -> void:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var width: int = int(bar.get_combined_minimum_size().x) if bar != null else 0
	slot.add_theme_constant_override("margin_right", width)


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


func _build_loan_panel() -> void:
	if _loan_panel != null:
		return
	_loan_panel = LoanPanelScene.instantiate()
	add_child(_loan_panel)
	_loan_panel.setup(_session)
	_loan_panel.borrow_requested.connect(_on_borrow_requested)
	_loan_panel.payment_requested.connect(_on_payment_requested)
	_loan_panel.hide_panel()


## Empties a container **synchronously**.
##
## `queue_free()` alone is not enough: it defers until the end of the frame, so a
## freed row is still a child immediately afterwards. Anything that then counts
## or searches the container sees rows that are logically gone — a sold-out
## position would still appear on the board until the next frame.
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
	_refresh_loan_controls(game, player)


func _refresh_header(game: GameState, player: PlayerState) -> void:
	_year_label.text = "Year %d of %d" % [game.year, game.settings.max_years]

	var latest: YearResult = game.latest_result()
	if latest != null:
		_mood_label.text = MarketMood.label(latest.mood)
		_mood_label.add_theme_color_override("font_color", Palette.for_mood(latest.mood))
	else:
		_mood_label.text = ""

	# The seed is what makes a match reproducible, so it is worth being able to
	# read off the screen when something looks wrong.
	_seed_label.text = "seed %d" % game.settings.rng_seed

	_cash_label.text = Palette.format_money(player.cash)
	_net_worth_label.text = Palette.format_money(player.net_worth)

	var owed: int = player.owes()
	_loan_box.visible = owed > 0
	_loan_owed_label.text = Palette.format_money(owed)
	_loan_owed_label.add_theme_color_override("font_color", Palette.BEAR)


func _refresh_board(game: GameState, player: PlayerState) -> void:
	for stalk: StalkState in game.stalks:
		var row: StalkRow = _stalk_rows.get(stalk.id)
		if row == null:
			continue
		row.display(stalk)
		row.set_affordable_hint(TradeRules.max_affordable(player, stalk))
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


func _refresh_loan_controls(game: GameState, player: PlayerState) -> void:
	var loans_on: bool = game.settings != null and game.settings.loans_enabled
	_loan_button.visible = loans_on and not game.is_over

	if not loans_on:
		return

	# The prompt is advisory, never blocking: a player may ready up with a
	# payment outstanding and take the penalty. See docs/game-rules.md §9.5.
	if player.has_outstanding_loan() and not player.loan.paid_this_year:
		_loan_button.text = "Loan payment due: %s" % Palette.format_money(
			player.loan.min_payment
		)
		_loan_button.theme_type_variation = &"PrimaryButton"
	elif player.has_outstanding_loan():
		_loan_button.text = "Loan (paid this year)"
		_loan_button.theme_type_variation = &""
	else:
		_loan_button.text = "Take a loan…"
		_loan_button.theme_type_variation = &""

	if _loan_panel != null and _loan_panel.is_showing():
		_loan_panel.refresh()


# --------------------------------------------------------------- live validation

func _validate_buy_row(row: StalkRow, shares: int) -> void:
	if shares <= 0 or row.is_bankrupt_row():
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


func _on_loan_button_pressed() -> void:
	if _loan_panel != null:
		_loan_panel.show_panel()


func _on_borrow_requested(amount: int) -> void:
	_session.request_loan(_session.local_player_id(), amount)


func _on_payment_requested(amount: int) -> void:
	_session.pay_loan(_session.local_player_id(), amount)


# -------------------------------------------------------------- session handlers

func _on_player_changed(_player_id: StringName) -> void:
	_clear_message()
	for row: StalkRow in _stalk_rows.values():
		row.clear_amount()
	refresh()
	if _loan_panel != null and _loan_panel.is_showing():
		_loan_panel.refresh()


func _on_year_resolved(result: YearResult) -> void:
	_clear_message()
	_show_year_panel(result)
	refresh()


func _on_action_rejected(_player_id: StringName, reason: String) -> void:
	_show_message(reason)


func _on_game_over(winners: Array[StringName]) -> void:
	if _loan_panel != null:
		_loan_panel.hide_panel()
	match_finished.emit(winners)


# ------------------------------------------------------------------ presentation

func _reset_year_panel() -> void:
	# The panel keeps its space whether or not an event fired, so the rest of the
	# screen does not jump when one does.
	_event_flavour.text = ""
	_event_effect.text = "The market opens. Buy and sell, then ready up."
	_event_effect.remove_theme_color_override("font_color")
	_year_summary.text = ""


func _show_year_panel(result: YearResult) -> void:
	if result.event == null:
		_event_flavour.text = ""
		_event_effect.text = "No special event this year."
		_event_effect.remove_theme_color_override("font_color")
	else:
		var target: StalkState = _session.state().stalk_by_id(result.event.target_stalk_id)
		var target_name: String = (
			target.definition.display_name
			if target != null
			else String(result.event.target_stalk_id)
		)
		_event_flavour.text = result.event.flavour_text
		_event_effect.text = "%s %s by %d" % [
			target_name,
			"rose" if result.event.price_change > 0 else "fell",
			absi(result.event.price_change),
		]
		_event_effect.add_theme_color_override(
			"font_color", Palette.for_change(result.event.price_change)
		)

	_year_summary.text = _summarise(result)


## The one-line digest of what else happened: dividends, splits, bankruptcies and
## any loan activity. These all happen in the simulation and were previously
## invisible, which made a doubled share count look like a bug.
func _summarise(result: YearResult) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var me: StringName = _session.local_player_id()

	var dividend: int = result.dividends.get(me, 0)
	if dividend > 0:
		parts.append("Dividends %s" % Palette.format_money(dividend))

	var splits: Array[StringName] = result.split_ids()
	if not splits.is_empty():
		parts.append("Split: %s" % ", ".join(_display_names(splits)))

	var bankruptcies: Array[StringName] = result.bankrupt_ids()
	if not bankruptcies.is_empty():
		parts.append("Bankrupt: %s" % ", ".join(_display_names(bankruptcies)))

	var loan_change: LoanYearChange = result.loan_change_for(me)
	if loan_change != null:
		if loan_change.defaulted:
			parts.append("LOAN DEFAULTED — assets seized")
		else:
			if loan_change.penalty_added > 0:
				parts.append("Missed payment penalty %s" % Palette.format_money(
					loan_change.penalty_added
				))
			if loan_change.interest_added > 0:
				parts.append("Loan interest %s" % Palette.format_money(
					loan_change.interest_added
				))

	return " · ".join(parts)


func _display_names(ids: Array[StringName]) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for stalk_id: StringName in ids:
		var stalk: StalkState = _session.state().stalk_by_id(stalk_id)
		names.append(stalk.definition.display_name if stalk != null else String(stalk_id))
	return names


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_label.theme_type_variation = &"Danger"
	_message_timer.start()


func _clear_message() -> void:
	_message_label.text = ""
	_message_timer.stop()


# ------------------------------------------------------------------- for tests

func current_message() -> String:
	return _message_label.text


func year_summary_text() -> String:
	return _year_summary.text


func stalk_row_for(stalk_id: StringName) -> StalkRow:
	return _stalk_rows.get(stalk_id)


func holding_row_for(stalk_id: StringName) -> HoldingRow:
	for child: Node in _holding_list.get_children():
		var row: HoldingRow = child as HoldingRow
		if row != null and row.stalk_id() == stalk_id:
			return row
	return null


func holding_row_count() -> int:
	var count: int = 0
	for child: Node in _holding_list.get_children():
		if child is HoldingRow:
			count += 1
	return count


func loan_panel() -> LoanPanel:
	return _loan_panel
