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
##   - Wire the @export slots (banner / health_bar / grace_label) to the children you
##     want. All optional — leave any unset to skip that feature.

const GRACE_MS: int = int(1.10 * 60 * 1000)
const MAX_HP: float = 500.0
## Raw weapon damage is multiplied by this before hitting the flag. A flag is an
## objective, not a duel — but capturing one shouldn't be a minute-long solo slog
## either. At 1.5 a fresh solo player needs ~20 swings; a leveled player or a
## 2-3 person group is much faster, which is the intended "bring friends" feel.
const HIT_SCALE: float = 1.5
## Own-guild repair mends at this fraction of a hit's damage, so a lone defender
## can chip in but can't out-heal a real attack (you must fight, not spam-repair).
const REPAIR_FRACTION: float = 0.5
## Floating nameplate (territory + owning guild, like a player nametag). Drawn at
## a big font then scaled down for crispness, matching DisplayNameLabel.
const NAMEPLATE_WIDTH: float = 320.0
const NAMEPLATE_SCALE: float = 0.28
const NAMEPLATE_Y: float = -62.0
## Guild emblem art comes from the shared GuildLogos catalog (client-only
## loads; the server never touches the textures).
## Max on-screen size (px) for the emblem. Downscaled by an integer divisor (1/N)
## from the source texture so it stays crisp under nearest-neighbor filtering.
const EMBLEM_MAX_PX: float = 32.0
## Emblem Y — above the nameplate (Sprite2D centers on its position).
const EMBLEM_Y: float = -82.0
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
## Whether NPC defender guards spawn here on capture (owning guild's Defenders
## upgrade). Designer-tunable per flag, so a territory can be kept PvP-only
## (e.g. an exclusive-PvP event zone) without touching the guild upgrade system.
@export var defenders_enabled: bool = true

@export_group("Visuals")
## Sprite whose `modulate` is tinted to the owning guild's color.
@export var banner: CanvasItem
## ProgressBar (or any Range) shown while the flag is damaged.
@export var health_bar: Range
## Label shown only during the post-capture immunity window, with a m:ss countdown.
@export var grace_label: Label

# Server-authoritative state. On clients these mirror what server pushed.
var hp: float = MAX_HP
var owner_guild_id: int = 0
var owner_guild_name: String = ""
## Owning guild's logo id (for the banner emblem). Synced via flag.update.
var owner_logo_id: int = 0
## Owning guild's custom banner color (HTML hex, "" = palette hash default).
## Synced via flag.update; a Guild Hall cosmetic (guild.banner.color).
var owner_banner_color: String = ""
var last_attacker: Character = null
var grace_until_ms: int = 0

## Client-only floating nameplate showing the territory + owning guild.
var _nameplate: Label
## Client-only HP readout, its own label under the nameplate (shown only while
## contested). Separate from the nameplate so a third line can't get clipped in
## the nameplate's fixed-height, scaled box.
var _hp_label: Label
## Client-only guild-logo emblem on the flag.
var _emblem: Sprite2D
## Client-only HP-bar fill stylebox, re-tinted blue when YOUR guild owns the flag
## (matching the blue ally tint on guildmates), red otherwise.
var _bar_fill: StyleBoxFlat

# True between damage start and the next capture or full-heal-broadcast. Lets
# us send a single "under attack" chat notice instead of one per arrow.
var _attack_notice_sent: bool = false
## Client-only: true once any live flag.update broadcast has been applied. Stops a
## late flag.get pull response (initial-state fallback) from clobbering fresher
## state — e.g. resetting HP to full right after the first hit, hiding the HP.
var _state_initialized: bool = false


func _ready() -> void:
	collision_layer = PhysicsLayers.FLAG # attacks target this for capture (not the player body's layer)
	# Self-register with the owning map (flag damage/capture resolution).
	var map: Map = Map.of(self)
	if map != null:
		map.register_keyed(map.territory_flags, flag_id, self, "territory flag")
	if multiplayer.is_server():
		set_process(false) # No client visuals to tick on the server.
		_load_state_from_db()
		# Once the surrounding instance/map is fully wired, broadcast initial
		# state so anyone already in the instance sees the banner color.
		call_deferred("_broadcast_state")
	else:
		Client.subscribe(&"flag.update", _on_flag_update_pushed)
		_build_nameplate()
		_build_hp_label()
		_build_emblem()
		_style_health_bar()
		_build_click_area()
		_request_state.call_deferred()
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
		grace_label.text = "Immune %d:%02d" % [seconds / 60, seconds % 60]
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

	# Basing is a guild-vs-guild system: solo players can't touch a flag.
	# Without this, a guildless griefer could grind the flag down for nothing.
	if attacker is not Player:
		return
	var attacker_guild: int = (attacker as Player).player_resource.active_guild_id
	if attacker_guild <= 0:
		return

	# Own guild REPAIRS the flag instead of attacking it — allies can't grief
	# their own territory (and no "under attack" spam), and chipping in mends it.
	if owner_guild_id > 0 and attacker_guild == owner_guild_id:
		_repair(amount)
		return

	last_attacker = attacker
	amount *= HIT_SCALE
	hp = maxf(0.0, hp - amount)
	_broadcast_hit(amount, false)

	# First damage since last full-HP -> notify the holding guild's members.
	if not _attack_notice_sent and hp < MAX_HP:
		_attack_notice_sent = true
		_notify_under_attack()

	if hp <= 0.0:
		_capture(attacker)
	else:
		_broadcast_state()


