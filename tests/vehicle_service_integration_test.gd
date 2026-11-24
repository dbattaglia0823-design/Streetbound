extends SceneTree
## Test real service interactions without modifying a player's normal save.
const PlayerScene = preload("res://scenes/vehicle.tscn")
const Service = preload("res://scripts/world/vehicle_damage_service.gd")
const Markers = preload("res://scripts/world/authored_map_markers.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Rules = preload("res://scripts/vehicle/vehicle_service_rules.gd")
const TEST_SAVE := "user://streetbound_service_test_resources.cfg"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)

func run() -> void:
	check("station_cap", Rules.station_repair_target(10.0) == 50.0
		and Rules.station_repair_target(70.0) == 70.0)
	check("station_fee_small", Rules.station_repair_fee(10.0) == 185
		and Rules.station_repair_fee(50.0) == 0)
	check("garage_priority", Rules.service_type(true, true) == "garage")

	var player: VehicleController2D = PlayerScene.instantiate()
	player.external_input = true
	root.add_child(player)
	await physics_frame
	var inventory = Ownership.new(false)
	var marker_node = Markers.new()
	var station: Dictionary = {"type":"fuel","name":"Service Test","x":0.0,"y":0.0,
		"properties":{"radius_m":12.0}}
	marker_node.markers.append(station)
	var service = Service.new()
	service.player = player
	service.economy = inventory
	service.authored_markers = marker_node
	service.resource_save_path = TEST_SAVE
	root.add_child(service)
	await process_frame
	service.set_physics_process(false)
	check("station_detected", service._location_type() == "station")

	service.damage.integrity = 10.0
	var original_balance: int = inventory.balance
	var charged: int = Rules.station_repair_fee(10.0)
	check("paid_station_repair", service.try_repair()
		and is_equal_approx(service.damage.integrity, 50.0)
		and inventory.balance == original_balance - charged)
	original_balance = inventory.balance
	check("station_cannot_exceed_50", not service.try_repair()
		and service.damage.integrity == 50.0
		and inventory.balance == original_balance)

	marker_node.markers.clear()
	marker_node.markers.append({"type":"garage","name":"Test Garage","x":0.0,"y":0.0,
		"properties":{"radius_m":12.0}})
	inventory.balance = 0
	check("garage_repairs_free_even_with_zero_cash", service.try_repair()
		and service.damage.integrity == 100.0 and inventory.balance == 0)
	service.fuel.remaining = 3.0
	check("garage_cannot_sell_fuel", not service.try_refuel()
		and service.fuel.remaining == 3.0)

	marker_node.markers.clear()
	marker_node.markers.append(station)
	inventory.balance = 500
	var fuel_price: int = service.fuel.refill_cost(Service.GAS_PRICE_PER_LITRE)
	check("gas_station_refuels_for_cash", service.try_refuel()
		and service.fuel.fraction() == 1.0 and inventory.balance == 500 - fuel_price)
	check("already_full_not_charged", not service.try_refuel()
		and inventory.balance == 500 - fuel_price)

	service.damage.integrity = 42.0
	service.fuel.remaining = 2.0
	player.reset_vehicle()
	check("reset_preserves_resources", service.damage.integrity == 42.0
		and service.fuel.remaining == 2.0)
	player.position = Vector2(500.0, 0.0)
	check("far_away_cannot_use_station", service._location_type().is_empty())
	player.position = Vector2.ZERO
	player.linear_velocity = Vector2(3.0, 0.0)
	check("moving_car_cannot_repair", service._location_type().is_empty())
	player.linear_velocity = Vector2.ZERO

	# No access to a service location and a dead vehicle: a limited tow
	# avoids soft-locking, but does not grant free full health or a full tank.
	marker_node.markers.clear()
	inventory.balance = 0
	service.damage.integrity = 0.0
	service.fuel.remaining = 0.0
	check("stranded_no_cash_tow_available", service.try_repair()
		and service.damage.integrity == 35.0
		and service.fuel.fraction() >= 0.08
		and inventory.balance == 0)
	check("fuel_stored_for_equipped_car", service.fuel_by_car.has(inventory.active_id))

	root.remove_child(service)
	service.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	player.queue_free()
	marker_node.free()
	print("GARAGE/FUEL SERVICE: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
