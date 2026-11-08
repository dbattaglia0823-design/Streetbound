extends CanvasLayer
const Imperial = preload("res://scripts/ui/imperial_units.gd")
const TuningProfile = preload("res://scripts/vehicle/tuning_profile.gd")
const TUNING_FIELDS = [["tire_grip", "Tire grip", 0.5, 1.8, 0.01], ["rear_grip_balance", "Rear grip balance", 0.65, 1.35, 0.01], ["countersteer_assist", "Countersteer assist", 0.0, 0.8, 0.01], ["handbrake_rear_grip", "Handbrake rear grip", 0.15, 0.8, 0.01], ["max_steer_degrees", "Low speed steering", 20.0, 55.0, 0.5], ["high_speed_steer_degrees", "High speed steering", 5.0, 18.0, 0.5], ["engine_torque_nm", "Engine torque / lb-ft", 200.0, 800.0, 10.0], ["engine_power_kw", "Engine power / hp", 150.0, 650.0, 10.0], ["mass_kg", "Mass / lb", 900.0, 2100.0, 25.0], ["brake_force_n", "Brakes / lbf", 8000.0, 25000.0, 500.0],
	["steering_response", "Steering response", 6.0, 25.0, 0.5],
	["arcade_steering_assist", "Arcade steering assist", 0.0, 1.0, 0.05],
	["arcade_cornering_accel", "Arcade cornering strength", 16.0, 40.0, 1.0],
	["brake_turn_boost", "Brake turning boost", 0.0, 1.0, 0.05],
	["handbrake_grip_recovery_seconds", "Rear tire recovery / seconds", 0.3, 1.8, 0.05],
	["handbrake_drive_grip", "Handbrake drive traction", 0.4, 1.0, 0.025],
	["wheel_spin_recovery_rate", "Wheelspin settling rate", 1.0, 8.0, 0.25],
	["cornering_stiffness", "Tire response / lbf per rad", 50000.0, 150000.0, 2500.0],
	["rear_cornering_stiffness_ratio", "Rear tire response balance", 0.8, 1.6, 0.02],
	["steering_return_strength", "Return-to-center strength", 4.0, 35.0, 0.5]]
var vehicle: VehicleController2D
var camera: Camera2D
var telemetry: Label
var speed_label: Label
var speed_unit_label: Label
var gear_label: Label
var rpm_bar: ProgressBar
var status: Label
var tuning: PanelContainer
var tune_box: VBoxContainer
var waiting_action := ""
var rebind_buttons: Dictionary = {}
var config_labels: Dictionary = {}
var tuning_sliders: Dictionary = {}
var drivetrain_select: OptionButton
var reset_tuning_button: Button
var tuning_save_label: Label
var tuning_profile: RefCounted
var _stock_tune: VehicleConfig
var _save_timer: Timer
var _tuning_dirty := false

func panel(at: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = at
	p.custom_minimum_size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.075, 0.085, 0.94)
	style.border_color = Color("3b5353")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", style)
	add_child(p)
	return p

