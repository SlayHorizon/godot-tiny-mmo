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
@export_multiline var description: String
## &"offensive", &"defensive" or &"supportive" — pure UI grouping.
@export var branch: StringName = &"offensive"
## 1-3. Doubles as point cost AND ability weight (the weapon-capacity gate).
@export_range(1, 3) var tier: int = 1
@export var ability: AbilityResource
@export var passive_modifiers: Array[StatModifier]
