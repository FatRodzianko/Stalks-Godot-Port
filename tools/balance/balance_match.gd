extends RefCounted
## One seeded StalkleHeads match played by the strategy players of
## docs/stalkleheads-design.md §2.1, for the balance tool (S2) and its GUT smoke
## test. The market is `stand_in_year.gd` over the real `src/sim/` classes.
##
## Each strategy is one player with the default starting cash. At the start of
## every year it sells everything and splits its cash equally across its
## targets, at last year's closing prices (HOLD trades in year 1 only). That is
## the probe's trading loop (Appendix A): it rebalances completely at no cost,
## which no real player does and which exaggerates every edge.
##
## Two random streams (decisions.md D145): the market draws from one seeded with
## the match seed, and only RANDOM draws from the other, so choosing which
## strategies to run never changes the market they are measured on.


const StandInYear := preload("res://tools/balance/stand_in_year.gd")

## Every strategy, in the order the report prints them. §2.1 also has FOLLOW
## (copy the best NPC trader), which needs the desk and arrives with S4.
const ALL_STRATEGIES: Array[StringName] = [
	&"HOLD", &"LOWPE", &"HIGHPE", &"TREND", &"MOMENTUM",
	&"CONTRARIAN", &"INCOME", &"RANDOM", &"BOND",
]

## How many companies a picking strategy holds.
const PICKS: int = 3

const BOND_ID: StringName = &"berry_bonds"


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


## One player's account.
class Book:
	extends RefCounted
	var cash: int = 0
	var held: Dictionary[StringName, int] = {}


## Plays one match. `strategies` is a subset of ALL_STRATEGIES. With
## `player_flow` the players' own net buying feeds the flow term, as §3.10 says
## it should once a desk exists; off by default, because the comparison target
## is the probe's no-flow run.
static func play(
	library: ContentLibrary,
	match_seed: int,
	years: int,
	strategies: Array[StringName],
	player_flow: bool = false,
) -> Result:
	var market_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	market_rng.seed = match_seed
	var player_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	player_rng.seed = hash("balance players %d" % match_seed)

	var bond: StalkDefinition = library.stalk_by_id(BOND_ID)
	var bond_price: int = bond.starting_price
	var bond_coupon: int = bond.bull_dividend
	var starting_cash: int = GameSettings.new().starting_cash

	var market: StandInYear = StandInYear.new(library, years)
	var books: Dictionary[StringName, Book] = {}
	for strategy: StringName in strategies:
		var book: Book = Book.new()
		book.cash = starting_cash
		books[strategy] = book

	var result: Result = Result.new()
	result.years = years
	for year: int in range(1, years + 1):
		var net_shares: Dictionary[StringName, int] = {}
		for strategy: StringName in strategies:
			if strategy == &"HOLD" and year > 1:
				continue
			var targets: Array[StringName] = _targets(strategy, market, player_rng)
			if targets.is_empty():
				continue
			_rebalance(books[strategy], targets, market, bond_price, net_shares)

		var traded: Dictionary[StringName, int] = {}
		if player_flow:
			traded = net_shares
		var outcome: StandInYear.Outcome = market.resolve_year(traded, market_rng)

		for book: Book in books.values():
			for company_id: StringName in outcome.bankrupt_ids:
				book.held[company_id] = 0
			for company_id: StringName in outcome.split_ids:
				book.held[company_id] = book.held.get(company_id, 0) * 2
			for asset_id: StringName in book.held:
				var amount: int = book.held[asset_id]
				if amount <= 0:
					continue
				if asset_id == BOND_ID:
					book.cash += amount * bond_coupon
				else:
					book.cash += amount * int(market.dividend[asset_id])

		result.splits += outcome.split_ids.size()
		result.bankruptcies += outcome.bankrupt_ids.size()
		if outcome.mood == MarketMood.Value.BULL:
			result.bull_years += 1
		result.moves.append_array(outcome.abs_moves)

	for strategy: StringName in strategies:
		result.net_worth[strategy] = _worth(books[strategy], market, bond_price)
	for company: CompanyState in market.companies:
		result.final_prices.append(company.price)
	return result


## Sell everything, then spend the cash equally across `targets`.
static func _rebalance(
	book: Book,
	targets: Array[StringName],
	market: StandInYear,
	bond_price: int,
	net_shares: Dictionary[StringName, int],
) -> void:
	for asset_id: StringName in book.held:
		var amount: int = book.held[asset_id]
		if amount <= 0:
			continue
		var price: int = _price_of(asset_id, market, bond_price)
		if price > 0:
			book.cash += amount * price
			net_shares[asset_id] = net_shares.get(asset_id, 0) - amount
		book.held[asset_id] = 0

	var each: int = book.cash / targets.size()
	for asset_id: StringName in targets:
		var price: int = _price_of(asset_id, market, bond_price)
		if price <= 0:
			continue
		var shares: int = each / price
		if shares <= 0:
			continue
		book.cash -= shares * price
		book.held[asset_id] = book.held.get(asset_id, 0) + shares
		net_shares[asset_id] = net_shares.get(asset_id, 0) + shares


## What a strategy wants to hold this year, read from last year's published
## state. Ties break by company id, so every run is reproducible.
static func _targets(
	strategy: StringName,
	market: StandInYear,
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
				var delta: float = float(market.last_delta[company.id])
				if strategy == &"MOMENTUM":
					delta = -delta
				scored.append([delta, company.id])
			return _lowest(scored)
		&"INCOME":
			var scored: Array[Array] = []
			for company: CompanyState in alive:
				if company.price <= 0:
					continue
				var paid: float = float(market.dividend[company.id])
				scored.append([-paid / float(company.price), company.id])
			return _lowest(scored)
	push_error("Unknown strategy %s" % strategy)
	return ids


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


static func _price_of(asset_id: StringName, market: StandInYear, bond_price: int) -> int:
	if asset_id == BOND_ID:
		return bond_price
	var company: CompanyState = market.company_by_id(asset_id)
	return company.price


static func _worth(book: Book, market: StandInYear, bond_price: int) -> int:
	var total: int = book.cash
	for asset_id: StringName in book.held:
		var amount: int = book.held[asset_id]
		if amount > 0:
			total += amount * _price_of(asset_id, market, bond_price)
	return total
