extends NavPanel


@export var guild_members_panel: NavPanel
@export var guild_name_label: Label

var guild_details: Dictionary

@onready var tag_button: Button = $GuildDisplay/VBoxContainer/HBoxContainer2/TagButton
@onready var members_button: Button = $GuildDisplay/VBoxContainer/HBoxContainer2/MembersButton
@onready var more_button: Button = $GuildDisplay/VBoxContainer/HBoxContainer2/MoreButton


func enter(payload: Dictionary = {}) -> void:
	if payload.is_empty():
		return
	guild_details = payload
	guild_name_label.text = payload.get("name", "No Guild Name")
	var is_in_guild: bool = payload.get("is_in_guild", false)
	tag_button.visible = is_in_guild
	#members_button.visible = is_in_guild
	#more_button.visible = is_in_guild
	if is_in_guild:
		var has_tag: bool = payload.get("tag", false)
		tag_button.text = "Untag" if has_tag else "Tag"


func exit(payload: Dictionary = {}) -> void:
	pass


func _on_tag_button_pressed() -> void:
	pass # Replace with function body.


func _on_members_button_pressed() -> void:
	navigate_requested.emit(NavigationAction.PUSH, guild_members_panel, guild_details)


func _on_more_button_pressed() -> void:
	pass # Replace with function body.
