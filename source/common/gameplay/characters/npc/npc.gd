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

@export var npc_resource: NPCResource

## Quest-giver key, mirrored from the resource (interactions resolve quests by it).
var npc_id: int


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
	var area: Area2D = Area2D.new()
	area.input_pickable = true
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = _sprite_size()
	collision.shape = rect
	collision.position = animated_sprite.position
	area.add_child(collision)
	add_child(area)
	area.input_event.connect(_on_clicked)


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


func _on_clicked(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if clicked:
		_open_interactions()


func _open_interactions() -> void:
	if npc_resource == null:
		return
	var entries: Array = []
	for interaction: NPCInteraction in npc_resource.interactions:
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
