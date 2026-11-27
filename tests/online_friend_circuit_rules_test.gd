extends SceneTree
## Host-only Ashford circuit gate checks. Exact physics cars are exercised
## separately in the real 2-process multiplayer world integration test.
const FriendRace = preload("res://scripts/network/online_friend_race.gd")
const Navigation = preload("res://scripts/world/race_navigation.gd")
const Session = preload("res://scripts/network/online_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)

func _run() -> void:
	check("protocol_v12_retains_circuit_event_RPC_shape",
		Session.PROTOCOL_VERSION == 12)
	var nav := Navigation.new()
	var corners := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(425.0, 0.0),
		Vector2(425.0, 425.0),
		Vector2(0.0, 425.0)])
	nav.setup(corners, true)
	var gates: Array[Dictionary] = FriendRace.make_circuit_gates(nav)
	check("closed_lap_uses_at_least_eight_real_route_checkpoints",
		gates.size() >= 8 and
		absf(float(nav.length_m) - 1700.0) < 0.01)
	var first: Dictionary = gates[0]
	var center: Vector2 = first["position"]
	var forward: Vector2 = first["forward"]
	check("valid_forward_approach_crosses_first_circuit_checkpoint",
		FriendRace.passed_directional_gate(center - forward * 3.0,
			center + forward * 3.0, first))
	check("reverse_crossing_never_advances_a_circuit_checkpoint",
		not FriendRace.passed_directional_gate(center + forward * 3.0,
			center - forward * 3.0, first))
	check("parallel_or_stationary_traffic_cannot_trigger_gate",
		not FriendRace.passed_directional_gate(center + forward.orthogonal() *
			-3.0, center + forward.orthogonal() * 3.0, first) and
		not FriendRace.passed_directional_gate(center, center, first))
	check("wide_shortcut_misses_the_gate_radius",
		not FriendRace.passed_directional_gate(center - forward * 3.0 +
			forward.orthogonal() * 30.0, center + forward * 3.0 +
			forward.orthogonal() * 30.0, first))
	var skipped: Dictionary = gates[5]
	var skipped_center: Vector2 = skipped["position"]
	var skipped_forward: Vector2 = skipped["forward"]
	check("crossing_a_later_checkpoint_cannot_skip_required_prior_gates",
		FriendRace.next_circuit_gate_index(0,
			skipped_center - skipped_forward * 2.0,
			skipped_center + skipped_forward * 2.0, gates) == 0)
	check("one_directional_gate_advances_exactly_one_checkpoint",
		FriendRace.next_circuit_gate_index(0, center - forward * 2.0,
			center + forward * 2.0, gates) == 1)
	check("same_crossing_does_not_advance_second_gate",
		FriendRace.next_circuit_gate_index(1, center - forward * 2.0,
			center + forward * 2.0, gates) == 1)
	check("already_finished_or_invalid_gate_index_never_advances",
		FriendRace.next_circuit_gate_index(gates.size(),
			center - forward, center + forward, gates) == gates.size())
	var open_nav := Navigation.new()
	open_nav.setup(PackedVector2Array([
		Vector2.ZERO, Vector2(650.0, 0.0)]), false)
	check("open_street_route_cannot_be_misread_as_closed_lap",
		FriendRace.make_circuit_gates(open_nav).is_empty())
	for count in range(2, 5):
		var safe := true
		for i in count:
			var offset := (float(i) - float(count - 1) * 0.5) * \
				FriendRace.CIRCUIT_LANE_SPACING_M
			if absf(offset) + 1.1 >= 7.0:
				safe = false
		check("circuit_%d_car_grid_stays_inside_14m_track" % count, safe)
	print("FRIEND CIRCUIT RULES: %s" % (
		"PASS" if failures.is_empty() else "FAIL " + str(failures)))
	quit(0 if failures.is_empty() else 1)
