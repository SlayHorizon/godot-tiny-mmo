extends Control


@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar


func _ready() -> void:
	ClientEvents.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			var health_component: HealthComponent = local_player.get_node("HealthComponent")
			health_component.health_changed.connect(_on_health_changed)
			health_component.max_health_changed.connect(_on_max_health_changed)
	)


func _on_health_changed(new_health: float) -> void:
	progress_bar.value = new_health
	update_label()


func _on_max_health_changed(new_max_health: float) -> void:
	progress_bar.max_value = new_max_health
	update_label()


func update_label() -> void:
	label.text = "%d / %d" % [progress_bar.value, progress_bar.max_value]
