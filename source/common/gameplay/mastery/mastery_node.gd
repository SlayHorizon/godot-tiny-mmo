class_name MasteryNode
extends Resource
## One unlockable entry in a weapon category's mastery tree. Two kinds:
## - ABILITY node: [member ability] is set — owning it lets the player mount
##   that ability in the weapon's special slot (their loadout pick).
## - PASSIVE node: [member ability] is null — its [member passive_modifiers]
##   apply to live stats while a weapon of the tree's category is wielded.
## Point cost and special-slot weight both equal [member tier] (one number,
## no drift — see docs/mastery.md).


@export var id: StringName
@export var node_name: String
## Tile art for the skill-tree node. Falls back to the ability's own icon
## (ABILITY nodes carry one), then the node's initials — so missing art degrades
## gracefully. Drop a ~26x26 pixel icon here; PixelIcon integer-scales it crisp.
@export var icon: Texture2D
@export_multiline var description: String
## &"offensive", &"defensive" or &"supportive" — pure UI grouping.
@export var branch: StringName = &"offensive"
## 1-4. Doubles as point cost AND ability weight (the weapon-capacity gate).
## Note: weapon capacity caps at 3 today, so a tier-4 ability is un-equippable
## until the capacity system extends — it still displays in the tree.
@export_range(1, 4) var tier: int = 1
@export var ability: AbilityResource
@export var passive_modifiers: Array[StatModifier]
## Passives are PERMANENT once learned — they apply no matter which weapon you wield, so
## investing in every tree reinforces your character (and your HP/stats never jump on a
## mid-fight weapon swap). Set this TRUE only for a passive that's a weapon-specific gimmick
## and would be wrong on other weapons — e.g. hammer Executioner's "+damage vs low-HP" should
## buff the hammer, not every weapon. Weapon-bound passives apply only while that weapon is held.
@export var weapon_bound: bool = false

## Upgrade chain: the id of the lower-tier node this one REPLACES (empty = a
## standalone ability or the chain's root). A "signature move" is a chain — you
## must own the lower tier to learn the next, you can't equip two tiers of the
## same chain, and an equipped slot always resolves to your HIGHEST owned tier.
## See docs/mastery.md and MasteryService chain helpers.
@export var upgrades: StringName


## Name to show in the tree/detail panel. ABILITY nodes can leave [member
## node_name] empty and inherit the ability's own name — one source of truth, no
## re-typing the same name in two places. PASSIVE nodes (no ability) set it here.
func display_name() -> String:
	if not node_name.is_empty():
		return node_name
	if ability != null:
		return ability.name
	return ""
