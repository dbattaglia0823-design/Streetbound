extends CanvasLayer
const Imperial = preload("res://scripts/ui/imperial_units.gd")
const TuningProfile = preload("res://scripts/vehicle/tuning_profile.gd")
# Explicit script dependency: the Controls autoload name can be unresolved
# when Godot compiles the HUD in a fresh project import / headless session.
# Static default action metadata must not rely on that global identifier.
const ControlsScript = preload("res://scripts/input/controls.gd")
const DashboardScript = preload("res://scripts/ui/vehicle_dashboard.gd")
const TUNING_FIELDS = [
	["engine_power_kw", "Horsepower (hp)", 50.0 / Imperial.KW_TO_HP, 10000.0 / Imperial.KW_TO_HP, 10.0],
	["engine_torque_nm", "Torque (lb-ft)", 50.0 / Imperial.NM_TO_LB_FT, 10000.0 / Imperial.NM_TO_LB_FT, 10.0],
	["mass_kg", "Weight (lb)", 50.0 / Imperial.KG_TO_LB, 10000.0 / Imperial.KG_TO_LB, 10.0]
]
var vehicle: VehicleController2D
var race: Node2D
var dashboard: Control
var environment_title := "DRIVING LAB    /    PROTOTYPE 01"
var active_vehicle_label: Label
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
	label(header, environment_title, 13, Color("a1c779"))
	label(header, "F1 STATS  ·  ESC PAUSE  ·  C CAMERA  ·  WHEEL ZOOM", 11, Color("93afa7"))
	active_vehicle_label = label(header, "SPORT COUPE  /  LAUREL MOTOR HOUSE GARAGE", 13, Color("c4d4d0"))
	status = label(header, "ASPHALT   /   NORTH UP", 14)
	# All primary driving instrumentation now shares a purpose-built,
	# responsive cluster rather than the old text-filled prototype box.
	dashboard = Control.new()
	dashboard.set_script(DashboardScript)
	dashboard.set("vehicle",vehicle)
	dashboard.set("race",race)
	add_child(dashboard)
	# HUD owns the update order, including tests that invoke HUD._process(0).
	dashboard.set_process(false)
	speed_label = dashboard.get("speed_label") as Label
	speed_unit_label = dashboard.get("speed_unit_label") as Label
	gear_label = dashboard.get("gear_label") as Label
	rpm_bar = dashboard.get("rpm_bar") as ProgressBar
	tuning = panel(Vector2(1000, 24), Vector2(416, 750))
	tuning.visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(376, 710)
	tuning.add_child(scroll)
	tune_box = VBoxContainer.new()
	tune_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tune_box)
	label(tune_box, "VEHICLE STATS / F1", 22)
	label(tune_box, "Power, torque and weight · step 10 · autosave", 12)
	# Detailed engineering readouts belong in the inspectable F1 panel,
	# not over the road and race timing instruments.
	telemetry = label(tune_box, "", 12, Color("c2d5d0"))
	tuning_save_label = label(tune_box, "Changes saved on adjustment.", 12, Color("a1c779"))
	reset_tuning_button = Button.new()
	reset_tuning_button.text = "Restore stock vehicle tuning"
	reset_tuning_button.pressed.connect(_restore_stock_tuning)
	tune_box.add_child(reset_tuning_button)
	for entry in TUNING_FIELDS:
		add_slider(entry)
	# F1 is only for vehicle performance stats; bindings are managed elsewhere.
	vehicle.impacted.connect(func(strength: float):
		if strength > 5:
			status.text = "IMPACT / R TO RESET")

func on_vehicle_selected(entry: Dictionary, restore_saved_tuning: bool = false) -> void:
	# Each selected model has its own stock baseline. Apply saved F1 edits
	# only on startup, not when switching to a *different* vehicle.
	if is_instance_valid(active_vehicle_label):
		active_vehicle_label.text = str(entry.display_name).to_upper()
	_stock_tune = vehicle.config.duplicate(true)
	if tuning_profile != null:
		if restore_saved_tuning:
			tuning_profile.load_into(vehicle.config)
		else:
			tuning_profile.clear_profile()
	if _save_timer != null:
		_save_timer.stop()
	_tuning_dirty = false
	for setting in TUNING_FIELDS:
		var field: String = setting[0]
		var value := float(vehicle.config.get(field))
		(tuning_sliders[field] as HSlider).set_value_no_signal(_display_slider_value(field, value))
		(config_labels[field] as Label).text = "%s   %s" % [
			setting[1], Imperial.tune_text(field, value)]
	if is_instance_valid(drivetrain_select):
		drivetrain_select.select(vehicle.config.drivetrain)
	if is_instance_valid(tuning_save_label):
		tuning_save_label.text = "Vehicle baseline loaded. F1 adjustments save separately."

func _display_slider_value(property: String, native_value: float) -> float:
	return clampf(roundf(Imperial.tune_value(property, native_value) / 10.0) * 10.0, 50.0, 10000.0)


func _slider_native_value(property: String, value: float) -> float:
	match property:
		"engine_power_kw":
			return value / Imperial.KW_TO_HP
		"engine_torque_nm":
			return value / Imperial.NM_TO_LB_FT
		"mass_kg":
			return value / Imperial.KG_TO_LB
	return value


func add_slider(entry: Array) -> void:
	var property: String = entry[0]
	var caption := label(tune_box, "%s   %s" % [entry[1], Imperial.tune_text(property, float(vehicle.config.get(property)))], 13)
	config_labels[property] = caption
	var slider := HSlider.new()
	tuning_sliders[property] = slider
	slider.min_value = 50.0
	slider.max_value = 10000.0
	slider.step = 10.0
	slider.value = _display_slider_value(property, float(vehicle.config.get(property)))
	slider.value_changed.connect(func(value: float):
		var native := _slider_native_value(property, value)
		vehicle.config.set(property, native)
		caption.text = "%s   %s" % [entry[1], Imperial.tune_text(property, native)]
		_queue_tuning_save())
	tune_box.add_child(slider)


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
		(tuning_sliders[property] as HSlider).set_value_no_signal(_display_slider_value(property, original))
		(config_labels[property] as Label).text = "%s   %s" % [
			entry[1], Imperial.tune_text(property, original)]
	tuning_save_label.text = "Stock tuning restored; saved override cleared."

func _exit_tree() -> void:
	# Exit/quit can occur during an active slider drag, before debounce fires.
	if _tuning_dirty:
		_save_tuning_now()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("tuning"):
		tuning.visible = not tuning.visible
		if not tuning.visible:
			_save_tuning_now()

func _process(_dt: float) -> void:
	if is_instance_valid(dashboard):
		dashboard.call("_process",_dt)
	telemetry.text = "POWER %.0f hp   /   TORQUE %.0f lb-ft   /   WEIGHT %.0f lb" % [
		Imperial.tune_value("engine_power_kw", vehicle.config.engine_power_kw),
		Imperial.tune_value("engine_torque_nm", vehicle.config.engine_torque_nm),
		Imperial.tune_value("mass_kg", vehicle.config.mass_kg)]
	if vehicle.linear_velocity.length() > 1 or Input.is_action_pressed("reset"):
		status.text = "%s   /   %s" % [vehicle.surface, "CAR FOLLOW" if camera.follow_heading else "NORTH UP"]
