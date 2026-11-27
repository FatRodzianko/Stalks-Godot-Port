class_name MarketTabs
extends VBoxContainer
## The tabs of a StalkleHeads match, in the middle of the playing screen
## (docs/stalkleheads-design.md §7): Stalk Exchange, Market Analysis,
## Industries, Company and Messages - and the side panel beside them, HOLDINGS,
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
## **Overlays, not columns** (D184). `Body` is a `MarginContainer`, which lays
## every child over the same rectangle: the row of pages first, then the
## company list's layer, then the side panel's. So the side panel opened on
## MARKET, INDUSTRIES or COMPANY covers the tab's right-hand side instead of
## squeezing it, inside the bright `OverlayFrame` that marks it as a window of
## its own. On EXCHANGE the board keeps a column free for it (`SideSpace`), so
## the board is never covered. The company list (`CompanyPicker`) opens the same
## way over the Company tab's left-hand side, below its title line so the
## COMPANIES button that opened it can close it. The layers ignore the mouse where
## they are empty, so the tab beneath still takes clicks.
##
## **Trading from anywhere.** Every company shown on its own - a board row, a
## holding, an industry's member, the Company tab - has a trade box. They all
## answer to one `TradeContext`, built here each refresh from the screen's two
## checks (`set_trade_checks`), and every buy or sell leaves through the same
## two signals.
##
## **MESSAGES** (decisions.md D192) is the fifth tab: private messages between
## the players. Its button carries the unread dot - grey, or yellow while any
## conversation has an unread line - redrawn whenever the message book changes
## (`refresh_messages`), whichever tab is showing.
##
## Holds nothing but which tab is showing and what each tab is pointed at.
## Every figure comes from the state it is handed (`refresh`).


signal buy_requested(stalk_id: StringName, shares: int)
signal sell_requested(stalk_id: StringName, shares: int)
## The player typed a message on the Messages tab.
signal message_submitted(recipient_id: StringName, text: String)


enum Tab { EXCHANGE, MARKET, INDUSTRIES, COMPANY, MESSAGES }

## The strip's captions, as the design writes them (§7.2).
const CAPTIONS: Dictionary[Tab, String] = {
	Tab.EXCHANGE: "EXCHANGE",
	Tab.MARKET: "MARKET",
	Tab.INDUSTRIES: "INDUSTRIES",
	Tab.COMPANY: "COMPANY",
	Tab.MESSAGES: "MESSAGES",
}


var _state: GameState
var _current: Tab = Tab.EXCHANGE
var _buttons: Dictionary[Tab, Button] = {}
var _pages: Dictionary[Tab, Control] = {}
var _side_buttons: Dictionary[SidePanel.Page, Button] = {}
var _side_open: bool = true
var _picker_open: bool = false

## The two checks every trade box asks, `GameplayScreen`'s (see TradeContext).
var _buy_check: Callable
var _sell_check: Callable
var _context: TradeContext

## This machine's messages (GameSession.messages), and whose machine it is.
var _book: MessageBook
var _local_id: StringName = &""

@onready var _strip: HBoxContainer = %TabStrip
@onready var _side_strip: HBoxContainer = %SideButtons
@onready var _exchange: ExchangeTab = %ExchangeTab
@onready var _market: MarketTab = %MarketTab
@onready var _industries: IndustriesTab = %IndustriesTab
@onready var _company: CompanyTab = %CompanyTab
@onready var _messages: MessagesTab = %MessagesTab
@onready var _side: SidePanel = %SidePanel
@onready var _side_frame: PanelContainer = %SideFrame
@onready var _side_space: Control = %SideSpace
@onready var _picker_frame: PanelContainer = %PickerFrame
@onready var _picker_top: Control = %PickerTop
@onready var _picker: CompanyPicker = %CompanyPicker


