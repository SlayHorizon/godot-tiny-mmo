class_name QuestResource
extends Resource
## Editor-authored quest, registered as the "quests" content type (same workflow as
## shops/recipes): create instances in a data folder, run the TinyMMO plugin's Generate
## for content_name "quests", and each quest gets a registry id/slug baked into metadata
## so it resolves through ContentRegistryHub and travels over the network as a small id.

@export var quest_name: String
@export_multiline var description: String
## Steps to complete, in order of display (all must be met to turn in).
@export var objectives: Array[QuestObjective]

@export_group("Rewards")
@export var reward_xp: int
@export var reward_gold: int
@export var reward_items: Array[QuestReward]
@export_group("")


## Loads a quest by its registry id, or null if the content type isn't generated yet.
static func load_quest(quest_id: int) -> QuestResource:
	if ContentRegistryHub.registry_of(&"quests") == null:
		return null
	return ContentRegistryHub.load_by_id(&"quests", quest_id) as QuestResource
