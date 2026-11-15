class_name GameplayScreen
extends MarginContainer
## The playing screen.
##
## Layout follows the original game — three columns of Available Stalks, Your
## Stats + Your Stalks, and Player Rankings, with the year and special event
## across the top and messages plus the ready control along the bottom. See
## docs/ui-reference.md, which is read from the original's scene and prefabs.
##
## Construction does NOT follow the original: this holds no rules and owns no
## state. It reads from a GameSession to render and turns clicks into `request_*`
## calls. See docs/architecture.md §6.
##
## Tests inject a session with `setup()`. Run directly it builds a default solo
## game so the screen is never empty.


const StalkRowScene: PackedScene = preload("res://src/ui/widgets/stalk_row.tscn")
const HoldingRowScene: PackedScene = preload("res://src/ui/widgets/holding_row.tscn")
const RankingRowScene: PackedScene = preload("res://src/ui/widgets/ranking_row.tscn")
const LoanPanelScene: PackedScene = preload("res://src/ui/widgets/loan_panel.tscn")
const ConfirmPanelScene: PackedScene = preload("res://src/ui/widgets/confirm_panel.tscn")

const MESSAGE_SECONDS: float = 5.0

signal match_finished(winners: Array[StringName])

@onready var _year_label: Label = %YearLabel
@onready var _mood_label: Label = %MoodLabel
@onready var _event_flavour: Label = %EventFlavour
@onready var _event_effect: Label = %EventEffect
@onready var _yeehaw_button: Button = %YeehawButton
@onready var _yeehaw_note: Label = %YeehawNote
@onready var _cash_label: Label = %CashLabel
@onready var _net_worth_label: Label = %NetWorthLabel
@onready var _loan_row: HBoxContainer = %LoanRow
@onready var _loan_owed_label: Label = %LoanOwedLabel
@onready var _board_header_slot: MarginContainer = %BoardHeaderSlot
@onready var _holdings_header_slot: MarginContainer = %HoldingsHeaderSlot
@onready var _ranking_header_slot: MarginContainer = %RankingHeaderSlot
@onready var _stalk_scroll: ScrollContainer = %StalkScroll
@onready var _holding_scroll: ScrollContainer = %HoldingScroll
@onready var _ranking_scroll: ScrollContainer = %RankingScroll
@onready var _stalk_list: VBoxContainer = %StalkList
@onready var _holding_list: VBoxContainer = %HoldingList
@onready var _holdings_empty: Label = %HoldingsEmpty
@onready var _ranking_list: VBoxContainer = %RankingList
@onready var _info_label: Label = %InfoLabel
@onready var _error_label: Label = %ErrorLabel
@onready var _loan_button: Button = %LoanButton
@onready var _loan_nag: Label = %LoanNag
@onready var _ready_button: Button = %ReadyButton
@onready var _message_timer: Timer = %MessageTimer

var _session: GameSession
var _stalk_rows: Dictionary[StringName, StalkRow] = {}
var _loan_panel: LoanPanel
var _confirm_panel: ConfirmPanel


func _ready() -> void:
	_ready_button.pressed.connect(_on_ready_pressed)
	_loan_button.pressed.connect(_on_loan_button_pressed)
	_yeehaw_button.pressed.connect(_on_yeehaw_pressed)
	_message_timer.timeout.connect(_clear_error)
	_message_timer.wait_time = MESSAGE_SECONDS
	_message_timer.one_shot = true

	_build_headers()

	if _session == null:
		_session = _build_default_session()
	_attach(_session)


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
		session.yeehaw_requested.connect(_on_yeehaw_requested)
		session.yeehaw_given.connect(_on_yeehaw_given)
		# Without this the board does not move when anybody readies up. In a solo
		# game the year advances instantly so it never showed; in a networked one
		# it made the whole screen look dead while it waited.
		session.ready_state_changed.connect(_on_ready_state_changed)

	_build_stalk_rows()
	_build_loan_panel()
	_build_confirm_panel()
	_reset_event_panel()
	refresh()



