class_name NetMotionSmoother
extends Node
## Client-side snapshot interpolation for a network-driven Character
## (see docs/netcode_smoothness.md). Buffers arrival-stamped :position samples and
## renders the parent [member delay_ms] in the past, lerping between the two samples
## straddling the render time — turning 10-20 Hz network steps into 60 fps motion.
## The first sample and teleport-sized jumps snap (buffer reset) so warps, respawns
## and Blink never smear across the map.

## Samples kept. 8 covers 400 ms at 20 Hz (players) / 800 ms at 10 Hz (mobs) —
## enough history to absorb a TCP loss-burst delivering several updates at once.
const MAX_SAMPLES: int = 8

## How far in the past the parent renders. ~2x the sender's update interval:
## 100 ms for players (20 Hz broadcast), 200 ms for mobs (10 Hz) — see
## Character.net_smooth_delay_ms.
@export var delay_ms: int = 100

## A sample jumping farther than this from the previous one is a teleport
## (warp / respawn / jail / Blink / leash reset): reset the buffer and snap.
## Must exceed one network step of the fastest continuous mover (mob lunge).
@export var snap_distance: float = 128.0

var _target: Node2D

# Parallel ring buffers: arrival time (ticks_msec) + received position.
var _times: Array[int] = []
var _positions: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_target = get_parent() as Node2D
	assert(_target != null, "NetMotionSmoother must be the child of a Node2D.")


## Feed one network :position sample. An empty buffer (first sight of the entity)
## or a teleport-sized jump snaps via [method reset_to]; everything else buffers
## for interpolation.
func push_sample(sample_position: Vector2) -> void:
	if _positions.is_empty() \
			or _positions[_positions.size() - 1].distance_to(sample_position) > snap_distance:
		reset_to(sample_position)
		return
	_times.append(Time.get_ticks_msec())
	_positions.append(sample_position)
	if _times.size() > MAX_SAMPLES:
		_times.pop_front()
		_positions.remove_at(0)


# --- Scripted-motion override (client dash playback) -------------------------

var _override_from: Vector2
var _override_to: Vector2
var _override_start_ms: int
var _override_end_ms: int = 0


## Play a LOCKED, straight, constant-speed motion locally instead of the
## interpolation buffer — mob dash prediction. The server simulates exactly
## this line (heading + landing locked at windup start), so playing it
## client-side removes the delay_ms render lag with no real divergence risk:
## samples keep buffering during the override, interpolation resumes
## seamlessly at the end, and the snap rule covers a wall-blocked early
## landing. [param start_delay_ms] schedules the playback (a lunge sends its
## dash together with the windup telegraph, so the LOCAL dash starts exactly
## when the LOCAL telegraph expires — one clock, coherent to the eye).
func play_motion(from: Vector2, to: Vector2, duration_ms: int, start_delay_ms: int = 0) -> void:
	_override_from = from
	_override_to = to
	_override_start_ms = Time.get_ticks_msec() + maxi(0, start_delay_ms)
	_override_end_ms = _override_start_ms + maxi(1, duration_ms)


## Abort a scheduled/active scripted motion (e.g. the mob died mid-windup) —
## buffered interpolation takes back over immediately.
func cancel_motion() -> void:
	_override_end_ms = 0


## Clear the buffer and place the parent immediately (baseline / teleport).
func reset_to(sample_position: Vector2) -> void:
	_times.clear()
	_positions.clear()
	_times.append(Time.get_ticks_msec())
	_positions.append(sample_position)
	_target.position = sample_position


func _process(_delta: float) -> void:
	# Scripted motion wins while active (see play_motion). Before its
	# scheduled start, normal interpolation continues (the mob is rooted in
	# its windup anyway).
	if _override_end_ms > 0:
		var now: int = Time.get_ticks_msec()
		if now >= _override_end_ms:
			_override_end_ms = 0
			# Hand-off: the buffer kept filling DURING the playback, and it
			# renders delay_ms in the past — resuming from it would teleport
			# the mob back into the dash and replay the tail. Snap the buffer
			# to the landing instead; a wall-blocked early landing diverges
			# > snap_distance and the snap rule corrects it on the next sample.
			reset_to(_override_to)
		elif now >= _override_start_ms:
			var weight: float = float(now - _override_start_ms) \
					/ float(_override_end_ms - _override_start_ms)
			_target.position = _override_from.lerp(_override_to, weight)
			return

	var count: int = _times.size()
	if count == 0:
		return
	var render_ms: int = Time.get_ticks_msec() - delay_ms
	# Starved (sender idle, or a network stall about to burst-deliver): hold the
	# newest known position; the snap rule recovers if the gap was a teleport.
	if render_ms >= _times[count - 1]:
		_target.position = _positions[count - 1]
		return
	if render_ms <= _times[0]:
		_target.position = _positions[0]
		return
	for i: int in range(count - 1, 0, -1):
		if _times[i - 1] <= render_ms:
			var span_ms: int = maxi(1, _times[i] - _times[i - 1])
			var weight: float = float(render_ms - _times[i - 1]) / float(span_ms)
			_target.position = _positions[i - 1].lerp(_positions[i], weight)
			return
