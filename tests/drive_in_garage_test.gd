extends SceneTree
## Validate a physical, marked garage entrance, a stop-to-switch interaction
## and the existing selectable vehicle collection without spawning cars in it.
const Geometry = preload("res://scripts/world/garage_geometry.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, passes: bool, info: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passes else "FAIL", label, info])
	if not passes:
		failures.append(label)


func local_to_world(prop: Dictionary, local_m: Vector2) -> Vector2:
	return (Geometry.position_of(prop) + local_m.rotated(float(prop.angle))) * PPM


func run() -> void:
	var save_path := "user://streetbound_selected_vehicle.cfg"
	var previous_save := FileAccess.get_file_as_string(save_path) if FileAccess.file_exists(save_path) else ""
	var had_save := FileAccess.file_exists(save_path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var world: MorrowCoast = main.ground
	var garage: Node2D = main.player_garage
	var selector: CanvasLayer = main.get_node("VehicleSelector")
	check("existing_laurel_garage_is_found",
		garage != null and bool(garage.available) and not world.player_garage_prop.is_empty())
	if garage == null or world.player_garage_prop.is_empty():
		quit(1)
		return
	var prop: Dictionary = world.player_garage_prop
	var size: Vector2 = Geometry.size_of(prop)
	var bay: Rect2 = Geometry.bay_rect(size)
	var parking: Rect2 = Geometry.parking_rect(size)
	check("doorway_is_wide_enough_for_cars",
		bay.size.y >= 12.0 and parking.size.y >= 9.0, bay)
	check("roof_keeps_three_wall_sections", Geometry.wall_rects(size).size() == 3)
	check("map_marks_laurel_as_start_garage",
		str(world.data.pois[0].name) == Geometry.POI_NAME and \
		str(world.data.pois[0].category).contains("GARAGE"))
	check("garage_has_paved_interior",
		str(world.surface_at(local_to_world(prop, parking.get_center())).name) == "ASPHALT")
	check("garage_is_not_open_from_start",
		not garage.can_switch() and selector.garage == garage)
	selector.open_menu()
	check("remote_vehicle_selection_is_blocked", not selector.overlay.visible)
	var before_location := car.global_position
	var approach := Vector2(-size.x * 0.5 - 4.0, 0.0)
	car.global_position = local_to_world(prop, approach)
	car.rotation = float(prop.angle) + PI * 0.5
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	car.reset_physics_interpolation()
	await physics_frame
	var motion := Vector2.RIGHT.rotated(float(prop.angle)) * PPM * 14.0
	var collision: KinematicCollision2D = car.move_and_collide(motion)
	check("drive_through_open_garage_door",
		collision == null, collision.get_collider() if collision != null else "")
	var local_after: Vector2 = Geometry.local_point(prop, car.global_position / PPM)
	check("car_enters_actual_bay", Geometry.inside_bay(prop, car.global_position),
		local_after)
	check("interior_parking_is_not_a_teleport",
		car.global_position.distance_to(before_location) > PPM * 8.0)
	# Parking eligibility depends on the driver's speed and a safe inset.
	car.global_position = local_to_world(prop, parking.get_center())
	car.linear_velocity = Vector2.RIGHT * 5.0
	check("moving_through_garage_does_not_open_selector",
		garage.inside_bay() and not garage.can_switch())
	selector.open_menu()
	check("moving_car_cannot_switch_models", not selector.overlay.visible)
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	check("stopped_interior_car_can_switch", garage.can_switch(),
		garage.prompt())
	selector._update_garage_access()
	check("visible_garage_button_is_enabled",
		selector.launch_button.visible and not selector.launch_button.disabled)
	selector.open_menu()
	check("parked_car_opens_scrollable_catalog",
		selector.overlay.visible and paused and selector.cards.size() == 88)
	var parked_location := car.global_position
	# Ownership is enforced outside the developer proving ground. Buy an
	# inexpensive second car using an isolated in-memory test economy first.
	var inventory := VehicleOwnership.new(false)
	main.vehicle_ownership = inventory
	selector.inventory = inventory
	var entry: Dictionary = Catalog.find_by_id("dodge-neon")
	check("second_garage_car_can_be_purchased", inventory.purchase(str(entry.id)) == "purchased")
	selector._choose(entry)
	check("garage_switch_unpauses_and_equips",
		not selector.overlay.visible and not paused and \
		is_equal_approx(car.config.mass_kg, float(entry.mass_kg)))
	check("vehicle_switch_keeps_car_inside_garage",
		car.global_position.distance_to(parked_location) < 0.1)
	check("garage_still_operates_after_switching",
		garage.can_switch())
	# From outside, G and the selector method should never open the garage.
	car.global_position = local_to_world(prop, Vector2(-size.x * 0.5 - 30.0, 0.0))
	car.linear_velocity = Vector2.ZERO
	selector._update_garage_access()
	check("garage_unavailable_after_driving_away", not garage.can_switch())
	selector.open_menu()
	check("cannot_open_garage_outside_parking_bay",
		not selector.overlay.visible)
	# The garage's solid roof wings cannot be driven through.
	car.global_position = local_to_world(prop,
		Vector2(-size.x * 0.5 - 5.0, -size.y * 0.40))
	car.reset_physics_interpolation()
	await physics_frame
	var side_hit: KinematicCollision2D = car.move_and_collide(motion)
	check("roof_sidewall_has_solid_collision", side_hit != null)
	# The solid rear wall also keeps the car from driving through the building.
	car.global_position = local_to_world(prop, Vector2(3.0, 0.0))
	car.reset_physics_interpolation()
	await physics_frame
	var rear_hit: KinematicCollision2D = car.move_and_collide(motion)
	check("garage_backwall_has_solid_collision", rear_hit != null)
	if had_save:
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		if file != null:
			file.store_string(previous_save)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("LAUREL DRIVE-IN GARAGE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
