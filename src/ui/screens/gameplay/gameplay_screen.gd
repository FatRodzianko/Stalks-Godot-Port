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
const NewsPanelScene: PackedScene = preload("res://src/ui/widgets/news_panel.tscn")
const StalkPanelScene: PackedScene = preload("res://src/ui/widgets/stalk_panel.tscn")

const MESSAGE_SECONDS: float = 5.0

signal match_finished(winners: Array[StringName])

## The player is done looking at the finished board and wants the result
## screen back. Only ever emitted while `show_as_final_board` is in force.
signal results_requested

## The connection ended while the match was running - the host quit, or this
## client was dropped. Carries text to show the player on the way out.
signal connection_ended(reason: String)

@onready var _year_label: Label = %YearLabel
@onready var _mood_label: Label = %MoodLabel
@onready var _event_flavour: ScrollingLabel = %EventFlavour
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
@onready var _loan_box: VBoxContainer = %LoanBox
@onready var _loan_button: Button = %LoanButton
@onready var _loan_min_label: Label = %LoanMinLabel
@onready var _loan_nag: Label = %LoanNag
## True when this screen is being shown *after* the match, as something to
## look over rather than play. See `show_as_final_board`.
var _viewing_final_board: bool = false

@onready var _ready_button: Button = %ReadyButton
@onready var _message_timer: Timer = %MessageTimer

var _session: GameSession

## The same session, narrowed. Both may be null in a solo game; at most one is
## ever set. They exist only for the two things that differ between the ends of
## a connection - being dropped, and being told somebody else was.
var _host: HostSession
var _client: ClientSession

var _stalk_rows: Dictionary[StringName, StalkRow] = {}
var _loan_panel: LoanPanel
var _confirm_panel: ConfirmPanel

## The year's news, put in front of the player when the year turns.
var _news_panel: NewsPanel

## A company's details, opened by clicking its row.
var _stalk_panel: StalkPanel

## Whether the transient message line is currently showing a refusal rather than
## a piece of news. Only a refusal is cleared by a state change.
## Which year's event the strip is currently showing, or -1 for none.
##
## **The strip is rebuilt from state, so it needs to know when not to be.**
## `refresh()` runs on every broadcast - every trade anybody makes - and
## re-setting the text would snatch a long description back to its first line
## under a player in the middle of reading it. The year is what changes when
## there is genuinely something new to show. See docs/decisions.md D121.
var _shown_event_year: int = -1

var _message_is_error: bool = false

## What the player last asked the loan panel to do, while the answer is still
## outstanding. Empty when nothing is pending. A client waits a round trip for
## this, which is why it is a flag rather than a return value.
var _pending_loan_action: StringName = &""


func _ready() -> void:
	_ready_button.pressed.connect(_on_ready_pressed)
	_loan_button.pressed.connect(_on_loan_button_pressed)
	_yeehaw_button.pressed.connect(_on_yeehaw_pressed)
	_message_timer.timeout.connect(_clear_error)
	_message_timer.wait_time = MESSAGE_SECONDS
	_message_timer.one_shot = true

	_build_headers()
	_reserve_bottom_bar_height()
	_reserve_yeehaw_note_height()
	_reserve_event_flavour_height()

	if _session == null:
		_session = _build_default_session()
	_attach(_session)


func setup(session: GameSession) -> void:
	_session = session
	_host = session as HostSession
	_client = session as ClientSession
	if is_node_ready():
		_attach(session)


func session() -> GameSession:
	return _session


