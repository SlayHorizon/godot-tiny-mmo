extends SettingWidget


var _items: Dictionary[String, int]


func _ready() -> void:
	assert(is_instance_valid(controller) and controller is OptionButton)

	for locale: String in TranslationServer.get_loaded_locales():
		var item_idx: int = controller.item_count
		var item_text: String = TranslationServer.get_locale_name(locale)
		controller.add_item(item_text, item_idx)
		controller.set_item_metadata(item_idx, locale)
		_items[locale] = item_idx

	controller.item_selected.connect(_on_language_item_selected)
	_load_defaults()


func _on_language_item_selected(index: int) -> void:
	var locale: String = controller.get_item_metadata(index)
	ClientState.settings.set_value(setting_section, setting_property, locale)


func _load_defaults() -> void:
	var locale: String = ClientState.settings.get_value(setting_section, setting_property)
	if locale == null or locale.is_empty(): return
	controller.select(_items[locale])
