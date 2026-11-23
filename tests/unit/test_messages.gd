extends GutTest
## Private messages between players (decisions.md D192, D193), without a
## network: the sanitiser, the rate limit, the relay rules, the message book,
## the session's send path, and the MESSAGES tab on the real playing screen.
##
## The wire - that a message reaches its one recipient and nobody else, and
## that a client cannot lie about who sent it - is in test_messages_wire.gd.


const ScreenScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")


# ------------------------------------------------------------- the sanitiser
#
# One test per thing in the security list in docs/architecture.md (Messages).

func test_printable_ascii_passes_untouched() -> void:
	var every: String = ""
	for code: int in range(0x21, 0x7F):
		every += char(code)
	assert_eq(MessageRules.clean(every), every)


func test_old_school_emoticons_survive() -> void:
	assert_eq(MessageRules.clean("<(' ')>"), "<(' ')>")
	assert_eq(MessageRules.clean(":-) ;-) \\o/ <3"), ":-) ;-) \\o/ <3")


func test_markup_is_kept_as_literal_text() -> void:
	# Cleaning does not strip markup: it is harmless as text, because nothing
	# that shows a message parses it (see the screen tests below).
	var markup: String = "[url=https://example.com]click[/url] [b]x[/b] [img]a.png[/img]"
	assert_eq(MessageRules.clean(markup), markup)


func test_a_network_path_is_kept_as_literal_text() -> void:
	assert_eq(MessageRules.clean("\\\\server\\share\\x"), "\\\\server\\share\\x")
	assert_eq(MessageRules.clean("file://c:/windows"), "file://c:/windows")


func test_newlines_and_tabs_become_spaces() -> void:
	# One paragraph per message, so a message cannot fake lines of its own.
	assert_eq(MessageRules.clean("one\ntwo\r\nthree\tfour"), "one two  three four")


func test_other_control_characters_are_removed() -> void:
	assert_eq(MessageRules.clean("a" + char(1) + "b" + char(7) + "c" + char(0x1B) + "[31md"), "abc[31md")
	assert_eq(MessageRules.clean("del" + char(0x7F) + "ete"), "delete")


func test_bidirectional_overrides_are_replaced() -> void:
	# U+202E would make the rest of a line read right to left.
	assert_eq(MessageRules.clean("abc" + char(0x202E) + "def"), "abc?def")
	assert_eq(MessageRules.clean(char(0x2066) + "x" + char(0x2069)), "?x?")


func test_zero_width_characters_are_replaced() -> void:
	assert_eq(MessageRules.clean("a" + char(0x200B) + "b" + char(0xFEFF) + "c"), "a?b?c")


func test_anything_beyond_ascii_is_replaced() -> void:
	assert_eq(MessageRules.clean("caf" + char(0xE9)), "caf?")
	assert_eq(MessageRules.clean("hi " + char(0x1F600)), "hi ?")
	assert_eq(MessageRules.clean(char(0x85) + "x"), "?x")


func test_a_message_is_cut_to_the_maximum_length() -> void:
	var long: String = "x".repeat(MessageRules.MAX_LENGTH * 50)
	assert_eq(MessageRules.clean(long).length(), MessageRules.MAX_LENGTH)


func test_leading_space_does_not_use_up_the_length() -> void:
	var padded: String = " ".repeat(500) + "x".repeat(MessageRules.MAX_LENGTH)
	assert_eq(MessageRules.clean(padded), "x".repeat(MessageRules.MAX_LENGTH))


func test_whitespace_and_control_only_is_empty() -> void:
	assert_eq(MessageRules.clean("   \n\t  "), "")
	assert_eq(MessageRules.clean(char(1) + char(2)), "")


# ------------------------------------------------------------- the rate limit

func test_the_limit_allows_up_to_its_count_then_refuses() -> void:
	var limiter: MessageLimiter = MessageLimiter.new(3, 1000)
	assert_true(limiter.allow(&"p1", 0))
	assert_true(limiter.allow(&"p1", 10))
	assert_true(limiter.allow(&"p1", 20))
	assert_false(limiter.allow(&"p1", 30), "the fourth inside the window is refused")


func test_the_window_slides() -> void:
	var limiter: MessageLimiter = MessageLimiter.new(2, 1000)
	limiter.allow(&"p1", 0)
	limiter.allow(&"p1", 500)
	assert_false(limiter.allow(&"p1", 999))
	assert_true(limiter.allow(&"p1", 1000), "the first send has left the window")
	assert_false(limiter.allow(&"p1", 1001), "but the second has not")


