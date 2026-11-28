extends RefCounted
## One seeded StalkleHeads match played by the strategy players of
## docs/stalkleheads-design.md §2.1, for the balance tool and its GUT smoke
## test. **The market is the game's own**: a `GameState` built by
## `EarningsMarket.new_game_state`, advanced by `EarningsYearResolver` (through
## `lever_year.gd`, which only adds the sweep's levers). Each strategy is a real
## `PlayerState`, so dividends, splits, bankruptcies and net worth are the
## pipeline's, not this file's.
##
## Each strategy starts with the default starting cash. At the start of every
## year it sells everything and splits its cash equally across its targets, at
## last year's closing prices (HOLD trades in year 1 only). That is the probe's
## trading loop (Appendix A): it rebalances completely at no cost, which no real
## player does and which exaggerates every edge. It moves shares and cash
## directly rather than through `TradeRules`, because year 0 is closed to
## trading and the probe trades before year 1.
##
## Two random streams (decisions.md D145): the market draws from one seeded with
## the match seed, and only RANDOM draws from the other, so choosing which
## strategies to run never changes the market they are measured on - unless the
## players' own trades feed the flow term (`FLOW_ALL`), when the players are part
## of the market, as they are in the game.
##
## **The NPC desk is the game's own** (since S4): `EarningsMarket.desk`, acting at
## the end of every year advance. FOLLOW reads it.


const LeverDesk := preload("res://tools/balance/lever_desk.gd")
const LeverYear := preload("res://tools/balance/lever_year.gd")
const Levers := preload("res://tools/balance/levers.gd")

## Every strategy, in the order the report prints them, which is the probe's.
const ALL_STRATEGIES: Array[StringName] = [
	&"HOLD", &"LOWPE", &"HIGHPE", &"TREND", &"MOMENTUM",
	&"CONTRARIAN", &"INCOME", &"FOLLOW", &"RANDOM", &"BOND",
]

## What feeds the flow term (§3.10):
## - FLOW_ALL: the desk's trades and the players', as in the game. The default.
## - FLOW_DESK: the desk's only, so the players do not move the market.
## - FLOW_NONE: nothing. The desk still trades and FOLLOW still reads it, but no
##   price moves because of its trading. S2 and S3 measured with no desk at all.
const FLOW_ALL: StringName = &"all"
const FLOW_DESK: StringName = &"desk"
const FLOW_NONE: StringName = &"none"
const FLOW_MODES: Array[StringName] = [FLOW_ALL, FLOW_DESK, FLOW_NONE]

## Strategies that play only when named with `--strategies` (D234). Not in
## the default set, so the P4 baseline keeps its ten players: in `FLOW_ALL` the
## players are part of the market, and an eleventh would change it.
## - WHISPER reads the latest whispers (§8.4) and nothing else.
const OPTIONAL_STRATEGIES: Array[StringName] = [&"WHISPER"]

## Every strategy the tool knows.
const KNOWN_STRATEGIES: Array[StringName] = [
	&"HOLD", &"LOWPE", &"HIGHPE", &"TREND", &"MOMENTUM",
	&"CONTRARIAN", &"INCOME", &"FOLLOW", &"RANDOM", &"BOND", &"WHISPER",
]

## How much a whisper's told outcome is worth to WHISPER, worst to best.
const WHISPER_VALUE: Dictionary[NewsBands.Surprise, float] = {
	NewsBands.Surprise.MUCH_WORSE: -2.0,
	NewsBands.Surprise.WORSE: -1.0,
	NewsBands.Surprise.AS_EXPECTED: 0.0,
	NewsBands.Surprise.BETTER: 1.0,
	NewsBands.Surprise.MUCH_BETTER: 2.0,
}

## An industry whisper counts this much for each of its members, against a
## whisper about the company itself.
const WHISPER_INDUSTRY_SHARE: float = 0.5

## How many companies a picking strategy holds.
const PICKS: int = 3

const BOND_ID: StringName = EarningsMarket.BOND_ID


## What one match produced.
class Result:
	extends RefCounted
	var net_worth: Dictionary[StringName, int] = {}
	var splits: int = 0
	var bankruptcies: int = 0
	var bull_years: int = 0
	var years: int = 0
	var moves: Array[int] = []
	var final_prices: Array[int] = []
	## Years whose event was a short squeeze, and years with a company flagged.
	var squeezes: int = 0
	var flagged_years: int = 0
	## The strategy of the desk's best trader at the end of the match.
	var best_npc_strategy: String = ""


