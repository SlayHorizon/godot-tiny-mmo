@icon("res://assets/node_icons/blue/icon_character.png")
class_name TerritoryFlag
extends StaticBody2D
## A capturable territory marker. Damaged like a Character; when HP hits zero
## the last guilded hitter's guild becomes the new owner, HP refills, and a
## 5-minute grace period blocks further damage so the holder actually has time
## to *be* the holder.
##
## Server-authoritative. Clients receive state via the `flag.update` data_push
## topic and only render — they never write to hp/owner directly.
##
## Designer setup:
##   - Place a TerritoryFlag node as a direct child of a Map.
##   - Set `flag_id` (must be unique across the project — used as DB primary key).
##   - Set `territory_name` (display string).
##   - Add a CollisionShape2D child (so arrows can hit it).
##   - Wire the @export slots (banner / health_bar / territory_zone / grace_label)
##     to the children you want. All optional — leave any unset to skip that feature.

const GRACE_MS: int = 5 * 60 * 1000
const MAX_HP: float = 500.0
## Color used for the banner when the flag is unowned (guild_id = 0).
const NEUTRAL_COLOR: Color = Color(0.7, 0.7, 0.7)
## Per-guild banner color is a hash of guild_id mapped into a saturated palette —
## good enough for prototype until guild customization exists.
const PALETTE: PackedColorArray = [
	Color(0.95, 0.30, 0.30), Color(0.30, 0.65, 0.95), Color(0.40, 0.85, 0.40),
	Color(0.95, 0.80, 0.25), Color(0.75, 0.40, 0.95), Color(0.95, 0.55, 0.25),
	Color(0.30, 0.85, 0.85), Color(0.95, 0.45, 0.75),
]

@export var flag_id: int = 0
@export var territory_name: String = "Unnamed Territory"

@export_group("Visuals")
## Sprite whose `modulate` is tinted to the owning guild's color.
@export var banner: CanvasItem
## ProgressBar (or any Range) shown while the flag is damaged.
@export var health_bar: Range
## Label shown only during the post-capture immunity window, with a m:ss countdown.
@export var grace_label: Label

@export_group("Gameplay")
## Area2D defining the base footprint — kills inside it by the owning guild's
## members count toward the Glory milestone. If unset, the flag has no surrounding
## base zone and kill credits are skipped (the territory tick still works).
@export var territory_zone: Area2D

# Server-authoritative state. On clients these mirror what server pushed.
var hp: float = MAX_HP
var owner_guild_id: int = 0
var owner_guild_name: String = ""
var last_attacker: Character = null
var grace_until_ms: int = 0

# True between damage start and the next capture or full-heal-broadcast. Lets
# us send a single "under attack" chat notice instead of one per arrow.
var _attack_notice_sent: bool = false


func _ready() -> void:
	if multiplayer.is_server():
		set_process(false) # No client visuals to tick on the server.
		_load_state_from_db()
		# Once the surrounding instance/map is fully wired, broadcast initial
		# state so anyone already in the instance sees the banner color.
		call_deferred("_broadcast_state")
	else:
		Client.subscribe(&"flag.update", _on_flag_update_pushed)
	_refresh_visuals()


## Client-only: keep the grace countdown ticking. Once the timer expires the
## label hides itself. Server doesn't process this (set_process(false) above).
func _process(_delta: float) -> void:
	if grace_label == null:
		return
	var remaining_ms: int = grace_until_ms - Time.get_ticks_msec()
	if remaining_ms > 0:
		@warning_ignore("integer_division")
		var seconds: int = remaining_ms / 1000
		@warning_ignore("integer_division")
		grace_label.text = "🛡 Immune %d:%02d" % [seconds / 60, seconds % 60]
		grace_label.visible = true
	elif grace_label.visible:
		grace_label.visible = false


# --- Server-side: damage + capture ---

## Mirrors Character.take_damage so existing hit code (arrows) just works.
func take_damage(amount: float, attacker: Character = null) -> void:
	if not multiplayer.is_server() or amount <= 0.0:
		return
	if Time.get_ticks_msec() < grace_until_ms:
		return # Immune during post-capture grace.

	# Basing is a guild-vs-guild system: solo players can't damage a flag.
	# Without this, a guildless griefer could grind the flag down to 0 HP and
	# the owning guild would lose ownership-grace cycles for nothing.
	if attacker is not Player:
		return
	if (attacker as Player).player_resource.active_guild_id <= 0:
		return

	last_attacker = attacker; amount *= 5
	hp = maxf(0.0, hp - amount)

	# First damage since last full-HP -> notify the holding guild's members.
	if not _attack_notice_sent and hp < MAX_HP:
		_attack_notice_sent = true
		_notify_under_attack()

	if hp <= 0.0:
		_capture(attacker)
	else:
		_broadcast_state()


func _capture(killer: Character) -> void:
	# Only guilded Players capture. Solo / NPC last-hits absorb the kill blow
	# (HP refills) but don't transfer ownership — this stops lone-wolf griefing
	# of guild-controlled territory.
	var new_owner_id: int = 0
	if killer is Player:
		new_owner_id = killer.player_resource.active_guild_id

	hp = MAX_HP
	_attack_notice_sent = false

	if new_owner_id <= 0 or new_owner_id == owner_guild_id:
		# No transfer: just reset HP and broadcast.
		_broadcast_state()
		return

	var previous_id: int = owner_guild_id
	var previous_name: String = owner_guild_name
	owner_guild_id = new_owner_id
	owner_guild_name = ServerHub.current.database.store.get_guild_name(new_owner_id)
	grace_until_ms = Time.get_ticks_msec() + GRACE_MS

	ServerHub.current.database.store.save_flag_state(
		flag_id, owner_guild_id, int(Time.get_unix_time_from_system() * 1000.0)
	)
	_announce_capture(killer as Player, previous_id, previous_name)
	_broadcast_state()


