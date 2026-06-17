@tool
class_name InteractableMarker
extends Node2D
## Floats a small pixel-art EMOTE above a world-space interactable (NPC, shop
## counter, mineable node, warper, ...) so the player can tell at a glance what the
## spot offers. Purely decorative — instance the scene as a child and set `kind`.
##
## Runs in @tool mode so changing `kind` previews live in the editor (the idle bob
## is skipped there so the marker stays put while you position it).
##
## Emotes are pixel-art PNGs (assets/sprites/gui/emotes) — they render crisply on
## web, unlike the emoji we started with, and read better than the big text label
## they replaced. The kind→emote map below is just data; re-point it freely.

enum Kind {
	QUEST_AVAILABLE, ## "!" — NPC has an acceptable quest
	QUEST_TURN_IN,   ## "?" — NPC has a ready turn-in
	SHOP,            ## buy / sell vendor
	CRAFT,           ## crafting station (forge / loom / ...)
	DIALOG,          ## generic talkable NPC
	GATHER,          ## ore vein / herb patch / etc.
}

const _EMOTE_DIR: String = "res://assets/sprites/gui/emotes/"
## Kind → emote file. Pure data — swap any of these for another emote freely.
const _EMOTES: Dictionary = {
	Kind.QUEST_AVAILABLE: "emote_exclamation.png",
	Kind.QUEST_TURN_IN: "emote_question.png",
	Kind.SHOP: "emote_cash.png",
	Kind.CRAFT: "emote_idea.png",
	Kind.DIALOG: "emote_dots3.png",
	Kind.GATHER: "emote_star.png",
}

## What kind of interaction this marker advertises. Drives the emote.
@export var kind: Kind = Kind.DIALOG : set = _set_kind
## Idle bob amplitude in pixels (set to 0 to disable the bob).
@export var bob_amplitude: float = 3.0
## Full bob cycle duration in seconds (down + up).
@export var bob_period: float = 1.6

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	_set_kind(kind)
	# Skip the bob in the editor so the marker stays put while you place it.
	if bob_amplitude > 0.0 and not Engine.is_editor_hint():
		_start_bob()


func _set_kind(value: Kind) -> void:
	kind = value
	# _sprite is null until _ready; the call in _ready handles that path.
	if is_node_ready() and _sprite != null:
		var file: String = _EMOTES.get(value, "")
		_sprite.texture = load(_EMOTE_DIR + file) if not file.is_empty() else null


## Subtle vertical bob so the marker reads as "live" without distracting from the
## action. Tween auto-cleans when the node is freed.
func _start_bob() -> void:
	var base_y: float = _sprite.position.y
	var tween: Tween = create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_sprite, ^"position:y", base_y - bob_amplitude, bob_period * 0.5)
	tween.tween_property(_sprite, ^"position:y", base_y, bob_period * 0.5)
