extends GutTest
## Who takes over a lobby when its host walks out.
##
## The decision only, with no Steam anywhere near it. Steam picks the new owner
## by itself; the question this answers is "has it decided yet, and is it me" -
## which is exactly the part that can be got wrong without a second machine to
## notice. See decisions.md D104.


const ME: int = 111
const DEPARTED: int = 222
const SOMEBODY: int = 333


func _migration() -> LobbyMigration:
	return LobbyMigration.new(ME, DEPARTED)


func test_nothing_decided_yet_means_wait() -> void:
	# Steam answers 0 while it has not chosen.
	assert_eq(_migration().next_step(0), LobbyMigration.Step.WAITING)


## The leaver can go on being reported as the owner for a moment.
##
## Taking that at face value would mean trying to rejoin the player who just
## left, which is the one answer that is certainly wrong.
func test_the_departed_host_still_counts_as_undecided() -> void:
	assert_eq(_migration().next_step(DEPARTED), LobbyMigration.Step.WAITING)


func test_being_made_the_owner_means_hosting() -> void:
	assert_eq(_migration().next_step(ME), LobbyMigration.Step.BECOME_HOST)


func test_somebody_else_being_made_the_owner_means_joining_them() -> void:
	assert_eq(_migration().next_step(SOMEBODY), LobbyMigration.Step.JOIN_NEW_HOST)


## The lobby may simply be gone, and a player left asking for ever is the fault
## the client join timeout was written for (D68).
func test_waiting_too_long_gives_up() -> void:
	var migration: LobbyMigration = _migration()
	migration.wait(LobbyMigration.GIVE_UP_SECONDS)

	assert_eq(migration.next_step(0), LobbyMigration.Step.GAVE_UP)


func test_it_does_not_give_up_early() -> void:
	var migration: LobbyMigration = _migration()
	migration.wait(LobbyMigration.GIVE_UP_SECONDS - 0.1)

	assert_eq(migration.next_step(0), LobbyMigration.Step.WAITING)


## An answer that arrives late is still an answer.
##
## The deadline is for a lobby that never responds, not a slow one, so a owner
## named after the deadline is still acted on rather than thrown away.
func test_an_owner_named_after_the_deadline_is_still_honoured() -> void:
	var migration: LobbyMigration = _migration()
	migration.wait(LobbyMigration.GIVE_UP_SECONDS * 2.0)

	assert_eq(migration.next_step(ME), LobbyMigration.Step.BECOME_HOST)


func test_waiting_accumulates() -> void:
	var migration: LobbyMigration = _migration()
	migration.wait(1.0)
	migration.wait(0.5)

	assert_almost_eq(migration.waited(), 1.5, 0.001)


func test_only_waiting_is_unsettled() -> void:
	assert_false(LobbyMigration.is_settled(LobbyMigration.Step.WAITING))
	assert_true(LobbyMigration.is_settled(LobbyMigration.Step.BECOME_HOST))
	assert_true(LobbyMigration.is_settled(LobbyMigration.Step.JOIN_NEW_HOST))
	assert_true(LobbyMigration.is_settled(LobbyMigration.Step.GAVE_UP))
