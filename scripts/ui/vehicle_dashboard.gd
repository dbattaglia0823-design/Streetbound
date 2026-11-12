extends Control
## Purpose-built vehicle instrumentation. All readings come from actual vehicle
## physics; no fabricated oil/fuel/temperature data. Optional turbo models use
## the controller's modeled charge pressure.
const Imperial = preload("res://scripts/ui/imperial_units.gd")
# Compact bottom-left instrument cluster. Each element has a dedicated
# non-overlapping region; viewport changes only apply a uniform scale.
const SIZE := Vector2(590.0,184.0)
const SPEED_CENTER := Vector2(82.0,99.0)
const RPM_CENTER := Vector2(211.0,99.0)
const GAUGE_RADIUS := 49.0
const METER_SIZE := Vector2(13.0,55.0)
const LOAD_METER_AT := Vector2(393.0,72.0)
const THROTTLE_METER_AT := Vector2(472.0,72.0)
const BRAKE_METER_AT := Vector2(545.0,72.0)
const ARC_START := deg_to_rad(150.0)
const ARC_END := deg_to_rad(390.0)
const BACK := Color("#101c24")
const LIGHT := Color("#eaf2e8")
const MUTED := Color("#97afa9")
const CYAN := Color("#63d6da")
const MINT := Color("#a5dfa0")
const GOLD := Color("#f2bd78")
const ALERT := Color("#ed796c")

var vehicle: VehicleController2D
var race: Node2D
var speed_label: Label
var speed_unit_label: Label
var rpm_label: Label
var gear_label: Label
var mode_label: Label
var model_label: Label
var boost_label: Label
var boost_value: Label
var throttle_value: Label
var brake_value: Label
var tire_value: Label
var surface_value: Label
var race_value: Label
var rpm_bar: ProgressBar
var boost_visible := false
var boost_fraction := 0.0
var _speed_fraction := 0.0
var _rpm_fraction := 0.0
var _throttle_fraction := 0.0
var _brake_fraction := 0.0
var _tire_fraction := 0.0
var _speed_max_mph := 200.0
var _longitudinal_g := 0.0
var _last_speed_mps := 0.0
var _last_car_config: VehicleConfig
var _last_race_state := ""
var _animation_clock := 0.0


func _ready() -> void:
	name = "LiveVehicleDashboard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE
	_last_speed_mps = vehicle.longitudinal_speed
	_build_labels()
	_refresh_vehicle_configuration()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_update_readouts(0.0)


