extends SceneTree
## Strict geometric and authoritative result rules for 2-4 driver friend drags.
const Race = preload("res://scripts/network/online_friend_race.gd")
const Session = preload("res://scripts/network/online_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)

func _run() -> void:
	check("protocol_v12_rejects_old_unsynchronized_race_clients",
		Session.PROTOCOL_VERSION == 12)
	for count in range(2, 5):
		var slots: Array[Vector2] = []
		var heading := Vector2(1.0, 0.0)
		var start := Vector2(150.0, 400.0)
		for index in count:
			slots.append(start + heading.orthogonal() * \
				Race.lane_offset_m(count, index))
		var separated := true
		for a in count:
			for b in count:
				if a != b and slots[a].distance_to(slots[b]) < 3.0:
					separated = false
		check("%d_racers_have_separate_starting_lanes" % count, separated)
		check("%d_racers_stay_inside_ashford_road_width" % count,
			absf(Race.lane_offset_m(count, 0)) <= Race.LANE_HALF_WIDTH_M - 1.0 and \
			absf(Race.lane_offset_m(count, count - 1)) <= Race.LANE_HALF_WIDTH_M - 1.0)
	var start_m := Vector2(125.0, 255.0)
	var forward := Vector2.UP
	var previous := start_m + forward * 400.0
	var finish := start_m + forward * 403.0
	var old: Vector2 = Race.race_position_m(previous * Race.PPM,
		start_m, forward)
	var current: Vector2 = Race.race_position_m(finish * Race.PPM,
		start_m, forward)
	check("forward_crossing_of_real_quarter_mile_finish_is_valid",
		Race.valid_finish(old, current))
	check("crossing_at_wide_off_track_position_does_not_finish",
		not Race.valid_finish(Vector2(400.0, 10.0), Vector2(403.0, 10.0)))
	check("reverse_or_repeated_finish_cannot_double_count",
		not Race.valid_finish(Vector2(404.0, 0), Vector2(403.0, 0)) and \
		not Race.valid_finish(Vector2(404.0, 0), Vector2(405.0, 0)))
	check("stationary_or_fast_local_physics_step_is_accepted",
		Race.legal_step(Vector2.ZERO, Vector2(4.0, 0.0),
			Vector2(150.0, 0.0), 0.0083))
	check("sudden_transform_or_reset_does_not_count_as_finish",
		not Race.legal_step(Vector2.ZERO, Vector2(1000.0, 0),
			Vector2.ZERO, 0.0083))
	var records := {
		7: {"name": "Later", "status": "finished", "ms": 11129},
		5: {"name": "First", "status": "finished", "ms": 10324},
		9: {"name": "DNF", "status": "dnf", "ms": 0},
		8: {"name": "Same Time", "status": "finished", "ms": 10324}
	}
	var ranks: Array = Race.sorted_finishers(records)
	check("host_places_finishers_by_time_not_RPC_arrival_order",
		ranks.size() == 3 and int(ranks[0]["id"]) == 5 and \
		int(ranks[1]["id"]) == 8 and int(ranks[2]["id"]) == 7)
	check("DNFs_cannot_appear_in_winner_ranking",
		ranks.size() == 3)
	print("FRIEND DRAG RULES: %s" % [
		"PASS" if failures.is_empty() else "FAIL " + str(failures)])
	quit(0 if failures.is_empty() else 1)
