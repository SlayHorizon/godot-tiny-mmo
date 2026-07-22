@tool
@icon("res://assets/node_icons/blue/icon_door.png")
class_name Portal
extends Warper
## A Warper dressed as an animated portal: the swirl sprite + a full HSV recolor + an
## optional destination label + a dwell-then-fade warp transition. All warp behavior is
## inherited — the server only honors [member Warper.warp_delay_s] before firing, so
## doors (delay 0) stay instant. Place it in a map exactly like a plain Warper (set
## target_instance / warper_id / target_id), then pick a color per destination.
## @tool so color + label preview live in the editor while placing.

## Dominant HSV of the source swirl art (weighted by s*v over opaque pixels — measured,
## don't eyeball). portal_color is matched against these: hue ROTATES to the target's
## hue, saturation and value SCALE by target/source. Scaling keeps the art's internal
## shading (bright core, dimmer rim), so a dark pick gives a genuinely dark portal
## instead of the hue-only bright-cyan miss the first iteration had.
const SOURCE_HUE: float = 0.7116
const SOURCE_SAT: float = 0.9219
const SOURCE_VAL: float = 0.8578
## Swirl animation speed while the local player charges the warp (client juice).
const REV_UP_SPEED: float = 2.6
## Screen fade-back-in time once the warp lands (fade-out time = warp_delay_s).
const FADE_IN_S: float = 0.3

## The color the swirl becomes — what you pick is what you get, including dark colors.
## Default = the source art's own color (renders unchanged).
@export var portal_color: Color = Color(0.28, 0.067, 0.858):
	set(value):
		portal_color = value
		_apply()
## Shown under the portal (e.g. "Forest"). Empty = no label.
@export var destination_label: String = "":
	set(value):
		destination_label = value
		_apply()

## Client-side: the screen fade covering the local player's pending warp, if any.
var _fade: WarpFade
## True while the LOCAL player stands inside this portal (drives the delayed charge).
var _local_inside: bool = false
## Invalidation token for a pending hesitation window: bumped on every enter/exit so
## a stale timer from an earlier visit can never start a charge.
var _warn_token: int = 0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $Label


func _ready() -> void:
	super._ready()
	_apply()
	# Client-only transition hooks: fade + rev-up while the LOCAL player stands in the
	# portal. The server enforces the same warp_delay_s dwell independently.
	if not Engine.is_editor_hint() and not multiplayer.is_server():
		body_entered.connect(_on_local_body_entered)
		body_exited.connect(_on_local_body_exited)
		# Sealed state is per-character and can change LIVE (the stone is granted
		# while this map is loaded) — re-skin on every wardstone update.
		ClientState.wardstones_changed.connect(_apply_sealed)
		_apply_sealed()


## Push color + label onto the child nodes. Safe to call before ready (setters fire on
## scene load, before @onready resolves) — it just no-ops until _ready re-applies.
func _apply() -> void:
	if animated_sprite == null or label == null:
		return
	var material_shader: ShaderMaterial = animated_sprite.material as ShaderMaterial
	if material_shader != null:
		material_shader.set_shader_parameter(&"hue_offset", wrapf(portal_color.h - SOURCE_HUE, 0.0, 1.0))
		material_shader.set_shader_parameter(&"sat_scale", portal_color.s / SOURCE_SAT)
		material_shader.set_shader_parameter(&"val_scale", portal_color.v / SOURCE_VAL)
	# Gated portals self-document ("Fungus Cave (Lv 5+)"). The floor comes from the
	# DESTINATION InstanceResource (gate_level()), so the label can never disagree
	# with the zone's actual band. Future-biome portals with no target_instance yet
	# bake their "(Lv N+)" into destination_label by hand.
	var gate_suffix: String = " (Lv %d+)" % gate_level() if gate_level() > 0 else ""
	label.text = destination_label + gate_suffix
	label.visible = not destination_label.is_empty()


