class_name MainMenu
extends MarginContainer
## The title screen: make a game, or go and find one.
##
## Two things you can do, and they are the two halves of this screen.
##
## **Create Game** carries the settings — how many years, how much to start
## with, whether loans are on, the seed — and then three ways to begin with
## those settings: on your own, hosted online through Steam, or hosted on the
## local network. The settings are identical for all three, because they are
## settings of the *match*, not of the transport.
##
## **Join Game** is for somebody else's match: the list of online games, or a
## direct address on the local network. No settings here at all — the host owns
## those and sends them with the opening state (architecture.md §5.3), so
## offering them to a joiner would be a lie.
##
## **Why this shape.** The first version had SOLO / HOST / JOIN tabs and a
## separate "Play on Steam" screen, and the settings lived only on the first
## two. Steam is how the game is actually played; local hosting exists so that
## two windows can be tested without Steam running. So the configuration lived
## on the development path and was absent from the real one, and a Steam match
## was always hosted with defaults — loans off, whatever the player had chosen.
## See docs/decisions.md D65, which replaces D62.
##
## This screen emits intent and builds nothing. It does not know what a session
## is.


## Play on your own, right now.
signal start_requested(settings: GameSettings)

## Host a game other people reach through Steam. No player name: Steam
## supplies it, and a second place to set it is a second place to disagree.
signal host_online_requested(settings: GameSettings)

## Host a game other people reach by typing an address. For testing two
## machines without Steam, and for a LAN with no Steam at all.
signal host_local_requested(settings: GameSettings, player_name: String, port: int)

## Show the list of games being hosted online.
signal browse_online_requested

## Join a local game by address. No settings — the host owns those.
signal join_local_requested(address: String, port: int, player_name: String)


## Where a local game listens unless somebody changes it. Picked from the IANA
## dynamic range, which is where a game has no business claiming a well-known
## number.
const DEFAULT_PORT: int = 42420

@onready var _name_field: LineEdit = %NameField
@onready var _game_name_field: LineEdit = %GameNameField
@onready var _years_spin: SpinBox = %YearsSpin
@onready var _cash_spin: SpinBox = %CashSpin
@onready var _loans_check: CheckBox = %LoansCheck
@onready var _invite_only_check: CheckBox = %InviteOnlyCheck
@onready var _seed_field: LineEdit = %SeedField
@onready var _create_box: VBoxContainer = %CreateBox
@onready var _join_box: VBoxContainer = %JoinBox
@onready var _create_tab: Button = %CreateTab
@onready var _join_tab: Button = %JoinTab
@onready var _single_player_button: Button = %SinglePlayerButton
@onready var _host_online_button: Button = %HostOnlineButton
@onready var _host_local_button: Button = %HostLocalButton
@onready var _host_port_spin: SpinBox = %HostPortSpin
@onready var _browse_online_button: Button = %BrowseOnlineButton
@onready var _join_local_button: Button = %JoinLocalButton
@onready var _join_port_spin: SpinBox = %JoinPortSpin
@onready var _address_field: LineEdit = %AddressField
@onready var _message: Label = %ContentWarning


## Which half of the screen is showing.
enum Mode { CREATE, JOIN }

var _mode: Mode = Mode.CREATE

## Where this screen reads and writes what the player last typed. Empty until
## `recall_settings` sets it, and an empty one means remember nothing.
var _settings_path: String = ""


func _ready() -> void:
	_single_player_button.pressed.connect(_on_single_player_pressed)
	_host_online_button.pressed.connect(_on_host_online_pressed)
	_host_local_button.pressed.connect(_on_host_local_pressed)
	_browse_online_button.pressed.connect(_on_browse_online_pressed)
	_join_local_button.pressed.connect(_on_join_local_pressed)
	_create_tab.pressed.connect(_on_create_tab_pressed)
	_join_tab.pressed.connect(_on_join_tab_pressed)

	show_mode(Mode.CREATE)

	# If the authored content is broken the game cannot be trusted, so say so
	# here rather than starting a match that misbehaves.
	var library: ContentLibrary = ContentLibrary.load_from()
	if library.is_valid():
		return
	show_problem("Content problem: %s" % library.errors[0])
	_single_player_button.disabled = true
	_host_online_button.disabled = true
	_host_local_button.disabled = true
	for error: String in library.errors:
		push_error("Content error: %s" % error)


## The settings the player chose. Public so a test can read them back.
func chosen_settings() -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	# Blank is allowed and means "name it after the host", which `Main` fills
	# in once it knows who that is — which, for an online game, is the Steam
	# account rather than anything typed here.
	settings.game_name = _game_name_field.text.strip_edges()
	settings.max_years = int(_years_spin.value)
	settings.starting_cash = int(_cash_spin.value)
	settings.player_count = 1
	settings.loans_enabled = _loans_check.button_pressed
	# Steam-only, and harmless to carry on a game that never reaches Steam:
	# a private lobby is one the browser never lists.
	settings.invite_only = _invite_only_check.button_pressed

	# A blank or non-numeric seed means "choose one", which LocalSession does
	# and records, so every match stays reproducible afterwards.
	var typed: String = _seed_field.text.strip_edges()
	if typed.is_valid_int():
		settings.rng_seed = typed.to_int()
	else:
		settings.rng_seed = 0
	return settings


