extends GutTest
## What the match does to a player who is not there.
##
## **This is the file the rejoin feature is really about.** Getting back into a
## game is plumbing; what makes coming back mean anything is that the match went
## on without you and your position moved while you were gone. The owner asked
## for exactly that: dividends paid, splits and bankruptcies applied, a missed
## loan payment for every year away, and your place in the standings kept —
## "tough but fair".
##
## Under D47 every one of those was false. An away player was removed from
## `state.players`, which is the list the year resolver walks, so they were paid
## nothing, charged nothing and ranked nowhere. D110 put them back in the list
## and took them out of the ready gate instead; these are the rules that follow
## from that, and the gate is tested here too because it is the thing that must
## *not* change.
##
## All pure simulation: no nodes, no peers, no Steam. See docs/decisions.md D110
## and docs/game-rules.md §4.6.


## A two-player state with prices that never move on their own, so each test
## sets up only the thing it is about. `p1` is the one who is away.
func _two_players() -> GameState:
	var state: GameState = StalksFixture.make_state(10, 2)
	state.players[1].is_away = true
	return state


func _frozen_year(state: GameState) -> YearResult:
	return StalksFixture.frozen_resolver().advance_year(state, StalksFixture.rng(1))


# ------------------------------------------------------------------- the gate
#
# The one thing being away changes. Everything below this section is a rule that
# must behave as though the player were sitting there.

func test_the_year_does_not_wait_for_a_player_who_is_away() -> void:
	var state: GameState = _two_players()

	state.players[0].is_ready = true

	assert_true(
		state.all_players_ready(),
		"everybody who is here has readied up",
	)


func test_the_year_still_waits_for_everybody_who_is_here() -> void:
	var state: GameState = StalksFixture.make_state(10, 2)

	state.players[0].is_ready = true

	assert_false(state.all_players_ready(), "p1 is here and has not readied")


## **A match everybody has left must not play itself out.** Without this the
## gate is vacuously satisfied — nobody present, so nobody unready — and the
## match would resolve year after year to an empty room, reaching its end before
## anybody could rejoin the game they still had a seat in.
func test_a_match_everybody_has_left_does_not_resolve_years() -> void:
	var state: GameState = _two_players()
	state.players[0].is_away = true
	state.players[0].is_ready = true
	state.players[1].is_ready = true

	assert_false(state.all_players_ready(), "there is nobody here to advance it")


func test_an_away_player_is_not_somebody_to_wait_for() -> void:
	var state: GameState = _two_players()

	assert_eq(state.players_present().size(), 1)
	assert_does_not_have(state.players_not_ready(), &"p1")
	assert_has(state.players_not_ready(), &"p0")


func test_an_empty_roster_is_not_ready() -> void:
	var state: GameState = StalksFixture.make_state(10, 0)

	assert_false(state.all_players_ready())


# -------------------------------------------------------------------- the money

func test_an_away_player_is_paid_their_dividends() -> void:
	var state: GameState = _two_players()
	var stalk: StalkState = state.stalk_by_id(&"teamsters")
	var away: PlayerState = state.players[1]
	away.set_shares(stalk.id, 10)
	var cash_before: int = away.cash

	var result: YearResult = _frozen_year(state)

	var per_share: int = stalk.dividend_per_share(result.mood)
	assert_eq(
		away.cash, cash_before + 10 * per_share,
		"ten shares should pay ten dividends whether or not anybody is watching",
	)
	assert_eq(result.dividends[&"p1"], 10 * per_share, "and it should be recorded")


func test_an_away_players_stalk_splits_like_everybody_elses() -> void:
	var state: GameState = _two_players()
	var stalk: StalkState = state.stalk_by_id(&"mutuals")
	# Above the split threshold before the year begins, with a frozen model so
	# nothing else moves it.
	stalk.price = 153
	state.players[1].set_shares(stalk.id, 4)

	_frozen_year(state)

	assert_eq(stalk.price, 77, "halved, rounding up (game-rules.md §6)")
	assert_eq(
		state.players[1].shares_of(stalk.id), 8,
		"an away player's shares double with the split",
	)


func test_an_away_player_is_wiped_out_by_a_bankruptcy_like_everybody_else() -> void:
	var state: GameState = _two_players()
	var stalk: StalkState = state.stalk_by_id(&"mutuals")
	stalk.price = 1
	state.players[1].set_shares(stalk.id, 20)

	# A model that takes every stalk down past the threshold.
	StalksFixture.resolver_with_delta(-5).advance_year(state, StalksFixture.rng(1))

	assert_true(stalk.is_bankrupt)
	assert_eq(
		state.players[1].shares_of(stalk.id), 0,
		"being absent is not protection from a bankruptcy",
	)


func test_an_away_players_net_worth_is_recomputed() -> void:
	var state: GameState = _two_players()
	var stalk: StalkState = state.stalk_by_id(&"berry_bonds")
	state.players[1].set_shares(stalk.id, 5)

	var result: YearResult = _frozen_year(state)

	var expected: int = TradeRules.net_worth(state.players[1], state)
	assert_eq(state.players[1].net_worth, expected)
	assert_true(result.net_worths.has(&"p1"), "and it reaches the year's record")


# --------------------------------------------------------------------- the loan
#
# The owner's words: every year you are away counts as a missed payment, "tough
# but fair". **This needed no new rule.** `LoanRules.process_year_end` records a
# miss whenever `paid_this_year` is false, and a player who is not there never
# pays, so the existing 10% / 15% / seizure schedule applies the moment they
# stay in the pipeline. These tests are here because that is a load-bearing
# accident rather than something anybody wrote down.