## Stops listening the moment this screen leaves the tree.
##
## The same crash fix as on the lobby screen, for the same reason: `Main` swaps
## screens with `remove_child` plus a deferred `queue_free`, so without this a
## replaced screen still reacts to the next session signal and rebuilds rows
## outside the tree, where their `@onready` nodes stay null. The lobby hit this
## for real; this screen has the identical exposure when the match ends.
func _detach() -> void:
	if _session == null:
		return
	if not _session.year_resolved.is_connected(_on_year_resolved):
		return
	_session.year_resolved.disconnect(_on_year_resolved)
	_session.player_changed.disconnect(_on_player_changed)
	_session.action_rejected.disconnect(_on_action_rejected)
	_session.game_over.disconnect(_on_game_over)
	_session.yeehaw_requested.disconnect(_on_yeehaw_requested)
	_session.yeehaw_given.disconnect(_on_yeehaw_given)
	_session.ready_state_changed.disconnect(_on_ready_state_changed)


func _exit_tree() -> void:
	_detach()


# ----------------------------------------------------------------- construction

## Each board's column header is its row widget in header mode, so the columns
## cannot drift out of alignment. See docs/decisions.md D36.
func _build_headers() -> void:
	var stalk_header: StalkRow = StalkRowScene.instantiate()
	_board_header_slot.add_child(stalk_header)
	stalk_header.configure_as_header()

	var holding_header: HoldingRow = HoldingRowScene.instantiate()
	_holdings_header_slot.add_child(holding_header)
	holding_header.configure_as_header()

	var ranking_header: RankingRow = RankingRowScene.instantiate()
	_ranking_header_slot.add_child(ranking_header)
	ranking_header.configure_as_header()

	# Headers sit outside their scroll containers so they stay put while the list
	# scrolls, which also means they are not narrowed by the scrollbar the list
	# reserves. Both scrolls show their bar permanently and each header is inset
	# by exactly that width.
	_inset_header_for_scrollbar(_board_header_slot, _stalk_scroll)
	_inset_header_for_scrollbar(_holdings_header_slot, _holding_scroll)
	_inset_header_for_scrollbar(_ranking_header_slot, _ranking_scroll)


func _inset_header_for_scrollbar(slot: MarginContainer, scroll: ScrollContainer) -> void:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var width: int = int(bar.get_combined_minimum_size().x) if bar != null else 0
	slot.add_theme_constant_override("margin_right", width)


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


## The confirmation overlay, used for ending a year with a loan payment due.
## Built once and reused; it holds no state of its own between questions.
func _build_confirm_panel() -> void:
	if _confirm_panel != null:
		return
	_confirm_panel = ConfirmPanelScene.instantiate()
	add_child(_confirm_panel)
	_confirm_panel.confirmed.connect(_on_ready_confirmed)


func _build_loan_panel() -> void:
	if _loan_panel != null:
		return
	_loan_panel = LoanPanelScene.instantiate()
	add_child(_loan_panel)
	_loan_panel.setup(_session)
	_loan_panel.borrow_requested.connect(_on_borrow_requested)
	_loan_panel.payment_requested.connect(_on_payment_requested)
	_loan_panel.hide_panel()


## Empties a container synchronously. `queue_free()` alone defers to the end of
## the frame, leaving freed rows as children for the rest of the call.
func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


# -------------------------------------------------------------------- rendering

func refresh() -> void:
	if _session == null or _session.state() == null:
		return

	var game: GameState = _session.state()
	var player: PlayerState = game.player_by_id(_session.local_player_id())
	if player == null:
		return

	_refresh_year(game)
	_refresh_stats(player)
	_refresh_board(game, player)
	_refresh_holdings(game, player)
	_refresh_rankings(game)
	_refresh_bottom_bar(game, player)


func _refresh_year(game: GameState) -> void:
	_year_label.text = "Year: %d/%d" % [game.year, game.settings.max_years]

	var latest: YearResult = game.latest_result()
	if latest != null:
		_mood_label.text = MarketMood.label(latest.mood)
		_mood_label.add_theme_color_override("font_color", Palette.for_mood(latest.mood))
	else:
		_mood_label.text = ""


func _refresh_stats(player: PlayerState) -> void:
	_cash_label.text = Palette.format_money(player.cash)
	_net_worth_label.text = Palette.format_money(player.net_worth)

	var owed: int = player.owes()
	_loan_row.visible = owed > 0
	_loan_owed_label.text = Palette.format_money(owed)


func _refresh_board(game: GameState, player: PlayerState) -> void:
	var trading: bool = game.is_trading_open()
	for stalk: StalkState in game.stalks:
		var row: StalkRow = _stalk_rows.get(stalk.id)
		if row == null:
			continue
		row.display(stalk)
		row.set_affordable_hint(TradeRules.max_affordable(player, stalk))
		row.set_trading_open(trading)
		if trading:
			_validate_buy_row(row, row.shares_entered())


