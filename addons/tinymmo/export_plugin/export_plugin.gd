extends EditorExportPlugin
## Server-export adjustments. The old approach was to null the client autoload
## globals so the .pck didn't carry client/ at all. That worked in a simpler
## codebase where no common/ files referenced ClientState. Now multiple common
## files (audio_manager, sfx_pool, duel_master, ...) reference it as a typed
## global — nulling the autoload un-declares the identifier and parse-fails
## every common file that mentions it, which cascades to half the codebase.
##
## Current approach: leave the autoload entries alone. The autoload scripts
## already guard themselves with `if not OS.has_feature("client"): queue_free()`,
## so on a server build they self-free at _ready and no runtime work happens.
## The .pck is slightly larger but the parser stays happy.


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if features.has("client"):
		return
	print("Server export detected. Client autoloads stay registered — they self-free via OS.has_feature(\"client\").")


func _export_end() -> void:
	pass


func _get_name() -> String:
	return "Server Export Adjustments"