func test_each_sender_has_their_own_limit() -> void:
	var limiter: MessageLimiter = MessageLimiter.new(1, 1000)
	assert_true(limiter.allow(&"p1", 0))
	assert_true(limiter.allow(&"p2", 0))
	assert_false(limiter.allow(&"p1", 1))


func test_the_hosts_limit_is_looser_than_a_players() -> void:
	# An honest client must never be dropped by the host (MessageRules).
	assert_gt(MessageRules.RELAY_LIMIT, MessageRules.SEND_LIMIT)


# ---------------------------------------------------------- the relay rules

func _three_players() -> GameState:
	var state: GameState = GameState.new(GameSettings.new())
	for index: int in 3:
		state.players.append(PlayerState.new(StringName("p%d" % index), "P%d" % index, 1000))
	return state


func test_a_message_to_another_player_may_be_relayed() -> void:
	assert_eq(MessageRules.why_not_relay(&"p1", &"p2", _three_players()), "")


func test_a_recipient_not_in_the_match_is_refused() -> void:
	assert_ne(MessageRules.why_not_relay(&"p1", &"p7", _three_players()), "")
	assert_ne(MessageRules.why_not_relay(&"p1", &"", _three_players()), "")


func test_a_sender_not_in_the_match_is_refused() -> void:
	assert_ne(MessageRules.why_not_relay(&"p9", &"p1", _three_players()), "")
	assert_ne(MessageRules.why_not_relay(&"", &"p1", _three_players()), "")


func test_a_note_to_yourself_is_never_relayed() -> void:
	assert_ne(MessageRules.why_not_relay(&"p1", &"p1", _three_players()), "")


# ---------------------------------------------------------- the message book

func test_a_received_message_is_unread_until_marked() -> void:
	var book: MessageBook = MessageBook.new()
	book.record_received(&"p1", "hello")
	assert_eq(book.unread_from(&"p1"), 1)
	assert_true(book.has_unread())
	assert_true(book.mark_read(&"p1"))
	assert_eq(book.unread_from(&"p1"), 0)
	assert_false(book.has_unread())
	assert_false(book.mark_read(&"p1"), "nothing left to mark")


func test_what_you_send_is_never_unread() -> void:
	var book: MessageBook = MessageBook.new()
	book.record_sent(&"p0", &"p1", "hi")
	book.record_sent(&"p0", &"p0", "a note")
	assert_false(book.has_unread())
	assert_eq(book.lines(&"p1").size(), 1)
	assert_eq(book.lines(&"p0")[0].text, "a note")


func test_both_directions_are_one_conversation_in_order() -> void:
	var book: MessageBook = MessageBook.new()
	book.record_sent(&"p0", &"p1", "first")
	book.record_received(&"p1", "second")
	book.record_sent(&"p0", &"p1", "third")
	var texts: PackedStringArray = []
	for line: MessageBook.Line in book.lines(&"p1"):
		texts.append("%s:%s" % [line.from_id, line.text])
	assert_eq(texts, PackedStringArray(["p0:first", "p1:second", "p0:third"]))


func test_the_book_cleans_what_arrives_a_second_time() -> void:
	# Defence in depth: whatever the host did, the screen gets clean text.
	var book: MessageBook = MessageBook.new()
	book.record_received(&"p1", "a\nb" + char(0x202E) + "[url]x[/url]")
	assert_eq(book.lines(&"p1")[0].text, "a b?[url]x[/url]")


func test_an_empty_arrival_is_not_recorded() -> void:
	var book: MessageBook = MessageBook.new()
	book.record_received(&"p1", "\n" + char(1))
	assert_eq(book.lines(&"p1").size(), 0)
	assert_false(book.has_unread())


func test_a_conversation_keeps_only_its_newest_lines() -> void:
	var book: MessageBook = MessageBook.new()
	for index: int in MessageBook.MAX_LINES + 25:
		book.record_received(&"p1", "line %d" % index)
	var kept: Array[MessageBook.Line] = book.lines(&"p1")
	assert_eq(kept.size(), MessageBook.MAX_LINES)
	assert_eq(kept.back().text, "line %d" % (MessageBook.MAX_LINES + 24))