func _refresh_holdings(game: GameState, player: PlayerState) -> void:
	_clear_children(_holding_list)

	var trading: bool = game.is_trading_open()
	var held_any: bool = false
	for stalk: StalkState in game.stalks:
		var shares: int = player.shares_of(stalk.id)
		if shares <= 0:
			continue
		held_any = true
		var row: HoldingRow = HoldingRowScene.instantiate()
		_holding_list.add_child(row)
		row.display(stalk, shares)
		row.set_trading_open(trading)
		row.sell_requested.connect(_on_sell_requested)
		row.sell_all_requested.connect(_on_sell_all_requested)
		row.amount_changed.connect(_on_sell_amount_changed)

	_holdings_empty.visible = not held_any


func _refresh_rankings(game: GameState) -> void:
	_clear_children(_ranking_list)

	var latest: YearResult = game.latest_result()
	var order: Array[StringName] = (
		latest.rankings if latest != null else TradeRules.rank(game.players)
	)

	for player_id: StringName in order:
		var player: PlayerState = game.player_by_id(player_id)
		if player == null:
			continue
		var row: RankingRow = RankingRowScene.instantiate()
		_ranking_list.add_child(row)
		row.display(player, player.id == _session.local_player_id(), player.is_ready)


func _refresh_bottom_bar(game: GameState, player: PlayerState) -> void:
	if game.is_over:
		_ready_button.text = "Game Over"
		_ready_button.disabled = true
	elif player != null and player.is_ready:
		# Still enabled: pressing it again un-readies.
		_ready_button.disabled = false
		_ready_button.text = "Waiting..."
	else:
		_ready_button.disabled = false
		_ready_button.text = (
			"Finish Year %d" % game.settings.max_years
			if game.year >= game.settings.max_years
			else "Ready for New Year"
		)

	# Year 0 is the opening position: prices are all at their starting value and
	# no trading is allowed until everyone readies up. Straight from the original.
	if game.year == 0:
		_info_label.text = (
			"Year 0. The game begins when all players are ready. "
			+ "Highest net worth after the last year wins - "
			+ "buy stalks and hope they go up."
		)
	elif game.is_over:
		_info_label.text = "The game is over."

	# Once you are ready there is nothing left to do but wait, so say who for.
	# Without this the screen simply stops responding to you, which reads as
	# broken rather than as waiting.
	if player != null and player.is_ready and not game.is_over:
		var waiting: PackedStringArray = []
		for other_id: StringName in game.players_not_ready():
			var other: PlayerState = game.player_by_id(other_id)
			if other != null:
				waiting.append(other.display_name)
		_info_label.text = (
			"Waiting for %s." % Palette.list_names(waiting)
			if not waiting.is_empty()
			else "Everybody is ready. Starting the year..."
		)

	_refresh_yeehaw(game)

	_refresh_loan_controls(game, player)


## One button, two jobs, exactly as the original had it: it asks for a yeehaw
## until somebody is asking, and then offers to give one instead.
##
## Why the button is enabled or not comes from the same rule the authority
## enforces, so the greyed-out state can never disagree with it
## (docs/architecture.md 5.1).
##
## **One deviation from the original**, which hid the button entirely for the
## player who asked. Hiding it would reflow the top bar every time somebody
## asked, which is the fault D37 exists to prevent. It is disabled with a
## tooltip instead, so the row keeps its shape and the reason is still available.
func _refresh_yeehaw(game: GameState) -> void:
	var me: StringName = _session.local_player_id()
	var asker_id: StringName = game.yeehaw_requested_by

	if game.is_yeehaw_pending():
		var asker: PlayerState = game.player_by_id(asker_id)
		var asker_name: String = asker.display_name if asker != null else "Somebody"
		_yeehaw_button.text = "Give Yeehaw"
		var no_give: String = _session.why_not_give_yeehaw(me)
		_yeehaw_button.disabled = not no_give.is_empty()
		_yeehaw_button.tooltip_text = no_give
		_yeehaw_note.text = (
			"You asked for one." if asker_id == me
			else "%s wants a yeehaw!" % asker_name
		)
		_yeehaw_note.visible = true
		return

	_yeehaw_button.text = "Can I Get a Yeehaw?"
	var no_ask: String = _session.why_not_request_yeehaw(me)
	_yeehaw_button.disabled = not no_ask.is_empty()
	_yeehaw_button.tooltip_text = no_ask
	_yeehaw_note.text = "needs other players"
	_yeehaw_note.visible = game.players.size() < YeehawRules.MIN_PLAYERS


