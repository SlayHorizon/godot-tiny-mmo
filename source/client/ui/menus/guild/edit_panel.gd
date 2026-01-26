extends NavPanel


@export var guild_more_panel: NavPanel

const LOGOS: Array[Texture2D] = [
	preload("res://assets/sprites/guild_logos/wyvern.png"),
	preload("res://assets/sprites/guild_logos/kawaii_skull.png"),
	preload("res://assets/sprites/guild_logos/cute_crown.png"),
	preload("res://assets/sprites/guild_logos/cute_fish.png"),
]

var guild_details: Dictionary

@onready var texture_rect: TextureRect = $HBoxContainer/VBoxContainer/TextureRect
@onready var description_edit: TextEdit = $HBoxContainer/DescriptionEdit


func enter(payload: Dictionary = {}) -> void:
	if payload.is_empty():
		return
	guild_details = payload


func _on_logo_button_pressed() -> void:
	var logo_id: int = guild_details.get("logo_id", 0)
	logo_id = (logo_id + 1) % LOGOS.size()

	texture_rect.texture = LOGOS[logo_id]
	guild_details["logo_id"] = logo_id


func _on_save_button_pressed() -> void:
	if description_edit.text.length() > 220:
		description_edit.text  = description_edit.text.left(220)
	guild_details["description"] = description_edit.text

	Client.request_data(
		&"guild.edit",
		_on_save_result,
		{
			"logo_id": guild_details.get("logo_id", 0),
			"description": description_edit.text,
			"name": guild_details.get("name", "")
		}
	)

func _on_save_result(payload: Dictionary) -> void:
	if not payload.has("error"):
		navigate_requested.emit.bind(NavigationAction.PUSH, guild_more_panel, guild_details)
