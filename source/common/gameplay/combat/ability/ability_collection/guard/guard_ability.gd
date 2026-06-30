class_name GuardAbility
extends AbilityResource
## Instant SELF-BUFF defensive ability: raises the wielder's ARMOR for a few
## seconds and flashes a shield VFX on them. The Resolve branch's signature.
##
## Reuses [BuffService] (the timed-buff path potions use — auto-expires on the
## per-second status tick), so there is NO new combat code: just the buff plus a
## topic push that tells every client to show the shield on the caster (mirrors
## the channel.start push; InstanceClient._on_guard_cast spawns a SpriteEffect).
## SHIELD-as-absorb isn't wired into take_damage, so we buff ARMOR (mitigation).


## Flat ARMOR (physical mitigation) granted for [member buff_duration_s].
@export var armor_bonus: float = 50.0
## Flat MAGIC RESIST granted for the same window — so the cooldown braces against
## magic burst too, not just physical. 0 = armor only.
@export var mr_bonus: float = 0.0
@export var buff_duration_s: float = 6.0
## Shield animation shown on the caster (paladin guard-shield sheet). Sent by PATH
## in the push so the client loads it; the tint + scale let a higher tier reskin
## the same sheet without new art.
@export var shield_vfx: SpriteFrames
@export var vfx_modulate: Color = Color(1.0, 1.0, 1.0, 0.92)
@export var vfx_scale: float = 0.7
## Colour saturation of the shield flash (1.0 full, 0.0 grayscale) — the cheapest
## clearly-visible tier tell: a low-rank guard reads washed-out, a capstone vivid.
@export var vfx_saturation: float = 1.0


func use_ability(user: Entity, _direction: Vector2) -> void:
	# Server-authoritative: apply the buff, then tell every client to show the shield.
	if not GameMode.is_world_server() or user is not Player:
		return
	var caster: Player = user as Player
	BuffService.apply(caster, Stat.ARMOR, armor_bonus, buff_duration_s)
	if mr_bonus > 0.0:
		BuffService.apply(caster, Stat.MR, mr_bonus, buff_duration_s)
	if WorldServer.curr == null or caster.player_resource == null:
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"guard.cast", {
			"p": int(caster.player_resource.current_peer_id),
			"d": buff_duration_s,
			"fx": shield_vfx.resource_path if shield_vfx != null else "",
			"mod": vfx_modulate,
			"sc": vfx_scale,
			"sat": vfx_saturation,
		}),
		map.get_parent().name
	)


## Defensive amp shown in the mastery detail panel.
func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("+%s armor" % fmt_num(armor_bonus))
	if mr_bonus > 0.0:
		lines.append("+%s magic resist" % fmt_num(mr_bonus))
	lines.append("%ss" % fmt_num(buff_duration_s))
	return lines
