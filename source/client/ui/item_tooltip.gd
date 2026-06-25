class_name ItemTooltip
## Builds an item's tooltip body: the auto-generated stat lines (from the item's real
## data via Item.stat_lines()) coloured by ROLE, above the hand-written flavor
## description. Shared by the inventory + shop detail panels so both read the same.
## The target label must be a RichTextLabel with bbcode_enabled.
##
## One colour PER STAT reads as rainbow noise, so lines are coloured by role instead:
## offense warm, defense green, resource/utility blue. Non-stat lines get their own
## cue: weapon type amber, level gate red, heal green / mana blue, charges muted.

const ROLE_COLOR: Dictionary = {
	&"offense": "e0875a",
	&"defense": "82c785",
	&"utility": "6fb0e0",
}
const STAT_ROLE: Dictionary = {
	&"ad": &"offense", &"ap": &"offense", &"ability_haste": &"offense",
	&"attack_speed": &"offense", &"attack_range": &"offense",
	&"crit_chance": &"offense", &"crit_damage": &"offense",
	&"health_max": &"defense", &"armor": &"defense", &"mr": &"defense",
	&"mana_max": &"utility", &"mana_regen": &"utility", &"move_speed": &"utility",
}
const WEAPON_COLOR: String = "e0c070"  ## amber — weapon type + power line
const LEVEL_COLOR: String = "d98080"   ## red — level gate
const HEAL_COLOR: String = "82c785"
const MANA_COLOR: String = "6fb0e0"
const MUTED_COLOR: String = "9aa0aa"   ## charges and the like
const DEFAULT_COLOR: String = "c8c8d0" ## any stat without a role mapping


static func body(item: Item) -> String:
	if item == null:
		return ""
	var sections: PackedStringArray = PackedStringArray()
	var stat_block: PackedStringArray = PackedStringArray()
	for entry: Dictionary in item.stat_lines():
		stat_block.append("[color=#%s]%s[/color]" % [_entry_color(entry), str(entry.get("text", ""))])
	if not stat_block.is_empty():
		sections.append("\n".join(stat_block))
	var flavor: String = item.description.strip_edges()
	if not flavor.is_empty():
		sections.append(flavor)
	return "\n\n".join(sections)


static func _entry_color(entry: Dictionary) -> String:
	if entry.has("stat"):
		return ROLE_COLOR.get(STAT_ROLE.get(entry["stat"], &""), DEFAULT_COLOR)
	match StringName(entry.get("kind", &"")):
		&"weapon": return WEAPON_COLOR
		&"level": return LEVEL_COLOR
		&"heal": return HEAL_COLOR
		&"mana": return MANA_COLOR
		&"charges": return MUTED_COLOR
	return DEFAULT_COLOR
