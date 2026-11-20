extends CanvasLayer
const Imperial = preload("res://scripts/ui/imperial_units.gd")
const DashboardScript = preload("res://scripts/ui/vehicle_dashboard.gd")
var vehicle: VehicleController2D
var race: Node2D
var dashboard: Control
var environment_title := "DRIVING LAB    /    PROTOTYPE 01"
var active_vehicle_label: Label
var progression_slot: VBoxContainer
var camera: Camera2D
var speed_label: Label
var speed_unit_label: Label
var gear_label: Label
var rpm_bar: ProgressBar
var status: Label

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
	header.add_theme_constant_override("separation", 5)
	panel(Vector2(24, 24), Vector2(365, 0)).add_child(header)
	label(header, environment_title, 12, Color("a1c779"))
	active_vehicle_label = label(header, "CURRENT VEHICLE", 14, Color("e3eae0"))
	progression_slot = VBoxContainer.new()
	progression_slot.name = "ProgressionSlot"
	progression_slot.add_theme_constant_override("separation", 4)
	header.add_child(progression_slot)
	status = label(header, "ASPHALT   /   NORTH UP", 11, Color("93afa7"))
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
	vehicle.impacted.connect(func(strength: float):
		if strength > 5:
			status.text = "IMPACT / R TO RESET")

func show_unified_progression() -> void:
	# The equipped car name is included in the car-level row below.
	if is_instance_valid(active_vehicle_label):
		active_vehicle_label.visible = false


func on_vehicle_selected(entry: Dictionary) -> void:
	# Catalog.select() supplies fresh model-specific stats. Garage upgrades
	# are applied by the vehicle selector; the HUD never changes physics.
	if is_instance_valid(active_vehicle_label):
		active_vehicle_label.text = str(entry.display_name).to_upper()


func _process(_dt: float) -> void:
	if is_instance_valid(dashboard):
		dashboard.call("_process",_dt)
	if vehicle.linear_velocity.length() > 1 or Input.is_action_pressed("reset"):
		status.text = "%s   /   %s" % [vehicle.surface, "CAR FOLLOW" if camera.follow_heading else "NORTH UP"]
