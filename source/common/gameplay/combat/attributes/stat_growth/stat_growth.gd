class_name StatGrowthResource
extends Resource

enum Mode {LINEAR, PCT_MULT, CURVE}

@export var mode: int = Mode.LINEAR

# Used by LINEAR and CURVE
@export var per_level: float = 0.0

# Used by PCT_MULT (e.g., attack speed style growth)
@export_range(0.0, 5.0, 0.0001) var pct_per_level: float = 0.0

# Optional designer curve (0..1 sampled over levels 1..18)
@export var curve: Curve


func value_at_level(base: float, level: int) -> float:
	var lv: float = float(max(1, level))
	match mode:
		Mode.LINEAR:
			return base + per_level * (lv - 1.0)
		Mode.PCT_MULT:
			return base * pow(1.0 + pct_per_level, lv - 1.0)
		Mode.CURVE:
			if curve == null:
				return base
			var t: float = clamp((lv - 1.0) / 17.0, 0.0, 1.0)
			return base + per_level * curve.sample(t)
		_:
			return base
