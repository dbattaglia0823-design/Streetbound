extends SceneTree
## Verify the CPU-generated connected strips; a headless render server does
## not support reading MultiMesh instance transforms back from its GPU buffer.
const TireMarks = preload("res://scripts/world/tire_marks.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, good: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL", label, value])
	if not good:
		failures.append(label)

func run() -> void:
	var marks: TireMarks2D = TireMarks.new()
	root.add_child(marks)
	marks.add_mark(Vector2(100,100),0.0,true,0)
	marks.add_mark(Vector2(100,60),0.0,true,0)
	var straight_start: Vector2 = marks.last_strip_start
	var straight_end: Vector2 = marks.last_strip_end
	var straight_length: float = straight_start.distance_to(straight_end)
	check("second_mark_spans_previous_tire_position",
		straight_length >= 40.0 and straight_length <= 45.0 and
		straight_start.distance_to(Vector2(100,100)) <= 2.0 and
		straight_end.distance_to(Vector2(100,60)) <= 2.0,
		[straight_start,straight_end])
	var asphalt_ink: Color = marks.last_strip_color
	marks.add_mark(Vector2(130,30),0.0,true,0)
	var corner_start: Vector2 = marks.last_strip_start
	var corner_end: Vector2 = marks.last_strip_end
	check("corner_connects_to_last_strip",
		corner_start.distance_to(Vector2(100,60)) <= 2.0 and
		corner_end.distance_to(Vector2(130,30)) <= 2.0 and
		corner_start.distance_to(corner_end) > 40.0,
		[corner_start,corner_end])
	check("tracks_use_uniform_ribbon_width",
		marks.STRIP_WIDTH == 6.0 and marks.multimesh.mesh is QuadMesh)
	check("marks_are_not_fixed_size_boxes",
		(marks.multimesh.mesh as QuadMesh).size.is_equal_approx(Vector2.ONE))

	# Both tires retain their own history. Starting the second tire must not
	# connect to the previous left tire mark.
	marks.add_mark(Vector2(200,100),0.0,false,1)
	marks.add_mark(Vector2(200,80),0.0,false,1)
	check("separate_right_track_extends",
		marks.last_strip_track == 1 and
		marks.last_strip_start.distance_to(Vector2(200,100)) < 2.0 and
		marks.last_strip_end.distance_to(Vector2(200,80)) < 2.0)
	check("grass_tire_marks_use_soil_tint",
		marks.last_strip_color.r > asphalt_ink.r)
	# A switch between asphalt and grass must start a short new segment.
	marks.add_mark(Vector2(130,5),0.0,false,0)
	check("surface_transition_does_not_drag_old_road_track",
		marks.last_strip_start.distance_to(marks.last_strip_end) < 13.0)
	marks.reset_tracks()
	marks.add_mark(Vector2(700,700),0.0,true,0)
	check("reset_does_not_connect_teleport",
		marks.last_strip_start.distance_to(marks.last_strip_end) < 13.0)
	marks.add_mark(Vector2(1200,1200),0.0,true,0)
	check("long_discontinuity_is_capped",
		marks.last_strip_start.distance_to(marks.last_strip_end) < 13.0)
	check("pool_remains_fixed_size",
		marks.multimesh.instance_count == 1800 and marks.count == 8 and marks.next_slot == 8)
	print("CONTINUOUS TIRE MARKS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