func _away_with_a_loan(amount: int) -> GameState:
	var state: GameState = StalksFixture.make_state_with_loans(10, 2)
	state.players[1].is_away = true
	var loan: LoanState = StalksFixture.give_loan(state.players[1], amount)
	# The year a loan is taken is treated as already paid, which is how "your
	# first payment is next year" avoids an immediate miss. Cleared so the test
	# starts on a year the player owes for.
	loan.paid_this_year = false
	return state


func test_a_year_away_is_a_missed_payment() -> void:
	var state: GameState = _away_with_a_loan(1000)

	_frozen_year(state)

	assert_eq(state.players[1].loan.missed_payments, 1)


func test_the_first_year_away_costs_the_ten_per_cent_penalty() -> void:
	var state: GameState = _away_with_a_loan(1000)

	_frozen_year(state)

	# 1000 penalised to 1100, then a year's interest at 6%.
	assert_eq(state.players[1].loan.balance, int(1100 * 1.06))


func test_the_second_year_away_costs_the_fifteen_per_cent_penalty() -> void:
	var state: GameState = _away_with_a_loan(1000)

	_frozen_year(state)
	var after_one: int = state.players[1].loan.balance
	_frozen_year(state)

	assert_eq(state.players[1].loan.missed_payments, 2)
	assert_eq(state.players[1].loan.balance, int(int(after_one * 1.15) * 1.06))


## Three years away with a loan outstanding is the end of that player, exactly
## as three missed payments at the keyboard would be. This is the sharpest edge
## of "tough but fair" and the one most worth pinning down.
func test_three_years_away_seizes_everything() -> void:
	var state: GameState = _away_with_a_loan(1000)
	var away: PlayerState = state.players[1]
	away.set_shares(&"berry_bonds", 9)

	_frozen_year(state)
	_frozen_year(state)
	_frozen_year(state)

	assert_eq(away.loan.missed_payments, 3)
	assert_true(away.loan.is_defaulted, "the loan is written off")
	assert_true(away.is_bankrupt, "and the player is out")
	assert_eq(away.cash, 0)
	assert_eq(away.holdings.size(), 0, "assets seized")


## The counterpart: a player who is **here** and pays is not penalised, so the
## tests above are measuring absence and not simply the passage of years.
func test_a_player_who_is_here_and_pays_misses_nothing() -> void:
	var state: GameState = _away_with_a_loan(1000)
	state.players[1].is_away = false
	LoanRules.apply_payment(state.players[1], state.players[1].loan.min_payment)

	_frozen_year(state)

	assert_eq(state.players[1].loan.missed_payments, 0)


# ------------------------------------------------------------------ the standings
#
# The owner was told this changes who can win, and asked for it anyway: your
# position is still affected while you are away, which cuts both ways.

func test_an_away_player_keeps_their_place_in_the_rankings() -> void:
	var state: GameState = _two_players()
	state.players[0].cash = 100
	state.players[1].cash = 999

	var result: YearResult = _frozen_year(state)

	assert_eq(
		result.rankings, [&"p1", &"p0"] as Array[StringName],
		"the richer player leads whether or not they are at the keyboard",
	)


func test_an_away_player_can_win_the_match() -> void:
	var state: GameState = StalksFixture.make_state(1, 2)
	state.players[1].is_away = true
	state.players[0].cash = 100
	state.players[1].cash = 999

	# A one-year match ends on the advance into year 2 (game-rules.md §12).
	_frozen_year(state)
	var final_year: YearResult = _frozen_year(state)

	assert_true(final_year.is_final_year, "the match should have ended")
	assert_eq(
		final_year.winners, [&"p1"] as Array[StringName],
		"being away does not forfeit a match you were winning",
	)


## And losing works too: the match is capable of taking the lead off an absent
## player, which is the other half of what the owner asked for.
func test_an_away_player_can_be_overtaken_while_they_are_gone() -> void:
	var state: GameState = _two_players()
	var stalk: StalkState = state.stalk_by_id(&"teamsters")
	state.players[0].cash = 0
	state.players[0].set_shares(stalk.id, 100)
	state.players[1].cash = 500

	var result: YearResult = _frozen_year(state)

	assert_eq(
		result.rankings[0], &"p0",
		"the present player's holdings and dividends put them ahead",
	)


# ---------------------------------------------------------------------- yeehaws
#
# A gesture needs somebody to make it back.

func test_a_lone_survivor_cannot_ask_a_room_of_absentees_for_a_yeehaw() -> void:
	var state: GameState = _two_players()
	state.year = 1

	assert_eq(
		YeehawRules.validate_request(&"p0", state),
		"Yeehaws need other players.",
	)


func test_two_players_who_are_both_here_may_still_yeehaw() -> void:
	var state: GameState = StalksFixture.make_state(10, 2)
	state.year = 1

	assert_eq(YeehawRules.validate_request(&"p0", state), "")


# ------------------------------------------------------------------- the wire

func test_being_away_crosses_the_wire() -> void:
	var state: GameState = _two_players()
	var replica: GameState = GameState.new(null)

	assert_eq(
		StateSync.apply_state(
			replica, StateSync.encode_state(state), ContentLibrary.load_from()
		),
		"",
	)

	assert_false(replica.player_by_id(&"p0").is_away)
	assert_true(
		replica.player_by_id(&"p1").is_away,
		"a client that could not see this would wait on somebody the host is not",
	)
