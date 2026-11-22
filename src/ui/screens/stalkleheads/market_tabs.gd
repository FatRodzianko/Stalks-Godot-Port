class_name MarketTabs
extends VBoxContainer
## The four tabs of a StalkleHeads match, in the middle of the playing screen
## (docs/stalkleheads-design.md §7): Stalk Exchange, Market Analysis,
## Industries and Company.
##
## **The base game's screen is the frame around this.** `GameplayScreen` keeps
## its top bar (year, mood, the year's event, the yeehaw corner) and its bottom
## bar (loans, messages, READY), and in a match with a market it puts this in
## place of its three boards. One row goes to the tab strip, which is what the
## design's row budget allows (§7.1). The base game's boards are untouched and
## no base-game match ever builds this (§14 q1, decisions.md D180).
##
## The tab strip is four toggle buttons in one `ButtonGroup` rather than
## Godot's `TabContainer`, so it takes the shared Theme's button styles and
## needs no new theme entries.
##
## Holds nothing but which tab is showing and what each tab is pointed at.
## Every figure comes from the state it is handed (`refresh`).


signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)
signal amount_changed(stalk_id: StringName, shares: int)


enum Tab { EXCHANGE, MARKET, INDUSTRIES, COMPANY }

## The strip's captions, as the design writes them (§7.2).
const CAPTIONS: Dictionary[Tab, String] = {
	Tab.EXCHANGE: "EXCHANGE",
	Tab.MARKET: "MARKET",
	Tab.INDUSTRIES: "INDUSTRIES",
	Tab.COMPANY: "COMPANY",
}


var _state: GameState
var _current: Tab = Tab.EXCHANGE
var _buttons: Dictionary[Tab, Button] = {}
var _pages: Dictionary[Tab, Control] = {}

## The year's event as the top strip shows it, for the Market tab.
var _event_text: String = ""
var _event_effect: String = ""

@onready var _strip: HBoxContainer = %TabStrip
@onready var _exchange: ExchangeTab = %ExchangeTab
@onready var _market: MarketTab = %MarketTab
@onready var _industries: IndustriesTab = %IndustriesTab
@onready var _company: CompanyTab = %CompanyTab


func _ready() -> void:
	_pages = {
		Tab.EXCHANGE: _exchange,
		Tab.MARKET: _market,
		Tab.INDUSTRIES: _industries,
		Tab.COMPANY: _company,
	}
	var group: ButtonGroup = ButtonGroup.new()
	for tab: Tab in CAPTIONS:
		var button: Button = Button.new()
		button.text = CAPTIONS[tab]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_tab_button_pressed.bind(tab))
		_strip.add_child(button)
		_buttons[tab] = button

	_exchange.buy_requested.connect(_on_exchange_buy_requested)
	_exchange.sell_requested.connect(_on_exchange_sell_requested)
	_exchange.amount_changed.connect(_on_exchange_amount_changed)
	_exchange.company_requested.connect(show_company)
	_industries.selection_changed.connect(_on_industries_selection_changed)
	_company.company_changed.connect(_on_company_changed)
	select_tab(Tab.EXCHANGE)


## Builds the board for `state`'s market. Once per match.
func build(state: GameState) -> void:
	_state = state
	_exchange.build(state)


## Redraws whatever needs it. Only the tab on show is redrawn: the others redraw
## when they are opened, which is the same state, since nothing on the analysis
## tabs changes while anybody trades (§6.2).
func refresh(
	state: GameState,
	player: PlayerState,
	trading: bool,
	ranking_order: Array[StringName],
	local_id: StringName,
	host_id: StringName,
) -> void:
	_state = state
	# The board is always redrawn, even unseen: its rows carry the trade
	# controls, and their enabled state must be right the moment it is opened.
	_exchange.refresh(state, player, trading, ranking_order, local_id, host_id)
	_refresh_page(_current)


## The year's event, as the top strip shows it.
func set_event(text: String, effect: String) -> void:
	_event_text = text
	_event_effect = effect
	if _current == Tab.MARKET and _state != null:
		_refresh_page(Tab.MARKET)


func select_tab(tab: Tab) -> void:
	_current = tab
	for each: Tab in _pages:
		_pages[each].visible = each == tab
	_buttons[tab].set_pressed_no_signal(true)
	_refresh_page(tab)


## Opens a company on the Company tab: what clicking a row on the board does.
func show_company(stalk_id: StringName) -> void:
	if _state == null:
		return
	_company.show_company(stalk_id, _state)
	select_tab(Tab.COMPANY)


func current_tab() -> Tab:
	return _current


func exchange() -> ExchangeTab:
	return _exchange


func market_tab() -> MarketTab:
	return _market


func industries_tab() -> IndustriesTab:
	return _industries


func company_tab() -> CompanyTab:
	return _company


func tab_button(tab: Tab) -> Button:
	return _buttons[tab]


func _refresh_page(tab: Tab) -> void:
	if _state == null:
		return
	match tab:
		Tab.MARKET:
			_market.refresh(_state, _event_text, _event_effect)
		Tab.INDUSTRIES:
			_industries.refresh(_state)
		Tab.COMPANY:
			_company.refresh(_state)


func _on_tab_button_pressed(tab: Tab) -> void:
	select_tab(tab)


func _on_exchange_buy_requested(stalk_id: StringName, shares: int) -> void:
	buy_requested.emit(stalk_id, shares)


func _on_exchange_sell_requested(stalk_id: StringName, shares: int) -> void:
	sell_requested.emit(stalk_id, shares)


func _on_exchange_amount_changed(stalk_id: StringName, shares: int) -> void:
	amount_changed.emit(stalk_id, shares)


func _on_industries_selection_changed(_industry_id: StringName) -> void:
	_refresh_page(Tab.INDUSTRIES)


func _on_company_changed(_stalk_id: StringName) -> void:
	_refresh_page(Tab.COMPANY)
