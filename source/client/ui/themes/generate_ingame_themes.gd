@tool
extends EditorScript
## In-game theme generator — the "coherent palette → many themes" tool. It recolours
## `theme_horizon.tres`'s ACCENT (the horizon blue) to each palette's accent and writes
## `theme_<name>.tres`. Palette NAMES mirror the gateway (gateway_theming.md) so one "Theme" picker can
## drive both sides by name. Surface / text / dark fills are shared across palettes (exactly like the
## gateway palettes, which only vary idle/active), so only the two accent RGBs are swapped — alpha is
## preserved because we replace just the `r, g, b` triple, not the whole `Color(...)`.
##
## Workflow (like generate_gateway_themes.gd): edit `theme_horizon.tres` for STRUCTURE (styleboxes,
## layout, scrollbar/XP), edit PALETTES below for COLOURS, then File ▸ Run to (re)generate the variants.

const MASTER: String = "res://source/client/ui/themes/theme_horizon.tres"
const OUT_DIR: String = "res://source/client/ui/themes/"
## theme_horizon's own resource uid — stripped from variants so they don't all collide on it (Godot
## assigns each a fresh one on import). Update if the master's uid ever changes.
const MASTER_UID: String = ' uid="uid://ckrgqln54yumd"'

## theme_horizon's accent RGB triples (the horizon blue) — must match the master exactly.
const FROM_ACTIVE: String = "0.58, 0.82, 0.98"
const FROM_IDLE: String = "0.42, 0.6, 0.78"

## name -> [active_rgb, idle_rgb], mirroring the gateway palettes (so theme_<name> pairs with
## gateway_<name>). horizon is the master itself, so it isn't listed.
const PALETTES: Dictionary = {
	"gold":      ["0.95, 0.74, 0.44", "0.72, 0.56, 0.34"],
	"forest":    ["0.66, 0.85, 0.5", "0.48, 0.62, 0.36"],
	"fireforge": ["0.97, 0.56, 0.32", "0.76, 0.42, 0.28"],
}


func _run() -> void:
	var base: String = FileAccess.get_file_as_string(MASTER).replace(MASTER_UID, "")
	if base.is_empty():
		push_error("Could not read master theme: " + MASTER)
		return
	for palette_name: String in PALETTES:
		var rgb: Array = PALETTES[palette_name]
		var text: String = base.replace("Color(" + FROM_ACTIVE, "Color(" + str(rgb[0]))
		text = text.replace("Color(" + FROM_IDLE, "Color(" + str(rgb[1]))
		var path: String = OUT_DIR + "theme_" + palette_name + ".tres"
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		print("Generated ", path)
	EditorInterface.get_resource_filesystem().scan()
	print("Done — regenerated ", PALETTES.size(), " in-game theme variants from theme_horizon.")
