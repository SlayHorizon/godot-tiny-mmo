extends NavPanel


const LOGOS: Array[Texture2D] = [
	preload("res://assets/sprites/guild_logos/wyvern.png"),
	preload("res://assets/sprites/guild_logos/kawaii_skull.png"),
	preload("res://assets/sprites/guild_logos/cute_crown.png"),
	preload("res://assets/sprites/guild_logos/cute_fish.png"),
]

@export var guild_members_panel: NavPanel
@export var guild_more_panel: NavPanel
@export var guild_name_label: Label

var guild_details: Dictionary

@onready var guild_logo: TextureRect = $GuildDisplay/VBoxContainer2/GuildLogo
@onready var extra_rich_text_label: RichTextLabel = $GuildDisplay/VBoxContainer2/ExtraRichTextLabel

@onready var guild_description_rich_text_label: RichTextLabel = $GuildDisplay/VBoxContainer/GuildDescriptionRichTextLabel
@onready var guild_stats_rich_text_label: RichTextLabel = $GuildDisplay/VBoxContainer/GuildStatsRichTextLabel

@onready var tag_button: Button = $GuildDisplay/VBoxContainer/HBoxContainer2/TagButton
@onready var members_button: Button = $GuildDisplay/VBoxContainer/HBoxContainer2/MembersButton
@onready var more_button: Button = $GuildDisplay/VBoxContainer/HBoxContainer2/MoreButton


func enter(payload: Dictionary = {}) -> void:
	if payload.is_empty():
		return
	guild_details = payload
	guild_name_label.text = payload.get("name", "No Guild Name")
	var is_in_guild: bool = payload.get("is_member", false)
	tag_button.visible = is_in_guild
	#members_button.visible = is_in_guild
	more_button.visible = is_in_guild
	if is_in_guild:
		var has_tag: bool = payload.get("tag", false)
		tag_button.text = "Untag" if has_tag else "Tag"
	
	guild_logo.texture = LOGOS[payload.get("logo_id", 0)]
	guild_description_rich_text_label.clear()
	guild_description_rich_text_label.append_text(payload.get("description", ""))

	extra_rich_text_label.clear()
	extra_rich_text_label.append_text("Leader: %s" % payload.get("leader_name", "Unknown"))


func exit(payload: Dictionary = {}) -> void:
	pass


func _on_tag_button_pressed() -> void:
	pass # Replace with function body.


func _on_members_button_pressed() -> void:
	navigate_requested.emit(NavigationAction.PUSH, guild_members_panel, guild_details)


func _on_more_button_pressed() -> void:
	navigate_requested.emit(NavigationAction.PUSH, guild_more_panel, guild_details)
