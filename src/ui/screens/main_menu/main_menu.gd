class_name MainMenu
extends MarginContainer
## The opening screen: choose the match settings and start.
##
## Emits the chosen settings outward rather than building a session itself, so
## the screen host decides what to do with them. Knows nothing about sessions.
##
## Player count is deliberately absent. In a solo game it means nothing, and in a
## networked one the roster is whoever is in the lobby when the host starts, so
## there is nothing to choose here (decisions.md D48).
##
## The match settings belong to whoever *hosts*, so the settings panel is hidden
## when joining: a joiner is told the year limit and the seed by the host
## (architecture.md §5.3) and choosing them here would be a lie.


signal start_requested(settings: GameSettings)

## Host a networked match with these settings, listening on `port`.
signal host_requested(settings: GameSettings, player_name: String, port: int)

## Join somebody else's match. No settings — the host owns those.
signal join_requested(address: String, port: int, player_name: String)

## Open the Steam lobby browser. Carries nothing: Steam supplies the player's
## name, and the lobby supplies everything else.
signal steam_requested


## Where a networked match listens unless somebody changes it. Picked from the
## IANA dynamic range, which is where a game has no business claiming a
## well-known number.
const DEFAULT_PORT: int = 42420

@onready var _years_spin: SpinBox = %YearsSpin
@onready var _cash_spin: SpinBox = %CashSpin
@onready var _loans_check: CheckBox = %LoansCheck
@onready var _seed_field: LineEdit = %SeedField
@onready var _start_button: Button = %StartButton
@onready var _content_warning: Label = %ContentWarning
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _name_field: LineEdit = %NameField
@onready var _address_field: LineEdit = %AddressField
@onready var _port_spin: SpinBox = %PortSpin
@onready var _settings_box: VBoxContainer = %SettingsBox
@onready var _network_box: VBoxContainer = %NetworkBox
@onready var _mode_tabs: HBoxContainer = %ModeTabs
@onready var _solo_tab: Button = %SoloTab
@onready var _host_tab: Button = %HostTab
@onready var _join_tab: Button = %JoinTab
@onready var _steam_button: Button = %SteamButton


## Which of the three paths the player is looking at. Not an enum on purpose —
## it maps one-to-one onto the three tab buttons and nothing else uses it.
enum Mode { SOLO, HOST, JOIN }

var _mode: Mode = Mode.SOLO


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_solo_tab.pressed.connect(_on_solo_tab)
	_host_tab.pressed.connect(_on_host_tab)
	_join_tab.pressed.connect(_on_join_tab)
	_steam_button.pressed.connect(_on_steam_button_pressed)

	_port_spin.min_value = 1024
	_port_spin.max_value = 65535
	_port_spin.value = DEFAULT_PORT

	_years_spin.min_value = 2
	_years_spin.max_value = 99
	_years_spin.value = 10

	_cash_spin.min_value = 100
	_cash_spin.max_value = 1000000
	_cash_spin.step = 100
	_cash_spin.value = 10000

	_loans_check.button_pressed = true
	_show_mode(Mode.SOLO)

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


## The name typed, or a sensible stand-in. The host sanitises it again on arrival
## — this is convenience, not validation (see `HostSession.sanitised_name`).
func chosen_name() -> String:
	var typed: String = _name_field.text.strip_edges()
	return typed if not typed.is_empty() else "Player"


func chosen_port() -> int:
	return int(_port_spin.value)


## The address typed, defaulting to this machine so that the commonest test —
## two windows on one computer — needs no typing at all.
func chosen_address() -> String:
	var typed: String = _address_field.text.strip_edges()
	return typed if not typed.is_empty() else "127.0.0.1"


## Shows a failure — a port already in use, an unreachable host — on the menu
## the player is still looking at.
func show_problem(problem: String) -> void:
	_content_warning.visible = true
	_content_warning.text = problem


## Switches path. Public so a test can pick a mode without clicking.
func show_mode(mode: Mode) -> void:
	_show_mode(mode)


func current_mode() -> Mode:
	return _mode


func _show_mode(mode: Mode) -> void:
	_mode = mode
	# The host owns the match settings, so a joiner does not get to choose them.
	_settings_box.visible = mode != Mode.JOIN
	_network_box.visible = mode != Mode.SOLO
	_address_field.get_parent().visible = mode == Mode.JOIN

	_start_button.visible = mode == Mode.SOLO
	_host_button.visible = mode == Mode.HOST
	_join_button.visible = mode == Mode.JOIN

	_solo_tab.button_pressed = mode == Mode.SOLO
	_host_tab.button_pressed = mode == Mode.HOST
	_join_tab.button_pressed = mode == Mode.JOIN


func _on_solo_tab() -> void:
	_show_mode(Mode.SOLO)


func _on_host_tab() -> void:
	_show_mode(Mode.HOST)


func _on_join_tab() -> void:
	_show_mode(Mode.JOIN)


func _on_steam_button_pressed() -> void:
	steam_requested.emit()


func _on_start_pressed() -> void:
	start_requested.emit(chosen_settings())


func _on_host_pressed() -> void:
	host_requested.emit(chosen_settings(), chosen_name(), chosen_port())


func _on_join_pressed() -> void:
	join_requested.emit(chosen_address(), chosen_port(), chosen_name())
