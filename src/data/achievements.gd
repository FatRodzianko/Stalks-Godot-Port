class_name Achievements
extends RefCounted
## Every Steam achievement id, and what unlocks it.
##
## Read out of the original's `SteamAchievementManager.cs` and the handful of
## places that call it. The App ID is **reused** (decisions.md D57), so these are
## not names we get to choose: they must match what the Steam partner backend
## already holds, or an achievement silently never unlocks.
##
## **Steam achievement API names are case-sensitive.** The original hedged on two
## of them and set both spellings; see `UNCONFIRMED_CASING` below. That is the
## one open question here, and `tests/unit/test_achievements.gd` makes sure we
## never ship two ids that differ only by case.
##
## Nothing here is wired up yet. Phase 6 adds the code that calls Steam; this is
## the catalogue it will use, written now because the information came from a
## source a successor will not have. See docs/steam-integration.md 4.


# ------------------------------------------------------------------ win / loss

## Win a single game.
##
## Lowercase on purpose. The original's only live call is
## `SetAchievement("SSS_Win_One_Game")` DASH the shouting version is commented out
## DASH so this is the spelling that has actually unlocked for real players, and
## therefore the one the backend holds.
const WIN_ONE: StringName = &"SSS_Win_One_Game"

## Lose a single game. **Casing unconfirmed** DASH see `UNCONFIRMED_CASING`.
const LOSE_ONE: StringName = &"SSS_LOSE_ONE_GAME"

## Lifetime wins, from the Steam stat `sss_wins`.
const WIN_TEN: StringName = &"SSS_WIN_TEN"
const WIN_HUNDRED: StringName = &"SSS_WIN_HUNDRED"
const WIN_THOUSAND: StringName = &"SSS_WINS_THOUSAND"

## Lifetime losses, from the Steam stat `sss_loses`.
const LOSE_TEN: StringName = &"SSS_LOSES_TEN"
const LOSE_HUNDRED: StringName = &"SSS_LOSES_HUNDRED"
const LOSE_THOUSAND: StringName = &"SSS_LOSES_THOUSAND"


# -------------------------------------------------------------------- net worth

## Finish with net worth of 50,000 or more, **and** a starting cash of 10,000 or
## less. The second half stops it being bought with a generous lobby setting.
const NETWORTH_FIFTY: StringName = &"SSS_NETWORTH_FIFTY"

## Finish with net worth of **100 or less**.
##
## Misleadingly named: this is a wipe-out, not a milestone. Worth knowing before
## anybody "fixes" it to mean a hundred thousand.
const NETWORTH_HUNDRED: StringName = &"SSS_NETWORTH_HUNDRED"

## Cumulative net worth across every game played, from the Steam stat
## `lifetime_networth`.
const ONE_MIL: StringName = &"SSS_ONE_MIL"
const ONE_BIL: StringName = &"SSS_ONE_BIL"


# ----------------------------------------------------------------------- swings

## Finish with at least twice your starting cash.
const DOUBLED: StringName = &"SSS_DOUBLED"

## Finish with half your starting cash or less.
const HALVED: StringName = &"SSS_HALVED"

## Play a match of 30 years or more.
const MORTGAGE: StringName = &"SSS_MORTGAGE"

## Play a match of exactly 99 years, the maximum.
const CENTURY: StringName = &"SSS_CENTURY"


# ------------------------------------------------------------------------ loans

const TOOK_OUT_LOAN: StringName = &"SSS_TOOK_OUT_LOAN"
const PAID_LOAN: StringName = &"SSS_PAID_LOAN"
const DEFAULT_LOAN: StringName = &"SSS_DEFAULT_LOAN"


# ----------------------------------------------------------------------- events

## Hold a stalk that splits.
const SPLIT: StringName = &"SSS_SPLIT"

## Hold **300 or more shares of a single stalk**.
const ALL_IN: StringName = &"SSS_ALL_IN"

## Hold a stalk that goes bankrupt.
const BANKRUPT: StringName = &"SSS_BANKRUPT"

## Hold **10 or more shares of all ten stalks** at once.
const DIVERSIFIED: StringName = &"SSS_DIVERSIFIED"


# ----------------------------------------------------------------------- yeehaw

## Give a yeehaw. Given, not received DASH the stat is `sss_yeehaws` and it counts
## only what you hand out.
const YEEHAW_ONE: StringName = &"SSS_YEEHAW_ONE"
const YEEHAW_HUNDRED: StringName = &"SSS_YEEHAW_HUNDRED"


# ------------------------------------------------------------------------- lists

## All 25 ids. The port must unlock each of these and no others.
const ALL: Array[StringName] = [
	WIN_ONE, LOSE_ONE,
	WIN_TEN, WIN_HUNDRED, WIN_THOUSAND,
	LOSE_TEN, LOSE_HUNDRED, LOSE_THOUSAND,
	NETWORTH_FIFTY, NETWORTH_HUNDRED, ONE_MIL, ONE_BIL,
	DOUBLED, HALVED, MORTGAGE, CENTURY,
	TOOK_OUT_LOAN, PAID_LOAN, DEFAULT_LOAN,
	SPLIT, ALL_IN, BANKRUPT, DIVERSIFIED,
	YEEHAW_ONE, YEEHAW_HUNDRED,
]

## Ids whose capitalisation has **not** been checked against the partner backend.
##
## The original set `SSS_LOSE_ONE_GAME` *and* `SSS_Lose_One_Game` on the same
## line, so one of the two is a no-op and the source cannot say which. Reusing
## the App ID means the backend decides. Check it there before shipping, and if
## it disagrees, change `LOSE_ONE` above DASH nothing else needs to move.
const UNCONFIRMED_CASING: Array[StringName] = [LOSE_ONE]


## Steam stat names the achievements count against. Also case-sensitive, and
## also the backend's to confirm.
const STAT_WINS: StringName = &"sss_wins"
const STAT_LOSSES: StringName = &"sss_loses"
const STAT_LIFETIME_NET_WORTH: StringName = &"lifetime_networth"
const STAT_YEEHAWS: StringName = &"sss_yeehaws"
