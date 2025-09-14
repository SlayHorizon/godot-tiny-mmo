class_name ContentIndex
extends Resource


@export var content_name: StringName
@export var version: int
@export var next_id: int = 1
##{
##	&"slug": &"human_readable,
##	&"id": 123,
##	&"path": &"res://item.tres" or value ?
##}
## 
@export var entries: Array[Dictionary]

@export var scan_path: String
@export var filters: PackedStringArray