## An owning-guild member's hit mends the flag instead of damaging it — half the
## damage it would have dealt (REPAIR_FRACTION), so repairing helps but can't beat
## an attacker trading blow-for-blow. No-op at full HP.
func _repair(amount: float) -> void:
	if hp >= MAX_HP:
		return
	var mend: float = amount * HIT_SCALE * REPAIR_FRACTION
	hp = minf(MAX_HP, hp + mend)
	_broadcast_hit(mend, true)
	if hp >= MAX_HP:
		_attack_notice_sent = false # full again → a fresh assault re-notifies
	_broadcast_state()


## Juice: floating number over the flag on every hit (red damage / green heal),
## reusing the same combat.hit feedback path weapons use on characters.
func _broadcast_hit(amount: float, is_heal: bool) -> void:
	if amount <= 0.0 or WorldServer.curr == null:
		return
	var instance: Node = _server_instance()
	if instance == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"combat.hit", {
			"amount": int(round(amount)),
			"position": global_position,
			"heal": is_heal,
		}),
		instance.name
	)


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
	var owner_guild: Guild = WorldServer.curr.database.store.get_guild(new_owner_id)
	owner_guild_name = owner_guild.guild_name if owner_guild != null else ""
	owner_logo_id = owner_guild.logo_id if owner_guild != null else 0
	owner_banner_color = owner_guild.banner_color if owner_guild != null else ""
	grace_until_ms = Time.get_ticks_msec() + GRACE_MS

	WorldServer.curr.database.store.save_flag_state(
		flag_id, owner_guild_id, int(Time.get_unix_time_from_system() * 1000.0)
	)
	_announce_capture(killer as Player, previous_id, previous_name)
	# Guild logs: the winner records the capture, the previous holder the loss.
	var capturer_name: String = (killer as Player).player_resource.display_name if killer is Player else ""
	WorldServer.curr.database.store.add_guild_log(
		owner_guild_id, "flag_captured", capturer_name, "", {"territory": territory_name}
	)
	if previous_id > 0:
		WorldServer.curr.database.store.add_guild_log(
			previous_id, "flag_lost", "", owner_guild_name, {"territory": territory_name}
		)
	# Deferred: _capture runs inside the arrow's physics collision callback, and
	# spawning the guards' detection areas can't mutate physics mid-flush.
	if defenders_enabled:
		BasingService.spawn_defenders.call_deferred(self)
	_broadcast_state()


# --- Server-side: helpers ---

## Server: strip ownership without a capture (guild disband). Despawns any
## guards, clears the owner fields + grace, persists, and broadcasts the
## neutral state so clients re-tint immediately.
func release_ownership() -> void:
	if not multiplayer.is_server() or owner_guild_id <= 0:
		return
	BasingService.despawn_defenders(self)
	owner_guild_id = 0
	owner_guild_name = ""
	owner_logo_id = 0
	owner_banner_color = ""
	grace_until_ms = 0
	_attack_notice_sent = false
	WorldServer.curr.database.store.save_flag_state(flag_id, 0, 0)
	_broadcast_state()


func _load_state_from_db() -> void:
	var row: Dictionary = WorldServer.curr.database.store.get_flag_state(flag_id)
	if row.is_empty():
		return
	owner_guild_id = int(row.get("owner_guild_id", 0))
	if owner_guild_id > 0:
		var owner_guild: Guild = WorldServer.curr.database.store.get_guild(owner_guild_id)
		owner_guild_name = owner_guild.guild_name if owner_guild != null else ""
		owner_logo_id = owner_guild.logo_id if owner_guild != null else 0
		owner_banner_color = owner_guild.banner_color if owner_guild != null else ""
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
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"flag.update", payload),
		instance.name
	)


## Public accessor for the current state — used by the flag.get pull handler so a
## client entering the instance can fetch it on _ready (the one-shot flag.update
## broadcast may have fired before they joined, e.g. on warp re-entry).
func get_state_payload() -> Dictionary:
	return _state_payload()


