class_name CompanyProfile
extends Resource
## The fundamentals of one company in StalkleHeads mode, as authored content.
## Saved as a .tres in src/data/companies/.
##
## Kept beside `StalkDefinition` rather than added to it, so base-game content is
## untouched (docs/stalkleheads-design.md §10, decisions.md D128). For a company
## the base game already ships, `id` is that stalk's id; the eight companies the
## base game does not have exist only here until StalkleHeads content gets its own
## board rows (S3/S8).
##
## Nothing here changes during a match - that is `CompanyState`. The values come
## from the proposed profiles in docs/stalkleheads-design.md §3.2.4, which are
## placeholders with a rationale, not confirmed balance.


## Stable key. Equals the base game's stalk id where the company already exists.
@export var id: StringName = &""

@export var display_name: String = ""

## Board symbol. Placeholder companies use obviously temporary tickers (TRNA,
## TRNB, CONA, TECA, FODA) until the owner writes real ones (§3.2.3).
@export var ticker: StringName = &""

## The `IndustryDefinition.id` this company belongs to.
##
## Not `StalkDefinition.industry`: that field is reserved for this mode, but
## filling it in would edit base-game content files. See decisions.md D128.
@export var industry: StringName = &""

## What it earns a share in year 0. Times the base multiple of 12.5, this is
## what sets its opening price: the price is not separately authored.
@export var starting_earnings_per_share: float = 8.0

## Profit as a percentage of revenue at year 0. 12.0 everywhere for now, the
## STEADY target, since every company starts STEADY (decisions.md D129).
@export var starting_margin_percent: float = 12.0

## Divisor for earnings per share. Doubles on a split.
@export var shares_outstanding: int = 1000

## 0-100. Biases the regime roll toward better regimes. 50 is neutral.
@export_range(0, 100) var quality: int = 50

## How much of its industry's performance reaches its own revenue, in percent.
## 100 is one-for-one.
@export var industry_beta_percent: int = 100

## 0-100. Share of earnings paid as a dividend in a normal (STEADY) year. Paying
## more slows positive revenue growth. 35 is neutral. See §3.10a.
@export_range(0, 100) var payout_policy_percent: int = 35


func _to_string() -> String:
	return "CompanyProfile(%s)" % id