func test_clearing_forgets_everything() -> void:
	var book: MessageBook = MessageBook.new()
	book.record_received(&"p1", "hi")
	book.clear()
	assert_eq(book.lines(&"p1").size(), 0)
	assert_false(book.has_unread())


# ------------------------------------------------------ the session's send path

func _local(names: Array[String] = ["You", "Ann", "Bob"]) -> LocalSession:
	var settings: GameSettings = GameSettings.new()
	settings.mode = GameMode.Value.STALKLEHEADS
	settings.max_years = 10
	settings.player_count = names.size()
	settings.rng_seed = 4242
	var session: LocalSession = LocalSession.create(
		settings, MatchSetup.load_library(settings.mode), names
	)
	add_child_autofree(session)
	return session


func test_a_note_to_yourself_stays_in_your_own_book() -> void:
	var session: LocalSession = _local()
	assert_eq(session.send_message(&"p0", "remember this"), "")
	var notes: Array[MessageBook.Line] = session.messages().lines(&"p0")
	assert_eq(notes.size(), 1)
	assert_eq(notes[0].text, "remember this")
	assert_false(session.messages().has_unread(), "a note is never unread")


func test_notes_are_not_rate_limited() -> void:
	var session: LocalSession = _local()
	for index: int in MessageRules.SEND_LIMIT * 3:
		assert_eq(session.send_message(&"p0", "note %d" % index), "")


func test_sending_cleans_the_text_first() -> void:
	var session: LocalSession = _local()
	session.send_message(&"p1", "  hi\nthere" + char(0x200B) + "  ")
	assert_eq(session.messages().lines(&"p1")[0].text, "hi there?")


func test_sending_nothing_is_refused() -> void:
	var session: LocalSession = _local()
	assert_ne(session.send_message(&"p1", "  \n "), "")
	assert_eq(session.messages().lines(&"p1").size(), 0)


func test_sending_to_somebody_not_in_the_match_is_refused() -> void:
	var session: LocalSession = _local()
	assert_ne(session.send_message(&"p7", "hello?"), "")


func test_sending_to_an_away_player_is_refused() -> void:
	var session: LocalSession = _local()
	session.state().player_by_id(&"p2").is_away = true
	assert_string_contains(session.send_message(&"p2", "hi"), "not here")


func test_your_own_send_limit_refuses_with_a_reason() -> void:
	var session: LocalSession = _local()
	for index: int in MessageRules.SEND_LIMIT:
		assert_eq(session.send_message(&"p1", "m%d" % index), "")
	assert_string_contains(session.send_message(&"p1", "one more"), "Too many")
	assert_eq(session.messages().lines(&"p1").size(), MessageRules.SEND_LIMIT)


func test_messages_are_not_part_of_the_match() -> void:
	# Never in GameState, so never in a snapshot or the seeded stream.
	var session: LocalSession = _local()
	var before: Dictionary = StateSync.encode_state(session.state(), 0)
	session.send_message(&"p1", "hello")
	session.send_message(&"p0", "note")
	assert_eq(StateSync.encode_state(session.state(), 0), before)


# ------------------------------------------------------------ the MESSAGES tab

var _screen: GameplayScreen
var _session: LocalSession


func _show(names: Array[String] = ["You", "Ann", "Bob"]) -> MessagesTab:
	_session = _local(names)
	_screen = ScreenScene.instantiate()
	_screen.setup(_session)
	add_child_autofree(_screen)
	if _screen.news_panel() != null:
		_screen.news_panel().close()
	return _screen.market_tabs().messages_tab()


func _tab_button() -> Button:
	return _screen.market_tabs().tab_button(MarketTabs.Tab.MESSAGES)


func test_the_tab_is_on_the_strip() -> void:
	_show()
	assert_eq(_tab_button().text, "MESSAGES")


func test_the_tab_dot_is_grey_with_nothing_unread_and_yellow_with_something() -> void:
	_show()
	assert_eq(_tab_button().icon, StatusDot.unread(false))
	_session.messages().record_received(&"p1", "psst")
	assert_eq(_tab_button().icon, StatusDot.unread(true))


func test_the_dots_are_the_ready_marks_size_and_the_palettes_colours() -> void:
	assert_eq(StatusDot.unread(true).get_size(), Vector2(StatusDot.SIZE, StatusDot.SIZE))
	assert_eq(StatusDot.unread(true).get_image().get_pixel(0, 0), Palette.UNREAD)
	assert_eq(StatusDot.unread(false).get_image().get_pixel(0, 0), Palette.TEXT_FAINT)