## Shows this board as a finished one: something to look over rather than play.
##
## The original let you dismiss its winner panel and study the final board —
## prices, your holdings, the rankings as they ended — and the port's result
## screen had replaced that with a summary (audit 17.9). This is how the board
## comes back.
##
## Nothing is disabled here, because nothing needs to be: trading is already
## refused once the year counter passes the limit, and the loan panels hide
## themselves at game over. The only change is that the bottom bar's button
## becomes the way back instead of saying "Game Over" at you.
func show_as_final_board() -> void:
	_viewing_final_board = true
	if is_node_ready():
		refresh()


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

	# Losing the host mid-match used to show nothing at all: the screen stayed
	# up and every button answered "Not connected." See docs/decisions.md D61.
	if _client != null and not _client.connection_lost.is_connected(_on_connection_lost):
		_client.connection_lost.connect(_on_connection_lost)
	if _host != null and not _host.player_left.is_connected(_on_player_left):
		_host.player_left.connect(_on_player_left)
	# **And the other direction.** A player coming back is as much a change to
	# the board as one leaving, and the host hears about it only through this
	# signal: `_broadcast_state` skips the host's own peer, so nothing else
	# redraws its rankings. See docs/decisions.md D120.
	if _host != null and not _host.player_joined.is_connected(_on_player_joined):
		_host.player_joined.connect(_on_player_joined)

	_build_stalk_rows()
	_build_loan_panel()
	_build_confirm_panel()
	_build_news_panel()
	_build_stalk_panel()
	_event_flavour.more_requested.connect(_on_more_requested)
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
	if _client != null and _client.connection_lost.is_connected(_on_connection_lost):
		_client.connection_lost.disconnect(_on_connection_lost)
	if _host != null and _host.player_left.is_connected(_on_player_left):
		_host.player_left.disconnect(_on_player_left)
	if _host != null and _host.player_joined.is_connected(_on_player_joined):
		_host.player_joined.disconnect(_on_player_joined)


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


## Pins the bottom bar to one height for the whole match.
##
## It used to grow and shrink. The year-0 explanation is long enough to wrap
## onto a second line, later messages fit on one, and the loan reminder came
## and went - so the bar changed height several times a game and dragged the
## boards above it up and down with it.
##
## The fix is to reserve the tallest it can ever be: the reminder keeps its line
## whether or not it has anything to say, and the message label keeps room for
## both of the lines it is allowed. The refusal line below them is capped at one
## line already, so with those two pinned the total cannot move.
##
## The number comes from the theme rather than being written down as a pixel
## count, so changing the font cannot quietly break this again.
## Holds the note's line under the yeehaw button whether or not it says
## anything.
##
## The note is blank in a one-player game, says "needs other players" when
## there are not enough, and carries the asker's name when somebody wants one.
## Without a reserved line the top bar changes height as those come and go,
## which is the same fault as the corner changing width - just in the other
## axis.
##
## Computed from the theme rather than written down, like
## `_reserve_bottom_bar_height` above it, so changing the font does not quietly
## reintroduce the jump.
## Holds three lines for the special event's description, always.
##
## **Three, not two, and the number came from counting.** Measured across all
## ninety events in the content: twenty-one need one line, forty-nine need two,
## seventeen need three, two need four and one needs five. At two the longest
## fifth of the game's writing was being cut off mid-sentence, which is what
## was reported from play on 2026-11-17.
##
## Three covers eighty-seven of the ninety. The remaining three are still
## clipped, which is a content question rather than a layout one - the texts
## are 170 characters and up.
##
## **Reserved rather than allowed to grow**, for the reason D63 gives about the
## bottom bar: a panel that is tall only when it has a lot to say shoves
## everything below it up and down as the years pass. D63 also says what to do
## instead, and this is it - raise the reserve, do not make it conditional.
func _reserve_event_flavour_height() -> void:
	var line_height: int = _event_flavour.get_theme_font("normal_font").get_height(
		_event_flavour.get_theme_font_size("normal_font_size")
	)
	var spacing: int = 0
	if _event_flavour.has_theme_constant("line_separation"):
		spacing = _event_flavour.get_theme_constant("line_separation")
	_event_flavour.custom_minimum_size.y = (
		(line_height + spacing) * _event_flavour.max_lines_visible
	)