## What the strategies read: the published state, plus the two figures a report
## would carry that the state itself does not keep.
class View:
	extends RefCounted
	var state: GameState
	## Each company's profit before the latest earnings season. Absent until the
	## first season has run, so "growth" has no value in year 1.
	var previous_profit: Dictionary[StringName, float] = {}
	## The dividend per share each row paid in the latest year. 0 before year 1.
	var dividend: Dictionary[StringName, int] = {}
	## The sweep's levers; WHISPER reads the whisper ones.
	var levers: Levers
	## With a whisper lever set: the rounds the tool has worked out, by the
	## year heard, and how often each line was drawn in them.
	var whisper_rounds: Dictionary[int, WhisperRound] = {}
	var whisper_counts: Dictionary[StringName, int] = {}

	## Companies not bankrupt, in id order.
	func living() -> Array[CompanyState]:
		var alive: Array[CompanyState] = []
		for company: CompanyState in state.market.companies:
			if not state.stalk_by_id(company.id).is_bankrupt:
				alive.append(company)
		return alive


## Plays one match. `strategies` is a subset of ALL_STRATEGIES. `flow` is one
## of FLOW_MODES. `levers` overrides balance numbers for a sweep (levers.gd);
## null means the published values.
static func play(
	library: ContentLibrary,
	match_seed: int,
	years: int,
	strategies: Array[StringName],
	flow: StringName = FLOW_ALL,
	levers: Levers = null,
) -> Result:
	var market_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	market_rng.seed = match_seed
	var player_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	player_rng.seed = hash("balance players %d" % match_seed)

	var settings: GameSettings = GameSettings.new()
	settings.max_years = years
	settings.rng_seed = match_seed
	var view: View = View.new()
	view.state = EarningsMarket.new_game_state(library, settings)
	if levers == null:
		levers = Levers.new()
	view.levers = levers
	if levers.short_target != LeverDesk.SHORT_HIGHPE or levers.flag_at >= 0.0:
		# The same traders at year 0, through the lever desk's two seams.
		var desk: LeverDesk = LeverDesk.new()
		desk.traders = view.state.market.desk.traders
		desk.short_target = levers.short_target
		desk.flag_at = levers.flag_at
		view.state.market.desk = desk
	var squeeze: SpecialEventDefinition = library.short_squeeze
	if not levers.squeeze:
		squeeze = null
	var resolver: LeverYear = LeverYear.new(levers, squeeze)
	for strategy: StringName in strategies:
		view.state.players.append(PlayerState.new(strategy, String(strategy), settings.starting_cash))

	var result: Result = Result.new()
	result.years = years
	for year: int in range(1, years + 1):
		var net_shares: Dictionary[StringName, int] = {}
		for player: PlayerState in view.state.players:
			if player.id == &"HOLD" and year > 1:
				continue
			var targets: Array[StringName] = _targets(player.id, view, player_rng)
			if targets.is_empty():
				continue
			_rebalance(player, targets, view.state, net_shares)

		# The desk recorded its own trades at the end of last year's advance.
		if flow == FLOW_NONE:
			view.state.market.net_shares_traded = {}
		elif flow == FLOW_ALL:
			for asset_id: StringName in net_shares:
				view.state.market.record_trade(asset_id, net_shares[asset_id])
		var alive: Array[CompanyState] = view.living()
		for company: CompanyState in alive:
			view.previous_profit[company.id] = company.profit
		var outcome: EarningsYearResult = resolver.advance_year(view.state, market_rng)
		view.dividend = outcome.dividend_per_share

		for company: CompanyState in alive:
			var change: StalkYearChange = outcome.change_for(company.id)
			result.moves.append(absi(change.price_after - change.price_before))
			if change.did_split:
				result.splits += 1
			if change.went_bankrupt:
				result.bankruptcies += 1
		if outcome.mood == MarketMood.Value.BULL:
			result.bull_years += 1
		if outcome.squeezed:
			result.squeezes += 1
		if not outcome.short_interest_flagged.is_empty():
			result.flagged_years += 1

	for player: PlayerState in view.state.players:
		result.net_worth[player.id] = TradeRules.net_worth(player, view.state)
	for company: CompanyState in view.state.market.companies:
		result.final_prices.append(company.price)
	var best: NpcTraderState = view.state.market.desk.best_trader(view.state)
	if best != null:
		result.best_npc_strategy = NpcStrategy.name_of(best.strategy)
	return result