func test_every_player_is_listed_including_yourself() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	assert_not_null(tab.player_button(&"p0"))
	assert_not_null(tab.player_button(&"p1"))
	assert_not_null(tab.player_button(&"p2"))
	assert_string_contains(tab.player_button(&"p1").text, "Ann")


func test_each_name_has_its_own_unread_dot() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	_session.messages().record_received(&"p2", "from Bob")
	assert_eq(tab.player_button(&"p2").icon, StatusDot.unread(true))
	assert_eq(tab.player_button(&"p1").icon, StatusDot.unread(false))


func test_opening_a_chat_reads_it_and_puts_the_tab_dot_out() -> void:
	var tab: MessagesTab = _show()
	_session.messages().record_received(&"p1", "hello")
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.player_button(&"p1").pressed.emit()
	assert_eq(_session.messages().unread_from(&"p1"), 0)
	assert_eq(tab.player_button(&"p1").icon, StatusDot.unread(false))
	assert_eq(_tab_button().icon, StatusDot.unread(false))


func test_a_message_arriving_in_an_open_chat_is_read_at_once() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	_session.messages().record_received(&"p1", "while you watch")
	assert_false(_session.messages().has_unread())
	assert_eq(_tab_button().icon, StatusDot.unread(false))


func test_a_message_arriving_on_another_tab_stays_unread() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	_screen.market_tabs().select_tab(MarketTabs.Tab.EXCHANGE)
	_session.messages().record_received(&"p1", "while you trade")
	assert_true(_session.messages().has_unread())
	assert_eq(_tab_button().icon, StatusDot.unread(true))


func test_the_chat_header_says_who_it_is_with() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	assert_eq(tab.chat_with(&"p1").title_text(), "Chat with Ann")
	tab.open_chat(&"p0")
	assert_string_contains(tab.chat_with(&"p0").title_text(), "Notes")


func test_send_puts_the_line_in_the_chat_and_empties_the_box() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	var chat: ChatPanel = tab.chat_with(&"p1")
	chat.field().text = "hello Ann"
	chat.send_button().pressed.emit()
	assert_eq(chat.line_texts(), PackedStringArray(["You: hello Ann"]))
	assert_eq(chat.field().text, "")
	assert_eq(chat.refusal_text(), "")


func test_a_refused_send_keeps_the_text_and_says_why() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	_session.state().player_by_id(&"p1").is_away = true
	var chat: ChatPanel = tab.chat_with(&"p1")
	chat.field().text = "are you there"
	chat.field().text_submitted.emit(chat.field().text)
	assert_eq(chat.field().text, "are you there")
	assert_string_contains(chat.refusal_text(), "not here")


func test_the_send_box_is_capped_at_the_message_length() -> void:
	var tab: MessagesTab = _show()
	tab.open_chat(&"p1")
	assert_eq(tab.chat_with(&"p1").field().max_length, MessageRules.MAX_LENGTH)


func test_two_chats_open_side_by_side_and_a_third_replaces_the_less_recent() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	tab.open_chat(&"p2")
	assert_eq(tab.open_chats(), [&"p1", &"p2"] as Array[StringName])
	# Ann's chat is used again, so Bob's is the one to go.
	tab.open_chat(&"p1")
	tab.open_chat(&"p0")
	assert_eq(tab.open_chats(), [&"p1", &"p0"] as Array[StringName])


func test_typing_in_a_chat_makes_it_the_one_kept() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	tab.open_chat(&"p2")
	tab.chat_with(&"p1").field().focus_entered.emit()
	tab.open_chat(&"p0")
	assert_eq(tab.open_chats(), [&"p1", &"p0"] as Array[StringName])


func test_every_line_is_a_plain_label() -> void:
	# The security property the screen owns (decisions.md D193): a Label has no
	# markup, no links and no meta handling, so nothing in a message can be
	# clicked open. A RichTextLabel here would need BBCode off and meta
	# ignored; not having one at all is simpler to keep true.
	var tab: MessagesTab = _show()
	_session.messages().record_received(&"p1", "[url=https://example.com]x[/url]")
	_session.messages().record_received(&"p1", "\\\\server\\share")
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	var chat: ChatPanel = tab.chat_with(&"p1")
	for line: Control in chat.line_controls():
		assert_true(line is Label, "a line must be a Label")
		assert_false(line is RichTextLabel)
	assert_eq(chat.line_texts(), PackedStringArray([
		"Ann: [url=https://example.com]x[/url]",
		"Ann: \\\\server\\share",
	]))


