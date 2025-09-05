class_name ConsumableBehavior
extends ItemBehavior


@export var base_effects: Array[GameplayEffect]
@export var category_cd_key: StringName = &"potion"
@export var shared_cooldown_ms: int = 1500

#func can_use(ctx, entity, inst): return ctx.cooldowns.can_use(entity.id, category_cd_key)
#func on_use(ctx, entity, inst) -> bool:
	#for e in base_effects: entity.asc.add_effect(e)
	#ctx.cooldowns.trigger(entity.id, category_cd_key, shared_cooldown_ms)
	#ctx.inventory.consume_one(inst)
	#return true
