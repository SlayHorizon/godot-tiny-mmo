class_name WeatherResource
extends Resource
## Data-driven ambient weather overlay for a map (drifting leaves, rain, snow, dust...).
## Add one (or several) to Map.weather; on entering the map the client's WeatherLayer
## drives one CPUParticles2D emitter per entry from these knobs. Pure cosmetic + client-side —
## new looks are a new .tres, no code. Leave [member texture] null for a procedural
## (untextured) particle, which is plenty for rain / snow / dust / soft leaves.

## Particle sprite. Null = a small procedural square tinted by [member color]. May be a
## horizontal sprite-sheet (e.g. leaf.png is 6 frames) — set [member h_frames].
@export var texture: Texture2D
## Horizontal frame count when [member texture] is a sprite-sheet (1 = a plain image).
## Each particle is given a random frame for variety (a field of differently-shaped leaves).
@export var h_frames: int = 1

## How particles spawn + move (see WeatherLayer): TOP_FALL rains them from a strip above
## the view (leaves, rain, snow); AREA_DRIFT scatters them across the whole view to drift
## sideways (cloud shadows, fog patches).
enum EmitMode { TOP_FALL, AREA_DRIFT }
@export var emit_mode: EmitMode = EmitMode.TOP_FALL
## Particle tint (alpha included). The overlay fades each particle out over its life on
## top of this, so they don't pop when recycled.
@export var color: Color = Color(1, 1, 1, 1)
## How many particles are alive on screen at once (density).
@export var amount: int = 40
## Seconds before a particle recycles back to the top.
@export var lifetime: float = 8.0
## Movement, px/s: downward = fall, sideways = wind. TOP_FALL applies it as gravity (the
## particle accelerates); AREA_DRIFT applies it as a constant velocity. See WeatherLayer.
@export var fall_speed: float = 45.0
@export var wind: float = 25.0
## Direction jitter (degrees) around the drift, so particles don't fall in lockstep.
@export var spread_degrees: float = 30.0
@export var scale_min: float = 0.4
@export var scale_max: float = 0.9
## Max tumble speed (deg/s, applied ±) — gives leaves/snow a lazy spin. 0 = no spin.
@export var spin_degrees: float = 60.0
