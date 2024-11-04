extends Control


@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar


func _ready() -> void:
	ClientEvents.health_changed.connect(self._on_health_changed)


func _on_health_changed(new_value: float, is_max: bool) -> void:
	if is_max:
		progress_bar.max_value = new_value
	else:
		progress_bar.value = new_value
	update_label()


func update_label() -> void:
	label.text = "%d / %d" % [progress_bar.value, progress_bar.max_value]