func test_no_rich_text_anywhere_on_the_tab() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	tab.open_chat(&"p2")
	assert_eq(tab.find_children("*", "RichTextLabel", true, false).size(), 0)


func test_a_solo_game_lists_only_your_notes() -> void:
	var tab: MessagesTab = _show(["You"])
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	assert_not_null(tab.player_button(&"p0"))
	assert_eq(tab.player_button(&"p0").text, "You", "not 'You (you)'")
	assert_null(tab.player_button(&"p1"))


func test_a_base_game_screen_has_no_messages_tab() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.mode = GameMode.Value.BASE
	settings.player_count = 1
	settings.rng_seed = 4242
	var session: LocalSession = LocalSession.create(settings, MatchSetup.load_library(settings.mode))
	add_child_autofree(session)
	var screen: GameplayScreen = ScreenScene.instantiate()
	screen.setup(session)
	add_child_autofree(screen)
	assert_null(screen.market_tabs())


# ------------------------------------------- the ALL PLAYERS room (D195)

func test_the_room_may_be_relayed_to() -> void:
	assert_eq(MessageRules.why_not_relay(&"p1", MessageRules.ALL_PLAYERS, _three_players()), "")


func test_the_room_id_can_never_be_a_players() -> void:
	assert_true(String(MessageRules.ALL_PLAYERS).begins_with("*"))
	assert_null(_three_players().player_by_id(MessageRules.ALL_PLAYERS))


func test_a_room_arrival_goes_into_the_room_not_the_senders_chat() -> void:
	var book: MessageBook = MessageBook.new()
	book.record_received(&"p1", "to everyone", true)
	assert_eq(book.lines(MessageRules.ALL_PLAYERS).size(), 1)
	assert_eq(book.lines(MessageRules.ALL_PLAYERS)[0].from_id, &"p1")
	assert_eq(book.lines(&"p1").size(), 0)
	assert_eq(book.unread_from(MessageRules.ALL_PLAYERS), 1)
	assert_eq(book.unread_from(&"p1"), 0)


func test_sending_to_the_room_keeps_your_copy_in_the_room() -> void:
	var session: LocalSession = _local()
	assert_eq(session.send_message(MessageRules.ALL_PLAYERS, "hello all"), "")
	var room: Array[MessageBook.Line] = session.messages().lines(MessageRules.ALL_PLAYERS)
	assert_eq(room.size(), 1)
	assert_eq(room[0].from_id, &"p0")
	assert_false(session.messages().has_unread())


func test_sending_to_the_room_is_rate_limited() -> void:
	var session: LocalSession = _local()
	for index: int in MessageRules.SEND_LIMIT:
		assert_eq(session.send_message(MessageRules.ALL_PLAYERS, "m%d" % index), "")
	assert_ne(session.send_message(MessageRules.ALL_PLAYERS, "one too many"), "")


# ------------------------------------------------------ blocking (D196)

func test_a_blocked_players_messages_are_dropped() -> void:
	var book: MessageBook = MessageBook.new()
	book.set_blocked(&"p1", true)
	book.record_received(&"p1", "direct")
	book.record_received(&"p1", "in the room", true)
	assert_eq(book.lines(&"p1").size(), 0)
	assert_eq(book.lines(MessageRules.ALL_PLAYERS).size(), 0)
	assert_false(book.has_unread())


func test_blocking_one_player_leaves_the_others_heard() -> void:
	var book: MessageBook = MessageBook.new()
	book.set_blocked(&"p1", true)
	book.record_received(&"p2", "still here")
	book.record_received(&"p2", "and here", true)
	assert_eq(book.lines(&"p2").size(), 1)
	assert_eq(book.lines(MessageRules.ALL_PLAYERS).size(), 1)


func test_blocking_marks_their_chat_read_and_keeps_what_was_said() -> void:
	var book: MessageBook = MessageBook.new()
	book.record_received(&"p1", "before")
	book.set_blocked(&"p1", true)
	assert_eq(book.unread_from(&"p1"), 0)
	assert_eq(book.lines(&"p1").size(), 1)


