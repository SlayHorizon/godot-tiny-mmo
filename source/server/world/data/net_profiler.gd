class_name NetProfiler
## Server-only network + tick profiler for load testing (docs/netcode_perf_audit.md, F0).
## All static, in-memory, cheap (a few int adds per tick). The send path feeds the
## accumulators; WorldServer flushes a one-line report every second and resets the window.
##
## The number that matters is the whole-process tick cost vs its budget (50 ms at the
## 20 Hz send rate, 100 ms at the 10 Hz physics tick). proc/phys come FREE from Godot's
## built-in Performance monitors, so they capture mob AI + everything, not just the send.
##
## DORMANT by default — no log noise in normal play. Flip on ONLY when you actually
## want to measure (a load test, a "why did that hitch" investigation), then off again:
##   NetProfiler.enabled = true

## When false, report_and_reset stays silent (but still clears the window).
static var enabled: bool = false

# Accumulated since the last report.
static var _entity_usec_total: int = 0
static var _entity_usec_max: int = 0
static var _entity_ticks: int = 0
static var _props_usec_total: int = 0
static var _props_ticks: int = 0
static var _bytes_out: int = 0
static var _msgs_out: int = 0


## Record one entity-send tick's wall-clock cost (microseconds).
static func record_entity_tick(usec: int) -> void:
	_entity_usec_total += usec
	if usec > _entity_usec_max:
		_entity_usec_max = usec
	_entity_ticks += 1


## Record one props-send tick's wall-clock cost (microseconds).
static func record_props_tick(usec: int) -> void:
	_props_usec_total += usec
	_props_ticks += 1


## Record one outbound message and its payload size (bytes).
static func record_send(byte_count: int) -> void:
	_bytes_out += byte_count
	_msgs_out += 1


## Log one aggregate line for the window and reset. Called ~1 Hz by WorldServer.
## [param window_s] is the real elapsed time since the last call (for per-second rates).
static func report_and_reset(player_count: int, window_s: float) -> void:
	if not enabled or window_s <= 0.0:
		_reset()
		return
	var entity_avg: float = float(_entity_usec_total) / _entity_ticks if _entity_ticks > 0 else 0.0
	var props_avg: float = float(_props_usec_total) / _props_ticks if _props_ticks > 0 else 0.0
	var msg_s: float = float(_msgs_out) / window_s
	var kb_s: float = (float(_bytes_out) / 1024.0) / window_s
	# Whole-process tick cost (seconds → ms). Captures mob AI, sync, everything.
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	ServerLog.info(
		"[NET] players=%d proc=%.1fms phys=%.1fms | entity_send avg=%.0f max=%d us (props avg=%.0f us) | out %.0f msg/s %.1f KB/s" % [
			player_count, proc_ms, phys_ms, entity_avg, _entity_usec_max, props_avg, msg_s, kb_s
		]
	)
	_reset()


static func _reset() -> void:
	_entity_usec_total = 0
	_entity_usec_max = 0
	_entity_ticks = 0
	_props_usec_total = 0
	_props_ticks = 0
	_bytes_out = 0
	_msgs_out = 0
