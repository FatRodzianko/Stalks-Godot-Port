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
	var game: GameState = _session.state()
	var player: PlayerState = game.player_by_id(_session.local_player_id())
	if player == null:
		return

	_terms_label.text = (
		"Terms: %d years at %d%% interest, compounded yearly. " % [
			LoanRules.TERM_YEARS, int(LoanRules.ANNUAL_RATE * 100.0),
		]
		+ "You may borrow up to 25%% of your net worth, minimum %s. " % (
			Palette.format_money(LoanRules.MIN_PRINCIPAL)
		)
		+ "One loan per game — even after you pay it off."
	)

	var has_loan: bool = player.has_outstanding_loan()
	var ever_borrowed: bool = player.loan != null

	_borrow_box.visible = not ever_borrowed
	_pay_box.visible = has_loan

	if has_loan:
		var loan: LoanState = player.loan
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
		# Greyed out with no reason given reads as broken. Say which of the two
		# reasons it is — a brand new loan, or one already paid this year — and
		# that paying more is still allowed either way.
		_pay_minimum_button.tooltip_text = (
			"" if not loan.paid_this_year
			else (
				"Your first payment is due next year."
				if _is_brand_new(loan)
				else "Already paid for this year."
			)
		)

		# Spell out the consequence rather than leaving it to be discovered.
		if loan.paid_this_year and _is_brand_new(loan):
			# The commonest confusion: the pay controls appear the instant you
			# borrow, which looks like a demand for money you just received.
			_warning_label.text = (
				"Nothing is due yet — your first payment is next year. "
				+ "You may still pay early, but never less than the minimum."
			)
		elif loan.missed_payments == 1:
			_warning_label.text = "One payment missed. A second adds 15% to the balance."
		elif loan.missed_payments == 2:
			_warning_label.text = "Two payments missed. A third seizes everything you own."
		elif not loan.paid_this_year:
			_warning_label.text = "Missing this payment adds 10% to the balance."
		else:
			_warning_label.text = "Paid for this year. You may still pay more."

	elif ever_borrowed:
		_status_label.text = "Your loan is settled. You cannot take another this game."
		_warning_label.text = ""
	else:
		var maximum: int = LoanRules.max_loan_for(player)
		_status_label.text = "You may borrow up to %s." % Palette.format_money(maximum)
		_borrow_field.placeholder_text = "max %d" % maximum
		var reason: String = _session.why_not_loan(
			_session.local_player_id(), LoanRules.MIN_PRINCIPAL
		)
		_warning_label.text = reason
		_max_button.disabled = maximum < LoanRules.MIN_PRINCIPAL

	_validate_borrow()
	_validate_pay()


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
