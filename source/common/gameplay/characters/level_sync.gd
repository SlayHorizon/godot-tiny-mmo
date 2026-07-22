class_name LevelSync
## FFXIV-style level sync: temporarily rebuild a player's combat stats AS IF
## they were [sync_level], preserving their build's SHAPE (attribute spread
## rescaled to the synced budget) and their equipment's contribution, then
## restore on demand. A reusable service, not a spar feature — normalized spar
## uses it first; capped hardcore dungeons / events can reuse it later
## (owner design, 2026-07-19).
##
## Mirrors the spawn-time stat build in instance_server.instantiate_player:
## BASE_STATS + HEALTH_PER_LEVEL x (level-1) + attr_to_stats(attributes),
## with equipment riding on top. Equipment's contribution is preserved as the
## DELTA between live stats and PlayerResource.stats (the spawn-time
## base+attributes snapshot) — gear itself is bracket-gated by the caller.

## Meta key on the Player node holding the pre-sync stat snapshot.
const META_SNAPSHOT: StringName = &"level_sync_snapshot"


## Total attribute points a level-[param level] character has ever earned
## (ATTRIBUTE_POINTS_PER_LEVEL at creation + the same per level-up).
static func attribute_budget(level: int) -> int:
	return PlayerResource.ATTRIBUTE_POINTS_PER_LEVEL * maxi(level, 1)


## Sync [param player] to [param sync_level]. Idempotent — a second apply
## without a restore is a no-op. Ends with HEALTH full at the synced pool.
static func apply(player: Player, sync_level: int) -> void:
	if player == null or player.has_meta(META_SNAPSHOT):
		return
	var res: PlayerResource = player.player_resource
	var comp: StatsComponent = player.stats_component
	var snapshot: Dictionary[StringName, float] = comp.stats.values.duplicate()
	player.set_meta(META_SNAPSHOT, snapshot)

	# Synced baseline: BASE_STATS at sync_level + the rescaled attribute spread.
	var synced: Dictionary[StringName, float]
	synced.assign(PlayerResource.BASE_STATS)
	synced[Stat.HEALTH_MAX] += PlayerResource.HEALTH_PER_LEVEL * (sync_level - 1)
	var from_attrs: Dictionary[StringName, float] = AttributeMap.attr_to_stats(
		scaled_attributes(res.attributes, attribute_budget(sync_level)))
	for stat_name: StringName in from_attrs:
		synced[stat_name] = synced.get(stat_name, 0.0) + from_attrs[stat_name]

	# Final = synced baseline + whatever ISN'T baseline right now (equipment
	# modifiers etc.), i.e. live minus the spawn-time base+attrs snapshot.
	# HEALTH is set explicitly at the end instead.
	var final_stats: Dictionary[StringName, float] = synced.duplicate()
	for stat_name: StringName in snapshot:
		if stat_name == Stat.HEALTH:
			continue
		var extra: float = snapshot[stat_name] - float(res.stats.get(stat_name, 0.0))
		final_stats[stat_name] = final_stats.get(stat_name, 0.0) + extra

	for stat_name: StringName in final_stats:
		comp.set_stat(stat_name, final_stats[stat_name])
	comp.set_stat(Stat.HEALTH, final_stats.get(Stat.HEALTH_MAX, 0.0))


## Undo apply(): every pre-sync stat returns exactly as snapshotted.
static func restore(player: Player) -> void:
	if player == null or not player.has_meta(META_SNAPSHOT):
		return
	var snapshot: Dictionary = player.get_meta(META_SNAPSHOT)
	player.remove_meta(META_SNAPSHOT)
	var res: PlayerResource = player.player_resource
	var comp: StatsComponent = player.stats_component
	# Stats that only exist because of the sync fall back to the spawn baseline.
	for stat_name: StringName in comp.stats.values.keys():
		if not snapshot.has(stat_name):
			comp.set_stat(stat_name, float(res.stats.get(stat_name, 0.0)))
	for stat_name: StringName in snapshot:
		comp.set_stat(stat_name, float(snapshot[stat_name]))


## Rescale an attribute spread to [param budget] total points, preserving its
## proportions (the build's SHAPE survives, only its weight changes — both up
## for low-level players and down for high-level ones). Rounding drift lands
## on the largest attribute so totals stay exact.
static func scaled_attributes(attributes: Dictionary[StringName, int], budget: int) -> Dictionary[StringName, int]:
	var spent: int = 0
	for attr: StringName in attributes:
		spent += attributes[attr]
	if spent <= 0 or spent == budget:
		return attributes.duplicate()

	var out: Dictionary[StringName, int]
	var total: int = 0
	var largest: StringName = &""
	for attr: StringName in attributes:
		var scaled: int = int(round(float(attributes[attr]) * float(budget) / float(spent)))
		out[attr] = scaled
		total += scaled
		if largest == &"" or attributes[attr] > attributes[largest]:
			largest = attr
	if largest != &"" and total != budget:
		out[largest] = maxi(0, out[largest] + (budget - total))
	return out
