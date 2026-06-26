class_name Player
extends Character


var player_resource: PlayerResource

## Synced guild tag — drives the blue ally health-bar tint guildmates see on each
## other. Synced like display_name (set_by_path → baseline + live dirty).
var active_guild_id: int = 0:
	set = _set_active_guild_id

var zone_flags: int = 0

var teleport_lock_until_ms: int = 0

## --- Weapon equip-cast (server-authoritative draw) ---
## A weapon "draws" over WEAPON_DRAW_MS before it actually equips: abilities are
## locked (the action.perform gate + the client lock) and the client shows a cast
## bar, but movement stays free. A fresh draw replaces any in-progress one (token).
const WEAPON_DRAW_MS: int = 500
var _equip_cast_token: int = 0
var _equip_cast_until_ms: int = 0


func _init() -> void:
	pass


## Seconds the player stays down before a no-penalty respawn at the map spawn point.
const RESPAWN_DELAY: float = 3.0
## Grace window after respawn where the player can't traverse warpers — the map spawn point can sit
## on a warper (e.g. forest↔overworld), and without this the first step off re-warps the player.
const RESPAWN_WARP_GRACE_MS: int = 2000


## On death: tell the client (death screen + countdown + where to respawn), wait, then
## restore full health and clear the dead flag. Position is client-authoritative, so the
## client teleports itself to the spawn (see LocalPlayer); the server only owns HP/state.
## Staying dead during the delay also makes nearby enemies drop aggro (they ignore dead
## targets) instead of trailing the corpse.
func die(killer: Character) -> void:
	# Leaderboard: credit the killer if this was a player-vs-player kill. NPC
	# killers are filtered out inside record_pvp_kill.
	LeaderboardService.record_pvp_kill(killer)

	# Hardcore dungeon: a death spends a shared revive. If the pool's empty the whole run fails —
	# DungeonService revives + ejects the party to town, so skip the normal respawn here.
	if DungeonService.register_dungeon_death(self):
		return

	# Default spawn = map's spawn point.
	var spawn_position: Vector2 = Vector2.ZERO
	var map: Map = get_parent() as Map
	if map:
		spawn_position = map.get_spawn_position()

	# Sparring: override to the duel master's position BEFORE ending the match
	# (on_player_died_in_match clears in_match and would un-resolve us otherwise).
	# Then end the match so wins/losses are tallied and the opponent is healed.
	if player_resource != null and player_resource.in_match:
		var sparring_pos: Vector2 = SparringService.return_position_for(self)
		if sparring_pos != Vector2.ZERO:
			spawn_position = sparring_pos
		SparringService.on_player_died_in_match(self, killer)

	var peer_id: int = int(player_resource.current_peer_id)
	if peer_id > 0:
		# Death-screen attribution. Every Character carries a display_name (the
		# player's character name, or the enemy's EnemyTypeResource name); empty
		# means an unattributed death (environment, or the source already freed).
		var killed_by: String = killer.display_name if is_instance_valid(killer) else ""
		WorldServer.curr.data_push.rpc_id(peer_id, &"player.died", {
			"respawn_in": RESPAWN_DELAY,
			"spawn": spawn_position,
			"killed_by": killed_by,
		})

	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(self):
		return # left the game while down

	revive()
	# The respawn lands on the map spawn point, which may sit on a warper — lock warper traversal
	# briefly so stepping off doesn't immediately warp the player (their idea; mirrors spawn_player).
	mark_just_teleported(RESPAWN_WARP_GRACE_MS)


## Top HP and mana back to full (does NOT touch the dead flag). The dungeon enter/exit refill uses it
## to save players a few potions, spar-style; revive() builds on it for respawns.
func restore_full() -> void:
	stats_component.set_stat(Stat.HEALTH, stats_component.get_stat(Stat.HEALTH_MAX))
	stats_component.set_stat(Stat.MANA, stats_component.get_stat(Stat.MANA_MAX))


