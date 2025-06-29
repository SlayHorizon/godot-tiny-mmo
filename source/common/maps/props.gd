@tool
extends TileMapLayer

@export_tool_button("Call") var callback = foo


func foo():
	for pos: Vector2i in get_used_cells():
		var source_id = get_cell_source_id(pos)
		if source_id > -1:
			var scene_source: TileSetSource = tile_set.get_source(source_id)
			if scene_source is TileSetScenesCollectionSource:
				var alt_id = get_cell_alternative_tile(pos)
				# The assigned PackedScene.
				var scene = scene_source.get_scene_tile_scene(alt_id)
				if scene == preload("res://source/client/map_objects/collectibles/coin.tscn"):
					var coin: Area2D = scene.instantiate()
					coin.position = to_global(map_to_local(pos))
					$"../Coins".add_child(coin, true)
					coin.owner = EditorInterface.get_edited_scene_root()
