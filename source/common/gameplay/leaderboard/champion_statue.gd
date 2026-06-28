class_name ChampionStatue
extends Character
## A plaza statue wearing the current leaderboard leader's skin, with a rank / name / score
## plaque. Pulls the cached champions ONCE when the local player enters this map; clicking it
## opens the champion's profile by player_id (so it works even while they're offline). Extends
## Character purely to reuse the skin_id->sprite property + the AnimatedSprite/AnimationPlayer;
## no combat — the over-head health bar + default name label are hidden, it never takes damage.

## Which board this statue honors; maps to the all-time leaderboard board id.
@export_enum("pve", "pvp", "level") var category: String = "pve"

const BOARD_BY_CATEGORY: Dictionary = {"pve": "pve_total", "pvp": "pvp_total", "level": "level"}
const RANK_LABEL: Dictionary = {"pve": "#1 PvE", "pvp": "#1 PvP", "level": "Highest Level"}

## player_id of the displayed champion, for the click-to-profile (0 = none yet).
var _champion_id: int = 0
var _plaque: Label
var _hovered: bool = false


func _ready() -> void:
	health_bar_auto_hide = false # a statue never takes damage; no flashing bar ever
	super._ready()
	if multiplayer.is_server():
		return # display-only — all the statue logic is client-side
	progress_bar.hide()
	display_name_label.hide() # the plaque carries the name instead
	_build_plaque()
	_spawn_click_area()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer) -> void: _refresh())
	if ClientState.local_player != null:
		_refresh()


## Pull the cached champions once and apply this statue's category.
func _refresh() -> void:
	if InstanceClient.current == null:
		return
	var result: Array = await Client.request_data_await(
		&"leaderboard.champions", {}, InstanceClient.current.name
	)
	if result[1] != OK:
		return
	var champions: Dictionary = (result[0] as Dictionary).get("champions", {})
	var entry: Dictionary = champions.get(BOARD_BY_CATEGORY.get(category, "pve_total"), {})
	if entry.is_empty():
		_champion_id = 0
		_plaque.text = "%s\n(unclaimed)" % RANK_LABEL.get(category, "")
		return
	_champion_id = int(entry.get("id", 0))
	skin_id = int(entry.get("skin_id", 1)) # Character's setter swaps the sprite
	if animated_sprite != null and animated_sprite.sprite_frames != null \
			and animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")
	_plaque.text = "%s\n%s\n%s" % [
		RANK_LABEL.get(category, ""),
		str(entry.get("name", "?")),
		_score_line(int(entry.get("score", 0))),
	]


func _score_line(score: int) -> String:
	return "Level %d" % score if category == "level" else "%s kills" % _comma(score)


func _build_plaque() -> void:
	_plaque = Label.new()
	_plaque.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plaque.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plaque.z_index = 10
	# Scaled-down crisp text, mirroring DisplayNameLabel (scale 0.x + big font). Tweak the
	# position/scale here or in the scene if the plaque sits off over a given map.
	_plaque.scale = Vector2(0.25, 0.25)
	_plaque.custom_minimum_size = Vector2(480, 0)
	_plaque.position = Vector2(-60, -70)
	_plaque.add_theme_font_size_override(&"font_size", 32)
	_plaque.add_theme_constant_override(&"outline_size", 6)
	_plaque.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_plaque.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.7))
	add_child(_plaque)


## Click -> open the champion's profile by player_id (works offline; reuses the click-a-player
## flow). Hover suppresses the local player's attack so a click doesn't also fire the weapon.
func _spawn_click_area() -> void:
	var area: ClickableArea = ClickableArea.new()
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(28, 44)
	collision.shape = rect
	collision.position = animated_sprite.position
	area.add_child(collision)
	add_child(area)
	area.clicked.connect(_on_clicked)
	area.mouse_entered.connect(_set_hover.bind(true))
	area.mouse_exited.connect(_set_hover.bind(false))
	area.tree_exiting.connect(_set_hover.bind(false))


func _on_clicked() -> void:
	if _champion_id > 0:
		ClientState.player_profile_requested.emit(_champion_id)


func _set_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _hovered:
		return
	_hovered = on
	ClientState.world_interactables_hovered += 1 if on else -1


## 12400 -> "12,400" for the plaque score line.
func _comma(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
