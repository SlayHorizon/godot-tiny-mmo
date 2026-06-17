class_name DungeonReward
extends Resource
## The completion payout for a dungeon run: a gold amount (rolled in a range) plus
## a roll on a loot table. EVERY clearing player gets their OWN roll (the same
## participation-reward model as mob kills — co-op, no split). Attach it to the
## dungeon's final RoomNode (the boss room); RoomNode hands it to DungeonService on
## clear.
##
## Soft daily lockout: a player who already collected this reward less than
## lockout_hours ago gets nothing this run (but may still run it to help a group).
## Set lockout_hours = 0 to disable the lockout.

## Gold paid on completion, rolled uniformly in [gold_min, gold_max]. 0 = no gold.
@export var gold_min: int = 0
@export var gold_max: int = 0
## Loot table — each entry rolls independently (its own chance + amount range),
## exactly like a mob's loot. Curate it richer than trash drops.
@export var loot: Array[LootDrop] = []
## Soft lockout window in hours (rolling from the last collection). 0 = no lockout.
@export var lockout_hours: float = 24.0
