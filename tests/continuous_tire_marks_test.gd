extends SceneTree
## Continuous, rounded tyre path regression. Headless tests inspect the
## underlying Line2D points/joins rather than reading back raster pixels.
const TireMarks = preload("res://scripts/world/tire_marks.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, good: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL",label,value])
	if not good:
		failures.append(label)


func run() -> void:
	var marks: TireMarks2D = TireMarks.new()
	root.add_child(marks)
	check("tyre_ink_layers_above_asphalt_and_under_vehicle",marks.z_index == 4)
	marks.add_mark(Vector2(100,100),0.0,true,0)
	var first: Line2D = marks.active_line(0)
	check("new_tyre_path_is_not_a_disconnected_footprint",
		first != null and first.get_point_count() == 1)
	marks.add_mark(Vector2(100,60),0.0,true,0)
	check("straight_line_joins_previous_contact_exactly",
		marks.active_line(0) == first and marks.last_strip_start == Vector2(100,100)
		and marks.last_strip_end == Vector2(100,60))
	check("rendering_uses_mesh_polyline_not_independent_quads",
		first.joint_mode == Line2D.LINE_JOINT_ROUND and \
		first.begin_cap_mode == Line2D.LINE_CAP_ROUND and \
		first.end_cap_mode == Line2D.LINE_CAP_ROUND and first.antialiased)
	var points_before_curve := first.get_point_count()
	marks.add_mark(Vector2(130,30),0.0,true,0)
	marks.add_mark(Vector2(170,22),0.0,true,0)
	marks.add_mark(Vector2(215,42),0.0,true,0)
	check("smooth_corner_is_one_unbroken_tyre_path",
		marks.active_line(0) == first and marks.trail_count() == 1 and
		first.get_point_count() > points_before_curve + 4)
	var continuous := true
	for i in range(1,first.get_point_count()):
		var span := first.get_point_position(i).distance_to(first.get_point_position(i-1))
		continuous = continuous and span > 0.1 and span <= marks.MAX_SAMPLE_SPACING + 0.1
	check("curved_path_is_densely_resampled",continuous)
	var road_ink: Color = marks.last_strip_color
	marks.add_mark(Vector2(300,100),0.0,false,1)
	marks.add_mark(Vector2(300,82),0.0,false,1)
	check("left_right_tracks_are_independent",
		marks.trail_count() == 2 and marks.active_line(1) != marks.active_line(0))
	check("grass_marks_are_soil_tinted",
		marks.last_strip_color.r > road_ink.r)
	var old_left := marks.active_line(0)
	marks.add_mark(Vector2(220,25),0.0,false,0)
	check("surface_change_ends_road_track_without_false_bridge",
		marks.active_line(0) != old_left and marks.active_line(0).get_point_count() == 1)
	marks.add_mark(Vector2(225,24),0.0,false,0)
	check("grass_path_is_continuous_within_its_surface",
		marks.active_line(0).get_point_count() == 2)
	var last_before_reset := marks.active_line(0)
	marks.reset_tracks()
	marks.add_mark(Vector2(700,700),0.0,true,0)
	check("reset_breaks_marks_without_erasing_older_paths",
		marks.active_line(0) != last_before_reset and marks.trail_count() >= 4
		and marks.active_line(0).get_point_count() == 1)
	marks.add_mark(Vector2(1200,1200),0.0,true,0)
	check("teleport_never_creates_one_giant_track",
		marks.active_line(0).get_point_count() == 1)
	var long_start := Vector2(900,1400)
	var long_drift_first_id := marks.count
	marks.reset_tracks()
	marks.add_mark(long_start,0.0,true,0)
	for i in 245:
		var t := float(i)*0.07
		var pos := long_start + Vector2(cos(t)*130.0+float(i)*3.0,
			sin(t)*130.0)
		# Limit intentional jumps so this always forms one long drift, even
		# as older lines split at the fixed per-trail point budget.
		marks.add_mark(pos,0.0,true,0)
	var splits := 0
	for line in marks._trails:
		if line.get_point_count() >= marks.POINTS_PER_TRAIL:
			splits += 1
	var seam_ok := true
	var valid_seams := 0
	for i in range(1,marks._trails.size()):
		var previous: Line2D = marks._trails[i-1]
		var next: Line2D = marks._trails[i]
		# Intentionally broken tracks (reset/material/teleport) must NOT
		# connect. Inspect only chunks belonging to this single long drift.
		var previous_id := int(str(previous.name).get_slice("_",2))
		var next_id := int(str(next.name).get_slice("_",2))
		if previous_id >= long_drift_first_id and next_id >= long_drift_first_id \
			and str(previous.name).begins_with("Tire_0_") and \
			str(next.name).begins_with("Tire_0_"):
			valid_seams += 1
			var p := previous.get_point_position(previous.get_point_count()-1)
			var n := next.get_point_position(0)
			if p.distance_to(n) > 0.05:
				seam_ok = false
	check("new_path_chunks_carry_old_endpoint_without_seams",
		seam_ok and valid_seams >= 2,valid_seams)
	check("skidmark_memory_stays_bounded_during_long_drifts",
		marks.trail_count() <= marks.MAX_TRAILS and
		marks.point_count() <= marks.CAPACITY,
		[marks.trail_count(),marks.point_count(),splits])
	check("rendered_marks_still_present_after_pool_recycling",
		marks.trail_count() >= 4 and marks.point_count() > 40)
	print("CONTINUOUS TIRE MARKS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
