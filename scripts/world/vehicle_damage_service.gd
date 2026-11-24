extends CanvasLayer
## Player-only damage + stationary garage repairs. Test drives and online
## sessions deliberately omit this system until their authority rules exist.
const DamageState = preload("res://scripts/vehicle/vehicle_damage.gd")
var player: VehicleController2D
var economy: Object
var garage: Node2D
var authored_markers: Node2D
var police: Node2D
var current_car_id := ""
var integrity_by_car: Dictionary = {}
var damage = DamageState.new()
var readout: Label
var notice := ""
var notice_remaining := 0.0

func _ready() -> void:
	layer = 4
	name = "VehicleDamageService"
	if not is_instance_valid(player):
		return
	current_car_id = str(economy.active_id) if is_instance_valid(economy) else "default"
	player.crash_contact.connect(_on_impact)
	player.vehicle_reset.connect(_apply_drive_condition)
	var readout_panel := PanelContainer.new()
	readout_panel.position = Vector2(24, 204)
	readout_panel.custom_minimum_size = Vector2(285, 30)
	add_child(readout_panel)
	readout = Label.new()
	readout.add_theme_font_size_override("font_size", 13)
	readout_panel.add_child(readout)
	_apply_drive_condition()

func _on_impact(speed_mps: float, _position_px: Vector2,
		_normal: Vector2, _velocity_mps: Vector2) -> void:
	var applied: float = damage.register_impact(speed_mps, Time.get_ticks_msec() / 1000.0)
	if applied > 0.0:
		integrity_by_car[current_car_id] = damage.integrity
		notice = "IMPACT -%d" % roundi(applied)
		notice_remaining = 2.0
		_apply_drive_condition()

func _apply_drive_condition() -> void:
	if is_instance_valid(player):
		player.damage_drive_fraction = damage.drive_fraction()

func _service_available() -> bool:
	if not is_instance_valid(player) or player.linear_velocity.length() > 1.0:
		return false
	if is_instance_valid(police) and int(police.get("wanted_level")) > 0:
		return false
	if is_instance_valid(garage) and garage.has_method("can_switch") and garage.can_switch():
		return true
	if is_instance_valid(authored_markers):
		var nearby: Dictionary = authored_markers.nearest_marker()
		return str(nearby.get("type", "")) in ["garage", "fuel"]
	return false

func repair_full() -> void:
	damage.repair()
	integrity_by_car[current_car_id] = 100.0
	_apply_drive_condition()

func try_repair() -> bool:
	if not _service_available() or damage.integrity >= 100.0:
		return false
	var fee := damage.repair_cost()
	if not is_instance_valid(economy) or int(economy.balance) < fee:
		notice = "INSUFFICIENT CASH FOR REPAIR"
		notice_remaining = 3.0
		return false
	economy.balance -= fee
	if not economy.save():
		economy.balance += fee
		notice = "REPAIR SAVE FAILED"
		notice_remaining = 3.0
		return false
	economy.changed.emit()
	repair_full()
	notice = "REPAIRED / -%s" % economy.dollars(fee)
	notice_remaining = 3.0
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		if try_repair():
			get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(readout):
		return
	var car_id := str(economy.active_id) if is_instance_valid(economy) else "default"
	if car_id != current_car_id:
		integrity_by_car[current_car_id] = damage.integrity
		current_car_id = car_id
		damage.integrity = clampf(float(integrity_by_car.get(car_id, 100.0)), 0.0, 100.0)
		damage.last_impact_at = -INF
		_apply_drive_condition()
	notice_remaining = maxf(0.0, notice_remaining - dt)
	var label := "VEHICLE %d%%" % roundi(damage.integrity)
	if damage.is_disabled():
		label += "  /  DISABLED"
	elif damage.integrity < 35.0:
		label += "  /  CRITICAL"
	if _service_available() and damage.integrity < 100.0:
		label += "  /  K REPAIR %s" % economy.dollars(damage.repair_cost())
	if notice_remaining > 0.0:
		label += "  /  " + notice
	readout.text = label
