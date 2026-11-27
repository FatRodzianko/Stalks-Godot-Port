class_name MarketNewsRules
extends RefCounted
## How a StalkleHeads year's market news is chosen and whom it hits
## (docs/stalkleheads-design.md §8.5, decisions.md D209, D210).
##
## **Chosen by the economy.** Market news moves prices, so it is drawn by the
## year's resolver with the match's own generator, before any price is set:
## one line whose mood and move match **last year's** mood and index move
## (D154: this year's are not known until the prices are), whose required
## lines have all been shown in an earlier year, and whose target is still
## trading. Among those, a follow-up line whose requirements are met is drawn
## first; otherwise the lines drawn least so far in this match, the way every
## other news line is bagged (D200). One draw from the generator when anything
## can be drawn, none when nothing can.
##
## **The amount goes to each target.** A company target gets it; an industry
## target gives every company of that industry still trading the same amount.
## Like a base-game special event it then fades by half a year.
##
## Pure rules: no nodes, no autoloads. The host draws; a client is sent the
## line's id and rebuilds the hits with `hits`.


## True when any market news line requires another, so the resolver needs to
## know what has been shown before.
static func any_requires(content: NewsContent) -> bool:
	if content == null:
		return false
	for line: MarketNews in content.market_news:
		if not line.requires.is_empty():
			return true
	return false


## The year's market news, drawn for the year `state` has just opened. `shown`
## holds the ids of every news line shown in an earlier year. Null when no line
## can be drawn.
static func draw(
	state: GameState,
	shown: Dictionary[StringName, bool],
	rng: RandomNumberGenerator,
) -> MarketNews:
	var content: NewsContent = state.market.news
	if content == null:
		return null
	var mood: NewsBands.Mood = NewsSelector.mood_band(state.market.last_mood)
	var move: NewsBands.Move = NewsSelector.move_band(last_index_move(state))
	var follow_ups: Array[MarketNews] = []
	var ordinary: Array[MarketNews] = []
	for line: MarketNews in content.market_news:
		if line.mood != NewsBands.Mood.ANY and line.mood != mood:
			continue
		if line.move != NewsBands.Move.ANY and line.move != move:
			continue
		if not requirements_met(line.requires, shown):
			continue
		if line.has_target() and hits(state, line).is_empty():
			continue
		if NewsSelector.is_waiting_follow_up(line, shown):
			follow_ups.append(line)
		else:
			ordinary.append(line)
	var pool: Array[MarketNews] = follow_ups
	if pool.is_empty():
		pool = ordinary
	if pool.is_empty():
		return null

	var counts: Dictionary[StringName, int] = drawn_before(state)
	var fewest: int = -1
	for line: MarketNews in pool:
		var drawn: int = counts.get(line.id, 0)
		if fewest < 0 or drawn < fewest:
			fewest = drawn
	var eligible: Array[MarketNews] = []
	for line: MarketNews in pool:
		if counts.get(line.id, 0) == fewest:
			eligible.append(line)
	return eligible[rng.randi_range(0, eligible.size() - 1)]


## Every company `news` hits, with the coins it adds to each: its company, or
## every living company of its industry. Empty for no news, news with no
## target, or a target with nobody left trading.
static func hits(state: GameState, news: MarketNews) -> Dictionary[StringName, int]:
	var found: Dictionary[StringName, int] = {}
	if news == null or not news.has_target():
		return found
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row == null or row.is_bankrupt:
			continue
		if company.id == news.target_company or company.profile.industry == news.target_industry:
			found[company.id] = news.amount
	return found


## True when every id in `required` has been shown.
static func requirements_met(required: Array[StringName], shown: Dictionary[StringName, bool]) -> bool:
	for id: StringName in required:
		if not shown.has(id):
			return false
	return true


## Last year's index move, in percent; 0 before year 1 has been played, which
## is a FLAT year for the news.
static func last_index_move(state: GameState) -> float:
	var last: EarningsYearResult = MarketReadouts.result_for_year(state, state.year - 1)
	if last == null:
		return 0.0
	return last.index_move_percent


## How many times each market news line was drawn in the years before the one
## `state` has just opened.
static func drawn_before(state: GameState) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for year: int in range(1, state.year):
		var result: EarningsYearResult = MarketReadouts.result_for_year(state, year)
		if result != null and result.market_news != null:
			counts[result.market_news.id] = counts.get(result.market_news.id, 0) + 1
	return counts
