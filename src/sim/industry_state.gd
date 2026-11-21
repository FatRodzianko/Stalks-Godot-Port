class_name IndustryState
extends RefCounted
## The live state of one industry during a StalkleHeads match, and the yearly
## roll that moves it. See docs/stalkleheads-design.md §3.4.
##
## Pairs with an immutable `IndustryDefinition`, as `StalkState` pairs with a
## `StalkDefinition`. Pure data and rules - no nodes, no signals.
##
## The roll is persistent: 40% of last year's performance carries into this
## year's, so a sector trend runs for several years and a player can see it
## coming. It also leans slightly with last year's market (the sentiment tilt).


## Each year's own swing, in percent: `randi_range(-15, 15)`.
const SWING: int = 15

## Share of last year's performance carried into this year's.
const PERSISTENCE: float = 0.40

## How much of last year's market move (sentiment) leans into every industry.
## Deliberately tiny, so "the market is up but oil is down" stays common.
const SENTIMENT_TILT: float = 0.10

## Performance is clamped to this, either way, in percent.
const LIMIT: float = 30.0

## Turns of multiple per point of performance: a +20% sector adds 1.2 turns.
const STANDING_GAIN: float = 0.06


var definition: IndustryDefinition

## This year's performance in percent, -30 to +30. Zero before the first roll.
var performance: float = 0.0


var id: StringName:
	get:
		return definition.id if definition != null else &""


func _init(industry_definition: IndustryDefinition) -> void:
	definition = industry_definition


## What the market will pay for this industry's earnings this year, in turns of
## multiple. A readout of `performance`, not separately stored.
func standing() -> float:
	return standing_for(performance)


## Rolls this year's performance from last year's and last year's sentiment.
## Exactly one draw from `rng`.
func advance(sentiment: float, rng: RandomNumberGenerator) -> void:
	performance = next_performance(performance, sentiment, rng)


static func standing_for(industry_performance: float) -> float:
	return industry_performance * STANDING_GAIN


## `clamp(roll + last * 0.40 + sentiment * 0.10, -30, +30)`. One draw.
static func next_performance(
	last_performance: float,
	sentiment: float,
	rng: RandomNumberGenerator,
) -> float:
	var roll: int = rng.randi_range(-SWING, SWING)
	var carried: float = last_performance * PERSISTENCE
	var tilt: float = sentiment * SENTIMENT_TILT
	return clampf(float(roll) + carried + tilt, -LIMIT, LIMIT)


## Advances every industry, **in id order**, so the draws land in the same order
## on every machine whatever order the caller holds them in.
static func advance_all(
	industries: Array[IndustryState],
	sentiment: float,
	rng: RandomNumberGenerator,
) -> void:
	var ordered: Array[IndustryState] = industries.duplicate()
	ordered.sort_custom(_by_id)
	for industry: IndustryState in ordered:
		industry.advance(sentiment, rng)


static func _by_id(a: IndustryState, b: IndustryState) -> bool:
	return String(a.id) < String(b.id)


func _to_string() -> String:
	return "IndustryState(%s %+.1f%%)" % [id, performance]