func label(parent: Node, text: String, size := 16, color := Color("d9e3dd")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _ready() -> void:
	# VehicleController duplicates the Resource in its own _ready(). Load only
	# the player's explicitly editable values into that instance, not stock .tres.
	_stock_tune = vehicle.config.duplicate(true)
	tuning_profile = TuningProfile.new(TUNING_FIELDS)
	tuning_profile.load_into(vehicle.config)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.35
	_save_timer.timeout.connect(_save_tuning_now)
	add_child(_save_timer)
	var header := VBoxContainer.new()
	panel(Vector2(24, 24), Vector2(365, 0)).add_child(header)
	label(header, "S T R E E T B O U N D", 24)
	label(header, "DRIVING LAB    /    PROTOTYPE 01", 13, Color("a1c779"))
	status = label(header, "ASPHALT   /   NORTH UP", 14)
	var dash := VBoxContainer.new()
	panel(Vector2(24, 650), Vector2(365, 220)).add_child(dash)
	var row := HBoxContainer.new()
	dash.add_child(row)
	speed_label = label(row, "000", 64)
	var column := VBoxContainer.new()
	row.add_child(column)
	speed_unit_label = label(column, " MPH", 16, Color("a1c779"))
	gear_label = label(column, " 1  /  AUTO", 23)
	rpm_bar = ProgressBar.new()
	rpm_bar.show_percentage = false
	rpm_bar.custom_minimum_size.y = 7
	dash.add_child(rpm_bar)
	telemetry = label(dash, "", 14)
	var hints := VBoxContainer.new()
	panel(Vector2(413, 802), Vector2(1003, 68)).add_child(hints)
	label(hints, "W / S  DRIVE & REVERSE     A / D  STEER     SPACE  HANDBRAKE     R  RESET", 15)
	label(hints, "ESC  PAUSE / SETTINGS     C  CAMERA     F1  TUNING & BINDINGS     M  AUTO / MANUAL     Q / E  SHIFT     V  MUTE", 13, Color("a2b4ab"))
	tuning = panel(Vector2(1000, 24), Vector2(416, 750))
	tuning.visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(376, 710)
	tuning.add_child(scroll)
	tune_box = VBoxContainer.new()
	tune_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tune_box)
	label(tune_box, "LIVE HANDLING / F1", 22)
	label(tune_box, "Tuning saves automatically. R only resets your car.", 12)
	tuning_save_label = label(tune_box, "Changes saved on adjustment.", 12, Color("a1c779"))
	reset_tuning_button = Button.new()
	reset_tuning_button.text = "Restore stock vehicle tuning"
	reset_tuning_button.pressed.connect(_restore_stock_tuning)
	tune_box.add_child(reset_tuning_button)
	for entry in TUNING_FIELDS:
		add_slider(entry)
	label(tune_box, "DRIVETRAIN", 14, Color("a1c779"))
	drivetrain_select = OptionButton.new()
	for name in ["FWD", "RWD", "AWD"]:
		drivetrain_select.add_item(name)
	drivetrain_select.selected = vehicle.config.drivetrain
	drivetrain_select.item_selected.connect(_on_drivetrain_selected)
	tune_box.add_child(drivetrain_select)
	label(tune_box, "CONTROLS / click to rebind", 17)
	for action in Controls.KEYS:
		var button := Button.new()
		button.text = binding_text(action)
		button.pressed.connect(func(): waiting_action = action; button.text = "Press key / pad…  (Esc cancels)")
		tune_box.add_child(button)
		rebind_buttons[action] = button
	label(tune_box, "CONTROLLER\nRT throttle · LT brake / reverse\nLeft stick steer · A handbrake · Y reset\nRB camera · D-pad up/down shift", 14)
	vehicle.impacted.connect(func(strength: float):
		if strength > 5:
			status.text = "IMPACT / R TO RESET")

func add_slider(entry: Array) -> void:
	var property: String = entry[0]
	var caption := label(tune_box, "%s   %s" % [entry[1], Imperial.tune_text(property, float(vehicle.config.get(property)))], 13)
	config_labels[property] = caption
	var slider := HSlider.new()
	tuning_sliders[property] = slider
	slider.min_value = entry[2]
	slider.max_value = entry[3]
	slider.step = entry[4]
	slider.value = vehicle.config.get(property)
	slider.value_changed.connect(func(value: float):
		vehicle.config.set(property, value)
		caption.text = "%s   %s" % [entry[1], Imperial.tune_text(property, value)]
		_queue_tuning_save())
	tune_box.add_child(slider)

func _on_drivetrain_selected(index: int) -> void:
	vehicle.config.drivetrain = index
	_queue_tuning_save()

func _queue_tuning_save() -> void:
	_tuning_dirty = true
	tuning_save_label.text = "Saving tuning…"
	_save_timer.start()

