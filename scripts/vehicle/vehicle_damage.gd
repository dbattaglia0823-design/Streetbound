extends RefCounted
## Deterministic per-vehicle impact damage; independent from the physical collision solver.
## Repeated contact in one crash cannot consume the whole integrity bar.
const MIN_DAMAGING_IMPACT_MPS := 6.0
const IMPACT_COOLDOWN_SECONDS := 0.25
## 20x point scale preserves the normalized stock damage balance.
const DAMAGE_POINTS_PER_MPS := 36.0
const MAX_BASE_IMPACT_POINTS := 1300.0
## Keep normalized integrity for existing saves, repairs and smoke thresholds.
var integrity := 100.0
var max_health_points: int = 2000
const PLAYER_DAMAGE_COLOR := Color("#ff9d32")
const POLICE_DAMAGE_COLOR := Color("#ff4545")

func current_health_points() -> float:
	return clampf(integrity, 0.0, 100.0) * float(maxi(1, max_health_points)) / 100.0
var last_impact_at := -INF

## Optional outgoing multiplier is an extension point for future impact upgrades.
## Stock collisions use 1.0; upgrades are not yet equipped or sold.
func register_impact(closing_speed_mps: float, now_seconds: float, outgoing_multiplier: float = 1.0) -> float:
	if not is_finite(closing_speed_mps) or not is_finite(now_seconds) or not is_finite(outgoing_multiplier) or outgoing_multiplier <= 0.0:
		return 0.0
	if closing_speed_mps < MIN_DAMAGING_IMPACT_MPS or now_seconds - last_impact_at < IMPACT_COOLDOWN_SECONDS:
		return 0.0
	var base_damage := minf(MAX_BASE_IMPACT_POINTS, (closing_speed_mps - MIN_DAMAGING_IMPACT_MPS) * DAMAGE_POINTS_PER_MPS)
	if base_damage <= 0.0:
		return 0.0
	last_impact_at = now_seconds
	var damage := base_damage * clampf(outgoing_multiplier, 0.0, 3.0)
	var capacity := float(maxi(1, max_health_points))
	var remaining := current_health_points()
	var applied := minf(remaining, maxf(1.0, roundf(damage)))
	integrity = maxf(0.0, remaining - applied) / capacity * 100.0
	return applied

## Engine health affects performance only in the critical last 20%.
## At 1% health the engine still produces roughly 81% of normal drive force;
## 0% remains a fully disabled vehicle for police/impound gameplay.
const POWER_LOSS_START_HEALTH := 20.0
const MAX_RUNNING_POWER_LOSS := 0.20

func drive_fraction() -> float:
	if integrity <= 0.0:
		return 0.0
	if integrity >= POWER_LOSS_START_HEALTH:
		return 1.0
	return 1.0 - MAX_RUNNING_POWER_LOSS * (
		(POWER_LOSS_START_HEALTH - integrity) / POWER_LOSS_START_HEALTH)

func is_disabled() -> bool:
	return integrity <= 0.0

func repair_cost() -> int:
	return ceili((100.0 - integrity) * 35.0)

func repair() -> void:
	integrity = 100.0
	last_impact_at = -INF

## World-anchored, screen-upright damage text. Reuse one overlay per vehicle.
## The existing impact cooldown bounds concurrent labels; each self-frees.
static func show_damage_number(vehicle: Node2D, points: float, police: bool = false) -> Label:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree() or points <= 0.0:
		return null
	var overlay := vehicle.get_node_or_null("DamageNumbers") as CanvasLayer
	if overlay == null:
		overlay = CanvasLayer.new()
		overlay.name = "DamageNumbers"
		overlay.layer = 3
		vehicle.add_child(overlay)
	var label := Label.new()
	label.text = "-%d" % maxi(1, roundi(points))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", POLICE_DAMAGE_COLOR if police else PLAYER_DAMAGE_COLOR)
	label.add_theme_color_override("font_outline_color", Color("#111719"))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(100.0, 36.0)
	overlay.add_child(label)
	var update := func(progress: float) -> void:
		if not is_instance_valid(vehicle) or not is_instance_valid(label):
			return
		label.position = vehicle.get_global_transform_with_canvas().origin + Vector2(-50.0, -55.0 - 46.0 * progress)
		label.modulate.a = 1.0 - smoothstep(0.35, 1.0, progress)
	update.call(0.0)
	var tween := label.create_tween()
	tween.tween_method(update, 0.0, 1.0, 0.9)
	tween.tween_callback(label.queue_free)
	return label
