class_name PlayerSkins
## The curated set of player-wearable skins — slugs into the `sprites` ContentRegistry.
## Shared by character creation (gateway), the wardrobe shop, and the server's buy/equip
## validation, so all three agree on what counts as a legit player skin. Add a slug here to
## offer a new look everywhere at once. (Enemies/NPCs also live in `sprites`, so the
## wardrobe lists THIS curated set, not the whole registry.)

## Skin slugs, in display order. Each resolves to a `sprites` registry id via id_from_slug.
const SLUGS: PackedStringArray = [
	"knight", "rogue", "wizard", "bandit_fighter", "bandit_scout",
	"bandit_sorcerer", "bandit_tracker", "goblin",
]


## All player-skin ids resolved from SLUGS (order preserved), skipping any slug the registry
## can't resolve. Used by the wardrobe to list every buyable skin.
static func ids() -> Array[int]:
	var out: Array[int] = []
	for slug: String in SLUGS:
		var id: int = ContentRegistryHub.id_from_slug(&"sprites", StringName(slug))
		if id > 0:
			out.append(id)
	return out


## True when [param skin_id] is one of the curated player skins. Server-side anti-cheat:
## stops a client buying/equipping an arbitrary sprite id (e.g. an enemy's).
static func is_valid(skin_id: int) -> bool:
	return skin_id > 0 and ids().has(skin_id)


## Display name for a skin id ("knight" -> "Knight"); empty string if not a player skin.
static func display_name(skin_id: int) -> String:
	for slug: String in SLUGS:
		if ContentRegistryHub.id_from_slug(&"sprites", StringName(slug)) == skin_id:
			return slug.capitalize()
	return ""
