class_name YearPipeline
extends RefCounted
## What `MatchAuthority` needs from a game mode's year: advance it, and hear
## about every trade.
##
## Two pipelines extend this: the base game's `YearResolver` and StalkleHeads'
## `EarningsYearResolver`. `MatchSetup` builds one of them when the match starts,
## and the authority never asks which it holds. That is how the mode is chosen
## once rather than with `if mode ==` through the code
## (docs/stalkleheads-design.md §10.2, decisions.md D171).
##
## **Why trades come here too.** In StalkleHeads a player's trade is an input to
## next year's price, through flow (design §3.10). In the base game it is not.
## Telling the pipeline about every trade, and letting the base game's ignore it,
## keeps that difference inside the pipelines, where the rest of each mode's
## rules already are.
##
## Pure, like everything in `src/sim`: no nodes, no signals.


## Advances `state` by one year and returns what happened. Every subclass
## overrides this; reaching this one is a bug.
func advance_year(_state: GameState, _rng: RandomNumberGenerator) -> YearResult:
	push_error("YearPipeline.advance_year is abstract; MatchSetup builds a real pipeline")
	return YearResult.new()


## A fresh match is about to start at year 0, with `rng` the match's own
## generator. Called once, by `LocalSession.build_authority`, before anybody
## sees the match; never on a match taken over (it is already open). Does
## nothing unless the mode draws ahead, which only StalkleHeads does
## (`EarningsYearResolver`, decisions.md D205).
func open_match(_state: GameState, _rng: RandomNumberGenerator) -> void:
	pass


## An accepted trade: `shares` positive for bought, negative for sold. Called by
## `MatchAuthority` after the trade is applied. Does nothing unless the mode's
## prices read trades, which only StalkleHeads' do.
func record_trade(_state: GameState, _stalk_id: StringName, _shares: int) -> void:
	pass
