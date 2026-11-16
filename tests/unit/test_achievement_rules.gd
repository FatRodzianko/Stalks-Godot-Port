extends GutTest
## What a match earns, decided without Steam.
##
## `AchievementRules` is pure for a reason that matters more here than
## anywhere else in `src/sim/`: the only other way to check an achievement is
## to unlock it for real on somebody's Steam account, and an achievement
## cannot be un-earned a test at a time. These thresholds have to be right
## before anything is ever sent.
##
## The ids themselves are not ours to choose @@ the App ID is reused, so the
## partner backend holds the names (decisions.md D57). `test_achievements.gd`
## guards the spelling; this guards the meaning.


func _state(players: int = 2, years: int = 10, starting_cash: int = 10000) -> GameState:
	var game: GameState = StalksFixture.make_state(years, players)
	game.settings.starting_cash = starting_cash
	for player: PlayerState in game.players:
		player.cash = starting_cash
		player.net_worth = starting_cash
	return game


func _me(game: GameState) -> PlayerState:
	return game.players[0]


# ------------------------------------------------------------ while playing

func test_three_hundred_shares_of_one_stalk_is_all_in() -> void:
	var game: GameState = _state()
	_me(game).set_shares(game.stalks[0].id, AchievementRules.ALL_IN_SHARES)
	assert_has(AchievementRules.while_playing(_me(game), game), Achievements.ALL_IN)


func test_one_share_short_is_not_all_in() -> void:
	var game: GameState = _state()
	_me(game).set_shares(game.stalks[0].id, AchievementRules.ALL_IN_SHARES - 1)
	assert_does_not_have(
		AchievementRules.while_playing(_me(game), game), Achievements.ALL_IN
	)


func test_ten_of_every_stalk_is_diversified() -> void:
	var game: GameState = _state()
	for stalk: StalkState in game.stalks:
		_me(game).set_shares(stalk.id, AchievementRules.DIVERSIFIED_SHARES)
	assert_has(AchievementRules.while_playing(_me(game), game), Achievements.DIVERSIFIED)


func test_missing_one_stalk_is_not_diversified() -> void:
	# "All ten", so nine of ten does not count however many shares they are.
	var game: GameState = _state()
	for stalk: StalkState in game.stalks:
		_me(game).set_shares(stalk.id, 50)
	_me(game).set_shares(game.stalks[0].id, AchievementRules.DIVERSIFIED_SHARES - 1)
	assert_does_not_have(
		AchievementRules.while_playing(_me(game), game), Achievements.DIVERSIFIED
	)


func test_borrowing_is_earned_even_after_the_loan_is_settled() -> void:
	# One loan per game, so having a loan object at all means you borrowed.
	var game: GameState = _state()
	var player: PlayerState = _me(game)
	player.loan = LoanState.new()
	player.loan.is_paid_off = true

	var earned: Array[StringName] = AchievementRules.while_playing(player, game)
	assert_has(earned, Achievements.TOOK_OUT_LOAN)
	assert_has(earned, Achievements.PAID_LOAN)


func test_an_unpaid_loan_earns_only_the_borrowing_one() -> void:
	var game: GameState = _state()
	var player: PlayerState = _me(game)
	player.loan = LoanState.new()

	var earned: Array[StringName] = AchievementRules.while_playing(player, game)
	assert_has(earned, Achievements.TOOK_OUT_LOAN)
	assert_does_not_have(earned, Achievements.PAID_LOAN)


# ------------------------------------------------------------------- a year

func _year_with(stalk_id: StringName, split: bool, bankrupt: bool) -> YearResult:
	var result: YearResult = YearResult.new()
	var change: StalkYearChange = StalkYearChange.new()
	change.stalk_id = stalk_id
	change.did_split = split
	change.went_bankrupt = bankrupt
	result.stalk_changes = [change] as Array[StalkYearChange]
	return result


func test_holding_a_stalk_that_split_is_earned() -> void:
	var held: Dictionary[StringName, int] = {&"a": 5}
	assert_has(
		AchievementRules.for_year(&"p0", held, _year_with(&"a", true, false)),
		Achievements.SPLIT,
	)


func test_a_split_you_did_not_hold_earns_nothing() -> void:
	var held: Dictionary[StringName, int] = {&"b": 5}
	assert_does_not_have(
		AchievementRules.for_year(&"p0", held, _year_with(&"a", true, false)),
		Achievements.SPLIT,
	)


