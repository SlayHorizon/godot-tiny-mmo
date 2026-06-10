class_name NPCResource
extends Resource
## A complete friendly, interactive NPC definition — the friendly-side mirror of
## EnemyTypeResource. One .tres holds who the NPC is (name, id, look), what it
## greets you with, and everything it can do (its interactions). The NPC node
## just points at this resource.

## Stable identity. Quest interactions resolve by this — it's the giver id, so a
## delivery quest's turn_in_giver_id points at it. Leave 0 for an NPC with no quests.
@export var npc_id: int = 0
## Display name — shown as the greeting-dialogue title.
@export var npc_name: String = "Villager"
## Appearance — same kind of resource EnemyTypeResource.skin uses.
@export var skin: SpriteFrames
## Line shown above the options when greeted (Beedle/WoW-gossip style).
@export_multiline var greeting: String = "What can I do for you?"
## What this NPC can do. Add ShopInteraction / QuestInteraction entries inline.
@export var interactions: Array[NPCInteraction]
