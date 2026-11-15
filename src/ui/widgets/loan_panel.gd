class_name LoanPanel
extends Control
## The loan dialog: terms, how much can be borrowed, what is owed, and the
## controls to borrow or pay.
##
## Shown as an overlay on the playing screen. Like every other widget it holds no
## rules — it asks the session what is allowed and emits intent outward.
##
## The payment prompt here is **advisory and never blocking**. A player may close
## this panel with a payment outstanding, ready up, and take the penalty. That is
## deliberate: the game must never penalise a player for something it hid from
## them, but it must also never take the choice away. See docs/game-rules.md §9.5.


signal borrow_requested(amount: int)
signal payment_requested(amount: int)


@onready var _terms_label: Label = %Terms
@onready var _status_label: Label = %Status
@onready var _borrow_box: VBoxContainer = %BorrowBox
@onready var _borrow_field: LineEdit = %BorrowAmount
@onready var _borrow_button: Button = %BorrowButton
@onready var _max_button: Button = %MaxButton
@onready var _pay_box: VBoxContainer = %PayBox
@onready var _pay_field: LineEdit = %PayAmount
@onready var _pay_button: Button = %PayButton
@onready var _pay_minimum_button: Button = %PayMinimumButton
@onready var _close_button: Button = %CloseButton
@onready var _warning_label: Label = %Warning

var _session: GameSession


func _ready() -> void:
	_borrow_button.pressed.connect(_on_borrow_pressed)
	_max_button.pressed.connect(_on_max_pressed)
	_pay_button.pressed.connect(_on_pay_pressed)
	_pay_minimum_button.pressed.connect(_on_pay_minimum_pressed)
	_close_button.pressed.connect(hide_panel)
	_borrow_field.text_changed.connect(_on_borrow_amount_changed)
	_pay_field.text_changed.connect(_on_pay_amount_changed)


func setup(session: GameSession) -> void:
	_session = session


func show_panel() -> void:
	visible = true
	refresh()


func hide_panel() -> void:
	visible = false
	_borrow_field.text = ""
	_pay_field.text = ""
	_warning_label.text = ""


func is_showing() -> bool:
	return visible


## Shows a refusal inside the panel.
##
## The screen behind this is covered, so its message line cannot be read while
## the panel is open — a refused borrow used to report its reason somewhere the
## player could not see.
func show_problem(reason: String) -> void:
	_warning_label.text = reason
	_warning_label.theme_type_variation = &"Danger"


## A loan taken this year, before any year-end has processed it.
##
## The counter starts at TERM_YEARS + 1 and is decremented by the first year-end
## pass, so this is exactly "no year has closed since you borrowed". See
## docs/decisions.md D28.
static func _is_brand_new(loan: LoanState) -> bool:
	return loan.years_remaining > LoanRules.TERM_YEARS


## Redraws from current state. The two halves are mutually exclusive: a player
## either has no loan and may borrow, or has one and may pay.
func refresh() -> void:
	if _session == null:
		return
	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	if player == null:
		return

	_terms_label.text = _terms_text()

	# Any refusal on screen belongs to the last attempt, not to this redraw.
	_warning_label.theme_type_variation = &""

	# The two halves are mutually exclusive: a player either has no loan and may
	# borrow, or has one and may pay.
	var ever_borrowed: bool = player.loan != null
	_borrow_box.visible = not ever_borrowed
	_pay_box.visible = player.has_outstanding_loan()

	if player.has_outstanding_loan():
		_show_repayment(player.loan)
	elif ever_borrowed:
		_show_settled()
	else:
		_show_borrowing(player)

	_validate_borrow()
	_validate_pay()


## The standing terms, which never change. Separated out because it is four
## lines of string building that say nothing about the player's situation.
func _terms_text() -> String:
	return (
		"Terms: %d years at %d%% interest, compounded yearly. " % [
			LoanRules.TERM_YEARS, int(LoanRules.ANNUAL_RATE * 100.0),
		]
		+ "You may borrow up to 25%% of your net worth, minimum %s. " % (
			Palette.format_money(LoanRules.MIN_PRINCIPAL)
		)
		+ "One loan per game — even after you pay it off."
	)