func _on_local_body_entered(body: Node2D) -> void:
	if warp_delay_s <= 0.0 or not _is_local_player(body):
		return
	# Warp arrival: we spawn ON the destination portal, marked just-teleported by
	# InstanceClient (mirroring the server), so this entry is an arrival, not a
	# departure — no fade, no rev.
	if body.has_recently_teleported():
		return
	_local_inside = true
	_warn_token += 1
	# Wardstone seal (docs/wardstones.md): the hard gate. No charge, no dwell —
	# just the explanation. The server refuses independently (can_join_instance +
	# its target_instance check), so a modified client gains nothing. Placeholder
	# portals (no destination authored yet) read as sealed future content.
	if _is_sealed():
		var subtitle: String = "This land is not yet within reach." if required_stone().is_empty() \
			else "Reclaim the %s Wardstone first." % String(required_stone()).capitalize()
		Announcer.announce(
			"The way is sealed", subtitle,
			{"eyebrow": "Sealed", "color": Color(0.78, 0.7, 1.0), "duration": 2.2}
		)
		return
	# SOFT level gate (docs/pve_plan.md: floor - 2, warn-and-confirm): well below the
	# zone's band, entry starts with a HESITATION window — the warning shows on a
	# clear screen and the charge (rev + fade) holds until the window elapses, so
	# staying through it IS the confirm and stepping out cancels. The server delays
	# its dwell by the same span (Warper.warn_extra_for), keeping both ends in sync
	# with no round trip: the destination resource + our level are client-known.
	var warn_s: float = warn_extra_for(ClientState.player_level)
	if warn_s > 0.0:
		var zone_name: String = target_instance.display_title() if target_instance != null else "This area"
		Announcer.announce(
			"%s is dangerous below level %d" % [zone_name, gate_level()],
			"Step out to cancel.",
			{"eyebrow": "Warning", "color": Color(1.0, 0.5, 0.4), "duration": warn_s - 0.5}
		)
		var token: int = _warn_token
		get_tree().create_timer(warn_s).timeout.connect(func() -> void:
			if _local_inside and token == _warn_token:
				_start_charge())
		return
	_start_charge()


## True on a client whose LOCAL character lacks this portal's wardstone — OR on
## a placeholder portal with no destination yet (future biomes in the hub: the
## fade used to rise and hold on nothing, since the server never warps a
## target-less portal). Client UI only — the server enforces via
## can_join_instance / its target_instance check.
func _is_sealed() -> bool:
	if target_instance == null:
		return true
	var stone: StringName = required_stone()
	return not stone.is_empty() and not ClientState.wardstones.has(String(stone))


## Skin the sealed state: dimmed, near-still swirl + "(Sealed)" label — the
## portal is visible signage of the road ahead, just not usable yet. Called on
## ready and on every wardstone update (unseals live on the grant). Placeholder
## portals keep their authored label (it already carries the "(Lv N+)" text).
func _apply_sealed() -> void:
	var sealed: bool = _is_sealed()
	animated_sprite.modulate = Color(0.42, 0.42, 0.5) if sealed else Color.WHITE
	animated_sprite.speed_scale = 0.35 if sealed else 1.0
	if not destination_label.is_empty() and target_instance != null:
		var suffix: String = " (Lv %d+)" % gate_level() if gate_level() > 0 else ""
		label.text = destination_label + (" (Sealed)" if sealed else suffix)


## Begin the visible warp commitment in two phases: the swirl revs on a CLEAR
## screen for SPIN_UP_S (so the acceleration actually reads — the fade used to
## swallow it instantly), THEN the fade rises timed to the dwell. The server
## waits SPIN_UP_S + warp_delay_s, so both ends stay in sync. Split out of
## body-entered so a warned entry can hold the whole thing back.
func _start_charge() -> void:
	animated_sprite.speed_scale = REV_UP_SPEED
	var token: int = _warn_token
	get_tree().create_timer(SPIN_UP_S).timeout.connect(func() -> void:
		if not _local_inside or token != _warn_token:
			return # stepped out during the spin-up — no fade, server dwell recheck cancels too
		# Pass OUR peer id from the portal's multiplayer (scoped to the game branch, live
		# peer). WarpFade sits under /root, where the DEFAULT MultiplayerAPI has no peer —
		# get_unique_id() there errors and returns 0, which broke arrival detection and
		# left every warp on the slow fallback reveal.
		_fade = WarpFade.new(portal_color, warp_delay_s, FADE_IN_S, multiplayer.get_unique_id())
		get_tree().root.add_child.call_deferred(_fade))


