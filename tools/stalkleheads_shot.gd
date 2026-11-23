extends Control
## Renders the StalkleHeads tabs, one after another, so the layout can be looked
## at rather than only asserted about: the Exchange (with two holdings), Market,
## Industries and Company tabs (the last with the side panel opened), then the
## year digest. A seeded solo match, six years in.
##
## Runs the real game with Movie Maker, as tools/loan_shot.gd explains. From
## the project root, in PowerShell:
##
##     $g = "<path to>\Godot_v4.7.2-stable_win64_console.exe"
##     $dir = "$env:TEMP\stalks_frames"
##     New-Item -ItemType Directory -Force $dir | Out-Null
##     & $g --path . res://tools/stalkleheads_shot.tscn --write-movie "$dir\f.png" `
##          --quit-after 30 --fixed-fps 10
##
## Frames 6, 11, 16, 21 and 26 are the five pictures (`f00000006.png` and so
## on). A developer tool: `tools/` is not exported.

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
	settings.player_count = 1
	settings.loans_enabled = true
	settings.rng_seed = 777
	_stage.game().start_match(settings)


func _process(_delta: float) -> void:
	_frames += 1
	var screen: GameplayScreen = _stage.game().current_screen() as GameplayScreen
	if screen == null:
		return
	if _frames == 3:
		var session: GameSession = _stage.game().session()
		for _year: int in 6:
			session.set_ready(session.local_player_id(), true)
		session.request_buy(session.local_player_id(), session.state().market.companies[0].id, 5)
		session.request_buy(session.local_player_id(), session.state().market.companies[7].id, 12)
		screen.news_panel().close()
	var tabs: MarketTabs = screen.market_tabs()
	if tabs == null:
		return
	match _frames:
		8:
			tabs.select_tab(MarketTabs.Tab.MARKET)
			tabs.side_button(SidePanel.Page.HOLDINGS).pressed.emit()
		13:
			tabs.select_tab(MarketTabs.Tab.INDUSTRIES)
		18:
			tabs.show_company(_stage.game().session().state().market.companies[0].id)
			tabs.company_tab().pick_button().pressed.emit()
		23:
			screen.get_node("%EventFlavour").more_requested.emit()
