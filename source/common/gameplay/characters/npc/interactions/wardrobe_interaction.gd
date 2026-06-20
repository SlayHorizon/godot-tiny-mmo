class_name WardrobeInteraction
extends NPCInteraction
## NPC capability: open the skin wardrobe — browse, buy (50g) and equip player skins. The
## purchase/equip themselves are the server-authoritative wardrobe.buy / wardrobe.equip
## handlers; this just routes the dialogue option to the wardrobe menu. Drop a
## WardrobeInteraction into any NPC's `interactions` array to make it a wardrobe vendor.


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Wardrobe"),
		"icon": _icon_or(""),
		"menu": &"wardrobe",
		"arg": null,
	}