## The reason `held_before` exists at all.
##
## `YearResolver` sets a bankrupt stalk's shares to zero, so by the time the
## year's result is in hand the state no longer remembers you held the thing
## that went under. Reading the current holdings would award this to nobody,
## ever, and the mistake would be invisible.
func test_holding_a_stalk_that_went_bankrupt_is_earned_from_the_holdings_before() -> void:
	var held: Dictionary[StringName, int] = {&"a": 5}
	assert_has(
		AchievementRules.for_year(&"p0", held, _year_with(&"a", false, true)),
		Achievements.BANKRUPT,
	)


func test_defaulting_on_a_loan_is_earned() -> void:
	var result: YearResult = YearResult.new()
	var change: LoanYearChange = LoanYearChange.new()
	change.player_id = &"p0"
	change.defaulted = true
	result.loan_changes = [change] as Array[LoanYearChange]

	var held: Dictionary[StringName, int] = {}
	assert_has(
		AchievementRules.for_year(&"p0", held, result), Achievements.DEFAULT_LOAN
	)


func test_somebody_elses_default_is_not_yours() -> void:
	var result: YearResult = YearResult.new()
	var change: LoanYearChange = LoanYearChange.new()
	change.player_id = &"p1"
	change.defaulted = true
	result.loan_changes = [change] as Array[LoanYearChange]

	var held: Dictionary[StringName, int] = {}
	assert_does_not_have(
		AchievementRules.for_year(&"p0", held, result), Achievements.DEFAULT_LOAN
	)


# ------------------------------------------------------------- the final year

func _ending(net_worth: int, starting_cash: int = 10000, years: int = 10) -> Array:
	var game: GameState = _state(2, years, starting_cash)
	var player: PlayerState = _me(game)
	player.net_worth = net_worth
	return [player, game]


func test_winning_and_losing_are_exclusive() -> void:
	var bits: Array = _ending(20000)
	var winners: Array[StringName] = [bits[0].id]
	var won: Array[StringName] = AchievementRules.at_the_end(bits[0], bits[1], winners)
	assert_has(won, Achievements.WIN_ONE)
	assert_does_not_have(won, Achievements.LOSE_ONE)

	var others: Array[StringName] = [&"p1"]
	var lost: Array[StringName] = AchievementRules.at_the_end(bits[0], bits[1], others)
	assert_has(lost, Achievements.LOSE_ONE)
	assert_does_not_have(lost, Achievements.WIN_ONE)


func test_fifty_thousand_from_a_modest_start_is_earned() -> void:
	var bits: Array = _ending(AchievementRules.NETWORTH_FIFTY_TARGET, 10000)
	assert_has(
		AchievementRules.at_the_end(bits[0], bits[1], [] as Array[StringName]),
		Achievements.NETWORTH_FIFTY,
	)


func test_fifty_thousand_cannot_be_bought_with_a_generous_start() -> void:
	# The whole point of the second condition: start rich enough and the
	# target is met by doing nothing.
	var bits: Array = _ending(
		AchievementRules.NETWORTH_FIFTY_TARGET,
		AchievementRules.NETWORTH_FIFTY_MAX_START + 100,
	)
	assert_does_not_have(
		AchievementRules.at_the_end(bits[0], bits[1], [] as Array[StringName]),
		Achievements.NETWORTH_FIFTY,
	)


func test_finishing_with_almost_nothing_is_a_wipeout() -> void:
	# Named NETWORTH_HUNDRED, and it means a hundred *or less*.
	var bits: Array = _ending(AchievementRules.WIPEOUT_NET_WORTH)
	assert_has(
		AchievementRules.at_the_end(bits[0], bits[1], [] as Array[StringName]),
		Achievements.NETWORTH_HUNDRED,
	)


func test_doubling_and_halving_your_money() -> void:
	var doubled: Array = _ending(20000, 10000)
	assert_has(
		AchievementRules.at_the_end(doubled[0], doubled[1], [] as Array[StringName]),
		Achievements.DOUBLED,
	)

	var halved: Array = _ending(5000, 10000)
	assert_has(
		AchievementRules.at_the_end(halved[0], halved[1], [] as Array[StringName]),
		Achievements.HALVED,
	)


func test_an_ordinary_finish_is_neither() -> void:
	var bits: Array = _ending(12000, 10000)
	var earned: Array[StringName] = AchievementRules.at_the_end(
		bits[0], bits[1], [] as Array[StringName]
	)
	assert_does_not_have(earned, Achievements.DOUBLED)
	assert_does_not_have(earned, Achievements.HALVED)