## Sell everything, then spend the cash equally across `targets`.
static func _rebalance(
	player: PlayerState,
	targets: Array[StringName],
	state: GameState,
	net_shares: Dictionary[StringName, int],
) -> void:
	for asset_id: StringName in player.held_stalk_ids():
		var amount: int = player.shares_of(asset_id)
		var price: int = state.stalk_by_id(asset_id).price
		if price > 0:
			player.cash += amount * price
			net_shares[asset_id] = net_shares.get(asset_id, 0) - amount
		player.set_shares(asset_id, 0)

	var each: int = player.cash / targets.size()
	for asset_id: StringName in targets:
		var price: int = state.stalk_by_id(asset_id).price
		if price <= 0:
			continue
		var shares: int = each / price
		if shares <= 0:
			continue
		player.cash -= shares * price
		player.add_shares(asset_id, shares)
		net_shares[asset_id] = net_shares.get(asset_id, 0) + shares


## What a strategy wants to hold this year, read from last year's published
## state. Ties break by company id, so every run is reproducible.
static func _targets(
	strategy: StringName,
	market: View,
	player_rng: RandomNumberGenerator,
) -> Array[StringName]:
	var alive: Array[CompanyState] = market.living()
	var ids: Array[StringName] = []
	if alive.is_empty():
		return ids
	for company: CompanyState in alive:
		ids.append(company.id)
	var first: Array[StringName] = ids.slice(0, PICKS)

	match strategy:
		&"BOND":
			return [BOND_ID]
		&"HOLD":
			return ids
		&"RANDOM":
			# Partial Fisher-Yates: PICKS distinct companies.
			var pool: Array[StringName] = ids.duplicate()
			for index: int in mini(PICKS, pool.size()):
				var swap: int = player_rng.randi_range(index, pool.size() - 1)
				var held: StringName = pool[index]
				pool[index] = pool[swap]
				pool[swap] = held
			return pool.slice(0, PICKS)
		&"LOWPE", &"HIGHPE":
			var scored: Array[Array] = []
			for company: CompanyState in alive:
				var eps: float = company.earnings_per_share()
				if eps <= 0.0 or company.price <= 0:
					continue
				var pe: float = float(company.price) / eps
				if strategy == &"HIGHPE":
					pe = -pe
				scored.append([pe, company.id])
			if scored.is_empty() and strategy == &"LOWPE":
				return first
			return _lowest(scored)
		&"TREND":
			# Last year's earnings growth, split-adjusted: profit does not change
			# when shares double, so its growth is the growth of EPS a report
			# would publish once restated for the split (decisions.md D146).
			var scored: Array[Array] = []
			for company: CompanyState in alive:
				if not market.previous_profit.has(company.id):
					continue
				var was: float = market.previous_profit[company.id]
				if was <= 0.0:
					continue
				scored.append([-(company.profit - was) / was, company.id])
			if scored.is_empty():
				return first
			return _lowest(scored)
		&"MOMENTUM", &"CONTRARIAN":
			var scored: Array[Array] = []
			for company: CompanyState in alive:
				var delta: float = float(market.state.stalk_by_id(company.id).last_yearly_change)
				if strategy == &"MOMENTUM":
					delta = -delta
				scored.append([delta, company.id])
			return _lowest(scored)
		&"FOLLOW":
			# §5.2: copy whichever NPC trader is worth most, by holding what it
			# holds, equally. If it holds nothing (a SHORT trader only ever sells
			# short, which players cannot), the first PICKS, as the probe did.
			var best: NpcTraderState = market.state.market.desk.best_trader(market.state)
			if best == null:
				return first
			var held: Array[StringName] = []
			for asset_id: StringName in best.held_ids():
				if market.state.stalk_by_id(asset_id).price > 0:
					held.append(asset_id)
			if held.is_empty():
				return first
			return held
		&"WHISPER":
			return _whisper_targets(market, alive)
		&"INCOME":
			var scored: Array[Array] = []
			for company: CompanyState in alive:
				if company.price <= 0:
					continue
				var paid: float = float(market.dividend.get(company.id, 0))
				scored.append([-paid / float(company.price), company.id])
			return _lowest(scored)
	push_error("Unknown strategy %s" % strategy)
	return ids