func _on_local_body_exited(body: Node2D) -> void:
	if not _is_local_player(body):
		return
	_local_inside = false
	_warn_token += 1 # invalidate any pending hesitation-window charge
	animated_sprite.speed_scale = 0.35 if _is_sealed() else 1.0 # sealed stays dormant
	# Stepped out before the dwell finished: abort the fade (the server cancels its side
	# by re-checking overlap after the dwell). Once the fade-out completed, cancel() is
	# a no-op — that exit is just our own despawn as the warp goes through.
	if _fade != null:
		_fade.cancel()
		_fade = null


## True only on the client that owns [body]: player nodes are named after their peer id,
## and the server's own unique id (1) never names a player.
func _is_local_player(body: Node2D) -> bool:
	return body is Player and body.name.to_int() == multiplayer.get_unique_id()


## Self-contained full-screen fade covering a portal warp: fade to a dark tint of the
## portal color over the dwell, hold dark until we actually ARRIVE (our player node
## re-added under the new map), then fade back in and free itself. Arrival-synced, not
## a fixed hold — a slow map load stays covered instead of un-fading onto the old map.
## Lives directly under the tree ROOT so it survives the old map (and the portal that
## spawned it) being freed mid-transition.
class WarpFade extends CanvasLayer:
	var _rect: ColorRect
	var _tween: Tween
	var _color: Color
	var _out_s: float
	var _in_s: float
	var _committed: bool = false
	var _arrived: bool = false
	var _revealing: bool = false
	## Captured at creation from the PORTAL's (scoped) multiplayer — our own /root
	## default MultiplayerAPI has no peer, so we must not call get_unique_id() here.
	var _local_peer_id: int

	func _init(portal_color: Color, out_s: float, in_s: float, local_peer_id: int) -> void:
		layer = 100
		_color = Color(portal_color.r * 0.15, portal_color.g * 0.15, portal_color.b * 0.15)
		_out_s = out_s
		_in_s = in_s
		_local_peer_id = local_peer_id

	func _ready() -> void:
		_rect = ColorRect.new()
		_rect.color = Color(_color, 0.0)
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rect)
		# Arrival detection: the local player node is REUSED across maps — the switch
		# removes it from the old map and spawn_player re-adds it under the new one
		# (instance_manager.gd / instance_client.gd), so node_added IS our arrival
		# signal. Engine-level, no client-autoload coupling.
		get_tree().node_added.connect(_on_node_added)
		_tween = create_tween()
		_tween.tween_property(_rect, ^"color:a", 1.0, _out_s)
		_tween.tween_callback(_on_fade_out_done)
		# Fallback: the warp never landed (server cancelled at the dwell boundary) —
		# reveal rather than stranding the player behind a dark screen.
		get_tree().create_timer(_out_s + 2.5).timeout.connect(_reveal)

	## Abort a not-yet-committed fade (player stepped out during the dwell): reverse
	## quickly and free. After commit (fade-out done, warp firing) this is a no-op —
	## the body_exited felt then is just our own despawn as the warp goes through.
	func cancel() -> void:
		if _committed:
			return
		_committed = true
		_tween.kill()
		var back: Tween = create_tween()
		back.tween_property(_rect, ^"color:a", 0.0, 0.15)
		back.tween_callback(queue_free)

	func _on_fade_out_done() -> void:
		_committed = true
		if _arrived:
			_reveal()

	func _on_node_added(node: Node) -> void:
		if _arrived or not (node is Player):
			return
		if node.name.to_int() != _local_peer_id:
			return
		_arrived = true
		if _committed:
			_reveal()

	## Reveal the destination: brief settle (spawn position + camera limits apply),
	## then fade in and free. Idempotent — arrival and the fallback timer both land here.
	func _reveal() -> void:
		if _revealing:
			return
		_revealing = true
		var reveal_tween: Tween = create_tween()
		reveal_tween.tween_interval(0.2)
		reveal_tween.tween_property(_rect, ^"color:a", 0.0, _in_s)
		reveal_tween.tween_callback(queue_free)
