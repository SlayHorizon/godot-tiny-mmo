extends PanelContainer


@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var rich_text_label: RichTextLabel = $VBoxContainer/VBoxContainer/RichTextLabel
@onready var confirm_button: Button = $VBoxContainer/VBoxContainer/ConfirmButton


func display_waiting_popup(text: String = "Waiting ...") -> void:
	confirm_button.hide()
	rich_text_label.text = text
	show()


func confirm_message(message: String) -> void:
	title_label.text = "Please Confirm"
	rich_text_label.text = message
	confirm_button.show()
	show()
	await confirm_button.pressed
	hide()