## WHISPER (D234): the whispers heard at the end of last year, about this one
## (`NewsSelector.latest_whispers`), and nothing else. Each whisper scores what
## it tells (`WHISPER_VALUE`) times its source's chance of telling the truth
## (`WhisperRules.ODDS`): a company whisper for that company, an industry
## whisper at `WHISPER_INDUSTRY_SHARE` for each member, a squeeze coming as +2
## and a squeeze ending as -2 for its company. It holds the best PICKS scoring
## above 0, and the bond when none does - every year 1, since the first round
## is heard at its end (D207). It reads only what a player sees: the told
## outcome and the source, never the truth.
static func _whisper_targets(market: View, alive: Array[CompanyState]) -> Array[StringName]:
	var round: WhisperRound = _latest_whispers(market)
	var score: Dictionary[StringName, float] = {}
	if round != null:
		for line: WhisperRound.Line in round.lines:
			var trust: float = float(WhisperRules.ODDS[line.source].x) / 100.0
			match line.about:
				NewsBands.Subject.COMPANY:
					score[line.subject] = score.get(line.subject, 0.0) + WHISPER_VALUE[line.said] * trust
				NewsBands.Subject.INDUSTRY:
					for company: CompanyState in alive:
						if company.profile.industry == line.subject:
							score[company.id] = score.get(company.id, 0.0) 								+ WHISPER_VALUE[line.said] * trust * WHISPER_INDUSTRY_SHARE
				NewsBands.Subject.SQUEEZE:
					score[line.subject] = score.get(line.subject, 0.0) + 2.0 * trust
				NewsBands.Subject.CRASH:
					score[line.subject] = score.get(line.subject, 0.0) - 2.0 * trust
	var scored: Array[Array] = []
	for company: CompanyState in alive:
		var value: float = score.get(company.id, 0.0)
		if value > 0.0 and company.price > 0:
			scored.append([-value, company.id])
	if scored.is_empty():
		return [BOND_ID]
	return _lowest(scored)


## The round WHISPER hears now: the game's (`NewsSelector.latest_whispers`),
## or, with a whisper lever set, one worked out here by the game's own
## `select_whispers` with the overrides, in order, counting earlier rounds'
## lines as `NewsSelector.whispers_for` does (D236). Lines already shown are
## the year's news, its market news and these rounds, as the game counts them.
static func _latest_whispers(market: View) -> WhisperRound:
	var state: GameState = market.state
	if market.levers == null or not market.levers.changes_whispers():
		return NewsSelector.latest_whispers(state)
	var year: int = state.year
	if year < NewsSelector.FIRST_WHISPER_YEAR:
		return null
	if market.whisper_rounds.has(year):
		return market.whisper_rounds[year]
	var draws: KeptDraws = NewsSelector.draws_about(state, year + 1)
	if draws == null:
		return null
	var shown: Dictionary[StringName, bool] = {}
	for each: int in range(1, year):
		var news: YearNews = NewsSelector.news_for(state, each)
		if news != null:
			for id: StringName in news.drawn:
				shown[id] = true
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, each)
		if result != null and result.market_news != null:
			shown[result.market_news.id] = true
		if market.whisper_rounds.has(each):
			for id: StringName in market.whisper_rounds[each].drawn:
				shown[id] = true
	var count: int = NewsSelector.WHISPERS_PER_YEAR
	if market.levers.whisper_count >= 0:
		count = market.levers.whisper_count
	var round: WhisperRound = NewsSelector.select_whispers(
		state, year, draws, market.whisper_counts, shown,
		count, market.levers.whisper_odds_table(), market.levers.squeeze_whispers,
		market.levers.whisper_sources,
	)
	market.whisper_rounds[year] = round
	for id: StringName in round.drawn:
		market.whisper_counts[id] = market.whisper_counts.get(id, 0) + 1
	return round


## The PICKS ids with the lowest score, ties by id. Each entry is [score, id].
static func _lowest(scored: Array[Array]) -> Array[StringName]:
	scored.sort_custom(_score_then_id)
	var picked: Array[StringName] = []
	for entry: Array in scored.slice(0, PICKS):
		picked.append(entry[1])
	return picked


static func _score_then_id(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return String(a[1]) < String(b[1])
