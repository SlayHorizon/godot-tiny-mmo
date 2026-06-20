@tool
@icon("res://assets/node_icons/color/icon_map_colored.png")
class_name Map
extends Node2D


enum AOIMode {
	NONE,
	GRID,
}

enum ZoneMode {
	SAFE,
	PVP,
}

enum ZoneModifiers {
	ARENA,
	NO_SKILL,
	NO_MOUNT,
	NO_SUMMONS
}

@export_group("Area Of Interest")
@export var aoi_mode: AOIMode = AOIMode.NONE
@export var aoi_cell_size: Vector2i = Vector2i(250, 250)
@export var aoi_visible_radius_cells: int = 2
@export var aoi_margin_cells: int = 1
@export var aoi_origin: Vector2i = Vector2i.ZERO

@export_subgroup("Editor Debug Preview")
@export var preview_aoi: bool = true
@export var preview_aoi_follow_mouse: bool = true
@export var preview_rect: Rect2 = Rect2(-4096, -4096, 8192, 8192)
@export var aoi_test_point: Vector2 = Vector2.ZERO

# Independent from AOI
@export_group("Zones")
@export var default_mode: ZoneMode = ZoneMode.SAFE
@export_flags("NO_SKILL", "NO_CONSUMABLES", "NO_MOUNT", "NO_SUMMONS") var default_modifiers: int = 0
@export var zone_cell_size: Vector2i = Vector2i(64, 64)

@export_group("")
@export var replicated_props_container: ReplicatedPropsContainer
@export var map_background_color: Color = Color(0,0,0)
## Looping background music for this map, crossfaded in when the local player enters
## the instance (see Client._on_instance_changed). Leave empty to keep whatever track
## is already playing — e.g. a small building inherits the overworld's music.
@export var music: AudioStream
## Ambient weather overlays applied when the local player enters this map. Each entry is
## one stacked effect, so a map can run several at once (e.g. leaves + cloud shadows +
## fog). Empty = clear skies. Driven by the same instance hook as [member music]. See
## WeatherLayer.
@export var weather: Array[WeatherResource]
@export_group("Camera limits")
## Per-edge camera clamp (world px), mirroring Camera2D's own limit_* properties. On entry
## the local player's camera is clamped to whichever edges you set, so it never pans past the
## map into black. Each edge defaults to ±10,000,000 (effectively unbounded), so set ONLY the
## sides you want — e.g. camera_limit_left = -32 stops the camera at x = -32 and leaves the
## rest free. We use multiple TileMapLayers, so these are authored per map (not auto-derived).
## See LocalPlayer._apply_camera_limits.
@export var camera_limit_left: int = -10000000
@export var camera_limit_top: int = -10000000
@export var camera_limit_right: int = 10000000
@export var camera_limit_bottom: int = 10000000

var warpers: Dictionary[int, Warper]
## shop registry id -> ShopResource, gathered from the merchant nodes placed in this
## map (mirrors how warpers are collected). The server uses this to resolve/verify a
## shop the player is actually at, rather than trusting a client-sent id.
var shops: Dictionary[int, ShopResource]
## node-name -> MineableNode, gathered from the gathering nodes placed in this
## map (same pattern as warpers/shops). The server resolves the node a player
## mines by name (Godot guarantees uniqueness within a parent).
var mineables: Dictionary[StringName, MineableNode]
## crafting-station registry id -> CraftingStationResource, gathered from the station
## nodes placed in this map (mirrors shops). The server resolves/verifies the station
## a player crafts at, rather than trusting a client-sent id.
var crafting_stations: Dictionary[int, CraftingStationResource]
## giver_id -> quest source: a QuestInteraction on an NPC (registered by its
## register()). Exposes `quests` + `giver_name`, read by the quest handlers. The
## server resolves offered quests (never a client-sent list).
var quest_givers: Dictionary[int, Object]
## table_id -> TradeTable node. The server holds each table's trade session.
var trade_tables: Dictionary[int, TradeTable]
## flag_id -> TerritoryFlag node, gathered from the basing flags placed in this
## map. The server resolves which flag is being damaged/captured.
var territory_flags: Dictionary[int, TerritoryFlag]
## master_id -> DuelMaster NPC. The server queues sparring through these.
var duel_masters: Dictionary[int, DuelMaster]
## master_id -> DungeonMaster lobby station. The server queues dungeon runs here.
var dungeon_masters: Dictionary[int, DungeonMaster]


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint():
		return

	for child: Node in get_children():
		if child is Warper:
			var warper_id: int = child.warper_id
			warpers[warper_id] = child
		elif child is MineableNode:
			mineables[child.name] = child
		elif child is CraftingStation and child.station:
			crafting_stations[int(child.station.get_meta(&"id", 0))] = child.station
		elif child is TradeTable:
			trade_tables[child.table_id] = child
		elif child is TerritoryFlag:
			territory_flags[child.flag_id] = child
		elif child is DuelMaster:
			duel_masters[child.master_id] = child
		elif child is DungeonMaster:
			dungeon_masters[child.master_id] = child

	if not multiplayer.is_server():
		RenderingServer.set_default_clear_color(map_background_color)


