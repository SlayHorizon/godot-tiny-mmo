class_name Economy
## Currency helpers. Gold (and other currencies) are normal items flagged
## `is_currency`; the player's balance is the amount held in inventory. The default
## currency is the item with slug "gold" — create it in the editor and reindex items.


const GOLD_SLUG: StringName = &"gold"


## Registry id of the default currency (gold), or 0 if it hasn't been authored yet.
static func gold_id() -> int:
	if ContentRegistryHub.registry_of(&"items") == null:
		return 0
	return ContentRegistryHub.id_from_slug(&"items", GOLD_SLUG)
