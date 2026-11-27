extends RefCounted
## Sampling helpers for visual-only remote vehicles. The server still owns
## physics; client extrapolation never changes authoritative state.
const MAX_HISTORY := 7
const MAX_EXTRAPOLATE_MS := 60
const STALE_FREEZE_MS := 250
const MAX_LOCAL_FORWARD_MS := 80
const MAX_ROAD_HEIGHT_M := 12.0

static func interpolation_delay_ms(snapshot_interval_ms: float,
		rtt_variation_ms: float) -> int:
	# One-and-a-half snapshots of buffering reduces visible packet jitter.
	# More RTT variance adds buffering, but never unbounded display lag.
	var baseline := snapshot_interval_ms * 1.6
	var jitter_allowance := clampf(rtt_variation_ms * 1.25, 0.0, 60.0)
	return clampi(roundi(baseline + jitter_allowance), 50, 125)

static func valid_grade_height(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) \
		and absf(float(value)) <= MAX_ROAD_HEIGHT_M

static func add_snapshot(history: Array, time_ms: int, state: Array,
		grade_height: Variant = 0.0) -> void:
	if state.size() != 6:
		return
	# Only called when a newer authoritative sequence was admitted.
	history.append({"time": time_ms, "state": state.duplicate(),
		"grade_height": float(grade_height) if valid_grade_height(grade_height) else 0.0})
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

# Match the position interpolation clock. Never extrapolate height across
# a ramp mouth or a missing packet: the next host sample owns the grade.
static func sample_grade_height(history: Array, now_ms: int, delay_ms: int) -> float:
	if history.is_empty():
		return 0.0
	var render_ms := now_ms - delay_ms
	var first: Dictionary = history[0]
	if render_ms <= int(first["time"]):
		return float(first.get("grade_height", 0.0))
	for index in range(history.size() - 1):
		var older: Dictionary = history[index]
		var newer: Dictionary = history[index + 1]
		if render_ms <= int(newer["time"]):
			var duration := maxf(1.0, float(int(newer["time"]) - int(older["time"])))
			var alpha := clampf(float(render_ms - int(older["time"])) / duration, 0.0, 1.0)
			return lerpf(float(older.get("grade_height", 0.0)), float(newer.get("grade_height", 0.0)), alpha)
	var latest: Dictionary = history.back()
	return float(latest.get("grade_height", 0.0))

static func projected_local_authority(state: Array, rtt_ms: float) -> Vector2:
	# Do not reconcile the client toward an already-old host snapshot.
	# Approximate one-way network age from ENet RTT; keep the correction
	# strictly bounded and use only host-owned velocity for projection.
	if state.size() < 3 or not (state[0] is Vector2) or \
			not (state[2] is Vector2):
		return Vector2.ZERO
	var seconds := clampf(rtt_ms * 0.0005, 0.0,
		float(MAX_LOCAL_FORWARD_MS) / 1000.0)
	return (state[0] as Vector2) + (state[2] as Vector2) * seconds

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
