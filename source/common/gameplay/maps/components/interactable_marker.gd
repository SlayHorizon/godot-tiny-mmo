@tool
class_name InteractableMarker
extends Node2D
## Drop-in cosmetic marker that floats an emoji glyph above a world-space
## interactable (NPC, shop counter, mineable node, warper, ...) so the player
## can tell at a glance the spot can be poked. Purely decorative — no parent
## refactor needed; instance the scene as a child and set `kind` in the
## inspector.
##
## Runs in @tool mode so changing `kind` (or font_size/outline) in the editor
## updates the preview live — no need to boot the game to verify placement.
## The idle bob is skipped in the editor so the marker stays still while you
## position it.
##
## Glyphs are emoji so we don't need a sprite-sheet asset for alpha. Swap to
## PNG icons later by replacing the inner Label with a TextureRect; nothing
## else in the codebase cares.

enum Kind {
	QUEST_AVAILABLE, ## "!" — NPC has an acceptable quest
	QUEST_TURN_IN,   ## "?" — NPC has a ready turn-in
	SHOP,            ## buy / sell vendor
	CRAFT,           ## crafting station (forge / loom / ...)
	DIALOG,          ## generic talkable NPC
	GATHER,          ## ore vein / herb patch / etc.
}

## Glyph map. Untyped const so const-init doesn't trip on enum-key typing rules.
const _GLYPHS: Dictionary = {
	Kind.QUEST_AVAILABLE: "❗",
	Kind.QUEST_TURN_IN: "❓",
	Kind.SHOP: "💰",
	Kind.CRAFT: "⚒️",
	Kind.DIALOG: "💬",
	Kind.GATHER: "⛏️",
}

## What kind of interaction this marker advertises. Drives the emoji.
@export var kind: Kind = Kind.DIALOG : set = _set_kind
## Idle bob amplitude in pixels (set to 0 to disable the bob).
@export var bob_amplitude: float = 3.0
## Full bob cycle duration in seconds (down + up).
@export var bob_period: float = 1.6
## Glyph font size. Bigger = more visible from far away.
@export var font_size: int = 24 : set = _set_font_size
## Black outline thickness around the glyph so it stays readable on light
## backgrounds (grass, sand, sunlit walls).
@export var outline_size: int = 6 : set = _set_outline_size

@onready var _label: Label = $Label


func _ready() -> void:
	_apply_style()
	_set_kind(kind)
	# Skip the bob in the editor so the marker stays put while you place it.
	if bob_amplitude > 0.0 and not Engine.is_editor_hint():
		_start_bob()


## Refreshes the Label theme overrides from the exported style fields. Called
## on _ready and again whenever a style field is edited in the inspector.
func _apply_style() -> void:
	if _label == null:
		return
	_label.add_theme_font_size_override(&"font_size", font_size)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", outline_size)


func _set_kind(value: Kind) -> void:
	kind = value
	# _label is null until _ready; the deferred set in _ready handles that path.
	if is_node_ready() and _label != null:
		_label.text = _GLYPHS.get(value, "")


func _set_font_size(value: int) -> void:
	font_size = value
	_apply_style()


func _set_outline_size(value: int) -> void:
	outline_size = value
	_apply_style()


## Subtle vertical bob so the marker reads as "live" without distracting from
## the action. Tween auto-cleans when the node is freed.
func _start_bob() -> void:
	var base_y: float = _label.position.y
	var tween: Tween = create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_label, ^"position:y", base_y - bob_amplitude, bob_period * 0.5)
	tween.tween_property(_label, ^"position:y", base_y, bob_period * 0.5)
