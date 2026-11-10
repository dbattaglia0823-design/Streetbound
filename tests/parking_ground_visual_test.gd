extends SceneTree
## Regression: parking lots, static vehicle art and greenery are sourced from
## existing models and world-space materials, not detached hand-painted tiles.
const Scenery = preload("res://scripts/world/coast_scenery.gd")
const TrafficCar = preload("res://scripts/world/traffic_car.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, condition: bool, info: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if condition else "FAIL",label,info])
	if not condition:
		failures.append(label)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var world: MorrowCoast = main.ground
	main.vehicle.set_physics_process(false)
	await physics_frame
	var lots := 0
	var aprons := 0
	var parked := 0
	var planted := 0
	var models := {}
	var valid_models := true
	var collision_preserved := true
	for prop in world.data.props:
		match str(prop.kind):
			"lot":
				lots += 1
			"forecourt":
				aprons += 1
			"garden", "planter", "island":
				planted += 1
			"parked_car":
				parked += 1
				# Existing world collision footprints remain unchanged.
				collision_preserved = collision_preserved and bool(prop.solid)
				var seed_value := int(prop.seed)
				var slot := posmod(seed_value,TrafficCar.model_count())
				models[slot] = true
				var art: Dictionary = Scenery.parked_art_for(seed_value)
				if art.is_empty():
					valid_models = false
					continue
				var texture: Texture2D = art.texture
				var region: Rect2i = art.region
				valid_models = valid_models and texture != null and \
					region.size.x > 4 and region.size.y > 4 and \
					region.position.x >= 0 and region.position.y >= 0 and \
					region.end.x <= texture.get_width() and \
					region.end.y <= texture.get_height()
				var live_art := TrafficCar.appearance_for(seed_value)
				valid_models = valid_models and art.texture == live_art.texture and \
					art.region == live_art.region
	check("production_parking_lots_exist",lots >= 1,lots)
	check("production_forecourts_exist",aprons >= 1,aprons)
	check("parked_cars_exist",parked >= 1,parked)
	check("parked_cars_use_live_traffic_textures",valid_models)
	check("parked_car_collision_unchanged",collision_preserved)
	check("parked_cars_have_model_variation",models.size() >= 2,models.keys())
	check("shrubbery_and_gardens_exist",planted >= 1,planted)
	var cutout: String = preload("res://scripts/world/scenery_cutout.tres").shader.code
	var ground: String = preload("res://scripts/world/mountain_ground.tres").shader.code
	check("parking_asphalt_has_world_space_grain",
		cutout.contains("MODEL_MATRIX") and cutout.contains("world_px") and
		cutout.contains("parking_asphalt_detail") and cutout.contains("aggregate"))
	check("atlas_alpha_cutout_is_preserved",
		cutout.contains("smoothstep(0.12,0.90,COLOR.a)"))
	check("grass_has_world_space_soil_patches",
		ground.contains("world_m * 0.072") and ground.contains("soil_exposure") and
		ground.contains("earthy"))
	# Procedural art stays in the existing cached scenery Node2D.
	var chunk: Node = world.chunks.values()[0]
	var has_scenery := false
	for child in chunk.get_children():
		if child.get_script() == Scenery:
			has_scenery = true
	check("parking_uses_cached_chunk_scenery",has_scenery)
	print("PARKING / GROUND / SHRUBBERY TESTS: ",
		"PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
