extends GutTest
## The achievement catalogue.
##
## These cannot check Steam, so they check the thing that actually went wrong
## last time: the original shipped two spellings of the same achievement because
## nobody was sure which case Steam wanted, and Steam's names are
## case-sensitive. A duplicate or a near-duplicate here means an achievement that
## silently never unlocks for anybody.


func test_there_are_twenty_five_achievements() -> void:
	# The number the partner backend holds. If this changes, the backend has to
	# change with it, and that is a deliberate act rather than a refactor.
	assert_eq(Achievements.ALL.size(), 25)


func test_no_two_ids_differ_only_by_case() -> void:
	# The exact bug the original shipped: SSS_WIN_ONE_GAME alongside
	# SSS_Win_One_Game, one of which never unlocked anything.
	var seen: Dictionary = {}
	var collisions: PackedStringArray = []
	for id: StringName in Achievements.ALL:
		var folded: String = String(id).to_lower()
		if seen.has(folded):
			collisions.append("%s vs %s" % [seen[folded], id])
		seen[folded] = id

	assert_eq(collisions, PackedStringArray(), "ids differing only by case")


func test_no_id_appears_twice() -> void:
	var unique: Dictionary = {}
	for id: StringName in Achievements.ALL:
		unique[id] = true
	assert_eq(unique.size(), Achievements.ALL.size(), "every id should be distinct")


func test_every_id_is_prefixed_and_non_empty() -> void:
	for id: StringName in Achievements.ALL:
		assert_true(String(id).begins_with("SSS_"), "unexpected id: %s" % id)


func test_no_id_has_stray_whitespace() -> void:
	# A trailing space is invisible in a diff and fatal to a case-sensitive
	# string comparison on Steam's side.
	for id: StringName in Achievements.ALL:
		assert_eq(String(id), String(id).strip_edges(), "padded id: '%s'" % id)


func test_the_unconfirmed_ids_are_real_ids() -> void:
	# The list of things to check against the backend must not drift away from
	# the catalogue it refers to. Written to assert even when the list is empty,
	# which it is today — a loop over nothing is a test that proves nothing.
	var strays: PackedStringArray = []
	for id: StringName in Achievements.UNCONFIRMED_CASING:
		if not Achievements.ALL.has(id):
			strays.append(String(id))

	assert_eq(strays, PackedStringArray(), "unconfirmed ids not in the catalogue")


func test_nothing_is_waiting_on_a_backend_check() -> void:
	# A tripwire, not a formality: anything added to the catalogue whose casing
	# has not been read off the backend belongs in this list, and this test is
	# what makes forgetting it noisy.
	assert_eq(
		Achievements.UNCONFIRMED_CASING, [] as Array[StringName],
		"an id is still waiting on a backend check",
	)


func test_the_two_single_game_achievements_are_title_case() -> void:
	# Both were read off the partner backend, and both go against the pattern of
	# every other id. Guessing from the majority would have got both wrong, and
	# a wrong name does not error: the achievement just never unlocks.
	assert_eq(Achievements.WIN_ONE, &"SSS_Win_One_Game")
	assert_eq(Achievements.LOSE_ONE, &"SSS_Lose_One_Game")


func test_the_win_achievement_keeps_the_spelling_that_actually_fired() -> void:
	# The original's only live call is SetAchievement("SSS_Win_One_Game"); the
	# shouting version is commented out. So this is the spelling real players
	# have unlocked, and therefore what the backend holds. Changing it would
	# quietly orphan everyone's existing achievement.
	assert_eq(Achievements.WIN_ONE, &"SSS_Win_One_Game")


func test_the_stat_names_are_distinct() -> void:
	var stats: Array[StringName] = [
		Achievements.STAT_WINS,
		Achievements.STAT_LOSSES,
		Achievements.STAT_LIFETIME_NET_WORTH,
		Achievements.STAT_YEEHAWS,
	]
	var unique: Dictionary = {}
	for stat: StringName in stats:
		unique[String(stat).to_lower()] = true
	assert_eq(unique.size(), stats.size())


# ----------------------------------------------------------------- the rematch
#
# The reporter is made once per session (`Main._watch_for_achievements`) and a
# rematch reuses the session, which is right - a rematch is a real match and its
# wins and losses should count. What must not carry over is the position it
# judges the next first year against: `AchievementRules.for_year` reads
# `_held_before` to decide whether a stalk that split or went bankrupt was one
# you owned, and in year 1 of a rematch you own nothing. See decisions.md D124.

func test_a_rematch_forgets_the_position_the_last_match_ended_on() -> void:
	var library: ContentLibrary = ContentLibrary.load_from()
	assert_true(library.is_valid(), "the test needs content")
	var session: LocalSession = LocalSession.create(StalksFixture.make_settings(), library)
	add_child_autofree(session)

	var stalk_id: StringName = session.state().stalks[0].id
	session.state().players[0].set_shares(stalk_id, 10)

	var reporter: AchievementReporter = AchievementReporter.new()
	add_child_autofree(reporter)
	reporter.setup(session, null)
	assert_eq(
		reporter.held_before_for_testing().get(stalk_id, 0), 10,
		"the test needs the finished match's position remembered first",
	)

	reporter.forget_holdings()

	assert_eq(
		reporter.held_before_for_testing().size(), 0,
		"a rematch's first year must not be judged on the last match's holdings",
	)
