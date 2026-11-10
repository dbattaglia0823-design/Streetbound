extends Control
## Purpose-built vehicle instrumentation. All readings come from actual vehicle
## physics; no fabricated oil/fuel/temperature data. Optional turbo models use
## the controller's modeled charge pressure.
const Imperial = preload("res://scripts/ui/imperial_units.gd")
const SIZE := Vector2(810.0,238.0)
const SPEED_CENTER := Vector2(119,132)
const RPM_CENTER := Vector2(348,132)
const GAUGE_RADIUS := 77.0
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
	node.size = dimensions
	node.custom_minimum_size = dimensions
	node.text = value
	node.horizontal_alignment = alignment
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.clip_text = true
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	add_child(node)
	return node


func _build_labels() -> void:
	_label("LIVE  /  STREETBOUND",Vector2(20,11),Vector2(233,29),14,GOLD)
	model_label = _label("VEHICLE",Vector2(465,11),Vector2(326,29),12,LIGHT,HORIZONTAL_ALIGNMENT_RIGHT)
	speed_label = _label("000",Vector2(57,103),Vector2(124,61),48,LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
	speed_unit_label = _label("MPH",Vector2(89,158),Vector2(61,22),12,CYAN,HORIZONTAL_ALIGNMENT_CENTER)
	rpm_label = _label("0950",Vector2(287,109),Vector2(121,51),37,LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
	_label("RPM",Vector2(325,158),Vector2(55,22),12,MINT,HORIZONTAL_ALIGNMENT_CENTER)
	_label("GEAR",Vector2(220,81),Vector2(50,23),11,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	gear_label = _label("1",Vector2(215,101),Vector2(58,52),37,LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
	mode_label = _label("AUTO",Vector2(213,151),Vector2(61,22),10,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
	boost_label = _label("ENGINE LOAD",Vector2(488,54),Vector2(180,23),12,MUTED)
	boost_value = _label("0%",Vector2(666,49),Vector2(112,35),23,LIGHT,HORIZONTAL_ALIGNMENT_RIGHT)
	_label("THROTTLE",Vector2(488,101),Vector2(153,18),11,MUTED)
	throttle_value = _label("0%",Vector2(698,101),Vector2(78,18),12,LIGHT,HORIZONTAL_ALIGNMENT_RIGHT)
	_label("BRAKE",Vector2(488,139),Vector2(153,18),11,MUTED)
	brake_value = _label("0%",Vector2(698,139),Vector2(78,18),12,LIGHT,HORIZONTAL_ALIGNMENT_RIGHT)
	tire_value = _label("TIRES / GRIP",Vector2(488,177),Vector2(288,19),12,LIGHT)
	surface_value = _label("ASPHALT",Vector2(22,207),Vector2(435,19),11,MUTED)
	race_value = _label("0.00 G",Vector2(489,207),Vector2(285,20),12,GOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	rpm_bar = ProgressBar.new()
	rpm_bar.name = "RPMBar"
	rpm_bar.position = Vector2(285,192)
	rpm_bar.size = Vector2(126,5)
	rpm_bar.max_value = 100.0
	rpm_bar.show_percentage = false
	rpm_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rpm_bar)


func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	var factor := minf(1.0,minf((viewport_size.x - 25.0)/SIZE.x,
		(viewport_size.y - 30.0)/560.0))
	factor = maxf(0.35,factor)
	scale = Vector2.ONE * factor
	position = Vector2(20.0,viewport_size.y - SIZE.y * factor - 16.0)


func _refresh_vehicle_configuration() -> void:
	if not is_instance_valid(vehicle) or vehicle.config == null:
		return
	_last_car_config = vehicle.config
	boost_visible = vehicle.config.boost_max_psi > 0.05
	# Scale the speed dial with the rated vehicle power, not current speed.
	_speed_max_mph = clampf(ceilf(sqrt(vehicle.config.engine_power_kw/130.0)*4.5)*20.0,
		140.0,360.0)
	boost_label.text = "BOOST PRESSURE" if boost_visible else "ENGINE LOAD"
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
	tire_value.text = "WHEELSPIN %d%%   /   SLIP %.0f°" % [
		roundi(vehicle.wheel_spin*100.0),absf(rad_to_deg(vehicle.slip_angle))]
	tire_value.add_theme_color_override("font_color",grip_color)
	surface_value.text = "%s   /   GRIP %.2f   /   %s" % [
		vehicle.surface,vehicle.config.tire_grip*vehicle.surface_grip,
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
	model_label.text = "RACING  /  LIVE TELEMETRY" if race_state == "running" else \
		"ENGINE  /  %d HP  /  %d LB-FT" % [
			roundi(vehicle.config.engine_power_kw*1.34102),
			roundi(vehicle.config.engine_torque_nm*0.73756)]
	queue_redraw()


func _draw() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.045,0.078,0.101,0.96)
	frame.border_color = Color("#385159")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(16)
	frame.set_content_margin_all(10)
	draw_style_box(frame,Rect2(Vector2.ZERO,SIZE))
	draw_line(Vector2(19,44),Vector2(792,44),Color("#304952"),1.0,true)
	draw_line(Vector2(465,50),Vector2(465,198),Color("#304952"),1.0,true)
	draw_line(Vector2(19,200),Vector2(790,200),Color("#304952"),1.0,true)
	_gauge(SPEED_CENTER,_speed_fraction,CYAN,false)
	_gauge(RPM_CENTER,_rpm_fraction,MINT,true)
	# Shift lights use the real RPM/redline ratio; amber -> red near limiter.
	for i in range(7):
		var lit := _rpm_fraction >= (0.63 + float(i)*0.052)
		var color := ALERT if i >= 5 else (GOLD if i >= 3 else MINT)
		draw_circle(Vector2(288 + i*20,52),5.0,
			color if lit else Color("#263b42"))
	# Right-hand bar instrumentation
	_meter(Vector2(489,84),Vector2(286,7),boost_fraction,CYAN if boost_visible else MINT)
	_meter(Vector2(489,124),Vector2(286,7),_throttle_fraction,MINT)
	_meter(Vector2(489,162),Vector2(286,7),_brake_fraction,GOLD)
	# Engine redline zone stays visible even when revs are low.
	draw_rect(Rect2(Vector2(285,192),Vector2(126,5)),Color("#253b42"),false,1.0)


func _meter(at: Vector2, dimensions: Vector2, fraction: float, color: Color) -> void:
	draw_rect(Rect2(at,dimensions),Color("#253740"),true)
	if fraction > 0.001:
		draw_rect(Rect2(at,Vector2(dimensions.x*clampf(fraction,0,1),dimensions.y)),
			color,true)


func _gauge(center: Vector2, value: float, color: Color, tachometer: bool) -> void:
	draw_arc(center,GAUGE_RADIUS,ARC_START,ARC_END,64,Color("#293f48"),8.0,true)
	draw_arc(center,GAUGE_RADIUS,ARC_START,
		lerpf(ARC_START,ARC_END,clampf(value,0.0,1.0)),40,color,8.0,true)
	if tachometer:
		draw_arc(center,GAUGE_RADIUS+1,lerpf(ARC_START,ARC_END,0.88),
			ARC_END,18,ALERT,3.0,true)
	for i in range(13):
		var fraction := float(i)/12.0
		var angle := lerpf(ARC_START,ARC_END,fraction)
		var direction := Vector2(cos(angle),sin(angle))
		var length := 11.0 if i%3 == 0 else 6.0
		draw_line(center+direction*(GAUGE_RADIUS-16),
			center+direction*(GAUGE_RADIUS-16+length),
			ALERT if tachometer and fraction>=0.9 else MUTED,
			2.0 if i%3==0 else 1.0,true)
	var needle_angle := lerpf(ARC_START,ARC_END,clampf(value,0,1))
	var needle_dir := Vector2(cos(needle_angle),sin(needle_angle))
	draw_line(center+needle_dir*50.0,center+needle_dir*65.0,color,4.0,true)
	var maximum := vehicle.config.redline_rpm/1000.0 if tachometer else _speed_max_mph
	var text := "%d" % roundi(maximum) if not tachometer else "%.1f" % maximum
	draw_string(ThemeDB.fallback_font,center+Vector2(39,61),text,
		HORIZONTAL_ALIGNMENT_LEFT,45,11,MUTED)
