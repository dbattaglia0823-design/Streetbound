extends SceneTree
## Real storefront placement, independent dealer stock, persistence, purchases,
## map POIs and ownership-gated garage access.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(name: String, pass: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if pass else "FAIL",name,detail])
	if not pass:
		failures.append(name)


func site_position(site: Dictionary, key: String = "parking_m") -> Vector2:
	var raw: Array = site[key]
	return Vector2(float(raw[0]),float(raw[1]))


func run() -> void:
	var definitions: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/dealerships.json"))
	check("shop_locations_valid_json", definitions is Dictionary)
	var all_cars: Array[Dictionary] = Catalog.all()
	var counted: Dictionary = {}
	var valid_prices := true
	var exact_stock := true
	var all_building_images := true
	for definition in definitions.get("shops",[]):
		var shop: Dictionary = definition
		counted[str(shop.id)] = 0
		all_building_images = all_building_images and ResourceLoader.exists(str(shop.texture))
	for item in all_cars:
		var shop_id := str(item.get("dealership_id",""))
		exact_stock = exact_stock and counted.has(shop_id)
		if counted.has(shop_id):
			counted[shop_id] = int(counted[shop_id]) + 1
		valid_prices = valid_prices and int(item.get("price_usd",0)) >= 4500
	check("all_10_buildings_have_images", all_building_images)
	check("all_cars_have_valid_prices", all_cars.size() == 88 and valid_prices)
	check("all_88_have_exactly_one_dealership",exact_stock)
	check("each_dealer_has_stock", counted.size() == 10 and \
		counted.values().all(func(n: Variant): return int(n)>0),counted)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var manager: Node2D = main.dealership_world
	var menu: CanvasLayer = main.dealership_menu
	var garage: CanvasLayer = main.get_node("VehicleSelector")
	var world: MorrowCoast = main.ground
	check("dealership_world_and_shop_menu_active",
		manager != null and menu != null and main.vehicle_ownership != null)
	if manager == null or menu == null:
		quit(1)
		return
	check("all_dealer_sites_resolve_to_real_roadside_land",
		manager.sites.size() == 10,manager.sites.size())
	var centres: Array[Vector2] = []
	var well_spaced := true
	var sites_in_expected_regions := true
	var accessible := true
	var mapped := true
	for site in manager.sites:
		var shop: Dictionary = site
		var position := site_position(shop,"center_m")
		var parking := site_position(shop)
		for other in centres:
			if other.distance_to(position) < 92.0:
				well_spaced = false
		centres.append(position)
		if str(shop.id) in ["premium","luxury","exotic"]:
			sites_in_expected_regions = sites_in_expected_regions and \
				position.x>2800 and position.x<3900 and \
				position.y>2250 and position.y<3450
		if str(shop.id) in ["trail","summit"]:
			sites_in_expected_regions = sites_in_expected_regions and \
				position.x<2000 and position.y<1800
		if str(shop.id) in ["junk","budget","used"]:
			sites_in_expected_regions = sites_in_expected_regions and \
				(position.x<2300 or position.y>3450)
		accessible = accessible and site_position(shop,"road_m").distance_to(parking)<55.0
		mapped = mapped and world.data.pois.any(func(p: Dictionary) -> bool:
			return str(p.get("name","")) == str(shop.name) and \
				str(p.get("category","")).contains("DEALERSHIP"))
		check("building_asset_loaded_" + str(shop.id),
			manager.shop_nodes.any(func(n: Node2D) -> bool:
				return str(n.site.id) == str(shop.id) and \
					n.get_node_or_null("DealershipArtwork") != null))
	check("shops_are_not_overlapping",well_spaced)
	check("dealerships_respect_city_mountain_outskirt_zoning",sites_in_expected_regions)
	check("shops_have_drivable_roadside_aprons",accessible)
	check("all_shops_visible_on_atlas",mapped)
	menu.open_menu()
	check("cannot_shop_remotely",not menu.overlay.visible)
	var starter := Ownership.new(false)
	check("new_player_starts_with_one_vehicle_and_funds",
		starter.owned_count() == 1 and starter.owns(Ownership.STARTER_ID) and \
		starter.balance == Ownership.STARTING_CASH)
	check("invalid_vehicle_id_cannot_be_bought",starter.purchase("unknown-car") == "unknown")
	check("negative_money_grant_is_rejected",not starter.credit(-100))
	var budget: Dictionary = manager.get_site("budget")
	check("budget_dealer_exists",not budget.is_empty())
	if budget.is_empty():
		quit(1)
		return
	menu.economy = starter
	main.vehicle_ownership = starter
	garage.inventory = starter
	car.global_position = site_position(budget)*PPM
	car.linear_velocity = Vector2(7.0,0.0)
	check("moving_car_cannot_browse",not manager.can_browse(budget))
	menu.open_menu()
	check("must_stop_to_enter_dealer",not menu.overlay.visible)
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	check("stopped_customer_can_browse",manager.can_browse(budget))
	check("dealership_parking_is_asphalt",
		str(world.surface_at(car.global_position).name) == "ASPHALT")
	menu.open_menu()
	check("budget_shop_opens_paused_with_its_stock",
		menu.overlay.visible and paused and menu.cards.size() == counted.budget,
		menu.cards.size())
	var buy_entry := Catalog.find_by_id("acura-tl")
	check("budget_car_has_reachable_price",
		int(buy_entry.price_usd) <= starter.balance)
	var before := starter.balance
	menu._purchase(str(buy_entry.id))
	check("buy_deducts_correct_amount",
		starter.balance == before - int(buy_entry.price_usd),starter.balance)
	check("purchase_unlocks_owned_vehicle",starter.owns(str(buy_entry.id)))
	check("repeated_purchase_cannot_charge_again",
		starter.purchase(str(buy_entry.id)) == "owned" and \
		starter.balance == before-int(buy_entry.price_usd))
	check("cannot_buy_outside_this_dealer",
		not starter.owns("bugatti-chiron") and \
		str(Catalog.find_by_id("bugatti-chiron").dealership_id) != str(budget.id))
	var own_action_disabled := false
	for item in menu.cards:
		if str((item.entry as Dictionary).id) == str(buy_entry.id):
			own_action_disabled = (item.action as Button).disabled and \
				(item.action as Button).text.contains("OWNED")
	check("shop_shows_owned_status_after_purchase",own_action_disabled)
	menu.close_menu()
	check("leaving_shop_restores_driving",not paused and not menu.overlay.visible)
	check("garage_rejects_unowned_vehicle_switch",
		not starter.owns("bugatti-chiron"))
	# Buying never changes the active car automatically: the owned car is
	# equipped only when the driver returns to Laurel Motor House.
	check("purchase_does_not_auto_equip",starter.active_id == Ownership.STARTER_ID)
	var garage_prop: Dictionary = world.player_garage_prop
	var parking: Rect2 = preload("res://scripts/world/garage_geometry.gd").parking_rect(
		Vector2(float(garage_prop.size[0]),float(garage_prop.size[1])))
	var local := parking.get_center().rotated(float(garage_prop.angle))
	car.global_position = (Vector2(float(garage_prop.p[0]),float(garage_prop.p[1]))+local)*PPM
	car.linear_velocity = Vector2.ZERO
	garage.open_menu()
	check("garage_only_shows_owned_entries",
		garage.overlay.visible and \
		garage.cards.filter(func(a: Dictionary) -> bool: return \
			(a.button as Button).visible).size() == 2)
	var old_location := car.global_position
	garage._choose(buy_entry)
	check("owned_vehicle_can_be_equipped_at_garage",
		starter.active_id == str(buy_entry.id) and not paused and \
		car.global_position.distance_to(old_location)<0.1)
	# Verify genuine save/reload, restoring any preexisting user save afterwards.
	var file_path := Ownership.SAVE_PATH
	var had_save := FileAccess.file_exists(file_path)
	var old_data := FileAccess.get_file_as_string(file_path) if had_save else ""
	var recorded := Ownership.new(false)
	recorded.balance = 56000
	recorded.owned[str(buy_entry.id)] = true
	recorded.active_id = str(buy_entry.id)
	recorded.persist_enabled = true
	check("ownership_can_be_written_to_disk",recorded.save())
	var restored := Ownership.new()
	check("ownership_funds_and_car_survive_reload",
		restored.balance == recorded.balance and restored.owns(str(buy_entry.id)) and \
		restored.active_id == str(buy_entry.id))
	if had_save:
		var f := FileAccess.open(file_path,FileAccess.WRITE)
		if f != null:
			f.store_string(old_data)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	print("DEALERSHIP / OWNERSHIP INTEGRATION: ",
		"PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
