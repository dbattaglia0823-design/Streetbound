extends SceneTree
## Each rear tire now produces one uninterrupted ribbon per skid episode,
## including bends; the MultiMesh ring and no-long-gap safeguards stay bounded.
const TireMarks = preload("res://scripts/world/tire_marks.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, good: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL", label, value])
	if not good:
		failures.append(label)

func start_of(t: Transform2D) -> Vector2:
	return t.origin - t.y * 0.5

func end_of(t: Transform2D) -> Vector2:
	return t.origin + t.y * 0.5

func run() -> void:
	var marks: TireMarks2D = TireMarks.new()
	root.add_child(marks)
	marks.add_mark(Vector2(100,100),0.0,true,0)
	marks.add_mark(Vector2(100,60),0.0,true,0)
	var straight: Transform2D = marks.multimesh.get_instance_transform_2d(1)
	check("second_mark_spans_previous_tire_position",
		straight.y.length() >= 40.0 and straight.y.length() <= 45.0 and
		start_of(straight).distance_to(Vector2(100,100)) <= 2.0 and
		end_of(straight).distance_to(Vector2(100,60)) <= 2.0,
		[start_of(straight),end_of(straight)])
	marks.add_mark(Vector2(130,30),0.0,true,0)
	var corner: Transform2D = marks.multimesh.get_instance_transform_2d(2)
	check("corner_connects_to_last_strip",
		start_of(corner).distance_to(Vector2(100,60)) <= 2.0 and
		end_of(corner).distance_to(Vector2(130,30)) <= 2.0 and
		corner.y.length() > 40.0,[start_of(corner),end_of(corner)])
	check("tire_width_consistent", absf(straight.x.length()-6.0)<0.01 and
		absf(corner.x.length()-6.0)<0.01)
	check("marks_are_not_fixed_size_boxes",
		marks.multimesh.mesh is QuadMesh and
		(marks.multimesh.mesh as QuadMesh).size.is_equal_approx(Vector2.ONE))

	# Alternating left and right tires must not bridge to each other.
	marks.add_mark(Vector2(200,100),0.0,false,1)
	marks.add_mark(Vector2(200,80),0.0,false,1)
	var grass: Transform2D = marks.multimesh.get_instance_transform_2d(4)
	check("separate_right_track_extends",grass.y.length()>=20.0 and
		start_of(grass).distance_to(Vector2(200,100))<2.0)
	check("grass_tire_marks_have_soil_color",
		marks.multimesh.get_instance_color(4).r > marks.multimesh.get_instance_color(1).r)
	# A grip change or collision reset must start a short new strip.
	marks.add_mark(Vector2(130,5),0.0,false,0)
	var surface_change: Transform2D = marks.multimesh.get_instance_transform_2d(5)
	check("surface_transition_does_not_drag_old_road_track",
		surface_change.y.length() < 13.0,surface_change.y.length())
	marks.reset_tracks()
	marks.add_mark(Vector2(700,700),0.0,true,0)
	var restarted: Transform2D = marks.multimesh.get_instance_transform_2d(6)
	check("reset_does_not_connect_teleport",
		restarted.y.length() < 13.0,restarted.y.length())
	marks.add_mark(Vector2(1200,1200),0.0,true,0)
	var teleported: Transform2D = marks.multimesh.get_instance_transform_2d(7)
	check("long_discontinuity_is_capped",
		teleported.y.length() < 13.0,teleported.y.length())
	check("pool_remains_fixed_size",
		marks.multimesh.instance_count==1800 and marks.count==8 and marks.next_slot==8)
	print("CONTINUOUS TIRE MARKS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
