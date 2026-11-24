extends RefCounted
## Deterministic per-vehicle impact damage; independent from the physical collision solver.
## Repeated contact in one crash cannot consume the whole integrity bar.
const MIN_DAMAGING_IMPACT_MPS := 6.0
const IMPACT_COOLDOWN_SECONDS := 0.25
var integrity := 100.0
var last_impact_at := -INF

func register_impact(closing_speed_mps: float, now_seconds: float) -> float:
	if not is_finite(closing_speed_mps) or not is_finite(now_seconds):
		return 0.0
	if closing_speed_mps < MIN_DAMAGING_IMPACT_MPS or now_seconds - last_impact_at < IMPACT_COOLDOWN_SECONDS:
		return 0.0
	last_impact_at = now_seconds
	var damage := minf(65.0, (closing_speed_mps - MIN_DAMAGING_IMPACT_MPS) * 1.8)
	var applied := minf(integrity, damage)
	integrity = maxf(0.0, integrity - applied)
	return applied

func drive_fraction() -> float:
	if integrity <= 0.0:
		return 0.0
	if integrity >= 70.0:
		return 1.0
	return lerpf(0.35, 1.0, integrity / 70.0)

func is_disabled() -> bool:
	return integrity <= 0.0

func repair_cost() -> int:
	return ceili((100.0 - integrity) * 35.0)

func repair() -> void:
	integrity = 100.0
	last_impact_at = -INF
