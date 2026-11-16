class_name LaunchArgs
extends RefCounted
## Command-line flags that skip the menu and go straight into a match.
##
## Purely a development convenience, for testing multiplayer without clicking
## through the menu in two windows every time. See docs/development.md §6a.
##
## **Debug builds only.** `from_command_line()` ignores everything in an exported
## release build, so a shipped game cannot be made to auto-host by a stray
## argument. Parsing itself is pure and always works, which is what makes it
## testable.
##
## Supported flags, in either `OS.get_cmdline_args()` or the user args after a
## `--` separator:
##
## | Flag | Meaning |
## |---|---|
## | `--host` | Open a local lobby immediately |
## | `--join` | Join `127.0.0.1` immediately |
## | `--join=<address>` | Join a specific host |
## | `--port=<n>` | Listen on, or connect to, this port |
## | `--name=<name>` | Play under this name |
## | `--seed=<n>` | Host with a fixed match seed, to reproduce a bug |
## | `--ready` | Ready up as soon as the lobby is joined |
## | `--autostart` | Host: start the match as soon as everybody is ready |
##
## Anything unrecognised is ignored rather than refused: the command line also
## carries Godot's own arguments, which are none of this class's business.


enum Mode {
	## No flags given. Show the menu, as normal.
	MENU,
	HOST,
	JOIN,
}

## Where a `--join` with no address goes. The overwhelmingly common case is two
## windows on one machine.
const DEFAULT_ADDRESS: String = "127.0.0.1"

## Matches the menu's default, so a flag-launched game and a clicked one meet on
## the same port.
const DEFAULT_PORT: int = DevOverlay.DEFAULT_PORT


var mode: Mode = Mode.MENU
var address: String = DEFAULT_ADDRESS
var port: int = DEFAULT_PORT

## Empty means "pick one from the mode", which `resolved_name()` does.
var player_name: String = ""

## 0 means "choose one and record it", the same as everywhere else.
var rng_seed: int = 0

## Ready up on arrival, so a flag-launched guest does not need a click.
var auto_ready: bool = false

## Start as soon as the lobby allows it. With `--ready` on the other instance
## this takes two windows from launch to a running match with no input at all,
## which is what makes a networked bug reproducible from a script.
var auto_start: bool = false


## What this process was told to do, or MENU in a release build.
static func from_command_line() -> LaunchArgs:
	if not OS.is_debug_build():
		return LaunchArgs.new()

	var all: PackedStringArray = OS.get_cmdline_args()
	all.append_array(OS.get_cmdline_user_args())
	return parse(all)


## Pure, so the whole flag surface is testable without a command line.
static func parse(args: PackedStringArray) -> LaunchArgs:
	var parsed: LaunchArgs = LaunchArgs.new()

	for arg: String in args:
		var key: String = arg
		var value: String = ""
		var split: int = arg.find("=")
		if split != -1:
			key = arg.substr(0, split)
			value = arg.substr(split + 1)

		match key:
			"--host":
				parsed.mode = Mode.HOST
			"--join":
				parsed.mode = Mode.JOIN
				if not value.is_empty():
					parsed.address = value
			"--port":
				if value.is_valid_int():
					parsed.port = value.to_int()
			"--name":
				parsed.player_name = value
			"--seed":
				if value.is_valid_int():
					parsed.rng_seed = value.to_int()
			"--ready":
				parsed.auto_ready = true
			"--autostart":
				parsed.auto_start = true
				parsed.mode = Mode.HOST

	return parsed


## The name to play under. Defaulting the two sides differently means two windows
## launched from one dialog are told apart at a glance, with nothing typed.
func resolved_name() -> String:
	if not player_name.is_empty():
		return player_name
	return "Host" if mode == Mode.HOST else "Guest"


## Match settings for a flag-launched host.
##
## Loans are **on**, unlike `GameSettings`' own default, because these flags exist
## for testing the game and the loan panel is part of it. A flag-launched match is
## not trying to be the menu's defaults; it is trying to be useful.
func host_settings() -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.starting_cash = 10000
	settings.loans_enabled = true
	settings.rng_seed = rng_seed
	return settings


func _to_string() -> String:
	return "LaunchArgs(mode=%d %s:%d name=%s seed=%d)" % [
		mode, address, port, resolved_name(), rng_seed,
	]
