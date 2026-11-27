extends CanvasLayer
const DashboardScript = preload("res://scripts/ui/vehicle_dashboard.gd")
var vehicle: VehicleController2D
var race: Node2D
var dashboard: Control
var environment_title := "DRIVING LAB / PROTOTYPE 01"
var camera: Camera2D
var speed_label: Label
var speed_unit_label: Label
var gear_label: Label
var rpm_bar: ProgressBar
var status_host: VBoxContainer

## Shared action cards use the dashboard palette and occupy only visible rows.
static func status_card(parent: Node, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045,0.078,0.101,0.94)
	style.border_color = accent.darkened(0.5)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(9)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel",style)
	panel.custom_minimum_size.x = 300
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	panel.hide()
	return panel

static func status_text(parent: Node, value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func status_bar(parent: Node, tint: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = 7
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#263b44")
	track.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background",track)
	bar.add_theme_stylebox_override("fill",fill)
	parent.add_child(bar)
	return bar

func _ready() -> void:
	name = "DrivingHUD"
	status_host = VBoxContainer.new()
	status_host.name = "DynamicStatusStack"
	status_host.position = Vector2(16,16)
	status_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_host.add_theme_constant_override("separation",8)
	add_child(status_host)
	get_viewport().size_changed.connect(_layout_status)
	_layout_status()
	dashboard = Control.new()
	dashboard.set_script(DashboardScript)
	dashboard.set("vehicle",vehicle)
	dashboard.set("race",race)
	add_child(dashboard)
	dashboard.set_process(false)
	speed_label = dashboard.get("speed_label") as Label
	speed_unit_label = dashboard.get("speed_unit_label") as Label
	gear_label = dashboard.get("gear_label") as Label
	rpm_bar = dashboard.get("rpm_bar") as ProgressBar

func _layout_status() -> void:
	var viewport := get_viewport().get_visible_rect().size
	status_host.custom_minimum_size.x = 320
	status_host.reset_size()
	var factor := minf(1.0,maxf(0.35,(viewport.x-32.0)/750.0))
	status_host.scale = Vector2.ONE*factor

func on_vehicle_selected(_entry: Dictionary) -> void:
	# Dashboard reads the live selected configuration directly.
	pass

func _process(dt: float) -> void:
	if is_instance_valid(dashboard):
		dashboard.call("_process",dt)
