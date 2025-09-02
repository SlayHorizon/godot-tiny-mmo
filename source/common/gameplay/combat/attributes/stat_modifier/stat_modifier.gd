class_name StatModifier
extends Resource


enum Op {ADD,MUL}
enum Channel {VALUE, MAX}

@export var attr: StringName
@export var channel: Channel = Channel.MAX
@export var op: Op = Op.ADD
@export var magnitude: float = 0.0
@export var source_tags: PackedStringArray = []
@export var runtime_id: int = randi()
