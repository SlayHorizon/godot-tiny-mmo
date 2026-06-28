class_name NPCResource
extends Resource
## A complete friendly, interactive NPC definition — the friendly-side mirror of
## EnemyTypeResource. One .tres holds who the NPC is (name, id, look), what it
## greets you with, and everything it can do (its interactions). The NPC node
## just points at this resource.

## Display name — shown as the greeting-dialogue title.
@export var npc_name: String = "Villager"
## Appearance — same kind of resource EnemyTypeResource.skin uses.
@export var skin: SpriteFrames
## Line shown above the options when greeted (Beedle/WoW-gossip style).
@export_multiline var greeting: String = "What can I do for you?"
## What this NPC can do. Add ShopInteraction / QuestInteraction entries inline.
@export var interactions: Array[NPCInteraction]


## Stable giver identity for quests, derived from this resource's FILENAME (e.g.
## duel_master.tres -> &"duel_master"). No hand-assigned id to collide: the file you
## already named IS the key. A quest references a giver by dragging in its NPCResource;
## the runtime matches on this slug (both sides resolve to the same .tres, same slug).
func giver_key() -> StringName:
	return StringName(resource_path.get_file().get_basename()) if not resource_path.is_empty() else &""
