extends PanelContainer


@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var rich_text_label: RichTextLabel = $VBoxContainer/VBoxContainer/RichTextLabel
@onready var confirm_button: Button = $VBoxContainer/VBoxContainer/ConfirmButton


func display_waiting_popup(text: String = "WAITING") -> void:
	title_label.text = tr("WAITING")
	confirm_button.hide()
	rich_text_label.text = tr(text)
	show()


func confirm_message(message: String, title: StringName = &"PLEASE_CONFIRM", button: StringName = &"") -> void:
	title_label.text = tr(title)
	rich_text_label.text = message
	var original_button: String = confirm_button.text
	if button != &"":
		confirm_button.text = tr(button)
	confirm_button.show()
	show()
	# Put focus on OK so keyboard/gamepad players can dismiss it without a mouse.
	confirm_button.grab_focus()
	await confirm_button.pressed
	hide()
	confirm_button.text = original_button  # restore so other callers aren't affected


func show_reconnect_popup(seconds: int = 10) -> void:
	for remaining: int in range(seconds, 0, -1):
		var dots: String = ".".repeat(((seconds - remaining) % 3) + 1)
		display_waiting_popup(
			tr("RECONNECT_POPUP") % [
				remaining,
				dots
			]
		)
		await get_tree().create_timer(1.0).timeout

	hide()
