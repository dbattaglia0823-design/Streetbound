extends CanvasLayer
## Single-player vehicle condition and fuel. Repairs are location-based:
## garages restore 100% free; gas stations repair to 50% for a small fee.
## Real fuel is independent from nitrous. No R-key refuel/repair exploits.
const DamageState = preload("res://scripts/vehicle/vehicle_damage.gd")
const FuelState = preload("res://scripts/vehicle/vehicle_fuel.gd")
const ServiceRules = preload("res://scripts/vehicle/vehicle_service_rules.gd")
const FuelGauges = preload("res://scripts/ui/vehicle_resource_gauges.gd")
const HudStyle = preload("res://scripts/ui/driving_hud.gd")
const DamageSmoke = preload("res://scripts/visual/engine_damage_smoke.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const RESOURCE_PATH := "user://streetbound_vehicle_resources.cfg"
const GAS_PRICE_PER_LITRE := 1.25
const CHARGE_PRICE_PER_UNIT := 0.3

var resource_save_path := RESOURCE_PATH
# Test Drive reads the same condition snapshot but keeps later changes in memory.
var persist_enabled := true
var player: VehicleController2D
var economy: Object
var garage: Node2D
var authored_markers: Node2D
var police: Node2D
var current_car_id := ""
var integrity_by_car: Dictionary = {}
var fuel_by_car: Dictionary = {}
var damage = DamageState.new()
var fuel = FuelState.new()
var gauges: Control
var dashboard: Control
var status_host: VBoxContainer
var notice_panel: PanelContainer
var engine_smoke: Node2D
var readout: Label
var notice := ""
var notice_remaining := 0.0
var _save_clock := 0.0
var _low_fuel_warning := false
var _last_config_hp := -1
var _last_engine_shield := 1.0

func _ready() -> void:
	layer = 4
	name = "VehicleDamageService"
	if not is_instance_valid(player) or not is_instance_valid(economy):
		return
	_load_resources()
	current_car_id = str(economy.active_id)
	_configure_active_car()
	player.damage_contact.connect(_on_impact)
	player.vehicle_reset.connect(_apply_drive_condition)
	# The VFX follows the player in world coordinates, not the CanvasLayer.
	# Keep it separate from exhaust flames and tire smoke.
	engine_smoke = Node2D.new()
	engine_smoke.set_script(DamageSmoke)
	engine_smoke.set("vehicle", player)
	player.add_child(engine_smoke)
	if is_instance_valid(dashboard):
		gauges = dashboard
	else:
		gauges = Control.new()
		gauges.set_script(FuelGauges)
		add_child(gauges)
	var parent: Node = status_host if is_instance_valid(status_host) else self
	notice_panel = HudStyle.status_card(parent,Color("#f2bd78"))
	if not is_instance_valid(status_host):
		notice_panel.position = Vector2(16,16)
	var col := VBoxContainer.new()
	notice_panel.add_child(col)
	HudStyle.status_text(col,"VEHICLE CONDITION",11,Color("#f2bd78"))
	readout = HudStyle.status_text(col,"",13,Color("#eaf2e8"))
	_apply_drive_condition()
	_update_gauges()

func _exit_tree() -> void:
	if is_instance_valid(engine_smoke):
		engine_smoke.queue_free()
	if not current_car_id.is_empty():
		_save_resources()

func _load_resources() -> void:
	var file := ConfigFile.new()
	if file.load(resource_save_path) != OK:
		return
	for slot in ["integrity", "fuel"]:
		var saved: Variant = file.get_value("resources", slot, {})
		if not saved is Dictionary:
			continue
		var target: Dictionary = integrity_by_car if slot == "integrity" else fuel_by_car
		for key in saved:
			var id := str(key)
			var value: Variant = saved[key]
			if id.length() > 100 or Catalog.find_by_id(id).is_empty():
				continue
			if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
				continue
			target[id] = clampf(float(value), 0.0, 100.0 if slot == "integrity" else 500.0)

func _save_resources() -> bool:
	if current_car_id.is_empty():
		return false
	integrity_by_car[current_car_id] = damage.integrity
	fuel_by_car[current_car_id] = fuel.remaining
	if not persist_enabled:return true
	var file := ConfigFile.new()
	file.set_value("resources", "integrity", integrity_by_car)
	file.set_value("resources", "fuel", fuel_by_car)
	return file.save(resource_save_path) == OK

func _configure_active_car() -> void:
	var entry: Dictionary = Catalog.find_by_id(current_car_id)
	var vehicle_kind := str(entry.get("kind", "sport"))
	var powertrain := str(entry.get("reference_powertrain", "")).to_lower()
	fuel.configure(vehicle_kind, float(player.config.mass_kg), float(player.config.engine_power_kw),
		powertrain == "electric")
	damage.max_health_points = maxi(1, player.config.max_health_points)
	_last_config_hp = damage.max_health_points
	_last_engine_shield = player.config.critical_power_loss_factor
	damage.integrity = clampf(float(integrity_by_car.get(current_car_id, 100.0)), 0.0, 100.0)
	damage.last_impact_at = -INF
	fuel.remaining = clampf(float(fuel_by_car.get(current_car_id, fuel.capacity)), 0.0, fuel.capacity)
	_low_fuel_warning = fuel.fraction() < 0.15
	_apply_drive_condition()

func _sync_car() -> void:
	if not is_instance_valid(economy):
		return
	var new_car_id := str(economy.active_id)
	if new_car_id == current_car_id:
		return
	_save_resources()
	current_car_id = new_car_id
	_configure_active_car()
	_update_gauges()

func _sync_upgrade_health() -> void:
	if not is_instance_valid(player) or player.config == null:
		return
	var capacity := maxi(1,player.config.max_health_points)
	if capacity != _last_config_hp or not is_equal_approx(_last_engine_shield,player.config.critical_power_loss_factor):
		# Normalized integrity is preserved, never repair or refill on swaps.
		_last_config_hp = capacity
		_last_engine_shield = player.config.critical_power_loss_factor
		damage.max_health_points = capacity
		_apply_drive_condition()
		_update_gauges()

func _on_impact(speed_mps: float, _position_px: Vector2,
		_normal: Vector2, _velocity_mps: Vector2) -> void:
	_sync_car()
	_sync_upgrade_health()
	var applied: float = damage.register_impact(speed_mps, Time.get_ticks_msec() / 1000.0,clampf(player.config.impact_damage_factor,0.5,1.0))
	if applied <= 0.0:
		return
	# Disk writes are batched during driving, not executed inside the
	# physics collision signal for every police/traffic impact.
	integrity_by_car[current_car_id] = damage.integrity
	_apply_drive_condition()
	_update_gauges()
	DamageState.show_damage_number(player, applied)
	_show_notice("IMPACT -%d" % maxi(1, roundi(applied)))

func _apply_drive_condition() -> void:
	if not is_instance_valid(player):
		return
	player.damage_drive_fraction = damage.drive_fraction(player.config.critical_power_loss_factor)
	player.fuel_drive_fraction = 0.0 if fuel.empty() else 1.0
	if is_instance_valid(engine_smoke):
		engine_smoke.call("set_health_percentage", damage.health_percentage())

func _update_gauges() -> void:
	if is_instance_valid(gauges):
		if gauges == dashboard:
			gauges.call("update_levels", damage.health_fraction(), fuel.fraction(), fuel.electric,ceili(damage.current_health_points()),damage.max_health_points)
		else:
			gauges.call("update_levels", damage.health_fraction(), fuel.fraction(), fuel.electric)

func _show_notice(value: String) -> void:
	notice = value
	notice_remaining = 3.0

func _location_type() -> String:
	if not is_instance_valid(player) or player.linear_velocity.length() > 1.0:
		return ""
	if is_instance_valid(police) and int(police.get("wanted_level")) > 0:
		return ""
	var at_garage: bool = is_instance_valid(garage) and garage.has_method("can_switch") and bool(garage.call("can_switch"))
	var at_station := false
	if is_instance_valid(authored_markers):
		var raw: Variant = authored_markers.get("markers")
		if raw is Array:
			for marker in raw:
				if not marker is Dictionary or str(marker.get("type", "")) not in ["garage", "fuel"]:
					continue
				if authored_markers.has_method("_enabled") and not bool(authored_markers.call("_enabled", marker)):
					continue
				if not marker.has("x") or not marker.has("y"):
					continue
				var position_m := Vector2(float(marker.x), float(marker.y))
				var radius_m := clampf(float(marker.get("properties", {}).get("radius_m", 12.0)), 4.0, 50.0)
				if player.global_position.distance_to(position_m * 20.0) > radius_m * 20.0:
					continue
				if str(marker.type) == "garage":
					at_garage = true
				elif str(marker.type) == "fuel":
					at_station = true
	return ServiceRules.service_type(at_garage, at_station)

func _can_tow() -> bool:
	return is_instance_valid(player) and (damage.is_disabled() or fuel.empty()) and (
		not is_instance_valid(police) or int(police.get("wanted_level")) == 0)

func repair_full() -> void:
	# Recovery/legacy API. Gameplay calls garage repair or police impound.
	damage.repair()
	_apply_drive_condition()
	_update_gauges()
	_save_resources()

func impound_recovery() -> void:
	# Busted does not grant the free full garage repair. Player must reach
	# a garage for that, but the seized vehicle must remain driveable.
	damage.integrity = maxf(35.0, damage.integrity)
	fuel.remaining = maxf(fuel.remaining, fuel.capacity * 0.08)
	damage.last_impact_at = -INF
	_apply_drive_condition()
	_update_gauges()
	_save_resources()

func _try_tow() -> bool:
	if not _can_tow() or not is_instance_valid(economy):
		return false
	# An affordable recovery cannot full-repair or full-refill the vehicle.
	var fee: int = mini(ServiceRules.TOW_MAX_FEE, int(economy.balance))
	var previous_integrity: float = damage.integrity
	var previous_fuel: float = fuel.remaining
	damage.integrity = maxf(35.0, damage.integrity)
	fuel.remaining = maxf(fuel.remaining, fuel.capacity * 0.08)
	if not _save_resources():
		damage.integrity = previous_integrity
		fuel.remaining = previous_fuel
		_show_notice("TOW SAVE FAILED")
		return false
	economy.balance -= fee
	if not economy.save():
		economy.balance += fee
		damage.integrity = previous_integrity
		fuel.remaining = previous_fuel
		_save_resources()
		_show_notice("TOW PAYMENT FAILED")
		return false
	economy.changed.emit()
	player.reset_vehicle()
	_apply_drive_condition()
	_update_gauges()
	_show_notice("EMERGENCY TOW / -%s" % economy.dollars(fee))
	return true

func try_repair() -> bool:
	if not is_instance_valid(economy):
		return false
	_sync_car()
	var service := _location_type()
	if service == "garage":
		if damage.integrity >= 100.0:
			# A full-health car that has run dry at its garage must still
			# have a recovery route if no fuel pump is available there.
			return _try_tow() if _can_tow() else false
		repair_full()
		_show_notice("GARAGE / FULL REPAIR FREE")
		return true
	if service == "station":
		if damage.integrity >= ServiceRules.STATION_REPAIR_LIMIT:
			if _can_tow():
				return _try_tow()
			_show_notice("STATION REPAIR LIMIT / 50%")
			return false
		var fee: int = ServiceRules.station_repair_fee(damage.integrity)
		if int(economy.balance) < fee:
			if _can_tow():
				return _try_tow()
			_show_notice("NOT ENOUGH CASH FOR REPAIR")
			return false
		var previous: float = damage.integrity
		damage.integrity = ServiceRules.station_repair_target(previous)
		if not _save_resources():
			damage.integrity = previous
			_show_notice("REPAIR SAVE FAILED")
			return false
		economy.balance -= fee
		if not economy.save():
			economy.balance += fee
			damage.integrity = previous
			_save_resources()
			_show_notice("PAYMENT SAVE FAILED")
			return false
		economy.changed.emit()
		_apply_drive_condition()
		_update_gauges()
		_show_notice("GAS STATION / 50%% / -%s" % economy.dollars(fee))
		return true
	return _try_tow()

func try_refuel() -> bool:
	if not is_instance_valid(economy):
		return false
	_sync_car()
	if _location_type() != "station":
		return false
	if fuel.fraction() >= 0.9999:
		_show_notice("TANK ALREADY FULL")
		return false
	var price := CHARGE_PRICE_PER_UNIT if fuel.electric else GAS_PRICE_PER_LITRE
	var full_fee: int = fuel.refill_cost(price)
	var fee: int = mini(full_fee, int(economy.balance))
	if fee <= 0:
		_show_notice("NOT ENOUGH CASH FOR FUEL")
		return false
	var previous: float = fuel.remaining
	if fee == full_fee:
		fuel.refill()
	else:
		# Buying part of a tank is preferable to being stranded at a pump
		# because the player cannot afford the complete refill.
		fuel.remaining = minf(fuel.capacity, fuel.remaining + float(fee) / price)
	if not _save_resources():
		fuel.remaining = previous
		_show_notice("FUEL SAVE FAILED")
		return false
	economy.balance -= fee
	if not economy.save():
		economy.balance += fee
		fuel.remaining = previous
		_save_resources()
		_show_notice("PAYMENT SAVE FAILED")
		return false
	economy.changed.emit()
	_low_fuel_warning = false
	_apply_drive_condition()
	_update_gauges()
	_show_notice("%s %s / -%s" % [
		"CHARGE" if fuel.electric else "FUEL",
		"FULL" if fee == full_fee else "PARTIAL",
		economy.dollars(fee)])
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or get_tree().paused:
		return
	if event.keycode == KEY_K and try_repair():
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_J and try_refuel():
		get_viewport().set_input_as_handled()

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(economy):
		return
	_sync_car()
	_sync_upgrade_health()
	if fuel.consume(dt, player.linear_velocity.length(), player.throttle) > 0.0:
		player.fuel_drive_fraction = 0.0 if fuel.empty() else 1.0
		if fuel.fraction() < 0.15 and not _low_fuel_warning:
			_low_fuel_warning = true
			_show_notice("LOW %s" % ("CHARGE" if fuel.electric else "FUEL"))
	_save_clock += dt
	if _save_clock >= 5.0:
		_save_clock = 0.0
		_save_resources()

func _process(dt: float) -> void:
	if not is_instance_valid(readout) or not is_instance_valid(player):
		return
	_sync_car()
	_update_gauges()
	notice_remaining = maxf(0.0, notice_remaining - dt)
	var service := _location_type()
	var messages: PackedStringArray = []
	if damage.is_disabled():
		messages.append("ENGINE DISABLED")
	elif fuel.empty():
		messages.append("OUT OF %s" % ("CHARGE" if fuel.electric else "FUEL"))
	if service == "garage" and damage.integrity < 100.0:
		messages.append("[K] FREE FULL REPAIR")
	elif service == "station" and damage.integrity < ServiceRules.STATION_REPAIR_LIMIT:
		messages.append("[K] 50%% REPAIR %s" % economy.dollars(ServiceRules.station_repair_fee(damage.integrity)))
	if service == "station" and fuel.fraction() < 0.9999:
		var price := CHARGE_PRICE_PER_UNIT if fuel.electric else GAS_PRICE_PER_LITRE
		messages.append("[J] REFILL %s" % economy.dollars(fuel.refill_cost(price)))
	if (service.is_empty() or (service == "garage" and damage.integrity >= 100.0)) and _can_tow():
		messages.append("[K] TOW")
	if notice_remaining > 0.0:
		messages.append(notice)
	readout.text = "\n".join(messages)
	notice_panel.visible = not messages.is_empty()
