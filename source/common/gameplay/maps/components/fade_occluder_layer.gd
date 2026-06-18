class_name FadeOccluderLayer
extends TileMapLayer
## Set this script on a TileMapLayer that holds tall, view-blocking tiles (tree
## canopies, roofs, cliff faces). On the CLIENT it fades the tiles right around the
## local player so you can always see your own character behind them.
##
## Map-structure-agnostic ON PURPOSE: it only needs the local player's world
## position, so it works whether the layer lives under a WorldTiles node (overworld)
## or directly under Map (dungeon). This IS the convention — "should fade behind the
## player" = wear this script. No groups, no node paths, no baking.
##
## How it works: when the player crosses into a new tile we ask the layer to refresh
## its runtime tile data (cheap — only on cell change, not every frame). The two
## TileMapLayer virtuals then drop alpha on just the cells within [member
## fade_radius_cells]; cells outside the window render at full alpha, so walking away
## restores them automatically. Pure client visual — the headless server disables it.

## Radius (in tiles) of the soft fade window around the player.
@export var fade_radius_cells: int = 2
## Alpha a fully-occluding (closest) tile drops to. 1.0 = no fade, 0 = invisible.
@export_range(0.0, 1.0) var min_alpha: float = 0.35

## The player's current cell in THIS layer's coordinates. Seeded to an impossible
## value so the first frame always triggers a refresh.
var _player_cell: Vector2i = Vector2i(0x3fffffff, 0x3fffffff)


func _ready() -> void:
	# Server is headless (nothing to fade) and has no local player — stay inert.
	if not GameMode.is_client():
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	var local_player: Node2D = ClientState.local_player
	if local_player == null:
		return
	var cell: Vector2i = local_to_map(to_local(local_player.global_position))
	if cell == _player_cell:
		return # same tile — nothing changed, skip the refresh
	_player_cell = cell
	notify_runtime_tile_data_update()


## Only cells inside the fade window need a per-frame tweak; everything else uses
## its normal (full-alpha) tile data.
func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	return absi(coords.x - _player_cell.x) <= fade_radius_cells \
		and absi(coords.y - _player_cell.y) <= fade_radius_cells


## Fade by Chebyshev (square-ring) distance from the player's cell — the tile the
## player stands under goes most see-through, fading back to opaque at the edge.
func _tile_data_runtime_update(coords: Vector2i, tile_data: TileData) -> void:
	var ring: int = maxi(absi(coords.x - _player_cell.x), absi(coords.y - _player_cell.y))
	var closeness: float = 1.0 - float(ring) / float(fade_radius_cells + 1)
	tile_data.modulate.a = lerpf(1.0, min_alpha, clampf(closeness, 0.0, 1.0))
