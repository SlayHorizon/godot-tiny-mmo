class_name BetterThemeDB


static var theme: Theme:
	get = get_theme


static func get_theme() -> Theme:
	if not theme:
		theme = load(
			ProjectSettings.get_setting("gui/theme/custom", "res://source/client/ui/themes/theme_navy.tres")
		)
	return theme
