extends SceneTree
## Low-latency networking regression: pure timing, state interpolation,
## jitter buffering and bounded visual-only extrapolation.
const Buffer = preload("res://scripts/network/remote_snapshot_buffer.gd")
const OnlineWorld = preload("res://scripts/network/online_world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures.append(label)

func _state(position: Vector2, heading: float, velocity: Vector2) -> Array:
	return [position, heading, velocity, 0.25, 20.0, 0.0]

func _run() -> void:
	check("player_input_cadence_at_least_60hz",
		OnlineWorld.INPUT_RATE <= 1.0 / 60.0 + 0.00001 and
		OnlineWorld.INPUT_RATE > 0.0)
	check("authoritative_snapshots_30hz",
		OnlineWorld.SNAPSHOT_RATE <= 1.0 / 30.0 + 0.00001 and
		OnlineWorld.SNAPSHOT_RATE > 0.0)
	check("stationary_controls_use_bounded_heartbeat",
		OnlineWorld.INPUT_HEARTBEAT < float(OnlineWorld.COMMAND_TIMEOUT_MS) / 1000.0
		and OnlineWorld.INPUT_HEARTBEAT >= OnlineWorld.INPUT_RATE)
	check("smoothing_delay_is_not_unbounded_by_high_rtt",
		Buffer.interpolation_delay_ms(33.33, 0) >= 50 and
		Buffer.interpolation_delay_ms(33.33, 500) <= 125 and
		Buffer.interpolation_delay_ms(33.33, 30) >
		Buffer.interpolation_delay_ms(33.33, 0))
	var history: Array = []
	Buffer.add_snapshot(history, 0, _state(Vector2(0.0, 0.0), 0.0,
		Vector2(20.0, 0.0)))
	Buffer.add_snapshot(history, 40, _state(Vector2(12.0, 0.0), 0.5,
		Vector2(20.0, 0.0)))
	var halfway: Array = Buffer.sample(history, 60, 40)
	check("visual_car_interpolates_between_timestamped_states",
		halfway.size() == 6 and
		is_equal_approx((halfway[0] as Vector2).x, 6.0) and
		is_equal_approx(float(halfway[1]), 0.25))
	var ahead: Array = Buffer.sample(history, 150, 40)
	check("lost_packet_prediction_caps_to_60ms_of_velocity",
		ahead.size() == 6 and
		is_equal_approx((ahead[0] as Vector2).x, 13.2))
	var frozen: Array = Buffer.sample(history, 600, 40)
	check("long_packet_gap_freezes_visual_car_instead_of_wall_teleport",
		frozen.size() == 6 and
		(frozen[0] as Vector2) == Vector2(12.0, 0.0))
	check("local_authority_compensates_for_half_rtt_without_false_lag",
		is_equal_approx(Buffer.projected_local_authority(
			_state(Vector2.ZERO, 0.0, Vector2(20.0, 0.0)), 100.0).x, 1.0))
	check("local_authority_projection_is_bounded_on_large_rtt",
		is_equal_approx(Buffer.projected_local_authority(
			_state(Vector2.ZERO, 0.0, Vector2(20.0, 0.0)), 1200.0).x, 1.6))
	check("invalid_local_authority_is_not_predicted",
		Buffer.projected_local_authority([], 500.0) == Vector2.ZERO)
	check("empty_or_invalid_snapshots_are_safely_ignored",
		Buffer.sample([], 100, 50).is_empty())
	Buffer.add_snapshot(history, 80, [])
	check("malformed_snapshot_not_added", history.size() == 2)
	for index in 15:
		Buffer.add_snapshot(history, 100 + index * 40,
			_state(Vector2(float(index), 0.0), 0.0, Vector2.ZERO))
	check("history_is_bounded_and_latest_sample_is_retained",
		history.size() == Buffer.MAX_HISTORY and
		(history.back() as Dictionary)["time"] == 660)
	var short_rotation: Array = Buffer.interpolate(
		_state(Vector2.ZERO, PI - 0.1, Vector2.ZERO),
		_state(Vector2.ZERO, -PI + 0.1, Vector2.ZERO), 0.5)
	check("heading_wraps_across_pi_without_full_spin",
		short_rotation.size() == 6 and
		absf(absf(float(short_rotation[1])) - PI) < 0.01)
	var grades: Array = []
	Buffer.add_snapshot(grades, 0, _state(Vector2.ZERO, 0.0, Vector2.ZERO), -6.0)
	Buffer.add_snapshot(grades, 40, _state(Vector2(12, 0), 0.0, Vector2.ZERO), -3.0)
	check("signed_road_height_uses_the_position_interpolation_clock",
		is_equal_approx(Buffer.sample_grade_height(grades, 60, 40), -4.5))
	check("missing_packets_hold_last_authoritative_height",
		is_equal_approx(Buffer.sample_grade_height(grades, 600, 40), -3.0))
	Buffer.add_snapshot(grades, 80, _state(Vector2.ZERO, 0.0, Vector2.ZERO), 6.0)
	check("positive_deck_height_is_preserved",
		is_equal_approx(Buffer.sample_grade_height(grades, 120, 40), 6.0))
	check("invalid_road_height_is_rejected",
		not Buffer.valid_grade_height(INF) and not Buffer.valid_grade_height(NAN)
		and not Buffer.valid_grade_height(12.1) and not Buffer.valid_grade_height("6"))
	Buffer.add_snapshot(grades, 120, _state(Vector2.ZERO, 0.0, Vector2.ZERO))
	check("legacy_movement_snapshot_defaults_to_ground",
		is_zero_approx(Buffer.sample_grade_height(grades, 160, 40)))
	var replica := VehicleController2D.new()
	replica.set_physics_process(false)
	replica.z_index = 8
	replica.collision_layer = 0
	replica.collision_mask = 0
	replica.apply_remote_grade_visual(6.0)
	check("render_only_replica_uses_deck_z_without_enabling_collision",
		replica.road_layer == 1 and replica.z_index == 24
		and replica.collision_layer == 0 and replica.collision_mask == 0)
	replica.apply_remote_grade_visual(-6.0)
	check("render_only_replica_preserves_signed_tunnel_layer",
		replica.road_layer == -1 and is_equal_approx(replica.elevation_m, -6.0))
	replica.apply_remote_grade_visual(0.0)
	check("render_only_replica_restores_ground_z",
		replica.road_layer == 0 and replica.z_index == 8)
	replica.free()
	var online_session: Node = root.get_node_or_null("OnlineSession")
	check("disconnected_session_has_no_fake_ping_statistic",
		online_session != null and online_session.network_stats().is_empty())
	print("NETWORK SMOOTHING: %s" % ("PASS" if failures.is_empty()
		else "FAIL " + str(failures)))
	quit(0 if failures.is_empty() else 1)