func _refresh_loan_controls(game: GameState, player: PlayerState) -> void:
	var loans_on: bool = game.settings != null and game.settings.loans_enabled
	_loan_button.visible = loans_on and not game.is_over

	if not loans_on:
		_loan_nag.visible = false
		return

	var payment_due: bool = (
		player.has_outstanding_loan() and not player.loan.paid_this_year
	)
	# The original nagged in the bottom bar. It is a reminder, never a block:
	# the player may ready up with a payment due and take the penalty.
	_loan_nag.visible = payment_due
	if payment_due:
		_loan_nag.text = "Don't forget to pay your loan! Minimum %s" % (
			Palette.format_money(player.loan.min_payment)
		)

	# Short captions: the button is a few cells wide at this resolution.
	if player.has_outstanding_loan():
		_loan_button.text = "PAY LOAN" if payment_due else "LOAN"
	elif player.loan != null:
		_loan_button.text = "LOAN"
	else:
		_loan_button.text = "LOANS"

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
		row.set_sell_blocked(
			"" if shares <= 0
			else _session.why_not_sell(_session.local_player_id(), stalk_id, shares)
		)


func _on_buy_requested(stalk_id: StringName, shares: int) -> void:
	if shares <= 0:
		_show_error("Enter how many shares to buy.")
		return
	_session.request_buy(_session.local_player_id(), stalk_id, shares)


func _on_sell_requested(stalk_id: StringName, shares: int) -> void:
	if shares <= 0:
		_show_error("Enter how many shares to sell.")
		return
	_session.request_sell(_session.local_player_id(), stalk_id, shares)


func _on_sell_all_requested(stalk_id: StringName) -> void:
	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	if player != null:
		_session.request_sell(
			_session.local_player_id(), stalk_id, player.shares_of(stalk_id)
		)


## Toggles, rather than only setting true.
##
## A player who readies by accident in a networked match would otherwise be stuck
## waiting for a year they did not want to start, with no way back. The lobby
## already works this way.
##
## Readying up with a loan payment outstanding asks first. The payment itself
## stays **advisory** — the player may still go ahead and take the penalty, which
## is the rule in docs/game-rules.md 9.5. What was missing was that the cost was
## invisible at the moment of choosing: the nag sat in the bottom bar and was
## easy to miss, so a player could lose 10% of their net worth without ever
## noticing there was a decision to make. See docs/decisions.md D53.
func _on_ready_pressed() -> void:
	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	var now_ready: bool = player == null or not player.is_ready

	if now_ready and _payment_is_due(player):
		_ask_about_the_unpaid_loan(player)
		return

	_session.set_ready(_session.local_player_id(), now_ready)


func _payment_is_due(player: PlayerState) -> bool:
	var game: GameState = _session.state()
	if game.settings == null or not game.settings.loans_enabled:
		return false
	return player != null and player.has_outstanding_loan() and not player.loan.paid_this_year


## Names the penalty, because "are you sure?" without a consequence is noise.
func _ask_about_the_unpaid_loan(player: PlayerState) -> void:
	var missed_so_far: int = player.loan.missed_payments
	var penalty: String = (
		"That is your third miss: your stalks will be seized and you are out."
		if missed_so_far >= LoanRules.MISSES_BEFORE_DEFAULT - 1
		else "Your balance will grow by %d%%." % _penalty_percent_for(missed_so_far)
	)
	_confirm_panel.ask(
		"You still owe %s on your loan this year. %s" % [
			Palette.format_money(player.loan.min_payment), penalty,
		],
		"End the year anyway",
		"Pay first",
	)


## Derived from the multipliers rather than written out again, so the number the
## player is shown cannot drift from the number they are charged.
func _penalty_percent_for(missed_so_far: int) -> int:
	var multiplier: float = (
		LoanRules.FIRST_MISS_MULTIPLIER
		if missed_so_far == 0
		else LoanRules.SECOND_MISS_MULTIPLIER
	)
	return int(round((multiplier - 1.0) * 100.0))


## The player chose to end the year with the payment outstanding.
func _on_ready_confirmed() -> void:
	_session.set_ready(_session.local_player_id(), true)


func _on_ready_state_changed(_player_id: StringName, _is_ready: bool) -> void:
	refresh()


func _on_loan_button_pressed() -> void:
	if _loan_panel != null:
		_loan_panel.show_panel()


