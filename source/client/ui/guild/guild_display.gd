extends GuildPanel


@onready var button: Button = $MarginContainer/VBoxContainer/Button
@onready var guild_name_label: Label = $MarginContainer/VBoxContainer/Label


func open(data: Dictionary) -> void:
	guild_name_label.text = data.get("name", "No Guild Name")
	var is_in_guild: bool = data.get("is_in_guild", false)
	if is_in_guild:
		button.text = "Leave"
	else:
		button.text = "Request Join"
