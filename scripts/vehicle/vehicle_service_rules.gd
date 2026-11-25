extends RefCounted
## Driving-only service policy. Garages have precedence over fuel stops.
## Fuel stops can restore integrity to 50%, never above it.
const STATION_REPAIR_LIMIT := 50.0
const STATION_REPAIR_BASE_FEE := 25
const STATION_REPAIR_PER_POINT := 4
const TOW_MAX_FEE := 750

static func service_type(garage_available: bool, station_available: bool) -> String:
	if garage_available:
		return "garage"
	if station_available:
		return "station"
	return ""

static func station_repair_target(integrity: float) -> float:
	return clampf(maxf(integrity, STATION_REPAIR_LIMIT), 0.0, 100.0)

static func station_repair_fee(integrity: float) -> int:
	if not is_finite(integrity) or integrity >= STATION_REPAIR_LIMIT:
		return 0
	return STATION_REPAIR_BASE_FEE + ceili((STATION_REPAIR_LIMIT - maxf(0.0, integrity)) * STATION_REPAIR_PER_POINT)

static func can_apply_station_repair(integrity: float, balance: int) -> bool:
	return integrity >= 0.0 and integrity < STATION_REPAIR_LIMIT and balance >= station_repair_fee(integrity)