## A loan that is still owed: what is outstanding, and what happens if it is
## not paid.
func _show_repayment(loan: LoanState) -> void:
	_status_label.text = (
		"Owed %s · minimum payment %s · %d years remaining · %d missed"
		% [
			Palette.format_money(loan.balance),
			Palette.format_money(loan.min_payment),
			loan.years_remaining,
			loan.missed_payments,
		]
	)
	if loan.paid_this_year:
		_status_label.text += "  (paid this year)"

	_pay_field.placeholder_text = "min %d" % loan.min_payment
	_pay_minimum_button.text = "Pay minimum (%s)" % Palette.format_money(loan.min_payment)
	_pay_minimum_button.disabled = loan.paid_this_year
	_pay_minimum_button.tooltip_text = _why_minimum_is_disabled(loan)
	_warning_label.text = _consequence_of_not_paying(loan)


## A greyed-out button with no reason given reads as broken. There are two
## reasons it can be off, and they mean different things.
func _why_minimum_is_disabled(loan: LoanState) -> String:
	if not loan.paid_this_year:
		return ""
	if _is_brand_new(loan):
		return "Your first payment is due next year."
	return "Already paid for this year."


## Spelled out rather than left to be discovered. The escalation is 10%, then
## 15%, then seizure — see docs/game-rules.md 9.3.
func _consequence_of_not_paying(loan: LoanState) -> String:
	# The commonest confusion: the pay controls appear the instant you borrow,
	# which looks like a demand for money you have only just received.
	if loan.paid_this_year and _is_brand_new(loan):
		return (
			"Nothing is due yet — your first payment is next year. "
			+ "You may still pay early, but never less than the minimum."
		)
	if loan.missed_payments == 1:
		return "One payment missed. A second adds 15% to the balance."
	if loan.missed_payments == 2:
		return "Two payments missed. A third seizes everything you own."
	if not loan.paid_this_year:
		return "Missing this payment adds 10% to the balance."
	return "Paid for this year. You may still pay more."


## Borrowed once and cleared. One loan per game, so there is nothing to offer.
func _show_settled() -> void:
	_status_label.text = "Your loan is settled. You cannot take another this game."
	_warning_label.text = ""


## Never borrowed: what is available, and why it might not be.
func _show_borrowing(player: PlayerState) -> void:
	var maximum: int = LoanRules.max_loan_for(player)
	_status_label.text = "You may borrow up to %s." % Palette.format_money(maximum)
	_borrow_field.placeholder_text = "max %d" % maximum
	_warning_label.text = _session.why_not_loan(
		_session.local_player_id(), LoanRules.MIN_PRINCIPAL
	)
	_max_button.disabled = maximum < LoanRules.MIN_PRINCIPAL


# ------------------------------------------------------------------- validation

func _validate_borrow() -> void:
	if not _borrow_box.visible:
		return
	var amount: int = _borrow_field.text.strip_edges().to_int()
	if amount <= 0:
		_borrow_button.disabled = true
		_borrow_button.tooltip_text = ""
		_borrow_field.theme_type_variation = &""
		return
	var reason: String = _session.why_not_loan(_session.local_player_id(), amount)
	_borrow_button.disabled = not reason.is_empty()
	_borrow_button.tooltip_text = reason
	_borrow_field.theme_type_variation = &"InvalidLineEdit" if not reason.is_empty() else &""


func _validate_pay() -> void:
	if not _pay_box.visible:
		return
	var game: GameState = _session.state()
	var player: PlayerState = game.player_by_id(_session.local_player_id())
	var amount: int = _pay_field.text.strip_edges().to_int()
	if amount <= 0 or player == null:
		_pay_button.disabled = true
		_pay_button.tooltip_text = ""
		_pay_field.theme_type_variation = &""
		return
	var reason: String = LoanRules.validate_payment(player, amount)
	_pay_button.disabled = not reason.is_empty()
	_pay_button.tooltip_text = reason
	_pay_field.theme_type_variation = &"InvalidLineEdit" if not reason.is_empty() else &""


# ---------------------------------------------------------------------- handlers

func _on_borrow_amount_changed(_text: String) -> void:
	_validate_borrow()


func _on_pay_amount_changed(_text: String) -> void:
	_validate_pay()


func _on_borrow_pressed() -> void:
	borrow_requested.emit(_borrow_field.text.strip_edges().to_int())


func _on_max_pressed() -> void:
	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	if player == null:
		return
	_borrow_field.text = str(LoanRules.max_loan_for(player))
	_validate_borrow()


func _on_pay_pressed() -> void:
	payment_requested.emit(_pay_field.text.strip_edges().to_int())


func _on_pay_minimum_pressed() -> void:
	var player: PlayerState = _session.state().player_by_id(_session.local_player_id())
	if player == null or player.loan == null:
		return
	payment_requested.emit(player.loan.min_payment)


# ------------------------------------------------------------------- for tests

func status_text() -> String:
	return _status_label.text


func warning_text() -> String:
	return _warning_label.text
