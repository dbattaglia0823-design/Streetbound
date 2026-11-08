extends CanvasLayer
var vehicle: VehicleController2D
var camera: Camera2D
var telemetry: Label
var speed_label: Label
var gear_label: Label
var rpm_bar: ProgressBar
var status: Label
var tuning: PanelContainer
var tune_box: VBoxContainer
var waiting_action := ""
var rebind_buttons: Dictionary = {}
var config_labels: Dictionary = {}

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
	label(column, " KM/H", 16, Color("a1c779"))
	gear_label = label(column, " 1  /  AUTO", 23)
	rpm_bar = ProgressBar.new()
	rpm_bar.show_percentage = false
	rpm_bar.custom_minimum_size.y = 7
	dash.add_child(rpm_bar)
	telemetry = label(dash, "", 14)
	var hints := VBoxContainer.new()
	panel(Vector2(413, 802), Vector2(1003, 68)).add_child(hints)
	label(hints, "W / S  DRIVE & REVERSE     A / D  STEER     SPACE  HANDBRAKE     R  RESET", 15)
	label(hints, "C  CAMERA     F1  LIVE TUNING & BINDINGS     M  AUTO / MANUAL     Q / E  SHIFT     V  MUTE", 13, Color("a2b4ab"))
	tuning = panel(Vector2(1000, 24), Vector2(416, 750))
	tuning.visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(376, 710)
	tuning.add_child(scroll)
	tune_box = VBoxContainer.new()
	tune_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tune_box)
	label(tune_box, "LIVE HANDLING / F1", 22)
	label(tune_box, "Changes apply to this session. R resets position.", 12)
	for entry in [["tire_grip", "Tire grip", 0.5, 1.8, 0.01], ["rear_grip_balance", "Rear grip balance", 0.65, 1.35, 0.01], ["countersteer_assist", "Countersteer assist", 0.0, 0.8, 0.01], ["handbrake_rear_grip", "Handbrake rear grip", 0.15, 0.8, 0.01], ["max_steer_degrees", "Low speed steering", 20.0, 42.0, 0.5], ["high_speed_steer_degrees", "High speed steering", 5.0, 18.0, 0.5], ["engine_torque_nm", "Engine torque / Nm", 200.0, 800.0, 10.0], ["engine_power_kw", "Engine power / kW", 150.0, 650.0, 10.0], ["mass_kg", "Mass / kg", 900.0, 2100.0, 25.0], ["brake_force_n", "Brakes / N", 8000.0, 25000.0, 500.0]]:
		add_slider(entry)
	add_slider(["steering_response", "Steering response", 6.0, 25.0, 0.5])
	add_slider(["cornering_stiffness", "Tire response / N per rad", 50000.0, 150000.0, 2500.0])
	add_slider(["rear_cornering_stiffness_ratio", "Rear tire response balance", 0.8, 1.6, 0.02])
	add_slider(["steering_return_strength", "Return-to-center strength", 4.0, 35.0, 0.5])
	label(tune_box, "DRIVETRAIN", 14, Color("a1c779"))
	var drivetrain := OptionButton.new()
	for name in ["FWD", "RWD", "AWD"]:
		drivetrain.add_item(name)
	drivetrain.selected = vehicle.config.drivetrain
	drivetrain.item_selected.connect(func(index: int): vehicle.config.drivetrain = index)
	tune_box.add_child(drivetrain)
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
	var caption := label(tune_box, "%s   %.2f" % [entry[1], vehicle.config.get(property)], 13)
	config_labels[property] = caption
	var slider := HSlider.new()
	slider.min_value = entry[2]
	slider.max_value = entry[3]
	slider.step = entry[4]
	slider.value = vehicle.config.get(property)
	slider.value_changed.connect(func(value: float):
		vehicle.config.set(property, value)
		caption.text = "%s   %.2f" % [entry[1], value])
	tune_box.add_child(slider)

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

func _process(_dt: float) -> void:
	var speed := vehicle.linear_velocity.length() * 3.6
	speed_label.text = "%03d" % roundi(speed)
	var mode := "AUTO" if vehicle.transmission.automatic else "MANUAL"
	gear_label.text = " %s / %s" % ["R" if vehicle.reversing else str(vehicle.transmission.gear), mode]
	rpm_bar.value = vehicle.transmission.rpm / vehicle.config.redline_rpm * 100
	telemetry.text = "%04d RPM   /   %s\nLONG %+.1f m/s    LAT %+.1f m/s    SLIP %+.1f°\n%.0f kg   %.0f Nm   %.0f kW   GRIP %.2f" % [vehicle.transmission.rpm, vehicle.surface, vehicle.longitudinal_speed, vehicle.lateral_speed, rad_to_deg(vehicle.slip_angle), vehicle.config.mass_kg, vehicle.config.engine_torque_nm, vehicle.config.engine_power_kw, vehicle.config.tire_grip * vehicle.surface_grip]
	if vehicle.linear_velocity.length() > 1 or Input.is_action_pressed("reset"):
		status.text = "%s   /   %s" % [vehicle.surface, "CAR FOLLOW" if camera.follow_heading else "NORTH UP"]
