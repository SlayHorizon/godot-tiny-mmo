class_name RateLimiter
## Per-peer-per-endpoint sliding-window limiter. Cheap, in-memory, all static.
## Holds at most one short Array of msec timestamps per (peer, endpoint); old
## entries get popped each call so memory stays bounded by max_calls × peers.
##
## Use this on hot RPCs that can be spammed by a malicious or buggy client.
## It's not cryptographic — restart resets all state — which is the right
## tradeoff for alpha: it stops abuse without imposing a Redis dependency.
##
## Usage at the start of a data request handler:
##   if not RateLimiter.check(peer_id, &"chat.send", 5, 10_000):
##       return {"ok": false, "reason": "rate_limited"}

# (peer_id, endpoint) -> Array[int] of ticks_msec, oldest first.
static var _calls: Dictionary = {}


## Returns true if the call is allowed, false to reject. Recommended limits:
##   chat send:      5 per 10s   (anti-spam)
##   action.perform: 20 per 1s   (anti-DoS, weapon cooldowns already gate real use)
static func check(peer_id: int, endpoint: StringName, max_calls: int, window_ms: int) -> bool:
	var key: String = "%d::%s" % [peer_id, str(endpoint)]
	var now: int = Time.get_ticks_msec()
	var calls: Array = _calls.get(key, [])
	# Drop timestamps that have fallen out of the window.
	while not calls.is_empty() and int(calls[0]) < now - window_ms:
		calls.pop_front()
	if calls.size() >= max_calls:
		_calls[key] = calls
		return false
	calls.append(now)
	_calls[key] = calls
	return true


## Wipe a peer's entries — call on disconnect so the dictionary doesn't grow
## across reconnect cycles.
static func forget(peer_id: int) -> void:
	var prefix: String = "%d::" % peer_id
	for key: String in _calls.keys():
		if key.begins_with(prefix):
			_calls.erase(key)