# --- Server-side: helpers ---

func _load_state_from_db() -> void:
	var row: Dictionary = ServerHub.current.database.store.get_flag_state(flag_id)
	if row.is_empty():
		return
	owner_guild_id = int(row.get("owner_guild_id", 0))
	if owner_guild_id > 0:
		owner_guild_name = ServerHub.current.database.store.get_guild_name(owner_guild_id)
	# Grace from the persisted last_capture_ms — so a restart doesn't reset the
	# defender's protection window. last_capture_ms is unix-ms; grace_until_ms
	# is ticks-ms (uptime). Convert via the current offset.
	var last_capture_unix: int = int(row.get("last_capture_ms", 0))
	var now_unix: int = int(Time.get_unix_time_from_system() * 1000.0)
	var grace_left: int = (last_capture_unix + GRACE_MS) - now_unix
	if grace_left > 0:
		grace_until_ms = Time.get_ticks_msec() + grace_left


func _broadcast_state() -> void:
	var instance: Node = _server_instance()
	if instance == null:
		return
	var payload: Dictionary = _state_payload()
	ServerHub.current.propagate_rpc(
		ServerHub.current.data_push.bind(&"flag.update", payload),
		instance.name
	)


func _state_payload() -> Dictionary:
	return {
		"flag_id": flag_id,
		"territory_name": territory_name,
		"owner_guild_id": owner_guild_id,
		"owner_guild_name": owner_guild_name,
		"hp": hp,
		"hp_max": MAX_HP,
		"grace_until_ms_remaining": maxi(0, grace_until_ms - Time.get_ticks_msec()),
	}


func _notify_under_attack() -> void:
	if owner_guild_id <= 0:
		return # Nothing to defend if it's unowned.
	var ws: Node = ServerHub.current
	if ws == null or ws.chat_service == null:
		return
	# Notify every online member of the holding guild, wherever they are.
	# Triple-guard: skip nulls, skip guildless players (active_guild_id == 0),
	# and require exact guild match. Guildless players have active_guild_id 0,
	# which is also the unowned sentinel, so we explicitly require > 0.
	for peer_id: int in ws.connected_players:
		var player: PlayerResource = ws.connected_players[peer_id]
		if player == null:
			continue
		if player.active_guild_id <= 0:
			continue
		if player.active_guild_id != owner_guild_id:
			continue
		ws.chat_service.push_system_to_player(
			_server_instance(), player.player_id,
			"⚔ Your territory '%s' is under attack!" % territory_name
		)


func _announce_capture(killer: Player, previous_id: int, previous_name: String) -> void:
	var ws: Node = ServerHub.current
	if ws == null or ws.chat_service == null:
		return
	var killer_name: String = killer.player_resource.display_name if killer else "Someone"
	var msg: String
	if previous_id <= 0:
		msg = "🏴 %s claimed '%s' for %s!" % [killer_name, territory_name, owner_guild_name]
	else:
		msg = "🏴 %s took '%s' from %s for %s!" % [killer_name, territory_name, previous_name, owner_guild_name]
	for peer_id: int in ws.connected_players:
		var player: PlayerResource = ws.connected_players[peer_id]
		if player == null:
			continue
		ws.chat_service.push_system_to_player(_server_instance(), player.player_id, msg)


func _server_instance() -> Node:
	var n: Node = get_parent()
	while n:
		if n is SubViewport:
			return n
		n = n.get_parent()
	return null


## True if [param body] is inside this flag's territory zone (the @export
## `territory_zone` Area2D). Returns false when no zone is wired — useful for
## tests, where the flag still captures but doesn't generate kill credits.
func is_body_in_territory(body: Node2D) -> bool:
	if territory_zone == null:
		return false
	return territory_zone.overlaps_body(body)


# --- Client-side: state sync + visuals ---

func _on_flag_update_pushed(payload: Dictionary) -> void:
	if int(payload.get("flag_id", -1)) != flag_id:
		return
	owner_guild_id = int(payload.get("owner_guild_id", 0))
	owner_guild_name = str(payload.get("owner_guild_name", ""))
	hp = float(payload.get("hp", MAX_HP))
	var grace_left: int = int(payload.get("grace_until_ms_remaining", 0))
	grace_until_ms = Time.get_ticks_msec() + grace_left
	_refresh_visuals()


func _refresh_visuals() -> void:
	if banner != null:
		banner.modulate = _color_for_guild(owner_guild_id)
	if health_bar != null:
		health_bar.max_value = MAX_HP
		health_bar.value = hp
		# Hide when full HP so the world isn't cluttered with idle bars.
		if health_bar is CanvasItem:
			(health_bar as CanvasItem).visible = hp < MAX_HP


static func _color_for_guild(guild_id: int) -> Color:
	if guild_id <= 0:
		return NEUTRAL_COLOR
	return PALETTE[guild_id % PALETTE.size()]