func get_spawn_position(warper_id: int = 0) -> Vector2:
	if warpers.has(warper_id):
		return warpers[warper_id].global_position
	return Vector2.ZERO


## The shop sold by a merchant in this map, or null.
func get_shop(shop_id: int) -> ShopResource:
	return shops.get(shop_id)


## The gathering node with this name in this map, or null.
func get_mineable(node_name: StringName) -> MineableNode:
	return mineables.get(node_name)


## The crafting station with this registry id in this map, or null.
func get_crafting_station(station_id: int) -> CraftingStationResource:
	return crafting_stations.get(station_id)


## The quest-giver NPC with this id in this map, or null.
func get_quest_giver(giver_id: int) -> Object:
	return quest_givers.get(giver_id)


## The trade table with this id in this map, or null.
func get_trade_table(table_id: int) -> TradeTable:
	return trade_tables.get(table_id)


## The territory flag with this id in this map, or null.
func get_territory_flag(flag_id: int) -> TerritoryFlag:
	return territory_flags.get(flag_id)


## The duel master with this id in this map, or null.
func get_duel_master(master_id: int) -> DuelMaster:
	return duel_masters.get(master_id)


func get_dungeon_master(master_id: int) -> DungeonMaster:
	return dungeon_masters.get(master_id)


func override_map_rules(instance_resource: InstanceResource) -> void:
	# Can be implemented later.
	# Could override fields when instances of the same map need different rules.
	pass


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if aoi_mode == AOIMode.GRID and preview_aoi:
		_draw_aoi_preview()