func test_a_long_match_earns_the_mortgage() -> void:
	var bits: Array = _ending(10000, 10000, AchievementRules.MORTGAGE_YEARS)
	assert_has(
		AchievementRules.at_the_end(bits[0], bits[1], [] as Array[StringName]),
		Achievements.MORTGAGE,
	)


func test_the_longest_match_earns_both_long_match_ones() -> void:
	var bits: Array = _ending(10000, 10000, AchievementRules.CENTURY_YEARS)
	var earned: Array[StringName] = AchievementRules.at_the_end(
		bits[0], bits[1], [] as Array[StringName]
	)
	assert_has(earned, Achievements.CENTURY)
	assert_has(earned, Achievements.MORTGAGE, "99 is also 30 or more")


func test_a_short_match_earns_neither() -> void:
	var bits: Array = _ending(10000, 10000, 10)
	var earned: Array[StringName] = AchievementRules.at_the_end(
		bits[0], bits[1], [] as Array[StringName]
	)
	assert_does_not_have(earned, Achievements.MORTGAGE)
	assert_does_not_have(earned, Achievements.CENTURY)


# ------------------------------------------------------------ lifetime totals

func test_a_tenth_win_earns_the_ten_achievement() -> void:
	assert_has(
		AchievementRules.for_total(Achievements.STAT_WINS, 10), Achievements.WIN_TEN
	)


func test_nine_wins_earns_nothing() -> void:
	assert_eq(
		AchievementRules.for_total(Achievements.STAT_WINS, 9), [] as Array[StringName]
	)


## Everything reached, not only what was just crossed.
##
## A player whose Steam stats are already past a threshold from the original
## game should be given it the first time they finish a match here, rather
## than having to win another ninety.
func test_a_high_total_earns_every_threshold_below_it() -> void:
	var earned: Array[StringName] = AchievementRules.for_total(
		Achievements.STAT_WINS, 1000
	)
	assert_has(earned, Achievements.WIN_TEN)
	assert_has(earned, Achievements.WIN_HUNDRED)
	assert_has(earned, Achievements.WIN_THOUSAND)


func test_losses_have_their_own_ladder() -> void:
	var earned: Array[StringName] = AchievementRules.for_total(
		Achievements.STAT_LOSSES, 100
	)
	assert_has(earned, Achievements.LOSE_TEN)
	assert_has(earned, Achievements.LOSE_HUNDRED)
	assert_does_not_have(earned, Achievements.WIN_TEN)


func test_lifetime_net_worth_has_two_rungs() -> void:
	assert_has(
		AchievementRules.for_total(Achievements.STAT_LIFETIME_NET_WORTH, 1000000),
		Achievements.ONE_MIL,
	)
	assert_does_not_have(
		AchievementRules.for_total(Achievements.STAT_LIFETIME_NET_WORTH, 1000000),
		Achievements.ONE_BIL,
	)


func test_one_yeehaw_given_is_enough_for_the_first() -> void:
	assert_has(
		AchievementRules.for_total(Achievements.STAT_YEEHAWS, 1),
		Achievements.YEEHAW_ONE,
	)


func test_an_unknown_counter_earns_nothing() -> void:
	assert_eq(
		AchievementRules.for_total(&"not_a_stat", 1000000), [] as Array[StringName]
	)


# ------------------------------------------------------------------ the lists

func test_every_id_these_rules_award_is_in_the_catalogue() -> void:
	# A typo here would be a silent no-op at Steam's end: an unknown
	# achievement name does not error, it simply never unlocks (D57).
	var game: GameState = _state()
	var player: PlayerState = _me(game)
	player.loan = LoanState.new()
	player.loan.is_paid_off = true
	for stalk: StalkState in game.stalks:
		player.set_shares(stalk.id, AchievementRules.ALL_IN_SHARES)

	var awarded: Array[StringName] = []
	awarded.append_array(AchievementRules.while_playing(player, game))
	awarded.append_array(
		AchievementRules.for_year(player.id, player.holdings, _year_with(
			game.stalks[0].id, true, true
		))
	)
	awarded.append_array(
		AchievementRules.at_the_end(player, game, [player.id] as Array[StringName])
	)
	for stat: StringName in [
		Achievements.STAT_WINS,
		Achievements.STAT_LOSSES,
		Achievements.STAT_LIFETIME_NET_WORTH,
		Achievements.STAT_YEEHAWS,
	]:
		awarded.append_array(AchievementRules.for_total(stat, 1000000000))

	assert_gt(awarded.size(), 0, "the test should have awarded something")
	for id: StringName in awarded:
		assert_true(Achievements.ALL.has(id), "not in the catalogue: %s" % id)