func _reserve_yeehaw_note_height() -> void:
	var line_height: int = _yeehaw_note.get_theme_font("font").get_height(
		_yeehaw_note.get_theme_font_size("font_size")
	)
	var spacing: int = 0
	if _yeehaw_note.has_theme_constant("line_spacing"):
		spacing = _yeehaw_note.get_theme_constant("line_spacing")
	_yeehaw_note.custom_minimum_size.y = (
		(line_height + spacing) * _yeehaw_note.max_lines_visible
	)


func _reserve_bottom_bar_height() -> void:
	var line_height: int = _info_label.get_theme_font("font").get_height(
		_info_label.get_theme_font_size("font_size")
	)
	var spacing: int = 0
	if _info_label.has_theme_constant("line_spacing"):
		spacing = _info_label.get_theme_constant("line_spacing")
	_info_label.custom_minimum_size.y = (
		(line_height + spacing) * _info_label.max_lines_visible
	)


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
		row.info_requested.connect(show_stalk_details)
		_stalk_rows[stalk.id] = row


## The confirmation overlay, used for ending a year with a loan payment due.
## Built once and reused; it holds no state of its own between questions.
## The news panel is built once and reused, and added last so it sits in front
## of the board and the loan panel alike.
func _build_news_panel() -> void:
	if _news_panel != null:
		return
	_news_panel = NewsPanelScene.instantiate()
	add_child(_news_panel)


## The year's news. For tests.
func news_panel() -> NewsPanel:
	return _news_panel


func _build_stalk_panel() -> void:
	if _stalk_panel != null:
		return
	_stalk_panel = StalkPanelScene.instantiate()
	add_child(_stalk_panel)


## A company's details. For tests.
func stalk_panel() -> StalkPanel:
	return _stalk_panel


## Opens a company's details, with the players currently holding it.
##
## **Names only.** The panel lists who is in a company and not how much they
## hold - a choice about what it is for, since D105 put the amounts on the wire
## too. `invests_in` is the question being asked, which is also why this gives
## the same answer offline and over the wire. See decisions.md D103 and D105.
func show_stalk_details(stalk_id: StringName) -> void:
	if _stalk_panel == null or _session == null:
		return
	var game: GameState = _session.state()
	var stalk: StalkState = game.stalk_by_id(stalk_id)
	if stalk == null:
		return

	var investors: PackedStringArray = []
	for player: PlayerState in game.players:
		if player.invests_in(stalk_id):
			investors.append(player.display_name)

	_stalk_panel.show_stalk(
		stalk.definition.display_name,
		stalk.definition.description,
		investors,
		stalk.definition.investors_are_anonymous,
	)


func _build_confirm_panel() -> void:
	if _confirm_panel != null:
		return
	_confirm_panel = ConfirmPanelScene.instantiate()
	add_child(_confirm_panel)
	_confirm_panel.confirmed.connect(_on_ready_confirmed)
	# Saying "pay first" should put the player where they can pay, not just
	# close the question and leave them to find the button themselves.
	_confirm_panel.cancelled.connect(_on_pay_first_chosen)


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
	_refresh_event(game)
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


## True once this player has readied up and is only waiting for the others.
##
## Their own board goes read-only at that point: the rule is enforced in
## `TradeRules`, and this is the half that greys the buttons so a player is not
## invited to press something that will be refused. See decisions.md D97.
func _is_waiting(player: PlayerState) -> bool:
	return player != null and player.is_ready


func _refresh_board(game: GameState, player: PlayerState) -> void:
	var trading: bool = game.is_trading_open() and not _is_waiting(player)
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

	var trading: bool = game.is_trading_open() and not _is_waiting(player)
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

	var host_id: StringName = game.host_player_id()
	for player_id: StringName in order:
		var player: PlayerState = game.player_by_id(player_id)
		if player == null:
			continue
		var row: RankingRow = RankingRowScene.instantiate()
		_ranking_list.add_child(row)
		row.display(
			player,
			player.id == _session.local_player_id(),
			player.is_ready,
			player.id == host_id,
		)


