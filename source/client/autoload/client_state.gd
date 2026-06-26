extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.


signal local_player_ready(local_player: LocalPlayer)
signal player_profile_requested(id: int)
## Same as player_profile_requested but the target is identified by PEER id (a world
## click) — the client doesn't carry the persistent player_id, so the server resolves
## it (see profile.get.gd).
signal player_profile_by_peer_requested(peer_id: int)
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
## True while a blocking menu is open (NPC dialogue, shop, quest log, inventory).
## While set, the local player's movement and actions are suppressed, so you can't
## walk or fight with a menu up, and can't keep one open to act from afar. Only the
## movement polling is gated. Raw key events still flow, so menu UI can use arrows
## or stick for navigation later.
var menu_open: bool = false
## How many talkable world interactables (NPC click-areas) the cursor is over. While
## > 0, combat input is suppressed (InputComponent._ui_blocks_combat) so clicking an NPC
## to talk doesn't ALSO fire your weapon — the world-space mirror of the GUI gate.
## Counter, so overlapping NPCs balance; each NPC clears its own contribution on free.
var world_interactables_hovered: int = 0
## Fired when the local player's tagged guild changes (login / tag / create /
## join / leave). Ally-aware visuals (e.g. guild guard health bars) listen so
## they re-evaluate without a relog.
signal active_guild_id_changed(value: int)
var active_guild_id: int:
	set(value):
		if value == active_guild_id:
			return
		active_guild_id = value
		# Mirror into the static Player/HostileNpc read (avoids them importing us).
		Character.local_viewer_guild_id = value
		active_guild_id_changed.emit(value)
		_retint_local_players()
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


## Re-color visible players' team health bars after the local guild changes —
## already-spawned players read Character.local_viewer_guild_id (set above) but
## need a nudge to re-evaluate. Called by method name to avoid importing Player.
func _retint_local_players() -> void:
	if not is_instance_valid(local_player):
		return
	var map: Node = local_player.get_parent()
	if map == null:
		return
	for child: Node in map.get_children():
		if child.has_method(&"_apply_team_bar_color"):
			child.call(&"_apply_team_bar_color")


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
	Client.subscribe(&"mining.gather_result", _on_gather_result)
	Client.subscribe(&"quest.update", func(data: Dictionary):
		# One push can carry several messages ("Quest complete" + "Title unlocked").
		# Show them as ONE card, not a card per message (that was the worst spam).
		var msgs: PackedStringArray = PackedStringArray(data.get("messages", []))
		if not msgs.is_empty():
			Toaster.toast_group("Quest", msgs)
	)

	settings.load_file()
	settings.setting_changed.connect(_on_setting_changed)
	language = settings.data.get(&"general", {}).get(&"language", "en_US")


## Server-pushed kill rewards: surface them as ONE grouped toast card
## ("Defeated a Goblin" + XP + loot + level-up) so the player reads it
## as a single event instead of three flashes that happen to land
## together. enemy_type may be missing for non-mob reward paths (basing
## etc.) — falls back to a generic "Reward" header in that case.
func _on_combat_reward(data: Dictionary) -> void:
	var enemy_type: String = str(data.get("enemy_type", ""))
	var title: String = "Defeated %s" % _readable_enemy_name(enemy_type) if not enemy_type.is_empty() else "Reward"

	var lines: PackedStringArray = PackedStringArray()
	var xp: int = int(data.get("xp", 0))
	if xp > 0:
		lines.append("+%d XP" % xp)
	for entry: Dictionary in data.get("loot", []):
		lines.append("Looted %d %s" % [int(entry.get("amount", 1)), str(entry.get("name", "item"))])
	# Level-up + mastery are rare, high-value one-offs: give them their OWN card so
	# a stream of coalescing kills can't refresh the moment away.
	var big: PackedStringArray = PackedStringArray()
	if int(data.get("levels_gained", 0)) > 0:
		big.append("Level %d! +%d attribute points" % [int(data.get("level", 1)), int(data.get("points_gained", 0))])
	var mastery: Dictionary = data.get("mastery", {})
	if bool(mastery.get("started", false)):
		big.append("%s Mastery begun! +1 mastery point (Character > Mastery)" % str(mastery.get("category", "")).capitalize())
	elif bool(mastery.get("leveled_up", false)):
		big.append("%s Mastery Lv %d! +1 mastery point" % [
			str(mastery.get("category", "")).capitalize(),
			int(mastery.get("level", 1)),
		])
	if not big.is_empty():
		Toaster.toast_group("Level Up!" if int(data.get("levels_gained", 0)) > 0 else "Mastery", big)

	if lines.is_empty() and enemy_type.is_empty():
		return  # Nothing to show.
	# Repeated kills coalesce into one "Defeated a Goblin ×N" card; quest/basing
	# reward turn-ins (no enemy_type) are rare one-offs on the big lane.
	if enemy_type.is_empty():
		Toaster.toast_group(title, lines)
	else:
		Toaster.toast_feed("kill:" + enemy_type, title, lines)


