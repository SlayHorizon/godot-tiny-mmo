extends Control


@export var name_label: Label

var cache: Dictionary[int, Dictionary]

@onready var stats_text: RichTextLabel = $PanelContainer/HBoxContainer/StatsContainer/RichTextLabel
@onready var description_text: RichTextLabel = $PanelContainer/HBoxContainer/VBoxContainer2/RichTextLabel
@onready var player_character: AnimatedSprite2D = $PanelContainer/HBoxContainer/VBoxContainer2/Control/Control/AnimatedSprite2D

@onready var message_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/MessageButton
@onready var friend_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/FriendButton
@onready var invite_guild_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/InviteGuildButton


func open_player_profile(player_id: int) -> void:
	#if cache.has(player_id):
		#print_debug("Cache used")
		#apply_profile(cache[player_id])
	#else:
	print("open = ", player_id)
	Client.request_data(
		&"profile.get",
		apply_profile,
		{"id": player_id},
		InstanceClient.current.name
	)


func apply_profile(profile: Dictionary) -> void:
	var stats: Dictionary = profile.get("stats", {})
	var player_name: String = profile.get("name", "No Name")
	var player_skin: int = profile.get("skin_id", 1)
	var animation: String = profile.get("animation", "idle")
	var description: String = profile.get("description", "Hello I'am new!")
	
	var is_self: bool = profile.get("self", false)
	description_text.clear()
	description_text.append_text(description)

	add_stats(stats)
	set_player_character(player_skin, animation)
	name_label.text = player_name
	if profile.get("guild_name", ""):
		name_label.text += " (%s)" % profile.get("guild_name", "")

	message_button.visible = not is_self;print_debug(profile)
	friend_button.visible = not is_self
	friend_button.disabled = is_self
	friend_button.text = "Add friend" if not profile.get("friend", false) else "Remove Friend"
	invite_guild_button.visible = profile.get("can_guild_invite", false)

	var is_friend: bool = profile.get("friend", false)
	if is_friend:
		friend_button.text = "Remove friend"
	else:
		friend_button.text = "Add friend"
		if friend_button.pressed.is_connected(_on_friend_button_pressed):
			friend_button.pressed.disconnect(_on_friend_button_pressed)
		friend_button.pressed.connect(
			_on_friend_button_pressed.bind(profile.get("id", 0)),
			CONNECT_ONE_SHOT
		)
	show()

	if profile.get("id", 0):
		cache[profile.get("id")] = profile


func add_stats(stats: Dictionary):
	stats_text.clear()
	stats_text.text = ""
	for stat_name: String in stats:
		print("%s: %s" % [stat_name, stats[stat_name]])
		stats_text.append_text("%s: %s\n" % [stat_name, stats[stat_name]])


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


func _on_friend_button_pressed(player_id: int) ->void:
	Client.request_data(&"friend.request", Callable(), {"id": player_id})
	friend_button.disabled = true
	friend_button.text = "Added"
