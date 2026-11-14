class_name MainMenu
extends MarginContainer
## The opening screen: choose the match settings and start.
##
## Emits the chosen settings outward rather than building a session itself, so
## the screen host decides what to do with them. Knows nothing about sessions.
##
## Player count is deliberately absent. In a solo game it means nothing, and in
## multiplayer it belongs to the lobby, which arrives in Phase 5.


signal start_requested(settings: GameSettings)

@onready var _years_spin: SpinBox = %YearsSpin
@onready var _cash_spin: SpinBox = %CashSpin
@onready var _loans_check: CheckBox = %LoansCheck
@onready var _seed_field: LineEdit = %SeedField
@onready var _start_button: Button = %StartButton
@onready var _content_warning: Label = %ContentWarning


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)

	_years_spin.min_value = 2
	_years_spin.max_value = 99
	_years_spin.value = 10

	_cash_spin.min_value = 100
	_cash_spin.max_value = 1000000
	_cash_spin.step = 100
	_cash_spin.value = 10000

	_loans_check.button_pressed = true

	# If the authored content is broken the game cannot be trusted, so say so
	# here rather than starting a match that misbehaves.
	var library: ContentLibrary = ContentLibrary.load_from()
	if library.is_valid():
		_content_warning.visible = false
	else:
		_content_warning.visible = true
		_content_warning.text = "Content problem: %s" % library.errors[0]
		_start_button.disabled = true
		for error: String in library.errors:
			push_error("Content error: %s" % error)


## The settings the player chose. Public so a test can read them back.
func chosen_settings() -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = int(_years_spin.value)
	settings.starting_cash = int(_cash_spin.value)
	settings.player_count = 1
	settings.loans_enabled = _loans_check.button_pressed

	# A blank or non-numeric seed means "choose one", which LocalSession does and
	# records, so every match stays reproducible afterwards.
	var typed: String = _seed_field.text.strip_edges()
	settings.rng_seed = typed.to_int() if typed.is_valid_int() else 0
	return settings


func _on_start_pressed() -> void:
	start_requested.emit(chosen_settings())