func _label(value: String, at: Vector2, dimensions: Vector2,
		font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.position = at
	# Apply the single-line font BEFORE sizing the Control. Godot preserves
	# the larger initial label minimum when size is set prior to font overrides,
	# leaving 48px high rectangles that overlap the 17px instrument captions.
	node.add_theme_font_override("font", ThemeDB.fallback_font)
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.text = value
	node.horizontal_alignment = alignment
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.clip_text = true
	node.custom_minimum_size = dimensions
	add_child(node)
	# Recompute from the final theme, then explicitly place the requested
	# rectangle; all dashboard regions rely on these tight layout bounds.
	node.reset_size()
	node.size = dimensions
	return node


func _build_labels() -> void:
	# Top line: short identity and current power, without repeating the rest of
	# the HUD or allowing either caption into the circular instruments.
	_label("DRIVE", Vector2(16,7), Vector2(94,22), 12, GOLD)
	model_label = _label("VEHICLE", Vector2(273,7), Vector2(301,22), 11,
		LIGHT, HORIZONTAL_ALIGNMENT_RIGHT)

	# Main essentials stay readable but no longer dominate the lower screen.
	speed_label = _label("000", Vector2(39,70), Vector2(86,38), 34,
		LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	speed_unit_label = _label("MPH", Vector2(58,121), Vector2(49,17), 10,
		CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	rpm_label = _label("0950", Vector2(167,76), Vector2(88,36), 27,
		LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label("RPM", Vector2(189,121), Vector2(45,17), 10,
		MINT, HORIZONTAL_ALIGNMENT_CENTER)
	_label("GEAR", Vector2(278,54), Vector2(66,17), 10,
		MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	gear_label = _label("1", Vector2(284,78), Vector2(54,42), 32,
		LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	mode_label = _label("AUTO", Vector2(279,133), Vector2(64,17), 10,
		GOLD, HORIZONTAL_ALIGNMENT_CENTER)

	# Small, independent vertical gauges: captions above, bottom-up meters in
	# the middle and real values below. No labels intersect the bars or dials.
	boost_label = _label("LOAD", Vector2(367,47), Vector2(65,17), 10,
		MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	boost_value = _label("0%", Vector2(365,132), Vector2(68,19), 11,
		LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label("THROTTLE", Vector2(439,47), Vector2(80,17), 10,
		MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	throttle_value = _label("0%", Vector2(446,132), Vector2(66,19), 11,
		LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label("BRAKE", Vector2(519,47), Vector2(60,17), 10,
		MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	brake_value = _label("0%", Vector2(520,132), Vector2(57,19), 11,
		LIGHT, HORIZONTAL_ALIGNMENT_CENTER)

	# Bottom strip: only actionable traction and driving/race information.
	# Surface is already identified in the top-left HUD.
	surface_value = _label("GRIP 1.00", Vector2(16,161), Vector2(149,19), 10, MUTED)
	tire_value = _label("SPIN 0% / SLIP 0°", Vector2(172,161), Vector2(169,19),
		10, LIGHT)
	race_value = _label("0.00 G", Vector2(343,161), Vector2(233,19), 10,
		GOLD, HORIZONTAL_ALIGNMENT_RIGHT)

	# Keep the RPMBar compatibility readout for tests and integrations but
	# do not draw a duplicate horizontal gauge: the RPM arc/shift lights show it.
	rpm_bar = ProgressBar.new()
	rpm_bar.name = "RPMBar"
	rpm_bar.max_value = 100.0
	rpm_bar.show_percentage = false
	rpm_bar.visible = false
	rpm_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rpm_bar)


func _layout_factor_for(viewport_size: Vector2) -> float:
	return maxf(0.05, minf(1.0, minf(
		(viewport_size.x - 32.0) / SIZE.x,
		(viewport_size.y - 28.0) / SIZE.y)))


func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	var factor := _layout_factor_for(viewport_size)
	scale = Vector2.ONE * factor
	position = Vector2(16.0, maxf(8.0, viewport_size.y - SIZE.y * factor - 12.0))

func _refresh_vehicle_configuration() -> void:
	if not is_instance_valid(vehicle) or vehicle.config == null:
		return
	_last_car_config = vehicle.config
	boost_visible = vehicle.config.boost_max_psi > 0.05
	# Scale the speed dial with the rated vehicle power, not current speed.
	_speed_max_mph = clampf(ceilf(sqrt(vehicle.config.engine_power_kw/130.0)*4.5)*20.0,
		140.0,360.0)
	boost_label.text = "BOOST" if boost_visible else "LOAD"
	_last_speed_mps = vehicle.longitudinal_speed
	_longitudinal_g = 0.0


func _process(dt: float) -> void:
	if not is_instance_valid(vehicle):
		return
	if vehicle.config != _last_car_config:
		_refresh_vehicle_configuration()
	_update_readouts(dt)


func _update_readouts(dt: float) -> void:
	if not is_instance_valid(vehicle) or vehicle.config == null:
		return
	_animation_clock += maxf(0.0,dt)
	var speed_mph := Imperial.speed_mph(vehicle.linear_velocity.length())
	var max_rpm := maxf(1.0,vehicle.config.redline_rpm)
	var target_speed := clampf(speed_mph/_speed_max_mph,0.0,1.0)
	var target_rpm := clampf(vehicle.transmission.rpm/max_rpm,0.0,1.0)
	var smoothing := 1.0 - exp(-14.0*maxf(0.0,dt))
	if dt <= 0.0:
		smoothing = 1.0
	_speed_fraction = lerpf(_speed_fraction,target_speed,smoothing)
	_rpm_fraction = lerpf(_rpm_fraction,target_rpm,smoothing)
	_throttle_fraction = lerpf(_throttle_fraction,clampf(vehicle.throttle,0,1),smoothing)
	_brake_fraction = lerpf(_brake_fraction,clampf(vehicle.brake,0,1),smoothing)
	_tire_fraction = lerpf(_tire_fraction,clampf(vehicle.wheel_spin,0,1),smoothing)
	if dt > 0.001 and dt < 0.25:
		var sampled_g := (vehicle.longitudinal_speed-_last_speed_mps)/dt/9.80665
		_longitudinal_g = lerpf(_longitudinal_g,clampf(sampled_g,-3.0,3.0),
			1.0-exp(-5.0*dt))
	_last_speed_mps = vehicle.longitudinal_speed
	speed_label.text = "%03d" % maxi(0,roundi(speed_mph))
	speed_unit_label.text = "MPH"
	rpm_label.text = "%04d" % roundi(vehicle.transmission.rpm)
	gear_label.text = "R" if vehicle.reversing else str(vehicle.transmission.gear)
	mode_label.text = "AUTO" if vehicle.transmission.automatic else "MAN"
	rpm_bar.value = target_rpm * 100.0
	var grip_color := LIGHT
	if vehicle.wheel_spin >= 0.18 or absf(rad_to_deg(vehicle.slip_angle)) >= 12.0:
		grip_color = ALERT
	elif vehicle.wheel_spin > 0.06:
		grip_color = GOLD
	tire_value.text = "SPIN %d%% / SLIP %.0f°" % [
		roundi(vehicle.wheel_spin*100.0),absf(rad_to_deg(vehicle.slip_angle))]
	tire_value.add_theme_color_override("font_color",grip_color)
	surface_value.text = "GRIP %.2f / %s" % [
		vehicle.config.tire_grip*vehicle.surface_grip,
		["FWD","RWD","AWD"][clampi(int(vehicle.config.drivetrain),0,2)]]
	throttle_value.text = "%d%%" % roundi(vehicle.throttle*100.0)
	brake_value.text = "%d%%" % roundi(vehicle.brake*100.0)
	if boost_visible:
		var limit := maxf(0.1,vehicle.config.boost_max_psi)
		boost_fraction = clampf(vehicle.boost_psi/limit,0.0,1.0)
		boost_value.text = "%.1f PSI" % vehicle.boost_psi
	else:
		boost_fraction = clampf(vehicle.throttle,0.0,1.0)
		boost_value.text = "%d%%" % roundi(vehicle.throttle*100.0)
	var race_state := ""
	if is_instance_valid(race):
		race_state = str(race.state)
		if race_state == "running":
			race_value.text = "1/4 MILE   %.2f s   /   %.0f m" % [
				float(race.elapsed),maxf(0.0,float(race.progress_m))]
		elif race_state == "countdown":
			race_value.text = "RACE START   /   %d" % maxi(1,ceili(float(race.countdown)))
		elif race_state == "results":
			race_value.text = "FINISH   /   %.2f s" % float(race.elapsed)
		elif race_state == "aborted":
			race_value.text = "RUN INVALID"
		else:
			race_value.text = "%+.2f G   /   %s" % [
				_longitudinal_g,"HANDBRAKE" if vehicle.handbrake > 0.15 else "LIVE"]
	else:
		race_value.text = "%+.2f G   /   %s" % [
			_longitudinal_g,"HANDBRAKE" if vehicle.handbrake > 0.15 else "LIVE"]
	model_label.text = "RACE / LIVE" if race_state == "running" else \
		"%d HP  /  %d LB-FT" % [
			roundi(vehicle.config.engine_power_kw*1.34102),
			roundi(vehicle.config.engine_torque_nm*0.73756)]
	queue_redraw()


func _draw() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.045,0.078,0.101,0.96)
	frame.border_color = Color("#385159")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(12)
	frame.set_content_margin_all(8)
	draw_style_box(frame, Rect2(Vector2.ZERO, SIZE))
	draw_line(Vector2(14,33),Vector2(576,33),Color("#304952"),1.0,true)
	draw_line(Vector2(355,41),Vector2(355,152),Color("#304952"),1.0,true)
	draw_line(Vector2(14,155),Vector2(576,155),Color("#304952"),1.0,true)
	_gauge(SPEED_CENTER,_speed_fraction,CYAN,false)
	_gauge(RPM_CENTER,_rpm_fraction,MINT,true)
	# Six restrained shift lights below the RPM arc, never over its digits.
	for i in range(6):
		var lit := _rpm_fraction >= (0.68 + float(i)*0.052)
		var color := ALERT if i >= 4 else (GOLD if i >= 2 else MINT)
		draw_circle(Vector2(181 + i*12,146),3.0,
			color if lit else Color("#263b42"))
	# All three short gauges fill from bottom to top.
	_vertical_meter(LOAD_METER_AT,boost_fraction,CYAN if boost_visible else MINT)
	_vertical_meter(THROTTLE_METER_AT,_throttle_fraction,MINT)
	_vertical_meter(BRAKE_METER_AT,_brake_fraction,GOLD)


func _vertical_meter(at: Vector2, fraction: float, color: Color) -> void:
	draw_rect(Rect2(at,METER_SIZE),Color("#253740"),true)
	var fill_height := METER_SIZE.y * clampf(fraction,0.0,1.0)
	if fill_height > 0.01:
		draw_rect(Rect2(Vector2(at.x,at.y+METER_SIZE.y-fill_height),
			Vector2(METER_SIZE.x,fill_height)),color,true)
	draw_rect(Rect2(at,METER_SIZE),Color("#48616a"),false,1.0)


func _gauge(center: Vector2, value: float, color: Color, tachometer: bool) -> void:
	draw_arc(center,GAUGE_RADIUS,ARC_START,ARC_END,52,Color("#293f48"),6.0,true)
	draw_arc(center,GAUGE_RADIUS,ARC_START,
		lerpf(ARC_START,ARC_END,clampf(value,0.0,1.0)),36,color,6.0,true)
	if tachometer:
		draw_arc(center,GAUGE_RADIUS+1,lerpf(ARC_START,ARC_END,0.88),
			ARC_END,14,ALERT,2.5,true)
	for i in range(13):
		var fraction := float(i)/12.0
		var angle := lerpf(ARC_START,ARC_END,fraction)
		var direction := Vector2(cos(angle),sin(angle))
		var tick_length := 8.0 if i%3 == 0 else 4.0
		draw_line(center+direction*(GAUGE_RADIUS-12),
			center+direction*(GAUGE_RADIUS-12+tick_length),
			ALERT if tachometer and fraction>=0.9 else MUTED,
			1.4 if i%3==0 else 1.0,true)
	var needle_angle := lerpf(ARC_START,ARC_END,clampf(value,0.0,1.0))
	var needle_dir := Vector2(cos(needle_angle),sin(needle_angle))
	draw_line(center+needle_dir*29.0,center+needle_dir*42.0,color,3.0,true)
