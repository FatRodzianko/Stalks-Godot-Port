class_name MarketTabs
extends VBoxContainer
## The four tabs of a StalkleHeads match, in the middle of the playing screen
## (docs/stalkleheads-design.md §7): Stalk Exchange, Market Analysis,
## Industries and Company - and the side panel beside them, HOLDINGS,
## RANKINGS and THE DESK.
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
## **The side panel** (decisions.md D183) is always open on EXCHANGE, showing
## whichever of its three pages was last chosen. On the other tabs it starts
## closed with its three buttons still on the strip: a button opens it on that
## page, the same button again closes it, and changing tab closes it.
##
## **Trading from anywhere.** Every company shown on its own - a board row, a
## holding, an industry's member, the Company tab - has a trade box. They all
## answer to one `TradeContext`, built here each refresh from the screen's two
## checks (`set_trade_checks`), and every buy or sell leaves through the same
## two signals.
##
## Holds nothing but which tab is showing and what each tab is pointed at.
## Every figure comes from the state it is handed (`refresh`).


signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)


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
var _side_buttons: Dictionary[SidePanel.Page, Button] = {}
var _side_open: bool = true

## The two checks every trade box asks, `GameplayScreen`'s (see TradeContext).
var _buy_check: Callable
var _sell_check: Callable
var _context: TradeContext

## The year's event as the top strip shows it, for the Market tab.
var _event_text: String = ""
var _event_effect: String = ""

@onready var _strip: HBoxContainer = %TabStrip
@onready var _side_strip: HBoxContainer = %SideButtons
@onready var _exchange: ExchangeTab = %ExchangeTab
@onready var _market: MarketTab = %MarketTab
@onready var _industries: IndustriesTab = %IndustriesTab
@onready var _company: CompanyTab = %CompanyTab
@onready var _side: SidePanel = %SidePanel


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
	for page: SidePanel.Page in SidePanel.CAPTIONS:
		var button: Button = Button.new()
		button.text = SidePanel.CAPTIONS[page]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_side_button_pressed.bind(page))
		_side_strip.add_child(button)
		_side_buttons[page] = button

	_exchange.buy_requested.connect(_on_page_buy_requested)
	_exchange.sell_requested.connect(_on_page_sell_requested)
	_industries.buy_requested.connect(_on_page_buy_requested)
	_industries.sell_requested.connect(_on_page_sell_requested)
	_company.buy_requested.connect(_on_page_buy_requested)
	_company.sell_requested.connect(_on_page_sell_requested)
	_side.buy_requested.connect(_on_page_buy_requested)
	_side.sell_requested.connect(_on_page_sell_requested)
	_exchange.company_requested.connect(show_company)
	_industries.company_requested.connect(show_company)
	_side.company_requested.connect(show_company)
	_industries.selection_changed.connect(_on_industries_selection_changed)
	_company.company_changed.connect(_on_company_changed)
	select_tab(Tab.EXCHANGE)


## The screen's checks for a buy and a sell: (stalk_id, shares) -> the reason
## it would be refused, or empty. Set once, before the first refresh.
func set_trade_checks(buy_check: Callable, sell_check: Callable) -> void:
	_buy_check = buy_check
	_sell_check = sell_check


## Builds the board for `state`'s market. Once per match.
func build(state: GameState) -> void:
	_state = state
	_exchange.build(state)


## Redraws whatever needs it. The board and the side panel are always redrawn,
## seen or not, because their trade boxes must be right the moment they show;
## of the analysis tabs, only the one on show (§6.2).
func refresh(
	state: GameState,
	player: PlayerState,
	trading: bool,
	ranking_order: Array[StringName],
	local_id: StringName,
	host_id: StringName,
) -> void:
	_state = state
	_context = TradeContext.new(state, player, trading, _buy_check, _sell_check)
	_exchange.refresh(_context)
	_side.refresh(_context, _exchange.board_order(), ranking_order, local_id, host_id)
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
		# Without the signal the ButtonGroup does not release the others, so
		# opening a company from a click would leave two tabs lit.
		_buttons[each].set_pressed_no_signal(each == tab)
	# Always open on the board; on the others, closed until asked for.
	_set_side_open(tab == Tab.EXCHANGE)
	_refresh_page(tab)


## Opens a company on the Company tab: what clicking a company anywhere does.
func show_company(stalk_id: StringName) -> void:
	if _state == null:
		return
	_company.show_company(stalk_id)
	select_tab(Tab.COMPANY)


## Empties every quantity box: after a trade, or when the player changes.
func clear_amounts() -> void:
	_exchange.clear_amounts()
	_side.clear_amounts()
	_industries.clear_amounts()
	_company.clear_amount()


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


func side_panel() -> SidePanel:
	return _side


func is_side_open() -> bool:
	return _side_open


func tab_button(tab: Tab) -> Button:
	return _buttons[tab]


func side_button(page: SidePanel.Page) -> Button:
	return _side_buttons[page]


func _set_side_open(is_open: bool) -> void:
	_side_open = is_open
	_side.visible = is_open
	for page: SidePanel.Page in _side_buttons:
		_side_buttons[page].set_pressed_no_signal(is_open and page == _side.current_page())


func _refresh_page(tab: Tab) -> void:
	if _state == null or _context == null:
		return
	match tab:
		Tab.MARKET:
			_market.refresh(_state, _event_text, _event_effect)
		Tab.INDUSTRIES:
			_industries.refresh(_context)
		Tab.COMPANY:
			_company.set_board_order(_exchange.board_order())
			_company.refresh(_context)


func _on_tab_button_pressed(tab: Tab) -> void:
	select_tab(tab)


## On the board a button only changes the page. Elsewhere it opens the panel on
## its page, or closes it if that page is already showing.
func _on_side_button_pressed(page: SidePanel.Page) -> void:
	var closing: bool = _current != Tab.EXCHANGE and _side_open and _side.current_page() == page
	_side.show_page(page)
	_set_side_open(not closing)


func _on_page_buy_requested(stalk_id: StringName, shares: int) -> void:
	buy_requested.emit(stalk_id, shares)


func _on_page_sell_requested(stalk_id: StringName, shares: int) -> void:
	sell_requested.emit(stalk_id, shares)


func _on_industries_selection_changed(_industry_id: StringName) -> void:
	_refresh_page(Tab.INDUSTRIES)


func _on_company_changed(_stalk_id: StringName) -> void:
	_refresh_page(Tab.COMPANY)
