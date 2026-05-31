class_name QuestResource
extends Resource
## Editor-authored quest, registered as the "quests" content type (same workflow as
## shops/recipes): create instances in a data folder, run the TinyMMO plugin's Generate
## for content_name "quests", and each quest gets a registry id/slug baked into metadata
## so it resolves through ContentRegistryHub and travels over the network as a small id.

## How many objectives must be completed for the quest to be turnable.
## ALL = every objective; ANY = a single objective is enough (used for "pick one
## NPC to introduce yourself to"-style quests where the player chooses a path).
enum Completion { ALL, ANY }

@export var quest_name: String
@export_multiline var description: String
## Steps to complete, in display order.
@export var objectives: Array[QuestObjective]
## How many objectives need to be done. Defaults to ALL (classic AND behavior).
@export var completion: Completion = Completion.ALL
## When true, the quest turns in instantly the moment its objectives are met —
## no walk-back-to-the-giver step. Reserved for "self-evident" quests like the
## welcome tour where forcing a return trip is just friction.
@export var auto_complete: bool = false

@export_group("Availability")
## Player level required to see this quest at the giver. 0 = no level requirement.
## Used by the milestone notification system: when a player levels up to N, any
## quest with min_level == N triggers an unlock notification.
@export var min_level: int = 0
## Optional system-channel message pushed to the player when min_level is reached,
## styled to look like it's from the relevant NPC. Empty = no notification (the
## quest just becomes available silently). Include the NPC name in brackets at the
## start of the text so it reads like a personal message in chat, e.g.
##   "[Duel Master] I've heard you've been honing your blade. Find me at the arena."
@export_multiline var unlock_message: String

@export_group("Delivery")
## If set, only the QuestGiver with this giver_id can turn this quest in. Used
## for delivery quests: NPC A offers it, NPC B accepts the turn-in. When 0
## (default) the same giver who offered the quest also turns it in.
@export var turn_in_giver_id: int = 0
## Optional item granted to the player when they accept the quest (a sealed
## letter, a parcel, etc.). The item is consumed on turn-in. Use sparingly:
## quest items have no vendor utility and just clutter the bag.
@export var grant_on_accept: Item

@export_group("Rewards")
@export var reward_xp: int
@export var reward_gold: int
@export var reward_items: Array[QuestReward]
## Vanity title granted on turn-in. Empty = no title. Added to the player's
## titles_unlocked list; auto-equipped if no other title is active.
@export var grant_title: String
@export_group("")


## Loads a quest by its registry id, or null if the content type isn't generated yet.
static func load_quest(quest_id: int) -> QuestResource:
	if ContentRegistryHub.registry_of(&"quests") == null:
		return null
	return ContentRegistryHub.load_by_id(&"quests", quest_id) as QuestResource