## Restore to full (HP + mana) and clear the dead flag. Shared by the normal respawn and the
## dungeon-fail eject (DungeonService revives the party so they arrive home alive, not as corpses).
func revive() -> void:
	restore_full()
	is_dead = false


func _ready() -> void:
	super._ready()
	if not multiplayer.is_server():
		_apply_team_bar_color()


## Mana regen lives in ServerInstance's 1 Hz status tick (one timer per instance,
## not a per-frame poll on every player node) — see instance_server.gd.


func _set_active_guild_id(value: int) -> void:
	active_guild_id = value
	_apply_team_bar_color()


## Client-only: color this (remote) player's HP bar — blue for a guildmate, neutral
## otherwise. Reads Character.local_viewer_guild_id (a static mirror of ClientState)
## so Player never references ClientState — see the cycle note on that static.
## LocalPlayer overrides this to "self" (green). Re-applied for everyone on a local
## guild change by ClientState._retint_local_players.
func _apply_team_bar_color() -> void:
	if multiplayer.is_server():
		return
	# Spar team overrides guild for the duration of a match: an opposing
	# guildmate reads hostile, a non-guild teammate reads ally. (Client Player
	# nodes are named by peer id — see InstanceClient.)
	var peer: int = name.to_int()
	if Character.spar_opponent_peers.has(peer):
		set_health_bar_fill(BAR_COLOR_HOSTILE)
		return
	if Character.spar_ally_peers.has(peer):
		set_health_bar_fill(BAR_COLOR_ALLY)
		return
	# Co-op groupmates read as allies regardless of guild (dungeon context).
	if Character.group_peers.has(peer):
		set_health_bar_fill(BAR_COLOR_ALLY)
		return
	var same_guild: bool = active_guild_id > 0 and active_guild_id == Character.local_viewer_guild_id
	set_health_bar_fill(BAR_COLOR_ALLY if same_guild else BAR_COLOR_HOSTILE)


func is_pvp() -> bool:
	return zone_flags & Map.ZoneMode.PVP


func has_modifier(mod: Map.ZoneModifiers) -> bool:
	var mask: int = 1 << (1 + mod)
	return (zone_flags & mask) != 0


func mark_just_teleported(cooldown_ms: int = 500) -> void:
	teleport_lock_until_ms = Time.get_ticks_msec() + cooldown_ms


func has_recently_teleported() -> bool:
	return Time.get_ticks_msec() < teleport_lock_until_ms


# --- Weapon equip-cast ---

## True while a weapon draw is in flight (server-authoritative). action.perform
## reads this to refuse ability use mid-draw.
func is_equip_casting() -> bool:
	return Time.get_ticks_msec() < _equip_cast_until_ms


## Server: draw [param item_id] into the HAND over the equip-cast (a short charge —
## bar + ability lock, but move-free). On landing the hand slot becomes that item, so
## it MOUNTS (weapon, potion, anything) through _on_slot_changed -> item.equip. A newer
## draw abandons this one (token). Identical for every item type — the unified hand.
func begin_hand_draw(item_id: int, duration_ms: int = WEAPON_DRAW_MS) -> void:
	if not GameMode.is_world_server():
		return
	_equip_cast_token += 1
	var token: int = _equip_cast_token
	_equip_cast_until_ms = Time.get_ticks_msec() + duration_ms
	var peer: int = int(player_resource.current_peer_id)
	if peer > 0:
		WorldServer.curr.data_push.rpc_id(peer, &"equip.cast", {"ms": duration_ms, "id": item_id})
	await get_tree().create_timer(float(duration_ms) / 1000.0).timeout
	if not is_instance_valid(self) or _equip_cast_token != token or is_dead:
		return
	_equip_cast_until_ms = 0
	_complete_hand_draw(item_id)
	if peer > 0:
		WorldServer.curr.data_push.rpc_id(peer, &"equip.done", {})