func _refresh_bottom_bar(game: GameState, player: PlayerState) -> void:
	if game.is_over and _viewing_final_board:
		# The one control on a finished board that still does anything. The
		# original put a second Quit Game button here when its winner panel was
		# dismissed, for the same reason: once the panel is gone there has to
		# be a way back out of the board.
		_ready_button.text = "BACK TO RESULTS"
		_ready_button.disabled = false
	elif game.is_over:
		_ready_button.text = "Game Over"
		_ready_button.disabled = true
	elif player != null and player.is_ready:
		# Still enabled: pressing it again un-readies.
		_ready_button.disabled = false
		_ready_button.text = "Waiting..."
	else:
		_ready_button.disabled = false
		if game.year >= game.settings.max_years:
			_ready_button.text = "Finish Year %d" % game.settings.max_years
		else:
			_ready_button.text = "Ready for New Year"

	# Year 0 is the opening position: prices are all at their starting value and
	# no trading is allowed until everyone readies up. Straight from the original.
	if game.year == 0:
		# Two lines is all the bar reserves (D63), and the old third clause -
		# "buy stalks and hope they go up" - was being clipped mid-sentence.
		# Better to say less and finish the thought.
		_info_label.text = (
			"Year 0. The game begins when all players are ready. "
			+ "Highest net worth after the last year wins."
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
		if waiting.is_empty():
			_info_label.text = "Everybody is ready. Starting the year..."
		else:
			_info_label.text = "Waiting for %s." % Palette.list_names(waiting)

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
		# Just the name. The sentence version used to live here and made this
		# corner wide enough to shove the event strip along; the bottom bar
		# already announces who asked, and this is the part that has to persist
		# after that message fades. "you" rather than your own name, because
		# under a Give Yeehaw you cannot press it reads as the reason.
		_yeehaw_note.text = "you" if asker_id == me else asker_name
		_yeehaw_note.visible = true
		return

	_yeehaw_button.text = "Can I Get a Yeehaw?"
	var no_ask: String = _session.why_not_request_yeehaw(me)
	_yeehaw_button.disabled = not no_ask.is_empty()
	_yeehaw_button.tooltip_text = no_ask
	_yeehaw_note.text = "needs other players"
	_yeehaw_note.visible = game.players.size() < YeehawRules.MIN_PLAYERS


## The loan corner of the bottom bar: the button, the minimum payment under it,
## and the reminder in the message column.
##
## The minimum is shown under the button for as long as a loan is outstanding,
## not only when a payment is due. Knowing what you will owe is part of deciding
## whether to borrow more, and the figure was previously buried inside the loan
## panel - you had to open it to find out.
##
## Nothing here is ever hidden in a way that changes the bar's height. The
## reminder keeps its line and goes blank; the minimum label *is* hidden when
## there is nothing owed, which is safe because the bar's height comes from the
## message column rather than from this box. See `_reserve_bottom_bar_height`,
## and `test_the_loans_button_is_centred_when_it_stands_alone` for the measure
## that keeps it honest.
func _refresh_loan_controls(game: GameState, player: PlayerState) -> void:
	var loans_on: bool = game.settings != null and game.settings.loans_enabled
	_loan_box.visible = loans_on and not game.is_over

	if not loans_on:
		_loan_nag.text = ""
		_loan_min_label.text = ""
		return

	var payment_due: bool = (
		player.has_outstanding_loan() and not player.loan.paid_this_year
	)
	# The original nagged in the bottom bar. It is a reminder, never a block:
	# the player may ready up with a payment due and take the penalty. The
	# amount is no longer repeated here - it is under the button, always.
	if payment_due:
		_loan_nag.text = "Don't forget to pay your loan!"
	else:
		_loan_nag.text = ""

	if player.has_outstanding_loan():
		_loan_min_label.text = "Min %s" % Palette.format_money(player.loan.min_payment)
	else:
		_loan_min_label.text = ""
	# Hidden, not merely blank. A blank label still takes a line, and the box
	# around it is centred in the bar - so with nothing owed the LOANS button
	# rode half a line high, which is what "slightly off" looks like. Reported
	# from play on 2026-11-17 and measured at seven pixels.
	#
	# This does not change the bar's height. That is held by `_info_label`'s
	# reserved two lines in the message column (see `_reserve_bottom_bar_height`),
	# which is taller than this box either way.
	_loan_min_label.visible = not _loan_min_label.text.is_empty()

	# Short captions: the button is a few cells wide at this resolution.
	#
	# "PAY LOAN" for as long as anything is owed, not only in a year where a
	# payment is outstanding. Asked for in play: with a loan running, the button
	# should say what it is for. You can always pay more than the minimum, so it
	# is never a lie, and the reminder beside it is what says a payment is
	# actually due.
	if player.has_outstanding_loan():
		_loan_button.text = "PAY LOAN"
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
	# On a finished board this button is the way back to the result screen, not
	# a ready-up. Checked before anything reads the roster, because there is
	# nothing to be ready for.
	if _viewing_final_board:
		results_requested.emit()
		return

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
	var penalty: String = "Your balance will grow by %d%%." % _penalty_percent_for(
		missed_so_far
	)
	if missed_so_far >= LoanRules.MISSES_BEFORE_DEFAULT - 1:
		penalty = "That would be your third miss: your stalks are seized and you are out."
	_confirm_panel.ask(
		"You still owe %s on your loan this year. %s%s" % [
			Palette.format_money(player.loan.min_payment),
			_misses_so_far(missed_so_far),
			penalty,
		],
		"End the year anyway",
		"Pay first",
	)


## How much rope is left. A bare percentage does not tell a player whether this
## is a nuisance or the end of their game.
func _misses_so_far(missed: int) -> String:
	if missed == 0:
		return ""
	return "You have missed %d already. " % missed


## Derived from the multipliers rather than written out again, so the number the
## player is shown cannot drift from the number they are charged.
func _penalty_percent_for(missed_so_far: int) -> int:
	var multiplier: float = LoanRules.SECOND_MISS_MULTIPLIER
	if missed_so_far == 0:
		multiplier = LoanRules.FIRST_MISS_MULTIPLIER
	return int(round((multiplier - 1.0) * 100.0))


## The player chose to end the year with the payment outstanding.
func _on_ready_confirmed() -> void:
	_session.set_ready(_session.local_player_id(), true)


## The player chose to pay instead. Opens the loan panel for them.
##
## Only when a payment is actually due: the panel also answers "no" to other
## questions later, and opening the loan screen out of nowhere would be strange.
func _on_pay_first_chosen() -> void:
	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	if _payment_is_due(player) and _loan_panel != null:
		_loan_panel.show_panel()


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
	_pending_loan_action = &"borrow"
	_session.request_loan(_session.local_player_id(), amount)


func _on_payment_requested(amount: int) -> void:
	_pending_loan_action = &"pay"
	_session.pay_loan(_session.local_player_id(), amount)


## Borrowing or paying is a finished errand, so the panel gets out of the way
## and says what happened on the board behind it.
##
## Leaving it open after a successful borrow was actively confusing: the panel
## switched to its pay controls, which reads as being asked for money you have
## just this moment received.
func _finish_loan_action() -> void:
	var action: StringName = _pending_loan_action
	_pending_loan_action = &""

	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	if player == null or player.loan == null:
		return

	if action == &"borrow":
		_show_info(
			"Borrowed %s. Your first payment is due next year."
			% Palette.format_money(player.loan.balance)
		)
	elif player.loan.is_paid_off:
		_show_info("Loan paid off.")
	else:
		# Reported from state rather than from what was typed, because an
		# overpayment is clamped to the balance.
		_show_info("Payment made. %s still owed." % Palette.format_money(player.loan.balance))

	if _loan_panel != null:
		_loan_panel.hide_panel()


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
	# Everybody hears it, not just the two involved. That is the point of it.
	Audio.play_yeehaw()

	var giver: PlayerState = _session.state().player_by_id(giver_id)
	var receiver: PlayerState = _session.state().player_by_id(receiver_id)
	if giver == null or receiver == null:
		return
	_show_info("%s gave %s a yeehaw!" % [giver.display_name, receiver.display_name])
	refresh()


## Something changed about a player — usually a trade, on any machine.
##
## Only a stale *rejection* is swept away here, and only the local player's
## typing is reset. Both used to happen on every change, which was invisible
## while hosting and wrong on a client: the host follows each broadcast with a
## state push, so a client's "Host wants a yeehaw!" was cleared in the same
## frame it appeared, and a half-typed quantity vanished whenever somebody else
## traded. See docs/decisions.md D54.
func _on_player_changed(player_id: StringName) -> void:
	var is_me: bool = player_id == _session.local_player_id()
	if is_me and _message_is_error:
		_clear_error()
	if is_me:
		for row: StalkRow in _stalk_rows.values():
			row.clear_amount()
	refresh()
	if is_me and not _pending_loan_action.is_empty():
		_finish_loan_action()
	if _loan_panel != null and _loan_panel.is_showing():
		_loan_panel.refresh()


func _on_year_resolved(result: YearResult) -> void:
	# The year's mood, and breaking glass if anything went under. Both come
	# straight from the original; see src/audio/ for what it plays and why a
	# bankruptcy sounds once a year rather than once a stalk.
	Audio.play_mood(result.mood)
	if not result.bankrupt_ids().is_empty():
		Audio.play_bankruptcy()

	_clear_error()
	_show_event(result)
	_info_label.text = _summarise(result)
	refresh()

	# In front of the player rather than only along the top, because the strip
	# is easy to miss and this is the one thing each year that moves the market
	# under them. Every year, including the quiet ones. See decisions.md D101.
	_announce_the_news(result)


## A refusal goes wherever the player is looking. With the loan panel open that
## is the panel, not the message line it covers.
func _on_action_rejected(_player_id: StringName, reason: String) -> void:
	_pending_loan_action = &""
	if _loan_panel != null and _loan_panel.is_showing():
		_loan_panel.show_problem(reason)
		return
	_show_error(reason)


## The host went away, or this client was dropped.
##
## Before this, the screen stayed exactly as it was and every button answered
## "Not connected." - the message a client gets when it tries to act without a
## seat. The player was left looking at a board that had quietly stopped being
## connected to anything, with no way out but to kill the process.
##
## **Nothing is offered or decided here**: say what happened and hand back to
## the title screen, which is where the reason is shown. Reconnecting is a real
## thing now, but it is the title screen's REJOIN GAME button that does it
## (decisions.md D111) - this screen's job is to stop pretending it is
## connected, and the seat is waiting either way.
func _on_connection_lost(reason: String) -> void:
	if _loan_panel != null:
		_loan_panel.hide_panel()
	connection_ended.emit(reason)


## Somebody else dropped out. Only the host hears this, because only the host
## is told about other peers.
##
## Worth saying out loud: their row simply disappears from the standings
## otherwise, which looks like a fault rather than like somebody leaving. Their
## holdings are kept - see HostSession and docs/decisions.md D47 - they are just
## no longer playing.
func _on_player_left(player_id: StringName) -> void:
	if _host == null:
		return
	_show_info("%s left the game." % _name_for(player_id))
	refresh()


## Somebody who dropped out has come back and taken their seat again.
##
## **The board had no way to notice.** `_reclaim_slot` clears the away flag on
## the host's own state and `_broadcast_state` tells every client, but it skips
## the host's own peer - so the host's rankings kept the grey dot of an absent
## player until something unrelated forced a redraw, usually another player
## readying up. Reported from play: a rejoined player looked, to the host, as
## though they were still gone. See docs/decisions.md D120.
func _on_player_joined(player_id: StringName) -> void:
	if _host == null:
		return
	_show_info("%s rejoined the game." % _name_for(player_id))
	refresh()


## What to call a player in one of those messages. A player who has just left
## is off the active list, so this looks where they still exist.
func _name_for(player_id: StringName) -> String:
	var who: String = _host.display_name_of(player_id)
	return who if not who.is_empty() else "A player"


func _on_game_over(winners: Array[StringName]) -> void:
	if _loan_panel != null:
		_loan_panel.hide_panel()
	match_finished.emit(winners)


# ------------------------------------------------------------------ presentation

func _reset_event_panel() -> void:
	_event_flavour.set_full_text("")
	_event_effect.text = ""
	_shown_event_year = -1


## Puts the year's event back on the strip after the screen has been rebuilt.
##
## **The strip used to be filled only by the year-resolved signal**, so it was
## written once, when a year turned, and never again. Any screen built after
## that point started blank and stayed blank until the *next* year: a player
## rejoining a match saw no event text at all, and so did a new host, because
## migrating rebuilds the board. Reported from play both ways round, and in the
## same year as the disconnect as well as years later.
##
## The year is in `state.history`, which now travels (D118), so the strip can
## simply be derived from state like everything else on the board. See
## docs/decisions.md D121.
func _refresh_event(game: GameState) -> void:
	var latest: YearResult = game.latest_result()
	if latest == null:
		# Year 0. Nothing has happened yet, and the blank strip is correct.
		return
	if latest.year == _shown_event_year:
		return
	_show_event(latest)


## Puts the year's news back up, for a player who closed it and then wanted it
## again - or who has the panel switched off entirely and reads the strip.
func _on_more_requested() -> void:
	if _news_panel == null:
		return
	_news_panel.show_news(_event_flavour.full_text(), _event_effect.text)


## Puts the year's event in front of the player.
##
## Takes the two lines the top strip is already showing rather than reading the
## result again, so the panel and the strip can never say different things.
func _announce_the_news(result: YearResult) -> void:
	if _news_panel == null:
		return
	if not NewsPanel.is_wanted():
		return
	var description: String = ""
	if result.event != null:
		description = result.event.flavour_text
	_news_panel.show_news(description, _event_effect.text)


## Two labels, matching the original: the flavour text, then what it did.
func _show_event(result: YearResult) -> void:
	_shown_event_year = result.year
	if result.event == null:
		_event_flavour.set_full_text("")
		_event_effect.text = "No special event this year."
		_event_effect.remove_theme_color_override("font_color")
		return

	var target: StalkState = _session.state().stalk_by_id(result.event.target_stalk_id)
	var target_name: String = (
		target.definition.display_name if target != null
		else String(result.event.target_stalk_id)
	)
	# Through the label rather than straight onto `text`, so a long description
	# returns to its first line instead of opening wherever the last one had
	# been scrolled to. See decisions.md D100.
	_event_flavour.set_full_text(result.event.flavour_text)
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
	_message_is_error = variation == &"Danger"
	_error_label.theme_type_variation = variation
	_error_label.text = text
	_message_timer.start()


func _clear_error() -> void:
	_error_label.text = ""
	_message_is_error = false
	_message_timer.stop()


# ------------------------------------------------------------------- for tests

## The confirmation overlay, for tests and for anything that needs to know
## whether a question is on screen.
func confirm_panel() -> ConfirmPanel:
	return _confirm_panel


func current_message() -> String:
	return _error_label.text


## Puts a message on the transient line as a refusal would. For tests that need
## that line occupied without arranging a real refusal.
func show_message_for_testing(text: String) -> void:
	_show_error(text)


func info_text() -> String:
	return _info_label.text


func year_summary_text() -> String:
	return _info_label.text


## Whether the reminder is saying anything. The label itself is always visible
## - it holds its line open so the bar cannot change height - so its text is
## what tells you whether there is a reminder.
func loan_nag_visible() -> bool:
	return not _loan_nag.text.is_empty()


## The minimum payment as shown under the loan button, or empty when there is
## no loan to pay.
func loan_minimum_text() -> String:
	return _loan_min_label.text


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
