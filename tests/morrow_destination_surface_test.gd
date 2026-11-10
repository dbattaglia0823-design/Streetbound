extends SceneTree
## Landmark identity and surface-specific feedback stay bounded and require
## no new physics bodies, emitters or additional streamed world layers.
const Scenery = preload("res://scripts/world/coast_scenery.gd")
const Marks = preload("res://scripts/world/tire_marks.gd")
const Dust = preload("res://scripts/visual/driving_dust.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, good: bool, details: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL",label,details])
	if not good:
		failures.append(label)

func run() -> void:
	check("motor_house_has_distinct_identity",
		Scenery.destination_motif("Laurel Motor House") == "motorhouse")
	check("business_district_looks_different",
		Scenery.destination_motif("Eastgate Auto Gallery") == "showroom" and
		Scenery.destination_motif("Larkspur Performance") == "tuning")
	check("scenic_and_racing_landmarks_differ",
		Scenery.destination_motif("Juniper Lookout") == "scenic" and
		Scenery.destination_motif("Bellwether Marina") == "marina" and
		Scenery.destination_motif("Ashford Raceworks") == "racing")
	check("grass_dust_less_than_gravel",
		Dust.loose_strength("GRASS") < Dust.loose_strength("GRAVEL"))
	check("paved_dust_only_on_loss_of_grip",
		Dust.loose_strength("ASPHALT") == 0.0)
	check("sand_dust_tint_distinct",
		Dust.dust_color("SAND") != Dust.dust_color("GRASS") and
		Dust.dust_color("GRAVEL") != Dust.dust_color("ASPHALT"))
	var marks: TireMarks2D = Marks.new()
	root.add_child(marks)
	marks.add_mark(Vector2(100,100),0.0,false,0,"GRASS")
	var grass_color := marks.last_strip_color
	marks.add_mark(Vector2(100,85),0.0,false,0,"GRAVEL")
	check("different_loose_surface_breaks_tire_history",
		marks.last_strip_start.distance_to(marks.last_strip_end) < 13.0)
	check("gravel_and_grass_marks_differ",
		marks.last_strip_color != grass_color)
	check("tracks_remain_bounded",marks.point_count() <= marks.CAPACITY and \
		marks.trail_count() <= marks.MAX_TRAILS)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.vehicle.set_physics_process(false)
	var world: MorrowCoast = main.ground
	var named := {}
	for prop in world.data.props:
		if prop.has("poi"):
			named[str(prop.poi)] = true
	check("named_destination_set_preserved",
		named.has("Laurel Motor House") and named.has("Bellwether Marina") and
		named.has("Pinecrest Lodge"))
	var area_decor := 0
	for prop in world.data.props:
		if str(prop.kind) != "garden":
			continue
		if Vector2(float(prop.p[0]),float(prop.p[1])).distance_to(
			Vector2(float(world.data.pois[0].position[0]),
			float(world.data.pois[0].position[1]))) < 70:
			area_decor += 1
	check("laurel_entry_has_planting",area_decor >= 1,area_decor)
	var dust: Node2D = main.get_node("DrivingDust")
	main.vehicle.linear_velocity = Vector2.UP * 25.0
	main.vehicle.surface = "GRASS"
	for i in 4: dust._process(0.05)
	check("grass_blade_puffs_spawn",
		dust.puffs.any(func(p: Dictionary): return str(p.surface) == "GRASS"))
	check("surface_effect_pool_stays_bounded",dust.puffs.size() <= dust.MAX_PUFFS)
	print("DESTINATION / SURFACE POLISH: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