## Server: the draw landed — put [param item_id] in the HAND slot (it mounts via
## _on_slot_changed) and reconcile the bag. A WEAPON (gear) moves bag<->hand; a
## consumable / material is REFERENCED — it STAYS in the bag (you hold the stack and
## consume from it), so only a previous WEAPON returns to the bag. Bails if the item
## left the inventory during the draw.
func _complete_hand_draw(item_id: int) -> void:
	var inventory: Dictionary = player_resource.inventory
	if not Inventory.has_item(inventory, item_id):
		return
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if item == null:
		return
	var previous_id: int = int(equipment_component.slots.values.get(&"weapon", 0))
	var previous_is_gear: bool = previous_id > 0 \
		and ContentRegistryHub.load_by_id(&"items", previous_id) is GearItem
	equipment_component.set_hand(item_id)
	# A WEAPON (gear) moves bag->hand: removed from the bag and PERSISTED as equipment.
	# A consumable / material is REFERENCED — it stays in the bag, so it must NOT be
	# persisted as equipment, or the relog / instance-change re-equip loop would
	# equip_item()-fail on the non-gear id and add a DUPLICATE back to the bag.
	if item is GearItem:
		Inventory.remove_one_by_id(inventory, item_id)
		player_resource.equipment[&"weapon"] = item_id
	else:
		player_resource.equipment.erase(&"weapon")
	if previous_is_gear:
		Inventory.add_item(inventory, previous_id, 1)


#region Overhead chat
## How long a bubble stays fully visible before it starts to fade out.
const OVERHEAD_HOLD_SEC: float = 5.0
## Fade-out tween duration.
const OVERHEAD_FADE_SEC: float = 0.8
## Vertical offset above the player's origin where the bubble sits.
const OVERHEAD_OFFSET_Y: float = -58.0
## Cap on displayed text so we don't get a screen-wide banner.
const OVERHEAD_MAX_CHARS: int = 60

## Text used for the "is typing" indicator. Reuses the overhead bubble.
const TYPING_INDICATOR_TEXT: String = "..."
## Fade-out duration when the typing indicator clears. Quick, not a real
## message — no need to linger.
const TYPING_FADE_SEC: float = 0.25
## When a real message was shown less than this ago, the typing indicator
## defers itself by the remaining time so the recipient gets a moment to
## read the previous message instead of seeing it instantly steamrolled by
## "...". Peek-feed history covers the worst case; this just smooths the
## common "send → immediately compose follow-up" pattern.
const POST_MESSAGE_GRACE_MS: int = 1500

var _overhead_label: Label
var _overhead_tween: Tween
## True while we're displaying the typing indicator (not a real chat
## message). Lets set_typing(false) safely clear the bubble without wiping
## a chat message that might have just replaced it.
var _typing_indicator_active: bool = false
## Latest desired typing state. Read by the grace-period deferred apply so
## a fast type → un-focus during the grace window doesn't flash "...".
var _typing_requested: bool = false
## Ticks_msec at which the last real chat message was set as the overhead.
## Used to compute the grace window.
var _last_real_message_at_ms: int = 0


## Shows a short-lived chat bubble above this player's head. Used for
## world-channel messages so nearby chatter feels alive. A new message
## replaces any currently displayed bubble — no queue.
func show_overhead(text: String) -> void:
	if multiplayer.is_server():
		return  # Headless server doesn't draw bubbles.
	if text.is_empty():
		return

	_ensure_overhead_label()
	if _overhead_tween != null and _overhead_tween.is_running():
		_overhead_tween.kill()

	var display_text: String = text
	if display_text.length() > OVERHEAD_MAX_CHARS:
		display_text = display_text.substr(0, OVERHEAD_MAX_CHARS - 3) + "..."

	# A real message takes precedence over the typing indicator. Once a real
	# chat line lands, a subsequent set_typing(false) must not wipe it.
	_typing_indicator_active = false
	_last_real_message_at_ms = Time.get_ticks_msec()
	_set_overhead_text(display_text)

	_overhead_tween = create_tween()
	_overhead_tween.tween_interval(OVERHEAD_HOLD_SEC)
	_overhead_tween.tween_property(_overhead_label, ^"modulate:a", 0.0, OVERHEAD_FADE_SEC)


