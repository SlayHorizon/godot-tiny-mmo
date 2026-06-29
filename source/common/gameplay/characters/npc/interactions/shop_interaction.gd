class_name ShopInteraction
extends NPCInteraction
## NPC capability: opens a shop. The catalog renders client-side from the
## ShopResource carried in the menu arg; the server authorizes purchases by
## resolving the shop from the player's current map, keyed by the owning NPC's
## giver_key() (its NPCResource filename slug) — so an inline shop on an NPC
## works with no registry id and no plugin index, the same way quests resolve.

@export var shop: ShopResource


func menu_entry(npc: Node) -> Dictionary:
	var owner: NPC = npc as NPC
	if shop == null or owner == null:
		return {}
	# The ShopResource rides in the arg so the client renders the catalog
	# directly (no load-by-id); the key authorizes purchases server-side.
	return {
		"label": _label_or("Shop"),
		"icon": _icon_or(""),
		"menu": &"shop",
		"arg": {"key": String(owner.giver_key()), "shop": shop},
	}


func register(map: Map, npc: Node) -> void:
	var owner: NPC = npc as NPC
	if shop and owner != null:
		var key: StringName = owner.giver_key()
		# Shops key on the NPCResource slug, so two NPCs sharing one NPCResource collide and the
		# last write silently wins — a town's second merchant would mis-resolve. Crafting is immune
		# (node-name keyed). Warn the author rather than fail silently.
		if map.shops.has(key) and map.shops[key] != shop:
			push_warning("ShopInteraction: duplicate giver_key '%s' — two NPCs share an NPCResource with different shops; one will be unreachable. Give them distinct NPCResource files." % key)
		map.shops[key] = shop
