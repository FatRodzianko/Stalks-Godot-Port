class_name LocalSession
extends GameSession
## A complete game played in this process, with no peer and no Steam.
##
## The original could only run through a Steam lobby, so it could not be played
## or tested without Steam running. Offline play is a genuine new feature and the
## simplest place for the UI to be built against — see docs/decisions.md D14.
##
## This holds no rules of its own. It owns a MatchAuthority and does one job:
## turn the authority's yes-or-no answers into the signals the UI listens for.
## HostSession wraps the very same authority and additionally broadcasts, which is
## why offline and hosted play cannot diverge. See docs/decisions.md D43.


var _authority: MatchAuthority
var _local_player_id: StringName = &"p0"


## Builds a ready-to-play match from authored content. `library` must hold
## what `settings.mode` needs: see `MatchSetup.load_library`.
##
## `settings.rng_seed` of 0 means "pick one and record it", so that a match is
## always reproducible afterwards even when the player did not choose a seed.
static func create(
	settings: GameSettings,
	library: ContentLibrary,
	player_names: Array[String] = ["You"],
) -> LocalSession:
	var session: LocalSession = LocalSession.new()
	session.name = "LocalSession"
	session._authority = build_authority(settings, library, player_names)

	# The match opens at **Year 0**: every price at its starting value, trading
	# closed, waiting for players to ready up. That is the original's opening
	# state and what docs/game-rules.md §4 describes, so the session starts there
	# rather than skipping ahead.
	return session


## Assembles the authoritative half of a match. Shared with HostSession, which
## needs exactly this and then a transport on top.
static func build_authority(
	settings: GameSettings,
	library: ContentLibrary,
	player_names: Array[String],
) -> MatchAuthority:
	if settings.rng_seed == 0:
		settings.rng_seed = abs(int(Time.get_unix_time_from_system() * 1000.0)) | 1

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = settings.rng_seed

	# The board, the year and the mode's own settings all come from
	# `MatchSetup`, the one place the game mode is read (decisions.md D171).
	MatchSetup.apply_mode_rules(settings)
	var state: GameState = MatchSetup.new_game_state(settings, library)
	for index: int in player_names.size():
		state.players.append(PlayerState.new(
			StringName("p%d" % index),
			player_names[index],
			settings.starting_cash,
		))

	var pipeline: YearPipeline = MatchSetup.new_pipeline(settings, library)
	pipeline.open_match(state, rng)
	return MatchAuthority.new(state, pipeline, rng)


func state() -> GameState:
	return _authority.state if _authority != null else null


func local_player_id() -> StringName:
	return _local_player_id


## The seed this match is running on. Worth surfacing somewhere in the UI: it is
## what makes a match reproducible, and a player reporting a bug can quote it.
func seed_value() -> int:
	return _authority.seed_value() if _authority != null else 0


# ------------------------------------------------------------------ the requests

func request_buy(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	_settle(player_id, _authority.buy(player_id, stalk_id, shares))


func request_sell(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	_settle(player_id, _authority.sell(player_id, stalk_id, shares))


func request_loan(player_id: StringName, amount: int) -> void:
	_settle(player_id, _authority.take_loan(player_id, amount))


func pay_loan(player_id: StringName, amount: int) -> void:
	_settle(player_id, _authority.pay_loan(player_id, amount))


## Marks a player ready. Once every player is ready the year advances.
func set_ready(player_id: StringName, is_ready: bool) -> void:
	var reason: String = _authority.set_ready(player_id, is_ready)
	if not reason.is_empty():
		action_rejected.emit(player_id, reason)
		return

	ready_state_changed.emit(player_id, is_ready)
	if _authority.state.all_players_ready():
		_advance()


## Asks for a yeehaw. In a solo game this always refuses: there is nobody to ask,
## and nobody who could answer.
##
## A local game with several players on one machine (hot-seat) is not something
## the original supported, but the rule is written in terms of player count rather
## than peer count, so it would work either way.
func request_yeehaw(player_id: StringName) -> void:
	var reason: String = _authority.request_yeehaw(player_id)
	if not reason.is_empty():
		action_rejected.emit(player_id, reason)
		return
	yeehaw_requested.emit(player_id)
	player_changed.emit(player_id)


func give_yeehaw(giver_id: StringName) -> void:
	var receiver_id: StringName = _authority.receiver_of_yeehaw()
	var reason: String = _authority.give_yeehaw(giver_id)
	if not reason.is_empty():
		action_rejected.emit(giver_id, reason)
		return
	yeehaw_given.emit(giver_id, receiver_id)


# -------------------------------------------------------------------- internals

## One shape for every request that either changes a player or is refused.
func _settle(player_id: StringName, reason: String) -> void:
	if reason.is_empty():
		player_changed.emit(player_id)
	else:
		action_rejected.emit(player_id, reason)


func _advance() -> void:
	var result: YearResult = _authority.advance_year()
	year_resolved.emit(result)
	if result.is_final_year:
		game_over.emit(result.winners)
