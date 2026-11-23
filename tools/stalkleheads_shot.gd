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
##          --quit-after 65 --fixed-fps 10
##
## Frames 6, 11, 16, 21 and 26 are the five pictures (`f00000006.png` and so
## on). Then the Company tab's five charts (decisions.md D188): frames 31
## (PRICE), 36 (SALES), 41 (MARGIN), 46 (PER SHARE) and 51 (P/E). Frame 56 is
## the Market tab with the side panel closed, the year in review on its right
## (D189), and frame 61 the same scrolled to the bottom of the right half. A developer tool: `tools/` is not exported.

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
		28:
			screen.news_panel().close()
			tabs.company_tab().pick_button().pressed.emit()
			tabs.company_tab().select_view(CompanyTab.View.PRICE)
		33:
			tabs.company_tab().select_view(CompanyTab.View.SALES)
		38:
			tabs.company_tab().select_view(CompanyTab.View.MARGIN)
		43:
			tabs.company_tab().select_view(CompanyTab.View.PER_SHARE)
		48:
			tabs.company_tab().select_view(CompanyTab.View.PE)
		53:
			tabs.select_tab(MarketTabs.Tab.MARKET)
		58:
			var right: ScrollContainer = tabs.market_tab().get_node("%RightScroll")
			right.scroll_vertical = 10000
