class_name MineableNode
extends Area2D
## A world-space gathering node (ore vein, etc.). Mirrors ShopInteractable: it lives
## below the HUD layer and is clicked/tapped to gather. Works with mouse and touch.
##
## Design: shared charges + lazy regen + per-player cooldown.
## - The node holds a small pool of charges shared by everyone (server-authoritative).
## - A gather consumes one charge and puts that player on a per-node cooldown (handled
##   in the mining.gather handler), so no one can vacuum every charge in one burst.
## - Charges regenerate lazily (computed on access), so there are no per-node timers.
##
## Setup: instance mineable_node.tscn as a direct child of the Map, assign an
## ore Item (a MaterialItem with vendor_value so it sells), position it.
## Identity is the node's own `name` — Godot guarantees uniqueness within a
## parent, so duplicating the prefab auto-yields "MineableNode2", etc. No
## manual id wrangling needed; the server resolves by name.

## The item granted per gather. Use a MaterialItem with vendor_value set.
@export var ore: Item
@export var yield_amount: int = 1
@export var xp_reward: int = 10
## Minimum mining level required to work this node (0 = anyone). Higher-tier veins
## (iron, gold, ...) set this so they gate behind mining progression.
@export var required_level: int = 0
## Tool the player must have equipped (matched against ToolItem.tool_type).
@export var required_tool: StringName = &"pickaxe"
@export var max_charges: int = 3
## Seconds for one charge to regenerate (lazy, computed on access).
@export var charge_regen_seconds: float = 30.0
## Per-player cooldown on this node after a successful gather.
@export var player_cooldown_seconds: float = 8.0

# Server-only shared charge state.
var _charges: int
var _last_update_ms: int


func _ready() -> void:
	if multiplayer.is_server():
		_charges = max_charges
		_last_update_ms = Time.get_ticks_msec()
		# The server keeps the node for resolution/proximity but never handles input.
		input_pickable = false
		return
	if ore:
		input_pickable = true
		input_event.connect(_on_input_event)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if clicked:
		# `name` is the node's identity within its parent (the Map). Godot
		# enforces uniqueness, so we don't need a hand-assigned id.
		Client.request_data(&"mining.gather", _on_gather_result, {"name": String(name)}, InstanceClient.current.name)


func _on_gather_result(data: Dictionary) -> void:
	if not data.get("ok", false):
		_toast_failure(data)
		return
	ClientState.gather_succeeded.emit(data)

	var amount: int = int(data.get("amount", 0))
	if amount > 0 and ore:
		Toaster.toast("+%d %s" % [amount, str(ore.item_name)])
	if data.get("leveled_up", false):
		Toaster.toast("Mining — Level %d!" % int(data.get("level", 1)))
	if int(data.get("perk_points_gained", 0)) > 0:
		Toaster.toast("Perk point available! Spend it in Character → Jobs.")


func _toast_failure(data: Dictionary) -> void:
	match String(data.get("reason", "")):
		"no_tool":
			Toaster.toast("You need a pickaxe equipped.")
		"too_far":
			Toaster.toast("Too far from the node.")
		"level":
			Toaster.toast("Requires Mining Lv %d." % int(data.get("required_level", 0)))
		"depleted":
			Toaster.toast("This vein is depleted — come back later.")
		# "cooldown" is intentionally silent to avoid spam on rapid clicks.


## Server: lazily regenerate, then consume one charge if available. Returns false when
## the node is depleted.
func try_consume_charge() -> bool:
	_regen()
	if _charges <= 0:
		return false
	if _charges == max_charges:
		# Start the regen clock fresh from the first pull off a full node.
		_last_update_ms = Time.get_ticks_msec()
	_charges -= 1
	return true


func _regen() -> void:
	if _charges >= max_charges:
		return
	var regen_ms: int = int(charge_regen_seconds * 1000.0)
	if regen_ms <= 0:
		return
	@warning_ignore("integer_division")
	var gained: int = (Time.get_ticks_msec() - _last_update_ms) / regen_ms
	if gained > 0:
		_charges = mini(max_charges, _charges + gained)
		_last_update_ms += gained * regen_ms