func _state_payload() -> Dictionary:
	return {
		"flag_id": flag_id,
		"territory_name": territory_name,
		"owner_guild_id": owner_guild_id,
		"owner_guild_name": owner_guild_name,
		"owner_logo_id": owner_logo_id,
		"owner_banner_color": owner_banner_color,
		"hp": hp,
		"hp_max": MAX_HP,
		"grace_until_ms_remaining": maxi(0, grace_until_ms - Time.get_ticks_msec()),
	}


## Server: apply a live banner-color change (guild.banner.color) and rebroadcast
## so everyone watching re-tints without waiting for a recapture.
func update_owner_banner(color_html: String) -> void:
	if not multiplayer.is_server():
		return
	owner_banner_color = color_html
	_broadcast_state()


func _notify_under_attack() -> void:
	if owner_guild_id <= 0:
		return # Nothing to defend if it's unowned.
	var ws: WorldServer = WorldServer.curr
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
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.chat_service == null:
		return
	var killer_name: String = killer.player_resource.display_name if killer else "Someone"
	var msg: String
	if previous_id <= 0:
		msg = "%s claimed '%s' for %s!" % [killer_name, territory_name, owner_guild_name]
	else:
		msg = "%s took '%s' from %s for %s!" % [killer_name, territory_name, previous_name, owner_guild_name]
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


# --- Client-side: state sync + visuals ---

func _on_flag_update_pushed(payload: Dictionary) -> void:
	if int(payload.get("flag_id", -1)) != flag_id:
		return
	_state_initialized = true
	owner_guild_id = int(payload.get("owner_guild_id", 0))
	owner_guild_name = str(payload.get("owner_guild_name", ""))
	owner_logo_id = int(payload.get("owner_logo_id", 0))
	owner_banner_color = str(payload.get("owner_banner_color", ""))
	hp = float(payload.get("hp", MAX_HP))
	var grace_left: int = int(payload.get("grace_until_ms_remaining", 0))
	grace_until_ms = Time.get_ticks_msec() + grace_left
	_refresh_visuals()


## Pull the current flag state from the server on entry — robust to warp re-entry
## (the one-shot flag.update broadcast may have fired before this client joined).
func _request_state() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"flag.get", func(data: Dictionary) -> void:
		# Initial-state fallback only: skip if a live broadcast already arrived, so
		# a late pull can't overwrite fresher HP/owner state.
		if not data.is_empty() and not _state_initialized:
			_on_flag_update_pushed(data),
		{"flag_id": flag_id}, InstanceClient.current.name)


func _refresh_visuals() -> void:
	if banner != null:
		banner.modulate = _owner_color()
	if health_bar != null:
		health_bar.max_value = MAX_HP
		health_bar.value = hp
		# Hide when full HP so the world isn't cluttered with idle bars.
		if health_bar is CanvasItem:
			(health_bar as CanvasItem).visible = hp < MAX_HP
	# Blue fill when the local viewer's guild owns this flag (same blue guildmates
	# get), red otherwise — instant "mine vs theirs" read.
	var owned_by_viewer: bool = owner_guild_id > 0 and owner_guild_id == Character.local_viewer_guild_id
	if _bar_fill != null:
		_bar_fill.bg_color = Character.BAR_COLOR_ALLY if owned_by_viewer else Color(0.86, 0.33, 0.28)
	# Dedicated HP readout — shown only while contested, tinted to match the bar.
	if _hp_label != null:
		var damaged: bool = hp < MAX_HP
		_hp_label.visible = damaged
		if damaged:
			_hp_label.text = "%d / %d" % [int(ceil(hp)), int(MAX_HP)]
			_hp_label.add_theme_color_override(
				&"font_color", Character.BAR_COLOR_ALLY if owned_by_viewer else Color(0.96, 0.5, 0.45)
			)
	_update_nameplate()
	_update_emblem()


## Build the client-side floating nameplate above the flag. Big font scaled down
## (crisp), centered over the flag, lifted above the banner.
func _build_nameplate() -> void:
	_nameplate = Label.new()
	_nameplate.size = Vector2(NAMEPLATE_WIDTH, 40)
	_nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nameplate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_nameplate.autowrap_mode = TextServer.AUTOWRAP_OFF
	_nameplate.add_theme_font_size_override(&"font_size", 30)
	_nameplate.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_nameplate.add_theme_constant_override(&"outline_size", 6)
	_nameplate.scale = Vector2(NAMEPLATE_SCALE, NAMEPLATE_SCALE)
	# Center the scaled box over the flag origin and raise it above the banner.
	_nameplate.position = Vector2(-NAMEPLATE_WIDTH * NAMEPLATE_SCALE * 0.5, NAMEPLATE_Y)
	_nameplate.z_index = 20
	add_child(_nameplate)


