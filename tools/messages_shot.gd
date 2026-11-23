extends Control
## Renders the StalkleHeads MESSAGES tab (decisions.md D192) so its layout can
## be looked at: a seeded three-player local match - "You", "Ann" and "Bob" -
## with messages written straight into this machine's book, since a local game
## has nobody else to send them.
##
## Runs the real game with Movie Maker, as tools/loan_shot.gd explains. From
## the project root, in PowerShell:
##
##     $g = "<path to>\Godot_v4.7.2-stable_win64_console.exe"
##     $dir = "$env:TEMP\messages_frames"
##     New-Item -ItemType Directory -Force $dir | Out-Null
##     & $g --path . res://tools/messages_shot.tscn --write-movie "$dir\f.png" `
##          --quit-after 40 --fixed-fps 10
##
## Frames: 6, the Exchange tab with the MESSAGES dot lit; 11, the Messages tab
## with no chat open; 16, the chat with Ann (long enough to scroll, and lines
## that look like markup and a network path, drawn as plain text); 21, Ann and
## your notes side by side; 26, Bob opened, replacing the notes because Ann was
## used more recently; 31, Bob blocked (BLOCK? pressed); 36, the ALL PLAYERS room
## opened in place of Bob. A developer tool: `tools/` is not exported.

const StageScene: PackedScene = preload("res://src/ui/stage.tscn")

var _stage: Stage
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = StageScene.instantiate()
	add_child(_stage)

	var settings: GameSettings = GameSettings.new()
	settings.mode = GameMode.Value.STALKLEHEADS
	settings.max_years = 10
	settings.player_count = 3
	settings.rng_seed = 777
	var main: Main = _stage.game()
	var library: ContentLibrary = MatchSetup.load_library(settings.mode)
	main._mount_session(LocalSession.create(settings, library, ["You", "Ann", "Bob"]))
	main._show_gameplay()


func _process(_delta: float) -> void:
	_frames += 1
	var screen: GameplayScreen = _stage.game().current_screen() as GameplayScreen
	if screen == null:
		return
	var session: GameSession = _stage.game().session()
	var tabs: MarketTabs = screen.market_tabs()
	if tabs == null:
		return
	var book: MessageBook = session.messages()
	match _frames:
		3:
			if screen.news_panel() != null:
				screen.news_panel().close()
			for index: int in 14:
				book.record_received(&"p1", "Line %d of a long conversation." % (index + 1))
				book.record_sent(&"p0", &"p1", "Reply %d." % (index + 1))
			book.record_received(&"p1", "[url=https://example.com]click me[/url] [b]bold?[/b]")
			book.record_received(&"p1", "\\\\server\\share\\file.txt and file://c:/windows")
			book.record_received(&"p1", "<(' ')>  :-)  " + "x".repeat(60))
			book.record_received(&"p2", "Selling everything next year.")
			book.record_received(&"p1", "Anyone buying the index?", true)
			book.record_received(&"p2", "Not me.", true)
		8:
			tabs.select_tab(MarketTabs.Tab.MESSAGES)
		13:
			tabs.messages_tab().open_chat(&"p1")
		18:
			tabs.messages_tab().open_chat(&"p0")
			session.send_message(&"p0", "Buy the bakery if it dips.")
			tabs.messages_tab().open_chat(&"p1")
		23:
			tabs.messages_tab().open_chat(&"p2")
		28:
			tabs.messages_tab().chat_with(&"p2").block_button().pressed.emit()
		33:
			tabs.messages_tab().open_chat(&"p1")
			tabs.messages_tab().open_chat(MessageRules.ALL_PLAYERS)
