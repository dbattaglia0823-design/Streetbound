extends SceneTree
## Exercise real physics-backed instruments and layout in Morrow Coast,
## including boost-equipped and naturally aspirated model swaps.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Imperial = preload("res://scripts/ui/imperial_units.gd")
const DashboardScript = preload("res://scripts/ui/vehicle_dashboard.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",name,detail])
	if not passed:
		failures.append(name)


# On Godot 4.4's headless fallback font, Label.get_rect() can report
# three times the font height while the glyph ink remains around one em.
# Compare conservative drawn single-line text regions, not font line metrics.
func _text_ink_rect(item: Label) -> Rect2:
	var approximate_line_height := float(item.get_theme_font_size("font_size")) * 1.42
	return Rect2(item.position,Vector2(item.size.x,
		minf(item.size.y,approximate_line_height)))


func run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var car: VehicleController2D = game.vehicle
	car.set_physics_process(false)
	var hud: CanvasLayer
	for child in game.get_children():
		if child is CanvasLayer and child.get_script() == load(
				"res://scripts/ui/driving_hud.gd"):
			hud = child
	check("driving_hud_present",hud != null)
	if hud == null:
		quit(1)
		return
	var dash: Control = hud.dashboard
	check("dashboard_created_as_bottom_corner_cluster",dash != null and \
		dash.name == "LiveVehicleDashboard")
	check("speed_and_gear_labels_are_live_dashboard_controls",
		hud.speed_label == dash.speed_label and hud.gear_label == dash.gear_label)
	check("engineering_readout_is_moved_into_f1",
		hud.tuning.is_ancestor_of(hud.telemetry))
	var viewport_size := dash.get_viewport_rect().size
	check("dash_fits_inside_visible_game_window",
		dash.position.x >= 0.0 and dash.position.y >= 0.0 and \
		dash.position.x + dash.size.x * dash.scale.x <= viewport_size.x + 1.0 and \
		dash.position.y + dash.size.y * dash.scale.y <= viewport_size.y + 1.0)
	check("dashboard_is_substantially_smaller", dash.size.x <= 600.0 and
		dash.size.y <= 190.0, dash.size)
	check("rpm_uses_arc_instead_of_duplicate_horizontal_bar",
		dash.rpm_bar != null and not dash.rpm_bar.visible)
	var labels: Array[Label] = []
	for child in dash.get_children():
		if child is Label and child.visible:
			labels.append(child as Label)
	var collisions: Array[String] = []
	for i in labels.size():
		for j in range(i+1,labels.size()):
			if _text_ink_rect(labels[i]).intersects(_text_ink_rect(labels[j])):
				collisions.append("%s %s / %s %s" % [labels[i].text,
					_text_ink_rect(labels[i]),labels[j].text,
					_text_ink_rect(labels[j])])
	check("dashboard_label_rects_never_overlap",collisions.is_empty(),collisions)
	var inflated_font_rows_top_aligned := true
	for label in labels:
		if label.size.y > float(label.get_theme_font_size("font_size")) * 2.0:
			inflated_font_rows_top_aligned = inflated_font_rows_top_aligned and \
				label.vertical_alignment == VERTICAL_ALIGNMENT_TOP
	check("oversized_headless_font_controls_keep_text_in_its_row",
		inflated_font_rows_top_aligned)
	var meter_size: Vector2 = DashboardScript.METER_SIZE
	var vertical := meter_size.y > meter_size.x * 3.0 and meter_size.y < 70.0
	var tracks: Array[Rect2] = [
		Rect2(DashboardScript.LOAD_METER_AT,meter_size),
		Rect2(DashboardScript.THROTTLE_METER_AT,meter_size),
		Rect2(DashboardScript.BRAKE_METER_AT,meter_size)
	]
	var clear_tracks := true
	for track in tracks:
		clear_tracks = clear_tracks and Rect2(Vector2.ZERO,dash.size).encloses(track)
		for item in labels:
			clear_tracks = clear_tracks and not _text_ink_rect(item).intersects(track)
	check("three_small_vertical_bars_avoid_all_text",
		vertical and clear_tracks,[tracks,clear_tracks])
	var smaller_windows_fit := true
	for sample in [Vector2(1280,800),Vector2(960,540),Vector2(640,360),Vector2(360,240)]:
		var scale_factor: float = dash._layout_factor_for(sample)
		smaller_windows_fit = smaller_windows_fit and \
			16.0+dash.size.x*scale_factor <= sample.x and \
			dash.size.y*scale_factor+20.0 <= sample.y
	check("compact_dashboard_remains_inside_smaller_viewports",smaller_windows_fit)
	car.linear_velocity = Vector2.UP * 30.0
	car.longitudinal_speed = 30.0
	car.lateral_speed = 2.3
	car.transmission.rpm = 6700.0
	car.transmission.gear = 3
	car.transmission.automatic = false
	car.throttle = 0.72
	car.brake = 0.25
	car.wheel_spin = 0.24
	car.slip_angle = deg_to_rad(15.0)
	hud._process(0.0)
	check("dash_reads_actual_mph",
		dash.speed_label.text == "%03d" % roundi(Imperial.speed_mph(30.0)))
	check("dash_reads_actual_rpm_and_shift_lights",
		dash.rpm_label.text == "6700" and \
		absf(dash.rpm_bar.value - 6700.0 / car.config.redline_rpm * 100.0) < 0.1)
	check("dash_reads_manual_gear",
		dash.gear_label.text == "3" and dash.mode_label.text == "MAN")
	check("dash_reads_throttle_and_brake",
		dash.throttle_value.text == "72%" and dash.brake_value.text == "25%")
	check("dash_warns_on_actual_wheelspin_and_slip",
		dash.tire_value.text.contains("24%") and \
		dash.tire_value.text.contains("15°"))
	check("engine_stats_come_from_current_car",
		dash.model_label.text.contains("HP") and \
		dash.model_label.text.contains("LB-FT"))
	check("f1_stats_readout_stays_valid",
		hud.telemetry.text.contains("POWER ") and \
		hud.telemetry.text.contains("TORQUE ") and \
		hud.telemetry.text.contains(" lb-ft") and \
		hud.telemetry.text.contains("WEIGHT "))
	var na: Dictionary = Catalog.find_by_id("ford-fiesta")
	check("ordinary_stock_engine_has_no_turbo_calibration",
		float(na.get("boost_max_psi",0.0)) == 0.0)
	check("boost_hides_for_naturally_aspirated_engine",
		not bool(dash.boost_visible) and dash.boost_label.text == "LOAD")
	# Test the actual pressure model using an isolated, unobstructed car.
	var stand: VehicleController2D = load("res://scenes/vehicle.tscn").instantiate()
	root.add_child(stand)
	stand.set_physics_process(false)
	stand.external_input = true
	var boosted: Dictionary = Catalog.find_by_id("bmw-m3")
	check("turbo_model_has_positive_calibration",
		float(boosted.get("boost_max_psi",0.0)) > 0.0)
	check("turbo_model_can_be_equipped",Catalog.select(stand,boosted))
	stand.linear_velocity = Vector2.UP * 20.0
	for i in range(35):
		stand.step_vehicle(0.025,Vector4(1.0,0.0,0.0,0.0))
	check("boost_grows_under_load",
		stand.boost_psi > 1.0 and stand.boost_psi <= stand.config.boost_max_psi + 0.01,
		stand.boost_psi)
	var loaded_boost := stand.boost_psi
	for i in range(25):
		stand.step_vehicle(0.025,Vector4.ZERO)
	check("boost_bleeds_off_after_throttle_lift",
		stand.boost_psi < loaded_boost * 0.25,stand.boost_psi)
	# Validate a real equipped turbo car displays its actual live reading.
	check("catalog_selects_turbo_car_into_live_hud",
		Catalog.select(car,boosted))
	hud.on_vehicle_selected(boosted)
	car.boost_psi = 9.2
	car.throttle = 0.65
	hud._process(0.0)
	check("turbo_instruments_enabled_after_car_swap",
		dash.boost_visible and dash.boost_label.text == "BOOST" and \
		dash.boost_value.text == "9.2 PSI")
	check("boost_follows_physical_charge_pressure",
		absf(dash.boost_fraction - 9.2 / car.config.boost_max_psi) < 0.001)
	check("switching_back_clears_optional_turbo_gauge",
		Catalog.select(car,na))
	hud.on_vehicle_selected(na)
	hud._process(0.0)
	check("non_turbo_does_not_retain_old_boost",
		not dash.boost_visible and car.boost_psi == 0.0 and \
		dash.boost_label.text == "LOAD")
	car.reversing = true
	car.transmission.automatic = true
	hud._process(0.0)
	check("reverse_gear_is_identified",dash.gear_label.text == "R" and \
		dash.mode_label.text == "AUTO")
	# Existing race coordinator is the source of timing and distance.
	var race: Node2D = game.drag_race
	race.set_physics_process(false)
	race.state = "running"
	race.elapsed = 9.5
	race.progress_m = 184.0
	hud._process(0.0)
	check("dashboard_timing_reads_real_quarter_mile_state",
		dash.race_value.text.contains("9.50 s") and \
		dash.race_value.text.contains("184 m"))
	race.state = "results"
	race.elapsed = 12.345
	hud._process(0.0)
	check("finished_race_stays_on_instrument_cluster",
		dash.race_value.text.contains("FINISH") and \
		dash.race_value.text.contains("12.35"))
	print("LIVE DRIVING DASHBOARD: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
