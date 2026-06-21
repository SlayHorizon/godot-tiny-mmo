class_name MenuInteraction
extends NPCInteraction
## Generic NPC capability: open ANY client menu by name. Drop one into an NPC's `interactions`
## array and set `menu` to the menu's folder name (it auto-loads from
## source/client/ui/menus/<menu>/<menu>_menu.tscn — the same convention the HUD uses), plus a
## label. Selecting the option routes to ClientState.open_menu_requested(menu, arg).
##
## Use this for the simple "open this panel" case — e.g. a dungeon NPC that opens the dungeon-exit
## confirm (menu = &"dungeon_exit", label = "Leave dungeon"). Menus that need server-side data
## wiring (shop, quests, wardrobe) have their OWN interaction; this is the plain open-a-menu one.


## Folder name of the menu to open (→ ui/menus/<menu>/<menu>_menu.tscn).
@export var menu: StringName = &""
## Optional string argument forwarded to the menu's open(arg). Leave empty for menus that don't
## take one (most simple panels, including dungeon_exit).
@export var arg: String = ""


func menu_entry(_npc: Node) -> Dictionary:
	if menu.is_empty():
		return {}
	var entry: Dictionary = {
		"label": _label_or("Open"),
		"icon": _icon_or(""),
		"menu": menu,
		"arg": null,
	}
	if not arg.is_empty():
		entry["arg"] = arg # most simple menus (incl. dungeon_exit) ignore the arg → stays null
	return entry
