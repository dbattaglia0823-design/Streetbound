extends SceneTree
## Fast deterministic contract test for telemetry (no world or long race needed).
const Metrics = preload("res://scripts/world/ai_benchmark_metrics.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func verify(name: String, valid: bool) -> void:
	print("%s %s" % ["PASS" if valid else "FAIL", name])
	if not valid:
		failures.append(name)


func _run() -> void:
	var m := Metrics.new()
	m.sample(0.1, Vector2.ZERO, 5.0, Vector4(0.5,0.0,0.9,0.0), "ASPHALT")
	m.sample(0.1, Vector2(20,0), 5.0, Vector4(0.5,0.0,-0.9,0.0), "GRASS")
	m.sample(0.1, Vector2(40,0), 5.0, Vector4(0.5,0.0,0.02,0.0), "GRASS")
	verify("counts_only_real_steering_reversals", m.steering_corrections == 1)
	verify("measures_offroad_simulated_seconds", is_equal_approx(m.offroad_s,0.2))
	verify("counts_real_distance_in_metres", absf(m.distance_m-2.0)<0.001)
	m.collision(3.0)
	m.collision(5.0)
	verify("debounces_repeated_collision_contacts", m.collision_events==1)
	var repeated_contact := Metrics.new()
	for index in 100:
		repeated_contact.sample(0.1,Vector2.ZERO,0.0,
			Vector4(0.8,0,0,0),"ASPHALT")
		repeated_contact.collision()
	verify("continuous_wall_contact_is_one_collision_episode",
		repeated_contact.collision_events==1)
	for index in 9:
		repeated_contact.sample(0.1,Vector2.ZERO,0.0,
			Vector4.ZERO,"ASPHALT")
	repeated_contact.collision()
	verify("new_contact_after_separation_is_new_collision",
		repeated_contact.collision_events==2)
	m.sample(0.2,Vector2(40,0),0.3,Vector4(0.0,1,0,0),"ASPHALT")
	verify("braking_is_not_counted_as_a_stall", m.stall_events==0)
	for i in 30:
		m.sample(0.1,Vector2(40,0),0.2,Vector4(0.8,0,0,0),"ASPHALT")
	verify("sustained_throttle_with_no_motion_stalls", m.stall_events==1)
	verify("stalled_vehicle_does_not_self_recover", m.successful_recoveries==0)
	m.sample(0.1,Vector2(140,0),4.0,Vector4(0.8,0,0,0),"ASPHALT")
	verify("physical_movement_counts_as_a_stuck_recovery",
		m.successful_recoveries==1 and m.summary().unresolved_stuck_events==0)
	m.sample(0.25,Vector2(160,0),0.2,Vector4(0.7,0,0,0),"ASPHALT")
	verify("retains_collision_time_debounce_without_new_contacts",
		m.collision_events==1)
	var summary: Dictionary=m.summary()
	verify("exports_all_requested_numeric_metrics",
		summary.has("elapsed_s") and summary.has("steering_corrections") and
		summary.has("offroad_time_s") and summary.has("collisions") and
		summary.has("stuck_events") and summary.has("stuck_recoveries") and
		summary.has("unresolved_stuck_events"))
	print("AI BENCHMARK METRICS: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
