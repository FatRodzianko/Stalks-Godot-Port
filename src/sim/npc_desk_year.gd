class_name NpcDeskYear
extends RefCounted
## What the NPC desk did in one year (§4 step 13): every trader's appetite,
## target and action, and the net shares traded that become next year's flow.
## Carried on `EarningsYearResult.desk`. Pure data.
##
## Keyed by trader id; `trader_ids` is the order they acted in.


## The traders, in the sorted order they acted.
var trader_ids: Array[StringName] = []

## Each trader's appetite draw this year, 70-130 (percent of its conviction).
var appetites: Dictionary[StringName, int] = {}

## What each trader's strategy picked, or `&""` when it found nothing to pick.
var targets: Dictionary[StringName, StringName] = {}

## What each trader did, for the chatter (`NpcTraderDefinition.Situation`).
var actions: Dictionary[StringName, NpcTraderDefinition.Situation] = {}

## Net shares the desk bought (positive) or sold (negative), by stalk id,
## short sales included. Only companies' entries reach the price, as flow; the
## bond and the index have no flow term.
var net_shares: Dictionary[StringName, int] = {}


func add_net(stalk_id: StringName, shares: int) -> void:
	if shares == 0:
		return
	net_shares[stalk_id] = net_shares.get(stalk_id, 0) + shares