## Server-pushed harvest result. Re-uses the gather_succeeded signal +
## toast format that the legacy click-based mining handler used, so quest
## tracking and any inventory UI that already listens to gather_succeeded
## keeps working unchanged.
## Throttle for the "depleted" toast — depleted swings are now rejected
## server-side on every hit, so without this the message would spam.
var _last_depleted_toast_ms: int


func _on_gather_result(data: Dictionary) -> void:
	if data.is_empty():
		return

	# Route progress + charge state to the node's local visuals so the bar +
	# label show only when the node is mid-extraction or partially depleted.
	# Only fires for the player who swung — broadcast can come later if other
	# players need to see live state on the same node.
	_apply_node_visual_state(data)

	if not data.get("ok", false):
		match str(data.get("reason", "")):
			"no_tool":
				Toaster.toast("You need a gathering tool equipped.")
			"wrong_tool":
				Toaster.toast("You need a %s for this." % str(data.get("required_tool", "different tool")).capitalize())
			"too_far":
				Toaster.toast("Too far from the node.")
			"level":
				Toaster.toast("Requires Mining Lv %d." % int(data.get("required_level", 0)))
			"depleted":
				var now_ms: int = Time.get_ticks_msec()
				if now_ms - _last_depleted_toast_ms > 4000:
					_last_depleted_toast_ms = now_ms
					Toaster.toast("This vein is depleted — come back later.")
			# "cooldown" stays silent — players will spam swings during it.
		return

	# Successful hit. Two shapes:
	#   { ok: true, extracted: false, progress_hp, extraction_hp }   ← just a swing
	#   { ok: true, extracted: true,  ore_id, amount, xp, ... }      ← a full yield
	if not data.get("extracted", false):
		# Mid-extraction swings are intentionally silent — feedback comes
		# from the swing animation + (future) chip-sound, not a toast.
		return

	gather_succeeded.emit(data)

	# Build a single grouped card so a yield reads as one event.
	var title: String = "Mined"
	var lines: PackedStringArray = PackedStringArray()
	var amount: int = int(data.get("amount", 0))
	if amount > 0:
		lines.append("+%d %s" % [amount, str(data.get("ore_name", "ore"))])
	# XP entries — primary job first (verbose), additional grants compact.
	var grants_v: Variant = data.get("grants", [])
	if grants_v is Array:
		for grant: Dictionary in grants_v:
			lines.append("+%d %s XP" % [int(grant.get("xp", 0)), str(grant.get("job", "")).capitalize()])
	# Level-up / perk = one-off → its own card; the yield body coalesces per ore.
	var big: PackedStringArray = PackedStringArray()
	if data.get("leveled_up", false):
		big.append("%s — Level %d!" % [str(data.get("job", "mining")).capitalize(), int(data.get("level", 1))])
	if int(data.get("perk_points_gained", 0)) > 0:
		big.append("Perk point available — spend in Character → Jobs.")
	if not big.is_empty():
		Toaster.toast_group("Level Up!", big)

	Toaster.toast_feed("mine:" + str(data.get("ore_name", "ore")), title, lines)


## Look up the MineableNode the result is about and push the new progress +
## charge counts into its [method MineableNode.apply_visual_state]. Silently
## no-ops if the path is missing (older result shapes) or the node went away
## (instance switch / despawn between the swing and the push).
func _apply_node_visual_state(data: Dictionary) -> void:
	var raw_path: Variant = data.get("node_path", null)
	if raw_path == null:
		return
	if InstanceClient.current == null:
		return
	var path: NodePath = raw_path as NodePath
	var node: Node = InstanceClient.current.get_node_or_null(path)
	if node == null or not (node is MineableNode):
		return
	(node as MineableNode).apply_visual_state(
		int(data.get("progress_hp", 0)),
		int(data.get("extraction_hp", 1)),
		int(data.get("charges_left", 0)),
		int(data.get("max_charges", 1)),
	)


## "bandit_captain" → "a Bandit Captain". Article ("a"/"an") chosen by
## first letter so we don't produce "a Orc" / "a Iron Warlord" weirdness.
func _readable_enemy_name(slug: String) -> String:
	if slug.is_empty():
		return "an enemy"
	var words: PackedStringArray = slug.split("_")
	var titled: PackedStringArray = PackedStringArray()
	for w: String in words:
		if w.is_empty():
			continue
		titled.append(w.substr(0, 1).to_upper() + w.substr(1))
	var pretty: String = " ".join(titled)
	var article: String = "an" if "aeiou".contains(pretty.substr(0, 1).to_lower()) else "a"
	return "%s %s" % [article, pretty]


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
		if not data.has(section):
			data[section] = {}
		data[section][property] = value
		setting_changed.emit(section, property, value)
		save()
