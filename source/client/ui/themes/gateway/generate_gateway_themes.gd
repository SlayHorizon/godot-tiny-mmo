@tool
extends EditorScript

## One-time scaffolder for the gateway palette themes. Open this script and run it
## (File > Run, or Ctrl+Shift+X) to create the four gateway_*.tres seeded with the
## palettes below, each baked via GatewayTheme.rebuild().
##
## This only holds the SEED values (accent idle/active + backdrop). The build logic
## and every other colour live on GatewayTheme itself — so after scaffolding, the
## .tres ARE the source of truth: tweak a colour in the inspector and press
## "Rebuild styleboxes". Re-run this only to add a palette or reset one from scratch.

const OUT_DIR: String = "res://source/client/ui/themes/gateway/"
const BG_DIR: String = "res://assets/sprites/gui/backgrounds/"
const FRAME_TEX: String = "res://assets/sprites/gui/gateway/frame_h_neutral.png"

const SEED: Dictionary = {
	"gold":      {"idle": Color(0.72, 0.56, 0.34), "active": Color(0.95, 0.74, 0.44), "bg": "desert.png"},
	"horizon":   {"idle": Color(0.42, 0.60, 0.78), "active": Color(0.58, 0.82, 0.98), "bg": "castle_garden.png"},
	"forest":    {"idle": Color(0.48, 0.62, 0.36), "active": Color(0.66, 0.85, 0.50), "bg": "fairy_forest.png"},
	"fireforge": {"idle": Color(0.76, 0.42, 0.28), "active": Color(0.97, 0.56, 0.32), "bg": "fireforge.png"},
}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var frame: Texture2D = load(FRAME_TEX)
	for name: String in SEED:
		var p: Dictionary = SEED[name]
		var theme: GatewayTheme = GatewayTheme.new()
		theme.palette_name = StringName(name)
		theme.idle = p["idle"]
		theme.active = p["active"]
		theme.background = load(BG_DIR + str(p["bg"]))
		theme.frame_texture = frame
		theme.rebuild()
		var path: String = "%sgateway_%s.tres" % [OUT_DIR, name]
		var err: Error = ResourceSaver.save(theme, path)
		print("gateway theme '%s' -> %s (%s)" % [name, path, error_string(err)])
	print("Done — generated %d gateway themes." % SEED.size())
