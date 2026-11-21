class_name IndustryDefinition
extends Resource
## One industry of StalkleHeads mode, as authored content. Saved as a .tres in
## src/data/industries/.
##
## Content rather than an enum because every industry is handled identically -
## roll its performance, apply it to its members through their beta - and only
## the data attached to it differs. Adding an industry is adding a file. See
## docs/stalkleheads-design.md §3.2.1.
##
## A company names its industry by this resource's `id`, and
## `ContentLibrary.validate()` refuses a company whose industry does not resolve,
## an industry with fewer than two members, and reports one with fewer than
## three (decisions.md D128).


## Stable key a `CompanyProfile.industry` refers to. Never the display name.
@export var id: StringName = &""

## The owner's names: Energy, Transportation, Financial Services, Consumer Goods,
## Technology, Food (docs/stalkleheads-design.md §14).
@export var display_name: String = ""


func _to_string() -> String:
	return "IndustryDefinition(%s)" % id