func _draw_aoi_preview() -> void:
	var grid_color: Color = Color(1, 1, 1, 0.18)
	var visible_fill: Color = Color(0.15, 0.75, 1.0, 0.14)
	var visible_border: Color = Color(0.15, 0.85, 1.0, 0.95)
	var margin_border: Color = Color(0.15, 0.75, 1.0, 0.70)

	# EditorInterface is editor-only — the identifier doesn't exist in exports
	# and would parse-fail. Look it up dynamically so the parser sees only
	# Engine.get_singleton(), which is always available. _draw only fires in
	# the editor anyway (this is a @tool script), so the singleton is there.
	var zoom_scale: float = 1.0
	if Engine.has_singleton("EditorInterface"):
		var editor: Object = Engine.get_singleton("EditorInterface")
		zoom_scale = editor.get_editor_viewport_2d().global_canvas_transform.get_scale().x
	var px: float = 2.0 / zoom_scale
	var w_grid: float = clamp(1.25 * px, 0.75, 8.0)
	var w_border: float = clamp(2.25 * px, 1.0, 14.0)
	var dash_step: float = clamp(16.0 * px, 8.0, 32.0)

	# 1 Grid lines (aligned to origin)
	var x0: float = _snap_floor_to_cell(preview_rect.position.x, aoi_cell_size.x, aoi_origin.x)
	var y0: float = _snap_floor_to_cell(preview_rect.position.y, aoi_cell_size.y, aoi_origin.y)
	var x1: float = preview_rect.position.x + preview_rect.size.x
	var y1: float = preview_rect.position.y + preview_rect.size.y

	var x: float = x0
	while x <= x1:
		draw_line(Vector2(x, y0), Vector2(x, y1), grid_color, w_grid, true)
		x += float(aoi_cell_size.x)

	var y: float = y0
	while y <= y1:
		draw_line(Vector2(x0, y), Vector2(x1, y), grid_color, w_grid, true)
		y += float(aoi_cell_size.y)

	# 2 Visible window + margin ring around a test point
	var origin_v: Vector2 = Vector2(aoi_origin)
	var p: Vector2 = get_global_mouse_position() if preview_aoi_follow_mouse else aoi_test_point
	var rel: Vector2 = p - origin_v
	var cell_v: Vector2 = (rel / Vector2(aoi_cell_size)).floor()
	var cell: Vector2i = Vector2i(cell_v)

	var r: int = aoi_visible_radius_cells
	var m: int = max(0, aoi_margin_cells)

	var vis_rect: Rect2 = Rect2(
		origin_v + Vector2(cell - Vector2i(r, r)) * Vector2(aoi_cell_size),
		Vector2((2 * r + 1) * aoi_cell_size.x, (2 * r + 1) * aoi_cell_size.y)
	)
	var mar_rect: Rect2 = Rect2(
		origin_v + Vector2(cell - Vector2i(r + m, r + m)) * Vector2(aoi_cell_size),
		Vector2((2 * (r + m) + 1) * aoi_cell_size.x, (2 * (r + m) + 1) * aoi_cell_size.y)
	)

	# Fill visible window
	draw_rect(vis_rect, visible_fill, true)
	# Borders (dashed margin)
	_draw_rect_border(vis_rect, visible_border, w_border)
	if m > 0:
		_draw_rect_border(mar_rect, margin_border, w_border, true, dash_step)

	# Origin crosshair
	_draw_cross(origin_v, Color(1, 1, 0, 0.9), 10.0 * px, max(1.0, 2.0 * px))
	_draw_cross(p, Color(1, 1, 0, 0.9), 10.0 * px, max(1.0, 2.0 * px))


func _snap_floor_to_cell(v: float, cell: int, origin: int) -> float:
	var rel: float = v - float(origin)
	return float(origin) + floor(rel / float(cell)) * float(cell)


func _draw_rect_border(r: Rect2, color: Color, width: float, dashed: bool=false, step: float=16.0) -> void:
	if dashed:
		var pts: Array[Vector2] = [
			r.position,
			r.position + Vector2(r.size.x, 0.0),
			r.position + r.size,
			r.position + Vector2(0.0, r.size.y)
		]
		for i in pts.size():
			_draw_dashed_line(pts[i], pts[(i + 1) % pts.size()], color, width, step)
	else:
		draw_rect(r, color, false, width)


func _draw_dashed_line(a: Vector2, b: Vector2, color: Color, width: float, step: float) -> void:
	var dir: Vector2 = b - a
	var length: float = dir.length()
	if length <= 0.001:
		return
	var n: int = int(length / step)
	if n <= 0:
		draw_line(a, b, color, width, true)
		return
	var v: Vector2 = dir / float(n)
	for i in n:
		if (i % 2) == 0:
			draw_line(a + v * float(i), a + v * float(i + 1), color, width, true)


func _draw_cross(c: Vector2, color: Color, size: float, width: float) -> void:
	draw_line(c + Vector2(-size, 0.0), c + Vector2(size, 0.0), color, width, true)
	draw_line(c + Vector2(0.0, -size), c + Vector2(0.0, size), color, width, true)


# Returns defaults + every ZonePatch2D polygon in MAP space.
# This is the only thing SSM needs at startup to build a zone grid.
func get_zone_authoring_data() -> Dictionary:
	var patches: Array
	var zone_patches: Array[ZonePatch2D]
	zone_patches.assign(find_children("*", "ZonePatch2D", false))

	for zone_patch: ZonePatch2D in zone_patches:
		if not zone_patch.enabled:
			continue
		patches.append(zone_patch.get_bake_payload())

	return {
		"default_mode": default_mode,
		"default_modifiers": default_modifiers,
		"zone_cell_size": zone_cell_size,
		"patches": patches,
	}