## Dedicated HP readout, sitting just under the nameplate. Same crisp big-font-
## scaled-down approach, but its own node so it can't be clipped as a nameplate
## third line. Hidden until the flag is contested.
func _build_hp_label() -> void:
	_hp_label = Label.new()
	_hp_label.size = Vector2(NAMEPLATE_WIDTH, 40)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hp_label.add_theme_font_size_override(&"font_size", 26)
	_hp_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_hp_label.add_theme_constant_override(&"outline_size", 6)
	_hp_label.scale = Vector2(NAMEPLATE_SCALE, NAMEPLATE_SCALE)
	# Clearly below the two-line nameplate (territory + [guild]) so it doesn't
	# overlap the guild name. Nudge this offset if it needs more/less clearance.
	_hp_label.position = Vector2(-NAMEPLATE_WIDTH * NAMEPLATE_SCALE * 0.5, NAMEPLATE_Y + 28)
	_hp_label.z_index = 21
	_hp_label.visible = false
	add_child(_hp_label)


## Refresh nameplate text + color from the current owner. Guild color + tag when
## held, neutral "(Unclaimed)" otherwise. No-op on the server (plate is client-only).
func _update_nameplate() -> void:
	if _nameplate == null:
		return
	if owner_guild_id <= 0:
		_nameplate.text = "%s\n(Unclaimed)" % territory_name
		_nameplate.add_theme_color_override(&"font_color", NEUTRAL_COLOR)
	else:
		_nameplate.text = "%s\n[%s]" % [territory_name, owner_guild_name]
		_nameplate.add_theme_color_override(&"font_color", _owner_color())


## Build the client-side guild emblem on the flag. Sits on the banner if one is
## wired (reusing its placement), else a default spot above the origin.
func _build_emblem() -> void:
	_emblem = Sprite2D.new()
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # crisp pixels
	_emblem.position = Vector2(0, EMBLEM_Y) # above the nameplate (Sprite2D centers)
	_emblem.z_index = 20
	add_child(_emblem)


## Show the owning guild's logo on the emblem (hidden when unclaimed). Downscaled
## by an integer divisor (1/N) so it stays at or under EMBLEM_MAX_PX without
## fractional sampling — sharp under nearest-neighbor.
func _update_emblem() -> void:
	if _emblem == null:
		return
	if owner_guild_id <= 0:
		_emblem.visible = false
		return
	_emblem.visible = true
	var tex: Texture2D = GuildLogos.texture(owner_logo_id)
	_emblem.texture = tex
	if tex != null and tex.get_width() > 0:
		var n: int = maxi(1, ceili(tex.get_width() / EMBLEM_MAX_PX))
		_emblem.scale = Vector2.ONE / float(n)


## Client-only: clicking YOUR OWN guild's flag opens the Territory panel (info
## + reinforce). Deliberately gated to the owning guild — enemies attack the
## flag with weapon clicks, and popping a menu mid-assault would fight the
## combat controls. Ownership is checked at click time (it changes).
func _build_click_area() -> void:
	var area: ClickableArea = ClickableArea.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 34.0
	shape.shape = circle
	area.add_child(shape)
	area.clicked.connect(_on_flag_clicked)
	add_child(area)


func _on_flag_clicked() -> void:
	if owner_guild_id <= 0 or owner_guild_id != Character.local_viewer_guild_id:
		return
	ClientState.open_menu_requested.emit(&"territory", flag_id)


## Restyle the flag HP bar to the navy theme with a danger-red fill (only shows
## while contested). No-op if no bar is wired or it isn't a ProgressBar.
func _style_health_bar() -> void:
	if health_bar is not ProgressBar:
		return
	var bar: ProgressBar = health_bar as ProgressBar
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.078, 0.117, 0.85)
	bg.anti_aliasing = false # square, crisp edges for pixel art
	bg.set_border_width_all(1)
	bg.border_color = Color(0, 0, 0, 0.5)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.86, 0.33, 0.28)
	fill.anti_aliasing = false
	_bar_fill = fill # kept so _refresh_visuals can re-tint it on ownership change
	bar.add_theme_stylebox_override(&"background", bg)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.show_percentage = false


## The banner/nameplate color: the guild's purchased custom color when set,
## else the per-guild palette hash.
func _owner_color() -> Color:
	if owner_guild_id > 0 and Color.html_is_valid(owner_banner_color):
		return Color.html(owner_banner_color)
	return _color_for_guild(owner_guild_id)


static func _color_for_guild(guild_id: int) -> Color:
	if guild_id <= 0:
		return NEUTRAL_COLOR
	return PALETTE[guild_id % PALETTE.size()]
