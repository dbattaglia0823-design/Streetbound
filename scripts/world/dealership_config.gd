extends RefCounted
## The authored map stores only dealership overrides. Vehicle details always
## come from the live catalog; the ten legacy shops remain the defaults.
const PATH := "res://data/dealerships.json"
const CATALOG = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const MAX_SHOPS := 64

static func defaults() -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var result: Array[Dictionary] = []
	if parsed is Dictionary:
		for raw in parsed.get("shops", []):
			if raw is Dictionary:
				result.append(raw.duplicate(true))
	return result

static func combined(doc: Dictionary = {}) -> Array[Dictionary]:
	var shops := defaults()
	var by_id: Dictionary = {}
	for i in shops.size():
		by_id[str(shops[i].id)] = i
	for raw in doc.get("dealerships", []):
		if not raw is Dictionary:
			continue
		var id := str(raw.get("id", ""))
		if by_id.has(id):
			shops[int(by_id[id])].merge(raw, true)
		elif not id.is_empty() and shops.size() < MAX_SHOPS:
			by_id[id] = shops.size()
			shops.append(raw.duplicate(true))
	return shops

static func document() -> Dictionary:
	# Editor source is saved transactionally by the map builder. A game
	# exported without the authoring source still has the curated shops.
	var path := "res://map-editor/maps/morrow-coast.edits.world.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func available_inventory(shop: Dictionary) -> Array[Dictionary]:
	var stock: Array[Dictionary] = []
	var manual := str(shop.get("inventory_mode", "automatic")) == "manual"
	var ids: Dictionary = {}
	if manual:
		for id in shop.get("inventory", []):
			ids[str(id)] = true
	for vehicle in CATALOG.all():
		if (ids.has(str(vehicle.get("id", ""))) if manual else 				str(vehicle.get("dealership_id", "")) == str(shop.get("id", ""))):
			stock.append(vehicle)
	return stock

static func sells(shop: Dictionary, vehicle_id: String) -> bool:
	var car: Dictionary = CATALOG.find_by_id(vehicle_id)
	if car.is_empty():
		return false
	if str(shop.get("inventory_mode", "automatic")) == "manual":
		return vehicle_id in shop.get("inventory", [])
	return str(car.get("dealership_id", "")) == str(shop.get("id", ""))
