class_name NpcChatter
extends Resource
## One line of NPC chatter: what a desk trader says about what it did in a
## year, shown under its name on the Company tab and on the side panel's DESK
## page (docs/stalkleheads-design.md §8.1). At most one per trader a year.
##
## **Two places hold chatter.** Each trader's own `.tres` in src/data/traders/
## has one line per situation (`chatter_bought` and so on); `NewsContent`
## turns those into `NpcChatter` lines with `npc_id` set. A line in a
## `NewsBook` can also be written for every trader of a strategy, with
## `npc_id` empty. A trader's own line is preferred to its strategy's.
##
## **The words are the owner's.** The trader files hold placeholders that name
## their slot - `NPC CHATTER: value trader 1, bought`.


## Unique across every news line. Never shown.
@export var id: StringName = &""

## The `NpcTraderDefinition.id` this is for, or empty for every trader of
## `strategy`.
@export var npc_id: StringName = &""

## Read only when `npc_id` is empty.
@export var strategy: NpcStrategy.Value = NpcStrategy.Value.VALUE

@export var situation: NpcTraderDefinition.Situation = NpcTraderDefinition.Situation.BOUGHT

## May contain `{trader}`, the trader's display name, and `{company}`, the
## company it picked (empty when it picked nothing).
@export_multiline var text: String = ""
