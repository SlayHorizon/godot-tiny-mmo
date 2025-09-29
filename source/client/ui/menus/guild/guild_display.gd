extends GuildPanel


@export var no_guild_panel: GuildPanel

@onready var button: Button = $MarginContainer/VBoxContainer/Button
@onready var guild_name_label: Label = $MarginContainer/VBoxContainer/Label


func open(data: Dictionary) -> void:
	guild_name_label.text = data.get("name", "No Guild Name")
	var is_in_guild: bool = data.get("is_in_guild", false)
	if is_in_guild:
		button.text = "Leave"
	else:
		button.text = "Request Join"


func _on_button_pressed() -> void:
	# Quick n Dirty
	if button.text.begins_with("Leave"):
		InstanceClient.current.request_data(
			&"guild.quit",
			func(d): swap_requested.emit(no_guild_panel, {})
		)
	#else:
		#InstanceClient.current.request_data(
			#&"guild.apply",
			#Callable()
		#)
