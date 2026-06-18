class_name EventService
## Server-side orchestrator for admin-triggered live events. The first event is the
## WORLD BOSS — a beefed-up HostileNpc dropped into the live world that the whole
## server fights together.
##
## Participation rewards come FREE: a world boss is just a HostileNpc, so on death
## RewardService already splits its XP + loot across EVERY player who dealt
## meaningful damage (see reward_service.gd) — not just the last hitter. So this
## service only has to spawn the body, rally the server, and announce the result.
##
## Triggered from an in-game admin command (the master dashboard is owner-only),
## this is the seed of a broader admin event system: new event types can reuse the
## same spawn / announce / cleanup shape. Server-only; one event at a time.

## The world boss archetype — a dedicated boss EnemyTypeResource (big stats +
## visual, leashes=false so it commits, is_boss, single-life, the Boss tuning
## group). Registered in the enemy_types content index.
const WORLD_BOSS_SLUG: StringName = &"world_boss"

## The live world boss + the instance it was rallied from (used for announces).
## Only one world boss at a time. Static — the trigger command and the death
## handler share them without needing an instance of this service.
static var _active_boss: HostileNpc = null
static var _event_instance: ServerInstance = null


## Spawn the world boss at [param position] inside [param spawn_container]'s map and
## rally the server. Returns an admin-facing feedback string. Server-only.
static func start_world_boss(instance: ServerInstance, spawn_container: ReplicatedPropsContainer, position: Vector2) -> String:
	if not GameMode.is_world_server():
		return "World bosses can only be spawned on a world server."
	if is_instance_valid(_active_boss):
		return "A world boss (%s) is already active — finish it first." % _active_boss.display_name
	if spawn_container == null:
		return "No spawn container here."

	var boss: HostileNpc = spawn_container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		spawn_container.to_local(position),
		{"enemy_type_slug": WORLD_BOSS_SLUG}
	) as HostileNpc
	if boss == null:
		return "Failed to spawn the world boss (slug '%s' — is it registered?)." % WORLD_BOSS_SLUG

	# world_boss.tres already defines the whole fight (big stats + visual,
	# leashes=false so it commits, single-life, the Boss tuning group). Here we
	# only bolt on the polished boss brain — the same BossController node RoomNode
	# attaches to dungeon bosses (telegraphed slam, enrage, adds).
	var brain: BossController = BossController.new()
	brain.boss = boss
	boss.add_child(brain)

	_active_boss = boss
	_event_instance = instance
	boss.died.connect(_on_world_boss_died)

	_announce("A world boss has risen: %s! Rally and bring it down — everyone who fights shares the spoils." % boss.display_name)
	return "World boss '%s' spawned." % boss.display_name


## Boss down: the rewards were already split by RewardService inside
## HostileNpc.die(), so here we just trumpet the win server-wide and clear the slot.
static func _on_world_boss_died(_killer: Character) -> void:
	var boss_name: String = _active_boss.display_name if is_instance_valid(_active_boss) else "The world boss"
	_announce("%s has fallen! The spoils are shared among all who fought it." % boss_name)
	_active_boss = null
	_event_instance = null


## System message to every connected player across all instances — a world event
## concerns the whole server. Same reach as /broadcast.
static func _announce(text: String) -> void:
	var ws: WorldServer = ServerHub.current
	if ws == null or _event_instance == null:
		return
	for peer_id: int in ws.connected_players:
		var pr: PlayerResource = ws.connected_players[peer_id]
		if pr != null:
			ws.chat_service.push_system_to_player(_event_instance, pr.player_id, text)