## The name typed, or a sensible stand-in. The host sanitises it again on
## arrival — this is convenience, not validation (`HostSession.sanitised_name`).
##
## **Local games only.** An online game names you from your Steam account, so
## this field has no say there. It used to: the rebuilt menu dropped the
## persona lookup, so every player in a Steam game showed up as "Player", or
## as whatever had been typed here for some earlier local game. See
## docs/decisions.md D66.
func chosen_name() -> String:
	var typed: String = _name_field.text.strip_edges()
	if typed.is_empty():
		return "Player"
	return typed


## The port a locally hosted game would listen on.
func chosen_host_port() -> int:
	return int(_host_port_spin.value)


## The port to connect to when joining a local game. Separate from the hosting
## port because the two are typed on different halves of the screen and a
## shared control would read as though one answered for both.
func chosen_join_port() -> int:
	return int(_join_port_spin.value)


## The address typed, defaulting to this machine so that the commonest test —
## two windows on one computer — needs no typing at all.
func chosen_address() -> String:
	var typed: String = _address_field.text.strip_edges()
	if typed.is_empty():
		return "127.0.0.1"
	return typed


## Shows a failure — a port already in use, an unreachable host, Steam not
## running — on the screen the player is still looking at.
func show_problem(problem: String) -> void:
	_message.theme_type_variation = &"Danger"
	_message.text = problem
	_message.visible = not problem.is_empty()


## Shows something that is not a failure, in the same place. Creating a Steam
## lobby takes a moment and silence reads as a dead button.
func show_status(status: String) -> void:
	_message.theme_type_variation = &"Faint"
	_message.text = status
	_message.visible = not status.is_empty()


## Switches half. Public so a test can pick one without clicking.
func show_mode(mode: Mode) -> void:
	_mode = mode
	_create_box.visible = mode == Mode.CREATE
	_join_box.visible = mode == Mode.JOIN
	_create_tab.button_pressed = mode == Mode.CREATE
	_join_tab.button_pressed = mode == Mode.JOIN


func current_mode() -> Mode:
	return _mode


func _on_create_tab_pressed() -> void:
	show_mode(Mode.CREATE)


func _on_join_tab_pressed() -> void:
	show_mode(Mode.JOIN)


# ------------------------------------------------------- between sessions
#
# What you typed last time comes back, so a second run does not start from
# defaults. The **seed does not**, deliberately: a remembered seed would make
# every match identical and the player would have no reason to suspect why.

## Fills the controls in from what was saved, and makes this screen save to
## the same place from now on.
##
## **Called by `Main`, not by `_ready`.** A screen that read the file the
## moment it existed would make every test of the menu depend on whatever the
## developer last typed — the default-value tests would pass or fail by
## accident. Until this is called the screen neither reads nor writes
## anything, which is also what makes it safe to put one in a test.
func recall_settings(path: String = UserSettings.PATH) -> void:
	_settings_path = path
	var remembered: UserSettings = UserSettings.load_from(path)
	_name_field.text = remembered.player_name
	_game_name_field.text = remembered.game_name
	_years_spin.value = remembered.years
	_cash_spin.value = remembered.starting_cash
	_loans_check.button_pressed = remembered.loans_enabled
	_invite_only_check.button_pressed = remembered.invite_only


## Called whenever a game is started or joined, which is the moment the
## player has settled on these values.
func _remember_what_was_typed() -> void:
	if _settings_path.is_empty():
		return
	var remembered: UserSettings = UserSettings.new()
	remembered.player_name = _name_field.text.strip_edges()
	remembered.game_name = _game_name_field.text.strip_edges()
	remembered.years = int(_years_spin.value)
	remembered.starting_cash = int(_cash_spin.value)
	remembered.loans_enabled = _loans_check.button_pressed
	remembered.invite_only = _invite_only_check.button_pressed
	remembered.save_to(_settings_path)


func _on_single_player_pressed() -> void:
	_remember_what_was_typed()
	start_requested.emit(chosen_settings())


## No name goes with this: an online game takes it from Steam.
func _on_host_online_pressed() -> void:
	_remember_what_was_typed()
	host_online_requested.emit(chosen_settings())


func _on_host_local_pressed() -> void:
	_remember_what_was_typed()
	host_local_requested.emit(chosen_settings(), chosen_name(), chosen_host_port())


func _on_browse_online_pressed() -> void:
	_remember_what_was_typed()
	browse_online_requested.emit()


func _on_join_local_pressed() -> void:
	_remember_what_was_typed()
	join_local_requested.emit(chosen_address(), chosen_join_port(), chosen_name())
