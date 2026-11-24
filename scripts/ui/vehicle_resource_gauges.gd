extends Control
## Original engine and fuel-pump pictograms inside compact circular meters.
## Uses only Godot vector draw commands; no borrowed game artwork or assets.
const HEALTHY := Color("#a4df85")
const LOW := Color("#f2bd78")
const CRITICAL := Color("#ed796c")
const TRACK := Color("#3e5559")
const OUTLINE := Color("#071a20")
const ICON := Color("#eaf2e8")
const RADIUS := 24.0
var engine_fraction := 1.0
var fuel_fraction := 1.0
var electric := false

func _ready() -> void:
	name = "VehicleResourceGauges"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(140.0, 66.0)
	size = custom_minimum_size
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# Sits immediately to the left of Streetbound's 316px upper-right minimap.
	position = Vector2.ZERO
	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var viewport := get_viewport_rect().size
	# On wide screens, place meters to the left of the minimap.
	# On narrow screens, move below it so they do not cover the
	# driver's existing top-left garage/progression HUD.
	if viewport.x >= 1000.0 or viewport.y < 465.0:
		position = Vector2(maxf(8.0, viewport.x - 500.0), 44.0)
	else:
		position = Vector2(maxf(8.0, viewport.x - 190.0), 375.0)

func update_levels(engine: float, fuel: float, is_electric: bool = false) -> void:
	var next_engine := clampf(engine, 0.0, 1.0)
	var next_fuel := clampf(fuel, 0.0, 1.0)
	if is_equal_approx(next_engine, engine_fraction) and is_equal_approx(next_fuel, fuel_fraction) and electric == is_electric:
		return
	engine_fraction = next_engine
	fuel_fraction = next_fuel
	electric = is_electric
	queue_redraw()

func _ring(center: Vector2, value: float) -> void:
	var color := HEALTHY if value > 0.5 else (LOW if value > 0.2 else CRITICAL)
	draw_circle(center, 29.0, Color(0.02, 0.06, 0.07, 0.76))
	draw_arc(center, RADIUS, -PI * 0.5, PI * 1.5, 48, TRACK, 4.5, true)
	if value > 0.0:
		draw_arc(center, RADIUS, -PI * 0.5, -PI * 0.5 + TAU * value,
			48, color, 5.0, true)
	draw_arc(center, 18.0, -PI * 0.5, PI * 1.5, 48, OUTLINE, 1.0, true)

func _engine(center: Vector2) -> void:
	# Distinctive but original recognizable generic check-engine pictogram.
	var offset := center + Vector2(-13.0, -8.0)
	var shape := PackedVector2Array([
		Vector2(0, 3), Vector2(5, 3), Vector2(5, 0), Vector2(18, 0),
		Vector2(18, 3), Vector2(23, 3), Vector2(26, 6), Vector2(26, 16),
		Vector2(22, 18), Vector2(5, 18), Vector2(1, 14), Vector2(0, 14)
	])
	for i in shape.size():
		shape[i] += offset
	draw_colored_polygon(shape, ICON)
	draw_rect(Rect2(offset + Vector2(10, -4), Vector2(8, 3)), ICON)
	draw_line(offset + Vector2(-4, 7), offset + Vector2(1, 7), ICON, 3.0)
	draw_line(offset + Vector2(-4, 7), offset + Vector2(-4, 14), ICON, 3.0)

func _pump(center: Vector2) -> void:
	var offset := center + Vector2(-11, -13)
	draw_rect(Rect2(offset + Vector2(0, 3), Vector2(15, 22)), ICON)
	draw_rect(Rect2(offset + Vector2(3, 6), Vector2(9, 8)), OUTLINE)
	draw_rect(Rect2(offset + Vector2(-2, 24), Vector2(20, 3)), ICON)
	draw_polyline(PackedVector2Array([
		offset + Vector2(15, 9), offset + Vector2(20, 10),
		offset + Vector2(22, 15), offset + Vector2(22, 22)
	]), ICON, 2.8, true)
	if electric:
		# Distinguishes battery-electric vehicles while retaining pump layout.
		draw_colored_polygon(PackedVector2Array([
			offset + Vector2(9, 15), offset + Vector2(5, 21),
			offset + Vector2(9, 21), offset + Vector2(7, 25),
			offset + Vector2(13, 18), offset + Vector2(9, 18)
		]), OUTLINE)

func _draw() -> void:
	var engine_center := Vector2(33, 31)
	var fuel_center := Vector2(104, 31)
	_ring(engine_center, engine_fraction)
	_ring(fuel_center, fuel_fraction)
	_engine(engine_center)
	_pump(fuel_center)
