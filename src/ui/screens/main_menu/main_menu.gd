class_name MainMenu
extends MarginContainer
## The title screen: four things you can do, across the top.
##
## **SINGLE PLAYER** and **HOST ONLINE** are the same panel. Both configure a
## match — years, starting cash, loans, seed — and the only difference is that
## an online game also has a name, a player limit and a privacy setting, and
## takes your display name from Steam rather than from a field. They are two
## buttons rather than one Create Game with a choice inside it, because "what
## do you want to do" is the question a title screen exists to ask, and burying
## half the answer a level down made it worse.
##
## **JOIN GAME** is the list of online games, loaded when the tab is picked.
## No settings here at all — the host owns those and sends them with the
## opening state (architecture.md §5.3), so offering them to a joiner would be
## a lie.
##
## **SETTINGS** is the shared `SettingsPanel`, the same widget the in-match
## pause menu shows.
##
## **The panel never changes size.** Every tab draws into a card of one fixed
## size, so the title, the tab bar and the quit button stay exactly where they
## are as you move between them. Furniture that jumps around as you click is
## the thing this layout exists to prevent.
##
## **Direct host and join by address is not here.** It is a development tool,
## it means nothing to somebody who bought the game on Steam, and it used to
## take up a third of this screen. See `dev_overlay.gd`.
##
## This screen emits intent and builds nothing. It does not know what a session
## is.


## Play on your own, right now.
signal start_requested(settings: GameSettings)

## Host a game other people reach through Steam. No player name: Steam
## supplies it, and a second place to set it is a second place to disagree.
signal host_online_requested(settings: GameSettings)

## The player opened Join Game. The screen host answers by handing the browser
## a Steam service, because Steam is started once per process and this screen
## does not own it.
signal browse_online_requested

## The player picked a game from the list.
signal join_online_requested(lobby_id: int)

## The player asked to go back into the match they dropped out of. Which match
## that is, and whether it is still there, is the screen host's business — this
## screen only knows that a button was pressed.
signal rejoin_requested

## Close the game. The screen host owns shutting the session down, so this
## only says that the player asked.
signal quit_requested


## Which panel is showing.
enum Mode { SINGLE, HOST, JOIN, SETTINGS }


@onready var _single_tab: Button = %SinglePlayerTab
@onready var _host_tab: Button = %HostOnlineTab
@onready var _join_tab: Button = %JoinTab
@onready var _settings_tab: Button = %SettingsTab

@onready var _game_box: VBoxContainer = %GameBox
@onready var _join_box: VBoxContainer = %JoinBox
@onready var _settings_box: VBoxContainer = %SettingsBox

@onready var _name_label: Label = %NameLabel
@onready var _name_field: LineEdit = %NameField
@onready var _game_name_label: Label = %GameNameLabel
@onready var _game_name_field: LineEdit = %GameNameField
@onready var _years_spin: SpinBox = %YearsSpin
@onready var _cash_spin: SpinBox = %CashSpin
@onready var _players_label: Label = %PlayersLabel
@onready var _players_spin: SpinBox = %PlayersSpin
@onready var _loans_check: CheckBox = %LoansCheck
@onready var _privacy_label: Label = %PrivacyLabel
@onready var _invite_only_check: CheckBox = %InviteOnlyCheck
@onready var _seed_field: LineEdit = %SeedField
@onready var _start_button: Button = %StartButton

@onready var _browser: LobbyBrowser = %Browser
@onready var _settings: SettingsPanel = %Settings
@onready var _message: Label = %ContentWarning
@onready var _quit_button: Button = %QuitButton
@onready var _rejoin_button: Button = %RejoinButton
@onready var _supporter_note: Label = %SupporterNote


var _mode: Mode = Mode.SINGLE

## True once Join Game has asked for the lobby list. Asking twice would start
## Steam twice; never asking would leave the list empty.
var _browser_started: bool = false


