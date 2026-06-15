class_name AuthRateLimiter

## Per-IP sliding-window throttle for the gateway's auth endpoints (login, guest,
## account creation). Keeps brute-force and signup-spam off the master. In-memory
## and process-local — fine for a single gateway; a multi-gateway deployment would
## move this to shared state. State survives across calls (static), so unique IPs
## accumulate keys; negligible for alpha, prune later if needed.

static var _hits: Dictionary = {}


## True if this (ip, endpoint) is still under `max_calls` within the rolling
## `window_ms`; records the hit. False (and records nothing extra) when over.
static func allow(ip: String, endpoint: StringName, max_calls: int, window_ms: int) -> bool:
	var now: int = Time.get_ticks_msec()
	var cutoff: int = now - window_ms
	var key: String = "%s|%s" % [ip, endpoint]

	var kept: Array[int] = []
	for t: int in _hits.get(key, [] as Array[int]):
		if t > cutoff:
			kept.append(t)

	if kept.size() >= max_calls:
		_hits[key] = kept
		return false

	kept.append(now)
	_hits[key] = kept
	return true
