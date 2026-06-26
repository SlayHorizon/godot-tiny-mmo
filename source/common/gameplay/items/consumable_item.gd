class_name ConsumableItem
extends Item


## Flat health restored on use. 0 = this consumable doesn't heal.
## Prototype-simple effect; can later move to a data-driven GameplayEffect list.
@export var heal_amount: int
## Flat mana restored on use. 0 = none.
@export var mana_amount: int
## Optional timed buff (via BuffService): the stat to raise (&"mana_regen",
## &"move_speed", ...). Empty = no buff.
@export var buff_stat: StringName = &""
@export var buff_amount: float = 0.0
@export var buff_duration_s: float = 0.0
## Drink cooldown in ms, SHARED across every item with the same cooldown_category, so
## you can't chain-chug a heal then a mana potion. Recommended 5000-7000 for a real
## gate. Persists across re-equip (banked on Character.ability_cooldowns, like a weapon
## ability's cooldown); resets on logout.
@export var shared_cooldown_ms: int = 6000
## Items sharing this category share ONE drink cooldown. Give a type its own category
## (e.g. &"mana_potion") to make it cool down independently of other potions.
@export var cooldown_category: StringName = &"potion"
## Server roots the drinker in place for this long on use, so you can't run
## and chug at the same time (a sip animation slots in here later). 0 = no
## freeze.
@export var use_freeze_ms: int = 900
## initial charges per single copy if 1 can use the potion one time, if 2 can use the potion 2 times for example.
@export var default_charges: int = 1


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if heal_amount > 0:
		lines.append({"text": "Restores %d health" % heal_amount, "kind": &"heal"})
	if mana_amount > 0:
		lines.append({"text": "Restores %d mana" % mana_amount, "kind": &"mana"})
	if buff_stat != &"" and not is_zero_approx(buff_amount) and buff_duration_s > 0.0:
		var number: String = ("%+d" % int(buff_amount)) if is_equal_approx(buff_amount, roundf(buff_amount)) else ("%+.1f" % buff_amount)
		var duration: String = ("%dm" % int(buff_duration_s / 60.0)) if buff_duration_s >= 60.0 else ("%ds" % int(buff_duration_s))
		lines.append({"text": "%s %s for %s" % [number, Stat.display_name(buff_stat), duration], "stat": StringName(buff_stat)})
	if default_charges > 1:
		lines.append({"text": "%d charges" % default_charges, "kind": &"charges"})
	return lines


func can_use(character: Character) -> bool:
	if character == null:
		return false
	if heal_amount > 0 and character.stats_component.get_stat(Stat.HEALTH) < character.stats_component.get_stat(Stat.HEALTH_MAX):
		return true
	if mana_amount > 0 and character.stats_component.get_stat(Stat.MANA) < character.stats_component.get_stat(Stat.MANA_MAX):
		return true
	# Buff potions always drinkable — re-drinking refreshes the duration.
	if buff_stat != &"" and buff_amount != 0.0 and buff_duration_s > 0.0:
		return true
	return false


## Applies the consumable's effect. Returns true if something actually happened
## (so the caller knows whether to spend a charge / remove it from the bag).
func on_use(character: Character) -> void:
	var stats_component: StatsComponent = character.stats_component
	if heal_amount > 0:
		var healed: float = minf(
			stats_component.get_stat(Stat.HEALTH) + heal_amount,
			stats_component.get_stat(Stat.HEALTH_MAX)
		)
		stats_component.set_stat(Stat.HEALTH, healed)
	if mana_amount > 0:
		var refilled: float = minf(
			stats_component.get_stat(Stat.MANA) + mana_amount,
			stats_component.get_stat(Stat.MANA_MAX)
		)
		stats_component.set_stat(Stat.MANA, refilled)
	if buff_stat != &"" and buff_amount != 0.0 and buff_duration_s > 0.0 and character is Player:
		BuffService.apply(character as Player, buff_stat, buff_amount, buff_duration_s)
	if character is Player:
		Inventory.remove_one_by_id(character.player_resource.inventory, get_meta(&"id"))


## A potion is just "an item that carries a DRINK action". The generic hand mount
## (Item.mount_in_hand) does the rig + the sprite; here we only build the drink — fresh
## per mount (so it owns its own cooldown state), tuned from this item (the shared
## cooldown + the sip-root). It rides the SPECIAL (Q) slot, not left-click, so stray
## clicks can't waste it. Any other item holds the same way: a weapon brings its own
## rig, a material brings no action at all.
func equip(character: Character) -> void:
	var node: Weapon = mount_in_hand(character)
	if node == null:
		return
	var consume: ConsumeAbility = ConsumeAbility.new()
	consume.consumable = self
	consume.name = "Drink"
	consume.icon = item_icon # the ability-bar tile shows the potion itself
	consume.cooldown = float(shared_cooldown_ms) / 1000.0
	consume.root_s = float(use_freeze_ms) / 1000.0
	# Category-shared, character-persistent cooldown — the SAME mechanism weapon abilities
	# use (Character.ability_cooldowns), keyed by cooldown_category instead of the ability
	# path. So every potion in a category shares ONE cooldown that survives unequip+re-equip
	# (no reset exploit) and blocks across types (no heal->mana chug). _stamp_cooldown banks
	# it on drink; restoring it here on mount keeps the bar's cooldown sweep correct too.
	var cd_key: String = "consumable:" + str(cooldown_category)
	consume.set_meta(&"cooldown_key", cd_key)
	if character.ability_cooldowns.has(cd_key):
		consume.last_action_time = character.ability_cooldowns[cd_key]
	node.set_special_ability(consume)


func unequip(character: Character) -> void:
	unmount_hand(character)