## Asks, or answers whoever is asking. The button's label already says which.
func _on_yeehaw_pressed() -> void:
	if _session.state().is_yeehaw_pending():
		_session.give_yeehaw(_session.local_player_id())
	else:
		_session.request_yeehaw(_session.local_player_id())


func _on_borrow_requested(amount: int) -> void:
	_session.request_loan(_session.local_player_id(), amount)


func _on_payment_requested(amount: int) -> void:
	_session.pay_loan(_session.local_player_id(), amount)


# -------------------------------------------------------------- session handlers

## Somebody asked. Phase 7 adds the sound; for now the message carries it.
## The button itself is updated by `refresh`, driven by the state change.
func _on_yeehaw_requested(player_id: StringName) -> void:
	var asker: PlayerState = _session.state().player_by_id(player_id)
	if asker == null:
		return
	if player_id == _session.local_player_id():
		_show_info("You asked for a yeehaw.")
	else:
		_show_info("%s wants a yeehaw!" % asker.display_name)
	refresh()


func _on_yeehaw_given(giver_id: StringName, receiver_id: StringName) -> void:
	var giver: PlayerState = _session.state().player_by_id(giver_id)
	var receiver: PlayerState = _session.state().player_by_id(receiver_id)
	if giver == null or receiver == null:
		return
	_show_info("%s gave %s a yeehaw!" % [giver.display_name, receiver.display_name])
	refresh()


func _on_player_changed(_player_id: StringName) -> void:
	_clear_error()
	for row: StalkRow in _stalk_rows.values():
		row.clear_amount()
	refresh()
	if _loan_panel != null and _loan_panel.is_showing():
		_loan_panel.refresh()


func _on_year_resolved(result: YearResult) -> void:
	_clear_error()
	_show_event(result)
	_info_label.text = _summarise(result)
	refresh()


func _on_action_rejected(_player_id: StringName, reason: String) -> void:
	_show_error(reason)


func _on_game_over(winners: Array[StringName]) -> void:
	if _loan_panel != null:
		_loan_panel.hide_panel()
	match_finished.emit(winners)


# ------------------------------------------------------------------ presentation

func _reset_event_panel() -> void:
	_event_flavour.text = ""
	_event_effect.text = ""


## Two labels, matching the original: the flavour text, then what it did.
func _show_event(result: YearResult) -> void:
	if result.event == null:
		_event_flavour.text = ""
		_event_effect.text = "No special event this year."
		_event_effect.remove_theme_color_override("font_color")
		return

	var target: StalkState = _session.state().stalk_by_id(result.event.target_stalk_id)
	var target_name: String = (
		target.definition.display_name if target != null
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


## What else happened this year. The original did not show this; splits and
## dividends simply occurred, which makes a doubled share count look like a bug.
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
				parts.append("Missed payment penalty %s"
					% Palette.format_money(loan_change.penalty_added))
			if loan_change.interest_added > 0:
				parts.append("Loan interest %s"
					% Palette.format_money(loan_change.interest_added))

	return " · ".join(parts)


func _display_names(ids: Array[StringName]) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for stalk_id: StringName in ids:
		var stalk: StalkState = _session.state().stalk_by_id(stalk_id)
		names.append(stalk.definition.display_name if stalk != null else String(stalk_id))
	return names


## The transient message line, under the boards. Both kinds of message use it and
## both expire after MESSAGE_SECONDS; only the colour differs, so a yeehaw is not
## dressed up as a failure.
func _show_error(text: String) -> void:
	_show_message(text, &"Danger")


func _show_info(text: String) -> void:
	_show_message(text, &"")


func _show_message(text: String, variation: StringName) -> void:
	_error_label.theme_type_variation = variation
	_error_label.text = text
	_message_timer.start()


func _clear_error() -> void:
	_error_label.text = ""
	_message_timer.stop()


# ------------------------------------------------------------------- for tests

## The confirmation overlay, for tests and for anything that needs to know
## whether a question is on screen.
func confirm_panel() -> ConfirmPanel:
	return _confirm_panel


func current_message() -> String:
	return _error_label.text


func info_text() -> String:
	return _info_label.text


func year_summary_text() -> String:
	return _info_label.text


func loan_nag_visible() -> bool:
	return _loan_nag.visible


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


func ranking_row_count() -> int:
	return _ranking_list.get_child_count()


func loan_panel() -> LoanPanel:
	return _loan_panel
