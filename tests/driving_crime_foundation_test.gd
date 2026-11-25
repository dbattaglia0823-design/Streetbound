extends SceneTree
## Deterministic rules and real controller integration for driving-only police.
const Damage = preload("res://scripts/vehicle/vehicle_damage.gd")
const Containment = preload("res://scripts/world/police_containment.gd")
const Police = preload("res://scripts/world/police_pursuit.gd")
const DamageService = preload("res://scripts/world/vehicle_damage_service.gd")
const DamageSmoke = preload("res://scripts/visual/engine_damage_smoke.gd")
const PlayerScene = preload("res://scenes/vehicle.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)

func run() -> void:
	var damage = Damage.new()
	check("harmless_touch", damage.register_impact(3.0, 1.0) == 0.0)
	var strike: float = damage.register_impact(26.0, 2.0)
	check("impact_causes_integrity_loss", strike > 0.0 and damage.integrity < 100.0)
	var remaining: float = damage.integrity
	check("repeated_same_crash_debounced", damage.register_impact(26.0, 2.1) == 0.0
		and is_equal_approx(damage.integrity, remaining))
	check("nonfinite_collision_rejected", damage.register_impact(INF, 2.5) == 0.0)
	check("no_power_loss_at_64_percent", damage.drive_fraction() == 1.0)
	damage.integrity = 20.0
	check("no_power_loss_at_20_percent", damage.drive_fraction() == 1.0)
	damage.integrity = 19.0
	check("smooth_loss_below_20_percent", damage.drive_fraction() < 1.0
		and damage.drive_fraction() > 0.98)
	damage.integrity = 10.0
	check("only_ten_percent_loss_at_ten_health",
		is_equal_approx(damage.drive_fraction(), 0.90))
	damage.integrity = 1.0
	check("damaged_engine_still_usable_near_zero", damage.drive_fraction() > 0.80)
	damage.integrity = remaining
	damage.register_impact(60.0, 3.0)
	damage.register_impact(60.0, 4.0)
	check("disabled_after_severe_crashes", damage.is_disabled() and damage.drive_fraction() == 0.0)
	check("damage_cost_bounded", damage.repair_cost() == 3500)
	damage.repair()
	check("repair_restores_drivetrain", damage.integrity == 100.0 and
		damage.drive_fraction() == 1.0 and damage.repair_cost() == 0)

	var police_ring: Array[Vector2] = [
		Vector2(5.0, 0.0), Vector2(-2.5, 4.33), Vector2(-2.5, -4.33)]
	var p := Containment.progress(0.0, 1.0, Vector2.ZERO, 0.0, 0.0, police_ring)
	check("surrounded_stationary_car_can_be_busted", p == 1.0)
	p = Containment.progress(0.0, 1.0, Vector2.ZERO, 4.0, 1.0, police_ring)
	check("moving_car_not_busted", p == 0.0)
	var single_officer: Array[Vector2] = [Vector2(3.0, 0.0)]
	p = Containment.progress(0.0, 5.0, Vector2.ZERO, 0.0, 1.0, single_officer)
	check("one_police_car_cannot_arrest", p == 0.0)
	var same_side: Array[Vector2] = [
		Vector2(4.0, 0.0), Vector2(4.0, 1.0), Vector2(4.0, -1.0)]
	p = Containment.progress(0.0, 5.0, Vector2.ZERO, 0.0, 1.0, same_side)
	check("one_open_escape_side_cannot_arrest", p == 0.0)
	for i in 3:
		p = Containment.progress(p, 1.0, Vector2.ZERO, 0.0, 1.0, police_ring)
	check("capture_requires_full_timer", not Containment.is_busted(p))
	p = Containment.progress(p, 1.0, Vector2.ZERO, 0.0, 1.0, police_ring)
	check("surrounded_player_busted", Containment.is_busted(p))
	p = Containment.progress(p, 0.1, Vector2.ZERO, 5.0, 1.0, police_ring)
	check("breaking_box_resets_timer", p == 0.0)

	check("smoke_hidden_on_healthy_engine", DamageSmoke.smoke_strength(100.0) == 0.0
		and DamageSmoke.smoke_strength(60.0) == 0.0)
	check("smoke_increases_with_damage", DamageSmoke.smoke_strength(50.0) > 0.0
		and DamageSmoke.smoke_strength(20.0) > DamageSmoke.smoke_strength(50.0)
		and DamageSmoke.smoke_strength(0.0) > DamageSmoke.smoke_strength(20.0))

	var car: VehicleController2D = PlayerScene.instantiate()
	car.external_input = true
	root.add_child(car)
	await physics_frame
	car.damage_drive_fraction = 0.0
	car.reset_vehicle()
	check("reset_does_not_repair_vehicle", car.damage_drive_fraction == 0.0)
	car.damage_drive_fraction = 1.0
	car.fuel_drive_fraction = 0.0
	for frame in 120:
		car.step_vehicle(1.0 / 120.0, Vector4(1.0, 0.0, 0.0, 0.0))
	check("empty_fuel_disables_acceleration", car.linear_velocity.length() < 0.1)
	car.fuel_drive_fraction = 1.0
	for frame in 120:
		car.step_vehicle(1.0 / 120.0, Vector4(1.0, 0.0, 0.0, 0.0))
	check("refilled_fuel_restores_acceleration", car.linear_velocity.length() > 0.1)
	var smoke: Node2D = Node2D.new()
	smoke.set_script(DamageSmoke)
	smoke.set("vehicle", car)
	car.add_child(smoke)
	smoke.call("set_health", 10.0)
	for i in 120:
		smoke.call("_process", 0.05)
	var emitted: Array = smoke.get("puffs")
	check("smoke_emits_from_damaged_hood", emitted.size() > 0
		and emitted.size() <= DamageSmoke.MAX_PUFFS)
	smoke.call("set_health", 100.0)
	for i in 50:
		smoke.call("_process", 0.05)
	check("smoke_dissipates_after_repair", (smoke.get("puffs") as Array).is_empty())
	check("police_and_repair_scripts_constructible", Police.new() != null and
		DamageService.new() != null)
	car.queue_free()
	print("DRIVING CRIME FOUNDATION: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
