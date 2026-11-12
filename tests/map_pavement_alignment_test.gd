extends SceneTree
## Visual/physical alignment audit using the same metres-to-pixels transform
## as rendered world chunks. Does not modify any baked road or collision data.
const Pavement = preload("res://scripts/world/dealership_pavement.gd")
const Scenery = preload("res://scripts/world/coast_scenery.gd")
const Roads = preload("res://scripts/world/coast_roads.gd")
const PPM := 20.0
var failed: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, valid: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL", label, detail])
	if not valid:
		failed.append(label)


func global_point(site: Dictionary, local_m: Vector2) -> Vector2:
	var center := Vector2(float(site.center_m[0]), float(site.center_m[1]))
	return (center + local_m.rotated(float(site.rotation))) * PPM


func run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	scene.vehicle.set_physics_process(false)
	var world: MorrowCoast = scene.ground
	var dealer: Node2D = scene.dealership_world
	check("all_ten_dealerships_present", dealer.sites.size() == 10,
		dealer.sites.size())
	for site in dealer.sites:
		var id: String = str(site.id)
		var d: float = float(site.setback_m)
		var lot: Rect2 = Pavement.lot_rect(site)
		var entrance: PackedVector2Array = Pavement.entrance_polygon(site)
		check("valid_painted_lot_" + id,
			lot.has_area() and lot.size.x == 32.0 and
			is_equal_approx(lot.position.y, -d + 5.0))
		check("entrance_joins_lot_" + id,
			entrance.size() == 4 and entrance[2].y > lot.position.y and
			entrance[0].y < lot.position.y and
			absf(entrance[2].x) < lot.size.x * 0.5)
		for point in [Vector2(0.0, -17.0),
				Vector2(-12.0, -d + 9.0),
				Vector2(0.0, -d + 1.0),
				Vector2(5.5, -d - 1.0)]:
			var pixel_position := global_point(site, point)
			check("visible_asphalt_is_drivable_" + id + "_" + str(point),
				Pavement.contains_pavement(site, pixel_position) and
				dealer.is_paved_forecourt(pixel_position) and
				str(world.surface_at(pixel_position).name) == "ASPHALT")
		for point in [Vector2(19.0, -17.0),
				Vector2(9.0, -d + 1.0),
				Vector2(0.0, -7.0)]:
			check("no_invisible_dealer_asphalt_" + id + "_" + str(point),
				not Pavement.contains_pavement(site, global_point(site, point)) and
				not dealer.is_paved_forecourt(global_point(site, point)))
		var road_position := Vector2(float(site.road_m[0]),
			float(site.road_m[1])) * PPM
		var accessible := true
		for i in 21:
			var end: Vector2 = global_point(site, Vector2(0.0, -17.0))
			var check_position: Vector2 = road_position.lerp(end, float(i) / 20.0)
			accessible = accessible and str(world.surface_at(check_position).name) == "ASPHALT"
		check("road_to_browse_surface_continuous_" + id, accessible)
	# Every streamed parking lot must appear BELOW roadbed/linework while
	# solid buildings, vehicles and foliage remain ABOVE the road.
	var lower_lots := 0
	var above_scenery := 0
	var incorrect := 0
	for chunk in world.chunks.values():
		for child in chunk.get_children():
			if child.get_script() != Scenery:
				continue
			var has_lot := false
			var has_other := false
			for prop in child.prop_list:
				if str(prop.kind) in ["lot", "forecourt"]:
					has_lot = true
				else:
					has_other = true
			if has_lot:
				lower_lots += 1
			if has_other:
				above_scenery += 1
			if (has_lot and (has_other or child.z_index != 1)) or \
					(has_other and child.z_index != 6):
				incorrect += 1
			for node in chunk.get_children():
				if node.get_script() == Roads and int(node.render_stage) >= 1:
					if has_lot and child.z_index >= node.z_index:
						incorrect += 1
	check("parking_lots_below_roads_with_scenery_above",
		incorrect == 0 and lower_lots > 0 and above_scenery > 0,
		[lower_lots, above_scenery, incorrect])
	print("MAP PAVEMENT ALIGNMENT: ", "PASS" if failed.is_empty() else "FAIL")
	quit(0 if failed.is_empty() else 1)
