class_name DevOverlay
extends PanelContainer
## Host and join over a direct connection, for development only.
##
## **Why this is not on the title screen.** Direct host/join by address and
## port is how two copies of the game are tested on one machine without Steam,
## and it is the only way to play on a LAN. It is also meaningless to a player
## who bought the game on Steam, and it was taking up a third of the Join
## panel. The original had nothing like it.
##
## So it lives here: a small panel pinned to the top-left corner, shown only in
## a development build. `Main` checks `OS.is_debug_build()` before adding it,
## which is false in anything produced by the `Windows Release` preset. The
## shape is borrowed from the network-manager overlays Unity networking
## libraries ship for the same purpose.
##
## **F1 hides it.** It sits over the top-left of the title screen, which is
## exactly where the heading is, so judging a layout with it on display is
## harder than it should be. Reported while reviewing the rebuilt title screen.
##
## It decides nothing and holds no session. It emits what was asked for and
## `Main` does it, exactly as the title screen does.


## Host a direct game on `port`, under `player_name`.
signal host_requested(port: int, player_name: String)

## Join a direct game at `address`:`port`, under `player_name`.
signal join_requested(address: String, port: int, player_name: String)


## Where a local game listens unless somebody changes it. Picked from the IANA
## dynamic range, which is where a game has no business claiming a well-known
## number.
const DEFAULT_PORT: int = 42420


@onready var _address_field: LineEdit = %DevAddressField
@onready var _port_spin: SpinBox = %DevPortSpin
@onready var _host_button: Button = %DevHostButton
@onready var _join_button: Button = %DevJoinButton


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)


## F1 shows and hides the panel.
##
## Unhandled input, so a field on the title screen that wants the key gets it
## first. Nothing does, but that is the right way round for a tool that sits on
## top of the game.
func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_F1:
		return
	accept_event()
	visible = not visible


## What a directly connected player is called.
##
## **There is no field for it.** There was, and it earned its place on nothing:
## `HostSession.sanitised_name` already names an unnamed arrival after its seat,
## so two windows on one machine come out as distinct players without anybody
## typing. A name is also the one thing this overlay is not for — it exists to
## open a connection, and the real game takes names from Steam (D66).
##
## Named `chosen_*` like the title screen's readers rather than `name`, `port`
## and `address`, which collide with this class's own signal parameters and
## with `Node.name`.
func chosen_name() -> String:
	return ""


## The address typed here, defaulting to this machine — which is what it is
## for nearly every time it is used.
func chosen_address() -> String:
	var typed: String = _address_field.text.strip_edges()
	if typed.is_empty():
		return "127.0.0.1"
	return typed


func chosen_port() -> int:
	return int(_port_spin.value)


func _on_host_pressed() -> void:
	host_requested.emit(chosen_port(), chosen_name())


func _on_join_pressed() -> void:
	join_requested.emit(chosen_address(), chosen_port(), chosen_name())
