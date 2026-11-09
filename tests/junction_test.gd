extends SceneTree
var failures: Array[String] = []
const Clip = preload("res://scripts/world/road_marking_clip.gd")

func _initialize() -> void:
	call_deferred("run")

func check(name: String, passed: bool, details: Variant = "") -> void:
	print("%s %s %s"%["PASS" if passed else "FAIL",name,details])
	if not passed: failures.append(name)

func v(p: Array) -> Vector2:
	return Vector2(float(p[0]),float(p[1]))

func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/morrow-coast.world.json"))
	var invalid: Array = []
	var uncontrolled: Array = []
	for i in data.junctions.size():
		var j: Dictionary = data.junctions[i]
		var polygon := PackedVector2Array()
		for p in j.polygon: polygon.append(v(p))
		if Geometry2D.triangulate_polygon(polygon).is_empty():
			invalid.append([i,j.p,j.roads])
		if j.approaches.size()>=3:
			var controls := 0
			for arm in j.approaches:
				if arm.control in ["stop","yield"]: controls+=1
			if controls==0: uncontrolled.append(i)
	check("all_junctions_have_valid_pavement",invalid.is_empty(),invalid)
	check("intersections_have_explicit_priority",uncontrolled.is_empty(),uncontrolled)
	var missed: Array = []
	for crossing in data.road_crossings:
		var p := v(crossing.p)
		var covered := false
		for j in data.junctions:
			if j.roads.has(crossing.roads[0]) and j.roads.has(crossing.roads[1]) and p.distance_to(v(j.p))<3.01:
				covered=true
				break
		if not covered:
			var directions: Array[Vector2] = []
			for id in crossing.roads:
				var road: Dictionary = data.roads[int(id)]
				if p.distance_to(v(road.points[0]))<.2: directions.append((v(road.points[1])-p).normalized())
				elif p.distance_to(v(road.points[-1]))<.2: directions.append((v(road.points[-2])-p).normalized())
			if directions.size()!=2 or directions[0].dot(directions[1])>-.94: missed.append(crossing)
	check("every_crossing_or_T_join_has_junction_geometry",missed.is_empty(),missed)
	var untrimmed: Array = []
	for i in data.junctions.size():
		for arm in data.junctions[i].approaches:
			var covered := false
			for gap in data.roads[int(arm.road)].marking_gaps:
				if float(gap[0])<=float(arm.station) and float(gap[1])>=float(arm.station): covered=true
			if not covered: untrimmed.append([i,arm.road])
	check("every_approach_has_a_paint_exclusion",untrimmed.is_empty(),untrimmed)
	var blocked: Array = []
	for i in data.junctions.size():
		var j: Dictionary = data.junctions[i]
		var polygon := PackedVector2Array()
		for p in j.polygon: polygon.append(v(p))
		for prop in data.props:
			if not prop.solid or v(prop.p).distance_to(v(j.p))>float(j.radius)+float(prop.radius): continue
			var inside := Geometry2D.is_point_in_polygon(v(prop.p),polygon)
			for edge in polygon.size():
				if Geometry2D.get_closest_point_to_segment(v(prop.p),polygon[edge],polygon[(edge+1)%polygon.size()]).distance_to(v(prop.p))<float(prop.radius): inside=true
			if inside: blocked.append([i,prop.kind,prop.p])
	check("junction_turning_areas_clear_of_solid_scenery",blocked.is_empty(),blocked)
	var path := PackedVector2Array([Vector2.ZERO,Vector2(100,0),Vector2(200,0),Vector2(300,0)])
	var pieces := Clip.parts(path,0,[[3.0,8.0],[10.0,11.0]])
	check("markings_stop_before_and_resume_after_gaps",pieces.size()==3 and pieces[0].path[-1].is_equal_approx(Vector2(60,0)) and pieces[1].path[0].is_equal_approx(Vector2(160,0)) and pieces[1].path[-1].is_equal_approx(Vector2(200,0)) and pieces[2].path[0].is_equal_approx(Vector2(220,0)))
	check("dash_phase_survives_clipping",pieces.size()==3 and is_equal_approx(float(pieces[1].phase),160) and is_equal_approx(float(pieces[2].phase),220))
	var inside := Clip.parts(path,100,[[0.0,30.0]])
	check("paint_fully_inside_junction_is_removed",inside.is_empty())
	print("JUNCTION TESTS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
