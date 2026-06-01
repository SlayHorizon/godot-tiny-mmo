extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.


signal local_player_ready(local_player: LocalPlayer)
signal player_profile_requested(id: int)
signal open_menu_requested(menu: StringName, arg: Variant)
signal dm_requested(id: int)
## Emitted on the client after a successful gather (mining, ...). Carries the
## gather result so UI can refresh xp/inventory.
signal gather_succeeded(result: Dictionary)
## The quest currently shown on the HUD tracker changed (0 = none).
signal tracked_quest_changed(quest_id: int)

## Quest id pinned to the HUD tracker (manually via the log, or the latest accepted).
var tracked_quest_id: int

## The trade table whose panel is open (0 = closed). Independent of being seated: you can
## open a table's panel to view/join it, and closing the panel does NOT leave your seat.
signal viewed_trade_changed(table_id: int)
var viewed_trade_table: int
## Emitted whenever the active input type changes. [br]
## [b]Example[/b]: switching from keyboard to gamepad.
signal input_changed(input_type: InputComponent.InputType)

var local_player: LocalPlayer
var player_id: int
var active_guild_id: int
var stats: DataDict = DataDict.new()
var settings: Settings = Settings.new()
var quick_slots: DataDict = DataDict.new()
var guilds: DataDict = DataDict.new()

## Set of player_ids the local user has blocked. Used by chat_menu to drop
## incoming messages from blocked senders (server already filters too, but
## this catches the brief window between a Block click and the next message
## the server may have already dispatched). Hydrated once at instance entry
## via social.block.list and kept in sync as the user blocks/unblocks.
var blocked_ids: Dictionary[int, bool]
## Fired when blocked_ids changes — profile/chat-settings menus listen so
## their UI mirrors the live state without a refresh round-trip.
signal blocked_ids_changed

var language: String:
	set(value):
		var loaded_locales: PackedStringArray = TranslationServer.get_loaded_locales()
		if loaded_locales.is_empty() or value not in loaded_locales: value = "en_US"
		language = value
		TranslationServer.set_locale(value)

var input_type: InputComponent.InputType:
	set(value):
		input_type = value
		input_changed.emit(value)


func _ready() -> void:
	if not GameMode.is_client():
		queue_free()
	Client.subscribe(&"player_id.set", func(payload: Dictionary):
		player_id = payload.get("player_id", 0))
	Client.subscribe(&"active_guild_id.set", func(payload: Dictionary):
		active_guild_id = payload.get("active_guild_id", 0))
	Client.subscribe(&"stats.get", func(data: Dictionary):
		stats.data.merge(data, true)
	)
	Client.subscribe(&"combat.reward", _on_combat_reward)
	Client.subscribe(&"quest.update", func(data: Dictionary):
		for message: String in data.get("messages", []):
			Toaster.toast(message)
	)

	settings.load_file()
	settings.setting_changed.connect(_on_setting_changed)
	language = settings.data.get(&"general", {}).get(&"language", "en_US")


## Server-pushed kill rewards: surface them as toasts.
func _on_combat_reward(data: Dictionary) -> void:
	var xp: int = int(data.get("xp", 0))
	if xp > 0:
		Toaster.toast("+%d XP" % xp)
	for entry: Dictionary in data.get("loot", []):
		Toaster.toast("Looted %d %s" % [int(entry.get("amount", 1)), str(entry.get("name", "item"))])
	if int(data.get("levels_gained", 0)) > 0:
		Toaster.toast("Level %d! +%d attribute points" % [int(data.get("level", 1)), int(data.get("points_gained", 0))])


## Pin a quest to the HUD tracker (from the quest log, or auto on accept).
func set_tracked_quest(quest_id: int) -> void:
	tracked_quest_id = quest_id
	tracked_quest_changed.emit(quest_id)


## Replace the local block list (called after a social.block.list bootstrap).
func set_blocked_ids(entries: Array) -> void:
	blocked_ids.clear()
	for entry: Dictionary in entries:
		blocked_ids[int(entry.get("id", 0))] = true
	blocked_ids_changed.emit()


## Mark a player as blocked locally. Server confirms first.
func add_blocked(id: int) -> void:
	if id <= 0:
		return
	blocked_ids[id] = true
	blocked_ids_changed.emit()


## Unmark a player. Server confirms first.
func remove_blocked(id: int) -> void:
	blocked_ids.erase(id)
	blocked_ids_changed.emit()


## Open/close the trade panel for a table (0 = close). Does not join or leave a seat.
func set_viewed_trade(table_id: int) -> void:
	viewed_trade_table = table_id
	viewed_trade_changed.emit(table_id)


func _on_setting_changed(section: StringName, property: StringName, new_value: Variant) -> void:
	match property:
		"language":
			language = new_value


class DataDict:
	signal data_changed(property: Variant, value: Variant)
	
	var data: Dictionary
	
	
	func _set(property: StringName, value: Variant) -> bool:
		if property == &"data":
			return false
		data[property] = value
		data_changed.emit(property, value)
		return true
	
	
	func set_key(key: Variant, value: Variant) -> void:
		data.set(key, value)
		data_changed.emit(key, value)
	
	
	func get_key(property: Variant, default: Variant = null) -> Variant:
		return data.get(property, default)


class Settings:
	const SETTINGS_PATH: String = "user://client_settings.cfg"
	const DEFAULTS_PATH: String = "res://data/config/client_default_settings.cfg"

	signal setting_changed(section: StringName, property: StringName, new_value: Variant)

	var data: Dictionary


	func load_file() -> void:
		var defaults: Dictionary = ConfigFileUtils.load_file_with_defaults(DEFAULTS_PATH, {})
		data = ConfigFileUtils.load_file_with_defaults(SETTINGS_PATH, defaults)


	func save() -> void:
		ConfigFileUtils.save_sections(data, SETTINGS_PATH)
	

	func get_value(section: StringName, property: StringName) -> Variant:
		return data.get(section, {}).get(property)


	func set_value(section: StringName, property: StringName, value: Variant) -> void:
		data[section][property] = value
		setting_changed.emit(section, property, value)
		save()
