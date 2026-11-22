extends RefCounted
## Sampling helpers for visual-only remote vehicles. The server still owns
## physics; client extrapolation never changes authoritative state.
const MAX_HISTORY := 7
const MAX_EXTRAPOLATE_MS := 60
const STALE_FREEZE_MS := 250

static func interpolation_delay_ms(snapshot_interval_ms: float,
		rtt_variation_ms: float) -> int:
	# One-and-a-half snapshots of buffering reduces visible packet jitter.
	# More RTT variance adds buffering, but never unbounded display lag.
	var baseline := snapshot_interval_ms * 1.6
	var jitter_allowance := clampf(rtt_variation_ms * 1.25, 0.0, 60.0)
	return clampi(roundi(baseline + jitter_allowance), 50, 125)

static func add_snapshot(history: Array, time_ms: int, state: Array) -> void:
	if state.size() != 6:
		return
	# Only called when a newer authoritative sequence was admitted.
	history.append({"time": time_ms, "state": state.duplicate()})
	while history.size() > MAX_HISTORY:
		history.pop_front()

static func sample(history: Array, now_ms: int, delay_ms: int) -> Array:
	if history.is_empty():
		return []
	var render_ms := now_ms - delay_ms
	var first: Dictionary = history[0]
	if render_ms <= int(first["time"]):
		return (first["state"] as Array).duplicate()
	for index in range(history.size() - 1):
		var older: Dictionary = history[index]
		var newer: Dictionary = history[index + 1]
		var newer_time: int = int(newer["time"])
		if render_ms <= newer_time:
			var duration: float = maxf(1.0,
				float(newer_time - int(older["time"])))
			var alpha: float = clampf((render_ms -
				float(older["time"])) / duration, 0.0, 1.0)
			return interpolate(older["state"], newer["state"], alpha)
	var latest: Dictionary = history.back()
	var state: Array = (latest["state"] as Array).duplicate()
	var last_time: int = int(latest["time"])
	# On a temporary gap, extrapolate a *small* amount for visual continuity.
	# Freeze after 250 ms instead of allowing a car to drive far into a wall.
	if now_ms - last_time > STALE_FREEZE_MS:
		return state
	var advance_seconds: float = clampf(float(render_ms - last_time), 0.0,
		float(MAX_EXTRAPOLATE_MS)) / 1000.0
	state[0] = (state[0] as Vector2) + (state[2] as Vector2) * advance_seconds
	state[1] = float(state[1]) + float(state[5]) * advance_seconds
	return state

static func interpolate(a: Array, b: Array, fraction: float) -> Array:
	if a.size() != 6 or b.size() != 6:
		return []
	var alpha := clampf(fraction, 0.0, 1.0)
	return [
		(a[0] as Vector2).lerp(b[0] as Vector2, alpha),
		lerp_angle(float(a[1]), float(b[1]), alpha),
		(a[2] as Vector2).lerp(b[2] as Vector2, alpha),
		lerpf(float(a[3]), float(b[3]), alpha),
		lerpf(float(a[4]), float(b[4]), alpha),
		lerpf(float(a[5]), float(b[5]), alpha)]