func _save_tuning_now() -> void:
	if not _tuning_dirty or tuning_profile == null:
		return
	_save_timer.stop()
	var result: Error = tuning_profile.save_from(vehicle.config)
	if result == OK:
		_tuning_dirty = false
		tuning_save_label.text = "Tuning saved automatically."
	else:
		tuning_save_label.text = "Could not save tuning (error %s)." % result

func _restore_stock_tuning() -> void:
	if tuning_profile.clear_profile() != OK:
		tuning_save_label.text = "Could not clear saved tuning."
		return
	_save_timer.stop()
	_tuning_dirty = false
	for entry in TUNING_FIELDS:
		var property: String = entry[0]
		var original: float = float(_stock_tune.get(property))
		vehicle.config.set(property, original)
		(tuning_sliders[property] as HSlider).set_value_no_signal(original)
		(config_labels[property] as Label).text = "%s   %s" % [
			entry[1], Imperial.tune_text(property, original)]
	vehicle.config.drivetrain = _stock_tune.drivetrain
	drivetrain_select.select(vehicle.config.drivetrain)
	tuning_save_label.text = "Stock tuning restored; saved override cleared."

func _exit_tree() -> void:
	# Exit/quit can occur during an active slider drag, before debounce fires.
	if _tuning_dirty:
		_save_tuning_now()

func binding_text(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return "%s  /  %s" % [action.capitalize(), OS.get_keycode_string(event.physical_keycode)]
	return action

func _input(event: InputEvent) -> void:
	var key_pressed: bool = event is InputEventKey and event.pressed and not event.echo
	var pad_pressed: bool = event is InputEventJoypadButton and event.pressed
	var axis_moved: bool = event is InputEventJoypadMotion and absf(event.axis_value) > 0.7
	if not waiting_action.is_empty() and (key_pressed or pad_pressed or axis_moved):
		if not (key_pressed and event.physical_keycode == KEY_ESCAPE):
			var binding: InputEvent = event.duplicate()
			if binding is InputEventJoypadMotion:
				binding.axis_value = signf(binding.axis_value)
			Controls.bind_event(waiting_action, binding)
		rebind_buttons[waiting_action].text = binding_text(waiting_action)
		waiting_action = ""
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tuning"):
		tuning.visible = not tuning.visible
		if not tuning.visible:
			_save_tuning_now()

func _process(_dt: float) -> void:
	var speed: float = Imperial.speed_mph(vehicle.linear_velocity.length())
	speed_label.text = "%03d" % roundi(speed)
	var mode := "AUTO" if vehicle.transmission.automatic else "MANUAL"
	gear_label.text = " %s / %s" % ["R" if vehicle.reversing else str(vehicle.transmission.gear), mode]
	rpm_bar.value = vehicle.transmission.rpm / vehicle.config.redline_rpm * 100
	telemetry.text = "%04d RPM   /   %s\nLONG %+.1f MPH    LAT %+.1f MPH    SLIP %+.1f°\n%.0f lb   %.0f lb-ft   %.0f hp   GRIP %.2f" % [
		vehicle.transmission.rpm, vehicle.surface,
		Imperial.speed_mph(vehicle.longitudinal_speed),
		Imperial.speed_mph(vehicle.lateral_speed),
		rad_to_deg(vehicle.slip_angle),
		Imperial.tune_value("mass_kg", vehicle.config.mass_kg),
		Imperial.tune_value("engine_torque_nm", vehicle.config.engine_torque_nm),
		Imperial.tune_value("engine_power_kw", vehicle.config.engine_power_kw),
		vehicle.config.tire_grip * vehicle.surface_grip
	]
	telemetry.text += "\nWHEELSPIN %d%%   REAR CONTACT %d%%" % [roundi(vehicle.wheel_spin * 100), roundi((1.0 - vehicle.handbrake_grip_loss) * 100)]
	if vehicle.linear_velocity.length() > 1 or Input.is_action_pressed("reset"):
		status.text = "%s   /   %s" % [vehicle.surface, "CAR FOLLOW" if camera.follow_heading else "NORTH UP"]
