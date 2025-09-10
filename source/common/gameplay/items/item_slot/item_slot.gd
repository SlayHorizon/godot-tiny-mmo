class_name ItemSlot
extends Resource


# &"Weapon", &"Helmet", ...
## Should be constant, never changed like an unique identifier.
@export var key: StringName

## Can be translated, means to be used in UI.
@export var display_name: String

@export var unlock_rule: SlotUnlockRule

## Option icon for UI
@export var icon: Texture2D

## Avoid keeping runtime flag on a resource, may move it later.
var unlocked: bool = false


func is_unlocked_for(player: PlayerResource) -> bool:
	return unlock_rule and unlock_rule.is_unlocked(player)