func _ready() -> void:
	_single_tab.pressed.connect(_on_single_tab_pressed)
	_host_tab.pressed.connect(_on_host_tab_pressed)
	_join_tab.pressed.connect(_on_join_tab_pressed)
	_settings_tab.pressed.connect(_on_settings_tab_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_rejoin_button.pressed.connect(_on_rejoin_pressed)
	_browser.join_requested.connect(_on_browser_join_requested)

	show_mode(Mode.SINGLE)

	# If the authored content is broken the game cannot be trusted, so say so
	# here rather than starting a match that misbehaves.
	var library: ContentLibrary = ContentLibrary.load_from()
	if library.is_valid():
		return
	show_problem("Content problem: %s" % library.errors[0])
	_start_button.disabled = true
	for error: String in library.errors:
		push_error("Content error: %s" % error)


# ---------------------------------------------------------------------- tabs

## Switches panel. Public so a test can pick one without clicking.
func show_mode(mode: Mode) -> void:
	_mode = mode

	var configuring: bool = mode == Mode.SINGLE or mode == Mode.HOST
	_game_box.visible = configuring
	_join_box.visible = mode == Mode.JOIN
	_settings_box.visible = mode == Mode.SETTINGS

	_single_tab.button_pressed = mode == Mode.SINGLE
	_host_tab.button_pressed = mode == Mode.HOST
	_join_tab.button_pressed = mode == Mode.JOIN
	_settings_tab.button_pressed = mode == Mode.SETTINGS

	if configuring:
		_show_fields_for(mode)
	if mode == Mode.SETTINGS:
		# The pause menu shows the same settings and may have changed them.
		_settings.refresh()
	if mode == Mode.JOIN and not _browser_started:
		_browser_started = true
		browse_online_requested.emit()


## Which fields belong to which kind of game.
##
## **An online game names you from Steam**, so a name field there would be a
## control that silently does nothing. **A single-player game has no second
## player**, so a limit and a privacy setting would be decoration. Everything
## else — years, cash, loans, seed — is a setting of the *match* and is the
## same either way, which is why these are one panel and not two.
func _show_fields_for(mode: Mode) -> void:
	var online: bool = mode == Mode.HOST

	_name_label.visible = not online
	_name_field.visible = not online
	_game_name_label.visible = online
	_game_name_field.visible = online
	_players_label.visible = online
	_players_spin.visible = online
	_privacy_label.visible = online
	_invite_only_check.visible = online

	if online:
		_start_button.text = "HOST ONLINE"
		return
	_start_button.text = "START"


func current_mode() -> Mode:
	return _mode


## The settings panel, shared with the pause menu. For tests.
func settings_panel() -> SettingsPanel:
	return _settings


## The lobby list. For tests.
func lobby_browser() -> LobbyBrowser:
	return _browser


## Shows the supporter thank-you, if this player has earned one.
##
## Called by the screen host, which owns Steam, rather than asked for here —
## the title screen must come up identically with Steam closed, and a screen
## that reaches for Steam on its own cannot promise that.
##
## **Hidden unless told otherwise**, so the ordinary case needs no call at all.
func show_supporter_note(owns_dlc: bool) -> void:
	_supporter_note.visible = owns_dlc


## Shows REJOIN GAME, for a player who dropped out of a match that is still
## being played.
##
## **Hidden unless told otherwise**, like the supporter note, because most title
## screens have nothing to go back to and a button that explains itself only by
## failing is worse than no button. Whether there is a match is the screen
## host's question to answer: it owns the record of the last one
## (`LastMatch`), and this screen must come up identically with Steam closed.
##
## It sits opposite QUIT TO DESKTOP on the same row — the two things you can do
## with a title screen that are not starting a game.
func offer_rejoin(can_rejoin: bool) -> void:
	_rejoin_button.visible = can_rejoin


## Gives the lobby list a Steam service to work with. Called by the screen host
## in answer to `browse_online_requested`, because Steam is started once per
## process and belongs there.
func show_online_games(service: SteamService) -> void:
	_browser.setup(service)


# ------------------------------------------------------------------- choices

## The settings the player chose. Public so a test can read them back.
func chosen_settings() -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	# Blank is allowed and means "name it after the host", which `Main` fills
	# in once it knows who that is — which, for an online game, is the Steam
	# account rather than anything typed here.
	settings.game_name = _game_name_field.text.strip_edges()
	settings.max_years = int(_years_spin.value)
	settings.starting_cash = clampi(
		int(_cash_spin.value),
		GameSettings.MIN_STARTING_CASH,
		GameSettings.MAX_STARTING_CASH,
	)
	settings.loans_enabled = _loans_check.button_pressed

	# A single-player game is one player whatever the hidden control says, and
	# a private lobby means nothing without a lobby.
	if _mode == Mode.HOST:
		settings.player_count = int(_players_spin.value)
		settings.invite_only = _invite_only_check.button_pressed
	else:
		settings.player_count = 1
		settings.invite_only = false

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
## **Single-player only.** An online game names you from your Steam account, so
## this field has no say there. It used to: a rebuilt menu dropped the persona
## lookup, so every player in a Steam game showed up as "Player". See
## docs/decisions.md D66.
func chosen_name() -> String:
	var typed: String = _name_field.text.strip_edges()
	if typed.is_empty():
		return "Player"
	return typed


# ------------------------------------------------------------------ messages

## Shows a failure — a port already in use, an unreachable host, Steam not
## running — on the screen the player is still looking at.
func show_problem(problem: String) -> void:
	_message.theme_type_variation = &"Danger"
	_message.text = problem
	_message.visible = not problem.is_empty()


## Shows something that is not a failure, in the same place.
func show_status(status: String) -> void:
	_message.theme_type_variation = &"Faint"
	_message.text = status
	_message.visible = not status.is_empty()


# ------------------------------------------------------------------ pressing

func _on_single_tab_pressed() -> void:
	show_mode(Mode.SINGLE)


func _on_host_tab_pressed() -> void:
	show_mode(Mode.HOST)


func _on_join_tab_pressed() -> void:
	show_mode(Mode.JOIN)


func _on_settings_tab_pressed() -> void:
	show_mode(Mode.SETTINGS)


## One button, two meanings, decided by which tab is open. The alternative was
## two buttons with one always hidden, which is the same thing with more nodes
## and a second label to keep in step.
func _on_start_pressed() -> void:
	if _mode == Mode.HOST:
		host_online_requested.emit(chosen_settings())
		return
	start_requested.emit(chosen_settings())


func _on_browser_join_requested(lobby_id: int) -> void:
	join_online_requested.emit(lobby_id)


## No confirmation. Pressing a button labelled QUIT TO DESKTOP on a title
## screen is not something anybody does by accident, and there is no match to
## lose from here.
func _on_quit_pressed() -> void:
	quit_requested.emit()


## No confirmation here either: rejoining a game you were already in takes
## nothing away from you, and there is nothing on this screen to lose.
func _on_rejoin_pressed() -> void:
	rejoin_requested.emit()
