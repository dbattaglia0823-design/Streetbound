extends RefCounted
## Passive telemetry for headless, real-physics race AI benchmarks.
## All distances are metres unless explicitly named _px; timings are simulated.
const PIXELS_PER_METRE := 20.0
const STEER_DEADBAND := 0.22
const STALL_SPEED_MPS := 1.2
const STALL_THROTTLE := 0.25
const STALL_SECONDS := 2.5
const RECOVERY_SPEED_MPS := 3.0
const RECOVERY_DISTANCE_M := 4.0
const COLLISION_DEBOUNCE_S := 0.15

var elapsed_s := 0.0
var distance_m := 0.0
var offroad_s := 0.0
var steering_corrections := 0
var collision_events := 0
var stall_events := 0
var successful_recoveries := 0
var peak_speed_mps := 0.0
var _last_position_px := Vector2.ZERO
var _has_previous := false
var _steer_sign := 0
var _stall_clock := 0.0
var _in_stall := false
var _stall_origin_px := Vector2.ZERO
var _last_collision_s := -100.0


func sample(dt: float, position_px: Vector2, speed_mps: float,
		command: Vector4, surface_name: String) -> void:
	if dt <= 0.0:
		return
	elapsed_s += dt
	peak_speed_mps = maxf(peak_speed_mps, speed_mps)
	if _has_previous:
		distance_m += position_px.distance_to(_last_position_px) / PIXELS_PER_METRE
	_last_position_px = position_px
	_has_previous = true
	if surface_name != "ASPHALT":
		offroad_s += dt

	# Count committed left/right steering reversals, not zero crossings while
	# straightening the wheel or tiny controller oscillations.
	var sign_now := 0
	if absf(command.z) >= STEER_DEADBAND:
		sign_now = 1 if command.z > 0.0 else -1
	if sign_now != 0:
		if _steer_sign != 0 and _steer_sign != sign_now:
			steering_corrections += 1
		_steer_sign = sign_now

	# A stall is sustained throttle demand without forward progress.
	# Recovery requires real motion away from that stall's position.
	if _in_stall:
		if speed_mps >= RECOVERY_SPEED_MPS and position_px.distance_to(
				_stall_origin_px) >= RECOVERY_DISTANCE_M * PIXELS_PER_METRE:
			successful_recoveries += 1
			_in_stall = false
			_stall_clock = 0.0
	else:
		if speed_mps < STALL_SPEED_MPS and command.x > STALL_THROTTLE:
			_stall_clock += dt
			if _stall_clock >= STALL_SECONDS:
				stall_events += 1
				_in_stall = true
				_stall_origin_px = position_px
		else:
			_stall_clock = 0.0


func collision(_strength: float = 0.0) -> void:
	# One physical contact can emit several signals/contacts in adjacent
	# physics ticks. Count it as one collision event, not dozens.
	if elapsed_s - _last_collision_s < COLLISION_DEBOUNCE_S:
		return
	_last_collision_s = elapsed_s
	collision_events += 1


func summary() -> Dictionary:
	return {
		"elapsed_s": snappedf(elapsed_s, 0.001),
		"distance_driven_m": snappedf(distance_m, 0.01),
		"peak_speed_mps": snappedf(peak_speed_mps, 0.01),
		"steering_corrections": steering_corrections,
		"offroad_time_s": snappedf(offroad_s, 0.001),
		"offroad_fraction": snappedf(offroad_s / maxf(elapsed_s, 0.001), 0.0001),
		"collisions": collision_events,
		"stuck_events": stall_events,
		"stuck_recoveries": successful_recoveries,
		"unresolved_stuck_events": stall_events - successful_recoveries
	}
