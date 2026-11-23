class_name WhisperRules
extends RefCounted
## How a whisper knows next year, and how far its source bends it
## (docs/stalkleheads-design.md §8.4, decisions.md D205). Pure rules; the
## choosing is `NewsSelector.whispers_for`.
##
## **The truth.** A whisper is about next year's outcome against expectations,
## in the five surprise bands. For a company: its growth from next year's kept
## growth roll (damped and retained exactly as `CompanyState.move_accounts`
## does), against what **this** year's regime leads one to expect
## (`NewsSelector.expected_growth`). A regime change shows up as a surprise,
## which is what a rumor should foreshadow. Its industry's year is left out: a
## company's whisper is about the company. For an industry: next year's swing,
## the part of its performance nobody can see coming (`IndustryState`); the
## carried-over trend and the market's lean are already in plain view.
##
## **The source.** Each whisper comes from one of five sources, equally likely.
## The source decides how far the outcome the whisper tells is from the truth:
## the true band, a band next to it, or one two or more away.


enum Source { ROCK_SOLID, CREDIBLE, HIT_OR_MISS, QUESTIONABLE, GOSSIP }

const ALL_SOURCES: Array[Source] = [
	Source.ROCK_SOLID,
	Source.CREDIBLE,
	Source.HIT_OR_MISS,
	Source.QUESTIONABLE,
	Source.GOSSIP,
]

## As shown beside a whisper. The owner's names (design §8.4).
const SOURCE_NAMES: Dictionary[Source, String] = {
	Source.ROCK_SOLID: "Rock Solid",
	Source.CREDIBLE: "Credible",
	Source.HIT_OR_MISS: "Hit-or-miss",
	Source.QUESTIONABLE: "Questionable",
	Source.GOSSIP: "Gossip",
}

## Percent chance of telling the true band (x) and a band one away (y). The
## rest is a band two or more away. Design §8.4's first proposal.
const ODDS: Dictionary[Source, Vector2i] = {
	Source.ROCK_SOLID: Vector2i(85, 15),
	Source.CREDIBLE: Vector2i(60, 35),
	Source.HIT_OR_MISS: Vector2i(40, 35),
	Source.QUESTIONABLE: Vector2i(30, 35),
	Source.GOSSIP: Vector2i(20, 30),
}

## The five outcomes a whisper can tell, worst first. Their order is what "one
## band away" means.
const OUTCOMES: Array[NewsBands.Surprise] = [
	NewsBands.Surprise.MUCH_WORSE,
	NewsBands.Surprise.WORSE,
	NewsBands.Surprise.AS_EXPECTED,
	NewsBands.Surprise.BETTER,
	NewsBands.Surprise.MUCH_BETTER,
]


## A company's real outcome next year: growth from `growth_roll`, against what
## `regime_now` leads one to expect.
static func company_outcome(
	regime_now: EarningsRegime.Value,
	growth_roll: int,
	payout_policy_percent: int,
	match_years: int,
) -> NewsBands.Surprise:
	var growth: float = CompanyState.own_growth(growth_roll, payout_policy_percent, match_years)
	var expected: float = NewsSelector.expected_growth(regime_now, payout_policy_percent, match_years)
	return NewsSelector.surprise_band(growth, expected)


## An industry's real outcome next year: its swing, in the same bands.
static func industry_outcome(swing: int) -> NewsBands.Surprise:
	return NewsSelector.surprise_band(float(swing), 0.0)


## One of the five sources, evenly. One draw.
static func roll_source(rng: RandomNumberGenerator) -> Source:
	return ALL_SOURCES[rng.randi_range(0, ALL_SOURCES.size() - 1)]


## The outcome a whisper from `source` tells, when the truth is `truth`. One
## draw when it tells the truth, two otherwise. One band off goes either way
## evenly, or the only way there is at an end; two or more off picks evenly
## among the bands that far away.
static func distort(
	truth: NewsBands.Surprise,
	source: Source,
	rng: RandomNumberGenerator,
) -> NewsBands.Surprise:
	var odds: Vector2i = ODDS[source]
	var roll: int = rng.randi_range(1, 100)
	if roll <= odds.x:
		return truth
	var near: bool = roll <= odds.x + odds.y
	var at: int = OUTCOMES.find(truth)
	var options: Array[NewsBands.Surprise] = []
	for index: int in OUTCOMES.size():
		var distance: int = absi(index - at)
		if (near and distance == 1) or (not near and distance >= 2):
			options.append(OUTCOMES[index])
	if options.is_empty():
		return truth
	return options[rng.randi_range(0, options.size() - 1)]


## How many bands apart two outcomes are: 0 when a whisper came true.
static func distance(a: NewsBands.Surprise, b: NewsBands.Surprise) -> int:
	return absi(OUTCOMES.find(a) - OUTCOMES.find(b))
