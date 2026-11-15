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
	# the catalogue it refers to.
	for id: StringName in Achievements.UNCONFIRMED_CASING:
		assert_true(Achievements.ALL.has(id), "%s is not in ALL" % id)


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