## Toggle the "is typing" bubble above this player's head. Driven by
## chat.typing pushes from the server (focus_entered / focus_exited on the
## chat input). Shares the overhead Label slot with show_overhead — a real
## chat message landing replaces "..." automatically.
func set_typing(is_typing: bool) -> void:
	if multiplayer.is_server():
		return

	_typing_requested = is_typing

	if is_typing:
		# If a real chat message was shown very recently, defer the typing
		# indicator so it doesn't steamroll the message before the recipient
		# can read it. The deferred apply re-checks _typing_requested so a
		# fast focus-then-unfocus inside the grace window doesn't flash dots.
		var elapsed_ms: int = Time.get_ticks_msec() - _last_real_message_at_ms
		if _last_real_message_at_ms > 0 and elapsed_ms < POST_MESSAGE_GRACE_MS:
			var remaining_sec: float = float(POST_MESSAGE_GRACE_MS - elapsed_ms) / 1000.0
			get_tree().create_timer(remaining_sec).timeout.connect(_apply_typing_after_grace)
			return
		_show_typing_now()
		return

	# Stopping: only clear the bubble if it's currently the typing indicator.
	# If a chat message replaced "..." in the meantime, leave that alone.
	if not _typing_indicator_active:
		return
	_typing_indicator_active = false
	if _overhead_label == null:
		return
	if _overhead_tween != null and _overhead_tween.is_running():
		_overhead_tween.kill()
	_overhead_tween = create_tween()
	_overhead_tween.tween_property(_overhead_label, ^"modulate:a", 0.0, TYPING_FADE_SEC)


func _apply_typing_after_grace() -> void:
	# By the time the grace timer fires the user may have un-focused, sent a
	# message, or disconnected. Re-check before showing.
	if not _typing_requested:
		return
	if not is_instance_valid(self):
		return
	_show_typing_now()


func _show_typing_now() -> void:
	_ensure_overhead_label()
	if _overhead_tween != null and _overhead_tween.is_running():
		_overhead_tween.kill()
	_typing_indicator_active = true
	_set_overhead_text(TYPING_INDICATOR_TEXT)
	# No hold-then-fade — the indicator stays until set_typing(false) or a
	# real message replaces it. Disconnect cleans up via despawn.


func _ensure_overhead_label() -> void:
	if _overhead_label != null:
		return
	_overhead_label = Label.new()
	_overhead_label.name = "OverheadLabel"
	_overhead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overhead_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overhead_label.z_index = 10
	_overhead_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overhead_label.add_theme_font_size_override(&"font_size", 12)
	_overhead_label.add_theme_color_override(&"font_color", Color.WHITE)
	_overhead_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	#_overhead_label.add_theme_constant_override(&"outline_size", 2)
	add_child(_overhead_label)


## Sets the text and re-centres + re-shows the label. Called by both the
## chat-message path and the typing-indicator path so position math stays in
## one place.
func _set_overhead_text(display_text: String) -> void:
	_overhead_label.text = display_text
	_overhead_label.modulate.a = 1.0
	_overhead_label.show()
	# Auto-size to text width, then translate so the label is horizontally
	# centred above the player's origin. Round to an integer pixel offset so
	# the glyphs stay on the same texel even while the player walks at
	# fractional positions (subpixel labels blur badly under filtering).
	_overhead_label.reset_size()
	var half_w: int = int(round(_overhead_label.size.x * 0.5))
	_overhead_label.position = Vector2(-half_w, OVERHEAD_OFFSET_Y)
#endregion
