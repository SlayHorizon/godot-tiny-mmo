class_name NPC
extends Character
## A friendly, INTERACTIVE NPC (shopkeeper, quest giver, ...). Everything about it
## — name, look, greeting, and what it can do — lives in one NPCResource. Clicking
## opens a greeting dialogue (or, with a single action, that action directly).
## Place it as a direct child of a Map, like other interactables.
##
## Hostile enemies are HostileNpc — a separate Character subclass — so they get
## none of this interaction machinery. The display name uses Character.display_name
## (which drives the shared name label).

const MARKER_SCENE: PackedScene = preload("res://source/common/gameplay/maps/components/interactable_marker.tscn")
## Max distance (px) the local player can be from the NPC and still interact, so
## you can't talk to or shop with an NPC from across the map.
const INTERACT_RANGE: float = 90.0

@export var npc_resource: NPCResource

## Quest-giver key, mirrored from the resource (interactions resolve quests by it).
var npc_id: int

## Client-only: true while the cursor is over this NPC's click-area, so we contribute
## exactly once to ClientState.world_interactables_hovered (and can undo it on free).
var _interactable_hovered: bool = false


func _ready() -> void:
	_apply_resource()
	super._ready() # Character setup (animations, sync, etc.)
	# Friendly NPCs never take damage — hide the health bar Character wires up.
	if has_node(^"ProgressBar"):
		($ProgressBar as CanvasItem).hide()
	if npc_resource == null:
		return

	if multiplayer.is_server():
		# Server: register each capability so its data-request handler resolves it.
		# No client visuals server-side.
		var map: Map = _find_map()
		if map != null:
			for interaction: NPCInteraction in npc_resource.interactions:
				if interaction == null:
					continue # empty array slot (a designer added a slot but no resource) — skip, don't crash
				interaction.register(map, self)
		return

	# --- Client only past here ---
	# Idle the (static) NPC so it breathes instead of freezing on frame 0.
	if animation_tree != null:
		animation_tree.active = true
	anim = Animations.IDLE
	# An interactive NPC needs a click target + a floating "talk" glyph — spawn
	# both dynamically so the scene stays clean and the server carries no useless
	# nodes.
	if not npc_resource.interactions.is_empty():
		_spawn_click_area()
		_spawn_marker()


func _apply_resource() -> void:
	if npc_resource == null:
		return
	npc_id = npc_resource.npc_id
	display_name = npc_resource.npc_name # drives the shared name label (client)
	if npc_resource.skin != null:
		skin_id = 0 # disable id-based skin; drive it directly (mirrors HostileNpc)
		animated_sprite.sprite_frames = npc_resource.skin


## Walk up to the owning Map (interactables are placed as map children).
func _find_map() -> Map:
	var node: Node = get_parent()
	while node != null:
		if node is Map:
			return node
		node = node.get_parent()
	return null


func _spawn_click_area() -> void:
	var area: ClickableArea = ClickableArea.new()
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = _sprite_size()
	collision.shape = rect
	collision.position = animated_sprite.position
	area.add_child(collision)
	add_child(area)
	area.clicked.connect(_on_clicked) # ClickableArea does the left-click/tap detection
	# Mirror the GUI combat-gate into the world: while the cursor is over this talkable
	# NPC, suppress the player's attack so a click TALKS instead of also shooting. Undone
	# on free (tree_exiting) so the shared counter can't leak and stick combat off.
	area.mouse_entered.connect(_set_interactable_hover.bind(true))
	area.mouse_exited.connect(_set_interactable_hover.bind(false))
	area.tree_exiting.connect(_set_interactable_hover.bind(false))


## Client-only: suppress the local player's combat while the cursor is over this NPC (so
## a click talks, not shoots). Counted on ClientState; the [member _interactable_hovered]
## guard keeps it to a single contribution we can cleanly undo on mouse-exit / free.
func _set_interactable_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _interactable_hovered:
		return
	_interactable_hovered = on
	ClientState.world_interactables_hovered += 1 if on else -1


## Float a "DIALOG" glyph above the head so players know the NPC is talkable.
func _spawn_marker() -> void:
	var marker: InteractableMarker = MARKER_SCENE.instantiate()
	marker.kind = InteractableMarker.Kind.DIALOG
	var top_y: float = animated_sprite.position.y - _sprite_size().y * 0.5
	marker.position = Vector2(0, top_y - 8.0)
	add_child(marker)


## Best-effort click-box / marker-offset size from the idle frame, with a fallback.
func _sprite_size() -> Vector2:
	var fallback: Vector2 = Vector2(28, 44)
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(animated_sprite.animation):
		return fallback
	var tex: Texture2D = frames.get_frame_texture(animated_sprite.animation, 0)
	return tex.get_size() if tex != null else fallback


func _on_clicked() -> void:
	if _player_in_range():
		_open_interactions()
	else:
		# A too-far tap shouldn't be a silent no-op, so nudge the player closer.
		var who: String = display_name if not display_name.is_empty() else "them"
		Toaster.toast("Too far from %s." % who)


## True when the local player is close enough to interact. Clicks from too far are
## silently ignored, so you have to walk up to the NPC (this also underpins the
## "rooted while talking" model). Null-safe before the local player exists.
func _player_in_range() -> bool:
	var lp: LocalPlayer = ClientState.local_player
	if lp == null or not is_instance_valid(lp):
		return false
	return global_position.distance_to(lp.global_position) <= INTERACT_RANGE


func _open_interactions() -> void:
	if npc_resource == null:
		return
	# Talking to a quest-giver NPC counts as "visiting" it — advance any
	# "talk to NPC X" objective server-side (fire-and-forget; the server pushes
	# quest.update if anything changed). Pure shop/flavor NPCs (npc_id 0) skip it.
	if npc_id > 0 and InstanceClient.current != null:
		Client.request_data(&"npc.interact", func(_r: Dictionary) -> void: pass, {"npc": npc_id}, InstanceClient.current.name)
	var entries: Array = []
	for interaction: NPCInteraction in npc_resource.interactions:
		if interaction == null:
			continue # empty array slot — skip
		var entry: Dictionary = interaction.menu_entry(self)
		if not entry.is_empty():
			entries.append(entry)
	if entries.is_empty():
		return
	# A single ROUTING action (shop, quests, ...) opens directly — no pointless
	# one-option dialogue. A lone "Talk" still goes through the box (it plays lines
	# inline, it has no menu to route to).
	if entries.size() == 1 and entries[0].has("menu"):
		ClientState.open_menu_requested.emit(entries[0]["menu"], entries[0]["arg"])
		return
	# Several → the greeting dialogue.
	ClientState.open_menu_requested.emit(&"npc", {
		"name": display_name,
		"greeting": npc_resource.greeting,
		"entries": entries,
	})
