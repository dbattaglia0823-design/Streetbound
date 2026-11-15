extends RefCounted
## Consistent low-speed eligibility for in-world driving interactions.
## VehicleController2D.linear_velocity is measured in metres per second;
## HUD speed is shown in miles per hour.
const MAX_MPH := 15.0
const METRES_PER_SECOND_PER_MPH := 0.44704
const MAX_SPEED_MPS := MAX_MPH * METRES_PER_SECOND_PER_MPH

static func allowed(speed_mps: float) -> bool:
	return is_finite(speed_mps) and absf(speed_mps) <= MAX_SPEED_MPS + 0.00001
