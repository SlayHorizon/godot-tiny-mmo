extends Control


var cache: Dictionary[int, Dictionary]

@onready var name_label: Label = $PanelContainer/HBoxContainer/VBoxContainer2/Label
@onready var stats_text: RichTextLabel = $PanelContainer/HBoxContainer/StatsContainer/RichTextLabel
@onready var description_text: RichTextLabel = $PanelContainer/HBoxContainer/VBoxContainer2/RichTextLabel
@onready var player_character: AnimatedSprite2D = $PanelContainer/HBoxContainer/VBoxContainer2/Control/Control/AnimatedSprite2D

@onready var message_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/MessageButton
@onready var friend_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/FriendButton


func open_player_profile(player_id: int) -> void:
	if cache.has(player_id):
		apply_profile(cache[player_id])
	else:
		InstanceClient.current.request_data(
			&"profile.get",
			apply_profile,
			{"q": player_id}
		)


func apply_profile(profile: Dictionary) -> void:
	print_debug(profile)
	var stats: Dictionary = profile.get("stats", {})
	var player_name: String = profile.get("name", "No Name")
	var player_skin: int = profile.get("skin", 0)
	var animation: String = profile.get("animation", "idle")
	var description: String = profile.get("description", "")
	
	var params: Dictionary = profile.get("params", {})
	
	description_text.clear()
	description_text.append_text(description)
	
	add_stats(stats)
	set_player_character(player_skin, animation)
	name_label.text = player_name
	
	friend_button.visible = params.get("self", false)
	message_button.visible = params.get("self", false)
	friend_button.text = "Add friend" if params.get("friend", false) == true else "Remove Friend"
	
	show()
	
	if profile.get("id", 0):
		cache[profile.get("id")] = profile
	

func add_stats(stats: Dictionary):
	stats_text.clear()
	stats_text.text = ""
	for stat_name: String in stats:
		print("%s: %s" % [stat_name, stats[stat_name]])
		stats_text.append_text("%s: %s" % [stat_name, stats[stat_name]])


func set_player_character(skin_id: int, animation: String) -> void:
	var skin: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", skin_id)
	if not skin:
		return
	
	player_character.stop()
	player_character.sprite_frames = skin
	if player_character.sprite_frames.has_animation(animation):
		player_character.play(animation)


func _on_close_pressed() -> void:
	hide()
