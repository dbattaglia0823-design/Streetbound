extends RefCounted
## World weather is a surface-provider property, not a vehicle upgrade.
## Dry roads keep their original grip and archived map collision behavior.

static func rain_at(provider: Node,point_px: Vector2=Vector2.INF) -> float:
	if not is_instance_valid(provider) or not provider.has_method("get_rain_intensity"):
		return 0.0
	var value: float = float(provider.call("rain_at_position",point_px)) if point_px.is_finite() and provider.has_method("rain_at_position") else float(provider.call("get_rain_intensity"))
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0

static func grip_multiplier(surface: String, rain: float) -> float:
	var wet := clampf(rain, 0.0, 1.0) if is_finite(rain) else 0.0
	var loss := 0.0
	match surface:
		"ASPHALT": loss = 0.18
		"DIRT": loss = 0.15
		"GRASS": loss = 0.13
		"GRAVEL": loss = 0.08
		"SAND": loss = 0.04
		_: loss = 0.0
	return 1.0 - loss * wet

static func spray_strength(surface: String, speed_mps: float, rain: float) -> float:
	if not is_finite(speed_mps) or not is_finite(rain) or rain <= 0.01:
		return 0.0
	if surface in ["WATER", "OCEAN"]:
		return 0.0
	return clampf(rain, 0.0, 1.0) * smoothstep(3.0, 23.0, maxf(0.0, speed_mps))