func _ready() -> void:
	_pages = {
		Tab.EXCHANGE: _exchange,
		Tab.MARKET: _market,
		Tab.INDUSTRIES: _industries,
		Tab.COMPANY: _company,
		Tab.MESSAGES: _messages,
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
	_buttons[Tab.MESSAGES].icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_buttons[Tab.MESSAGES].icon = StatusDot.unread(false)
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
	_side.sell_requested.connect(_on_page_sell_requested)
	_exchange.company_requested.connect(show_company)
	_industries.company_requested.connect(show_company)
	_side.company_requested.connect(show_company)
	_industries.selection_changed.connect(_on_industries_selection_changed)
	_company.company_changed.connect(_on_company_changed)
	_company.picker_requested.connect(_on_company_picker_requested)
	_picker.company_chosen.connect(_on_picker_company_chosen)
	_messages.message_submitted.connect(_on_messages_message_submitted)
	_messages.lines_read.connect(_draw_unread_dot)
	select_tab(Tab.EXCHANGE)


## The screen's checks for a buy and a sell: (stalk_id, shares) -> the reason
## it would be refused, or empty. Set once, before the first refresh.
func set_trade_checks(buy_check: Callable, sell_check: Callable) -> void:
	_buy_check = buy_check
	_sell_check = sell_check


## The book the Messages tab shows. Set once, before the first refresh.
func set_message_book(book: MessageBook) -> void:
	_book = book


## The message book changed: a line arrived or was sent. Redraws the Messages
## tab if it is showing, and the tab's dot either way.
func refresh_messages() -> void:
	if _current == Tab.MESSAGES:
		_refresh_page(Tab.MESSAGES)
	_draw_unread_dot()


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
	_local_id = local_id
	_context = TradeContext.new(state, player, trading, _buy_check, _sell_check)
	_exchange.refresh(_context)
	_side.refresh(_context, _exchange.board_order(), ranking_order, local_id, host_id)
	_refresh_page(_current)
	if _picker_open:
		_picker.refresh(_context, _company.shown_id())
	_draw_unread_dot()


## The year's event has been shown in the top strip. The Market tab reads the
## same words from the state (`YearEventText`), so it only needs redrawing.
func set_event(_text: String, _effect: String) -> void:
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
	_set_picker_open(false)
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


func messages_tab() -> MessagesTab:
	return _messages


func side_panel() -> SidePanel:
	return _side


func is_side_open() -> bool:
	return _side_open


func is_picker_open() -> bool:
	return _picker_open


func company_picker() -> CompanyPicker:
	return _picker


func tab_button(tab: Tab) -> Button:
	return _buttons[tab]


func side_button(page: SidePanel.Page) -> Button:
	return _side_buttons[page]


func _set_side_open(is_open: bool) -> void:
	_side_open = is_open
	_side_frame.visible = is_open
	# The board's free column is exactly as wide as the framed panel.
	_side_space.custom_minimum_size.x = _side_frame.get_combined_minimum_size().x
	_side_space.visible = is_open and _current == Tab.EXCHANGE
	for page: SidePanel.Page in _side_buttons:
		_side_buttons[page].set_pressed_no_signal(is_open and page == _side.current_page())


func _refresh_page(tab: Tab) -> void:
	if _state == null or _context == null:
		return
	match tab:
		Tab.MARKET:
			_market.refresh(_state)
		Tab.INDUSTRIES:
			_industries.refresh(_context)
		Tab.COMPANY:
			_company.refresh(_context)
		Tab.MESSAGES:
			_messages.refresh(_state, _local_id, _book)
			_draw_unread_dot()


## The MESSAGES button's dot: yellow while anything is unread.
func _draw_unread_dot() -> void:
	var unread: bool = _book != null and _book.has_unread()
	var button: Button = _buttons[Tab.MESSAGES]
	button.icon = StatusDot.unread(unread)
	if unread:
		button.tooltip_text = "Unread messages"
	else:
		button.tooltip_text = "No unread messages"


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


func _on_messages_message_submitted(recipient_id: StringName, text: String) -> void:
	message_submitted.emit(recipient_id, text)


func _on_industries_selection_changed(_industry_id: StringName) -> void:
	_refresh_page(Tab.INDUSTRIES)


func _set_picker_open(is_open: bool) -> void:
	_picker_open = is_open
	_picker_frame.visible = is_open
	# Below the Company tab's title line, so COMPANIES stays clickable.
	_picker_top.custom_minimum_size.y = _company.title_height()
	_company.pick_button().set_pressed_no_signal(is_open)
	if is_open and _context != null:
		_picker.refresh(_context, _company.shown_id())


func _on_company_changed(_stalk_id: StringName) -> void:
	_refresh_page(Tab.COMPANY)
	if _picker_open:
		_picker.refresh(_context, _company.shown_id())


func _on_company_picker_requested() -> void:
	_set_picker_open(not _picker_open)


## A company picked from the list: the list closes and the tab shows it.
func _on_picker_company_chosen(stalk_id: StringName) -> void:
	_set_picker_open(false)
	show_company(stalk_id)
