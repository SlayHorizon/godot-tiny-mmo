extends Navigator


@onready var back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/Header/BackButton


func _ready() -> void:
	super._ready()

	back_button.pressed.connect(_on_back_requested.bind({}))

	#DataSynchronizerClient._self.request_data(
		#&"guild.self",
		#func(data: Dictionary):
			#ClientState.guilds.data.merge(data, true),
		##ClientState.guilds.data.assign,
		#{},
		#InstanceClient.current.name
	#)
