class_name ToolItem
extends WeaponItem
## A gathering tool (pickaxe, axe, fishing rod, ...). Equips in the weapon slot like
## any weapon (so it reuses the whole equip path), but is identified by its tool_type
## so gathering nodes can require a matching tool. Carries no special combat behavior
## by default — it can still define hand scenes for a visible in-hand tool.

## What this tool can gather, e.g. &"pickaxe", &"axe". A MineableNode requires a
## matching tool_type to be worked.
@export var tool_type: StringName
