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

## How many of [member requires_quests] must be turned in before this quest is
## available. ALL = classic chain link; ANY = "finish one of several paths".
enum RequiresMode { ALL, ANY }

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
## Optional system-channel message pushed to the player the moment the quest
## becomes ACCEPTABLE (all gates open: min_level reached AND prerequisites
## satisfied — see LevelMilestoneService), styled to look like it's from the
## relevant NPC. Empty = no notification (the quest just becomes available
## silently). Include the NPC name in brackets at the start of the text so it
## reads like a personal message in chat, e.g.
##   "[Duel Master] I've heard you've been honing your blade. Find me at the arena."
@export_multiline var unlock_message: String
## Prior quests gating this one (drag in their QuestResources). Empty = no quest
## prerequisite. Unmet prerequisites show the quest LOCKED at its giver (name +
## unlock conditions, no Accept — owner call 2026-07-04 after playtest; hiding
## made chain pops invisible) and hard-block accept server-side. min_level is
## always a separate AND on top, so "completed X AND reached level N" is both
## fields together.
@export var requires_quests: Array[QuestResource]
## ALL = every quest in requires_quests must be turned in; ANY = one is enough.
@export var requires_mode: RequiresMode = RequiresMode.ALL
## Character flag that must be set on the player (PlayerResource.character_flags),
## ANDed on top of requires_quests + min_level. This is the seam the v1 wardstone
## key-gate plugs into — nothing sets flags yet. Empty = no flag requirement.
@export var requires_flag: StringName

@export_group("Delivery")
## If set, only THIS NPC turns the quest in (drag in its NPCResource). For delivery
## quests: NPC A offers it, NPC B accepts the turn-in. Leave EMPTY (default) when the
## same NPC that offers it also turns it in (the runtime resolves to the offerer).
@export var turn_in_giver: NPCResource
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


## The slug of the NPC this quest turns in to, or &"" when it turns in at whoever
## offered it (turn_in_giver left empty). The turn-in handlers compare against this.
func turn_in_giver_key() -> StringName:
	return turn_in_giver.giver_key() if turn_in_giver else &""


## True when this quest's prerequisite gates are open for [param player]:
## requires_quests turned in (per requires_mode) AND requires_flag set.
## min_level is deliberately NOT checked here — it stays its own gate so
## callers can tell "too low" apart from "chain not done".
func prerequisites_met(player: PlayerResource) -> bool:
	if not requires_flag.is_empty() and not player.has_character_flag(requires_flag):
		return false
	if requires_quests.is_empty():
		return true
	var any_met: bool = false
	for prereq: QuestResource in requires_quests:
		var done: bool = false
		if prereq != null:
			# id 0 = the prereq isn't Generated yet (broken/stale data) —
			# treat as unmet so the problem surfaces in testing, not silently.
			var prereq_id: int = int(prereq.get_meta(&"id", 0))
			done = prereq_id > 0 and player.quest_state(prereq_id) == &"turned_in"
		if done:
			any_met = true
		elif requires_mode == RequiresMode.ALL:
			return false
	return any_met
