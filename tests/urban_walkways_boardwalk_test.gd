extends SceneTree
## New road-attached footpaths and beach promenade share the baked geometry,
## but retain existing lanes, curb mouths, collision clearance and streaming.
const Walkways = preload("res://scripts/world/urban_walkways.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, good: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL", label, value])
	if not good:
		failures.append(label)

func raw_vec(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func run() -> void:
	var straight := PackedVector2Array([Vector2(0,0),Vector2(0,150),Vector2(0,300)])
	var left := Walkways.urban_sidewalk_center(straight,200.0,-1.0)
	var right := Walkways.urban_sidewalk_center(straight,200.0,1.0)
	check("sidewalks_on_both_sides", left.size() == 3 and right.size() == 3 and
		left[1].x > 0.0 and right[1].x < 0.0 and
		is_equal_approx(left[1].y, straight[1].y) and is_equal_approx(right[1].y, straight[1].y),
		[left[1],right[1]])
	var curve := PackedVector2Array([
		Vector2(0,0),Vector2(0,125),Vector2(30,205),
		Vector2(95,260),Vector2(205,285)])
	var outer := Walkways.urban_sidewalk_outer(curve,180.0,1.0)
	var inner := Walkways.urban_sidewalk_outer(curve,180.0,-1.0)
	var continuous := outer.size() == curve.size() and inner.size() == curve.size()
	for i in range(1, outer.size()):
		if not is_finite(outer[i].x) or not is_finite(inner[i].x):
			continuous=false
		if outer[i].distance_to(outer[i-1]) > 260.0 or inner[i].distance_to(inner[i-1]) > 260.0:
			continuous=false
	check("both_sidewalks_follow_sweeping_bend", continuous, [outer,inner])

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	check("boardwalk_traced_from_coastline", world.boardwalk_path.size() >= 12,
		world.boardwalk_path.size())
	if world.boardwalk_path.size() >= 12:
		var boardwalk := world.boardwalk_path
		var ocean: Array = []
		for item in world.data.terrain:
			if item.kind == "ocean":
				ocean=item.points
				break
		var matching := true
		var samples := 0
		for raw in ocean.slice(0, maxi(0,ocean.size()-2)):
			var position := raw_vec(raw)
			if position.y < 2100 or position.y > 3700:
				continue
			if samples >= boardwalk.size() or boardwalk[samples].distance_to(position + Vector2(-35,0)) > 0.01:
				matching = false
				break
			samples += 1
		check("boardwalk_follows_real_shoreline", matching and samples == boardwalk.size(), samples)
		var shore_sample: Vector2 = boardwalk[boardwalk.size()/2]
		world.stream_at(shore_sample * 20.0)
		while not world.pending.is_empty():
			world._build_chunk(world.pending.pop_front())
		var cell := Vector2i((shore_sample/world.chunk_m).floor())
		check("boardwalk_chunk_streamed",world.chunks.has(cell), cell)
		if world.chunks.has(cell):
			var chunk: Node = world.chunks[cell]
			var deck: Node2D = chunk.get_node_or_null("BeachBoardwalk")
			check("boardwalk_draws_in_chunk", deck != null)
			if deck != null:
				check("boardwalk_below_asphalt", deck.z_index == 1)
			var vicinity := Rect2(Vector2(cell)*world.chunk_m - Vector2.ONE*8.0,
				Vector2.ONE*(world.chunk_m+16.0))
			var region := PackedVector2Array([vicinity.position,
				Vector2(vicinity.end.x,vicinity.position.y),
				vicinity.end,Vector2(vicinity.position.x,vicinity.end.y)])
			var cut := Geometry2D.intersect_polyline_with_polygon(boardwalk,region)
			check("boardwalk_geometry_survives_chunk_clipping",not cut.is_empty(),cut.size())

	var junction_count := 0
	var urban_roads := 0
	for r in world.data.roads:
		if r.kind in ["local","arterial"]:
			urban_roads += 1
	for j in world.data.junctions:
		var has_urban := false
		for arm in j.approaches:
			if world.data.roads[int(arm.road)].kind in ["local","arterial"]:
				has_urban=true
		if has_urban and j.curbs.size() > 0:
			junction_count += 1
	check("rounded_urban_intersection_corners_available",junction_count >= 5,junction_count)
	check("urban_road_network_present",urban_roads >= 5,urban_roads)

	# Sample adjacent walkway surfaces on both sides of unobstructed urban
	# stretches. This verifies usable hard ground, not grass-looking concrete.
	var left_walks := 0
	var right_walks := 0
	for r in world.data.roads:
		if r.kind not in ["local","arterial"]:
			continue
		var points: Array = r.points
		for i in range(4,points.size()-4,7):
			var a := raw_vec(points[i])
			var b := raw_vec(points[i+1])
			var direction := (b-a).normalized()
			if direction.length_squared()<0.9:
				continue
			for side in [-1.0,1.0]:
				var on_walk := (a+b)*0.5+direction.orthogonal()*side*(float(r.width)*0.5+1.8)
				var surface: Dictionary = world.surface_at(on_walk*20.0)
				if surface.name=="ASPHALT" and absf(float(surface.grip)-0.93)<0.02:
					if side<0: left_walks+=1
					else: right_walks+=1
			if left_walks > 4 and right_walks > 4:
				break
		if left_walks > 4 and right_walks > 4:
			break
	check("both_sidewalk_edges_are_firm_surfaces", left_walks > 4 and right_walks > 4,
		[left_walks,right_walks])
	print("URBAN STREETS AND BOARDWALK: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
