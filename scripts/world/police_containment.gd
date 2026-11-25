extends RefCounted
## Conservative arrest condition: three separate police cars must form a
## near-complete blockade around a slow/stationary car. No throttle input is
## required once physically surrounded; a single nearby cruiser cannot bust.
const CAPTURE_SECONDS := 4.0
const MAX_SPEED_MPS := 1.35
const BLOCK_RADIUS_M := 8.0
const MAX_OPEN_GAP_RAD := deg_to_rad(155.0)

static func progress(previous: float, dt: float, player_m: Vector2,
		speed_mps: float, _drive_intent: float, police_positions_m: Array[Vector2]) -> float:
	if dt <= 0.0 or speed_mps > MAX_SPEED_MPS:
		return 0.0
	var angles: Array[float] = []
	for position in police_positions_m:
		var displacement: Vector2 = position - player_m
		if displacement.length_squared() < 0.25 or displacement.length() > BLOCK_RADIUS_M:
			continue
		angles.append(wrapf(displacement.angle(), 0.0, TAU))
	if angles.size() < 3:
		return 0.0
	angles.sort()
	var biggest_gap := 0.0
	for i in angles.size():
		var next_angle: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		biggest_gap = maxf(biggest_gap, next_angle - angles[i])
	if biggest_gap > MAX_OPEN_GAP_RAD:
		return 0.0
	return minf(CAPTURE_SECONDS, previous + dt)

static func is_busted(progress_seconds: float) -> bool:
	return progress_seconds >= CAPTURE_SECONDS