func test_unblocking_hears_them_again_but_not_what_was_dropped() -> void:
	var book: MessageBook = MessageBook.new()
	book.set_blocked(&"p1", true)
	book.record_received(&"p1", "dropped")
	book.set_blocked(&"p1", false)
	book.record_received(&"p1", "heard")
	assert_false(book.is_blocked(&"p1"))
	assert_eq(book.lines(&"p1").size(), 1)
	assert_eq(book.lines(&"p1")[0].text, "heard")


func test_blocking_fires_changed() -> void:
	var book: MessageBook = MessageBook.new()
	watch_signals(book)
	book.set_blocked(&"p1", true)
	assert_signal_emitted(book, "changed")


func test_clearing_forgets_blocks() -> void:
	var book: MessageBook = MessageBook.new()
	book.set_blocked(&"p1", true)
	book.clear()
	assert_false(book.is_blocked(&"p1"))


# ------------------------------------------- the room and blocking on screen

func test_the_room_is_listed_first() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	var room: Button = tab.player_button(MessageRules.ALL_PLAYERS)
	assert_not_null(room)
	assert_eq(room.text, "ALL PLAYERS")
	assert_eq(room.get_index(), 0)


func test_a_solo_game_has_no_room() -> void:
	var tab: MessagesTab = _show(["You"])
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	assert_null(tab.player_button(MessageRules.ALL_PLAYERS))


func test_the_room_has_its_own_unread_dot_and_header() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	_session.messages().record_received(&"p1", "hi all", true)
	assert_eq(tab.player_button(MessageRules.ALL_PLAYERS).icon, StatusDot.unread(true))
	assert_eq(tab.player_button(&"p1").icon, StatusDot.unread(false))
	tab.open_chat(MessageRules.ALL_PLAYERS)
	assert_eq(tab.chat_with(MessageRules.ALL_PLAYERS).title_text(), "Chat with all players")
	assert_eq(tab.chat_with(MessageRules.ALL_PLAYERS).line_texts(), PackedStringArray([
		"Ann: hi all",
	]))
	assert_false(_session.messages().has_unread())


func test_a_chat_with_a_player_has_a_block_button() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p1")
	var button: Button = tab.chat_with(&"p1").block_button()
	assert_true(button.visible)
	assert_eq(button.text, "BLOCK?")


func test_notes_and_the_room_have_no_block_button() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p0")
	tab.open_chat(MessageRules.ALL_PLAYERS)
	assert_false(tab.chat_with(&"p0").block_button().visible)
	assert_false(tab.chat_with(MessageRules.ALL_PLAYERS).block_button().visible)


func test_pressing_block_blocks_and_marks_the_name() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p2")
	tab.chat_with(&"p2").block_button().pressed.emit()

	assert_true(_session.messages().is_blocked(&"p2"))
	var chat: ChatPanel = tab.chat_with(&"p2")
	assert_eq(chat.block_button().text, "UNBLOCK")
	assert_eq(chat.title_text(), "Chat with Bob (blocked)")
	var listed: Button = tab.player_button(&"p2")
	assert_string_contains(listed.text, "(blocked)")
	assert_eq(listed.theme_type_variation, &"BlockedName")
	assert_eq(tab.player_button(&"p1").theme_type_variation, &"")


func test_pressing_unblock_undoes_it() -> void:
	var tab: MessagesTab = _show()
	_screen.market_tabs().select_tab(MarketTabs.Tab.MESSAGES)
	tab.open_chat(&"p2")
	tab.chat_with(&"p2").block_button().pressed.emit()
	tab.chat_with(&"p2").block_button().pressed.emit()

	assert_false(_session.messages().is_blocked(&"p2"))
	assert_eq(tab.chat_with(&"p2").block_button().text, "BLOCK?")
	assert_eq(tab.chat_with(&"p2").title_text(), "Chat with Bob")
	assert_false(tab.player_button(&"p2").text.contains("(blocked)"))
	assert_eq(tab.player_button(&"p2").theme_type_variation, &"")


func test_the_blocked_look_is_in_the_theme() -> void:
	var theme: Theme = load("res://assets/themes/stalks_theme.tres")
	assert_eq(theme.get_type_variation_base(&"BlockedName"), &"Button")
	assert_true(theme.get_color(&"font_color", &"BlockedName").is_equal_approx(Palette.TEXT_FAINT))
