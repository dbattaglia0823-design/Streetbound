extends RefCounted
## Tunable driving-focused fuel/charge meter. All distances use metres.
## Fuel is distinct from the nitrous bottle and cannot be reset by R.
const CONSUMPTION_SCALE := 2.5
const IDLE_PER_HOUR := 0.65
var capacity := 55.0
var remaining := 55.0
var per_100_km := 11.0
var electric := false

func configure(vehicle_kind: String, mass_kg: float, power_kw: float,
		is_electric: bool) -> void:
	electric = is_electric
	capacity = 75.0 if electric else (80.0 if vehicle_kind in ["truck", "suv"] else
		(45.0 if vehicle_kind == "compact" else 60.0))
	per_100_km = clampf(
		(19.0 if electric else 6.5) +
		mass_kg / (1200.0 if electric else 650.0) +
		power_kw / (140.0 if electric else 160.0),
		17.0 if electric else 6.0,
		40.0 if electric else 24.0)
	remaining = capacity

func fraction() -> float:
	return clampf(remaining / maxf(capacity, 0.01), 0.0, 1.0)

func empty() -> bool:
	return remaining <= 0.0001

func consume(dt: float, speed_mps: float, throttle: float) -> float:
	if dt <= 0.0 or not is_finite(dt) or not is_finite(speed_mps) or not is_finite(throttle):
		return 0.0
	if empty():
		return 0.0
	# Scale to keep fuel a meaningful gameplay resource on a compact map.
	# High throttle increases burn, while coasting and low speed reduce it.
	var distance_km := maxf(speed_mps, 0.0) * dt / 1000.0
	var load_factor := lerpf(0.70, 1.75, clampf(throttle, 0.0, 1.0))
	var used := distance_km * per_100_km / 100.0 * CONSUMPTION_SCALE * load_factor
	if not electric:
		used += IDLE_PER_HOUR * dt / 3600.0
	var applied := minf(remaining, used)
	remaining -= applied
	return applied

func refill_amount() -> float:
	return maxf(0.0, capacity - remaining)

func refill_cost(unit_price: float = 4.0) -> int:
	return ceili(refill_amount() * maxf(unit_price, 0.0))

func refill() -> void:
	remaining = capacity
