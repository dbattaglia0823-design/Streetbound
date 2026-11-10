class_name VehicleOwnership
extends RefCounted
## Persistent vehicle collection and funds. No player can equip an unowned car
## in the open world; purchases use one canonical catalog price and ID.
signal changed
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const SAVE_PATH := "user://streetbound_vehicle_ownership.cfg"
const OLD_SELECTION_PATH := "user://streetbound_selected_vehicle.cfg"
const STARTER_ID := "ford-fiesta"
const STARTING_CASH := 32000

var balance := STARTING_CASH
var owned: Dictionary = {STARTER_ID: true}
var active_id := STARTER_ID
var persist_enabled := true


func _init(enable_persistence: bool = true) -> void:
	persist_enabled = enable_persistence
	if not persist_enabled:
		return
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) == OK:
		balance = maxi(0, int(file.get_value("economy", "balance", STARTING_CASH)))
		owned.clear()
		for value in file.get_value("economy", "owned_ids", [STARTER_ID]):
			var id := str(value)
			if not Catalog.find_by_id(id).is_empty():
				owned[id] = true
		if owned.is_empty():
			owned[STARTER_ID] = true
		active_id = str(file.get_value("economy", "active_id", STARTER_ID))
		if not owns(active_id):
			active_id = str(owned.keys()[0])
		return
	# Migration: previously all cars could be selected anywhere. Retain the
	# last driven car for existing players without granting every model.
	var old := ConfigFile.new()
	if old.load(OLD_SELECTION_PATH) == OK:
		var prior_id := str(old.get_value("vehicle", "selected_id", ""))
		if not Catalog.find_by_id(prior_id).is_empty():
			owned[prior_id] = true
			active_id = prior_id


func owns(id: String) -> bool:
	return bool(owned.get(id, false))


func owned_count() -> int:
	return owned.size()


func owned_cars() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in Catalog.all():
		if owns(str(entry.id)):
			result.append(entry)
	return result


func can_afford(entry: Dictionary) -> bool:
	return balance >= int(entry.get("price_usd", 0)) and int(entry.get("price_usd", 0)) > 0


func purchase(id: String) -> String:
	var entry: Dictionary = Catalog.find_by_id(id)
	if entry.is_empty():
		return "unknown"
	if owns(id):
		return "owned"
	var price := int(entry.get("price_usd", 0))
	if price <= 0:
		return "unavailable"
	if price > balance:
		return "insufficient"
	# Save atomically at the data-model level: rollback if storage fails.
	balance -= price
	owned[id] = true
	if not save():
		balance += price
		owned.erase(id)
		return "save_failed"
	changed.emit()
	return "purchased"


func equip(id: String) -> bool:
	if not owns(id) or Catalog.find_by_id(id).is_empty():
		return false
	var previous := active_id
	active_id = id
	if not save():
		active_id = previous
		return false
	changed.emit()
	return true


func credit(amount: int) -> bool:
	if amount <= 0:
		return false
	balance += amount
	if not save():
		balance -= amount
		return false
	changed.emit()
	return true


func save() -> bool:
	if not persist_enabled:
		return true
	var file := ConfigFile.new()
	file.set_value("economy", "balance", balance)
	file.set_value("economy", "owned_ids", owned.keys())
	file.set_value("economy", "active_id", active_id)
	return file.save(SAVE_PATH) == OK


static func dollars(value: int) -> String:
	var digits := str(absi(value))
	var formatted := ""
	while digits.length() > 3:
		formatted = "," + digits.substr(digits.length() - 3) + formatted
		digits = digits.substr(0, digits.length() - 3)
	return ("-$" if value < 0 else "$") + digits + formatted
