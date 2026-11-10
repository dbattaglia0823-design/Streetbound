extends RefCounted
## A single data source for the garage grid and actual player-car physics.
## The catalog contains representative trim-independent game balance values.
const PIXELS_PER_METER := 20.0
const DATA_FILE := "res://resources/vehicles/catalog.json"
const BASE_CONFIG = preload("res://resources/sport_coupe.tres")
static var _entries: Array[Dictionary] = []
static var _loaded := false
static var _bounds: Dictionary = {}


static func all_vehicles() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true
		if not FileAccess.file_exists(DATA_FILE):
			push_error("Vehicle roster missing: " + DATA_FILE)
			return _entries
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
		if not data is Dictionary or not data.get("vehicles", null) is Array:
			push_error("Invalid Streetbound vehicle roster JSON.")
			return _entries
		for raw in data.vehicles:
			if raw is Dictionary and raw.has("id") and raw.has("texture"):
				_entries.append(raw)
	return _entries


static func find_vehicle(vehicle_id: String) -> Dictionary:
	for entry in all_vehicles():
		if str(entry.id) == vehicle_id:
			return entry
	return {}


static func drivetrain_for(label: String) -> VehicleConfig.Drivetrain:
	match label:
		"FWD": return VehicleConfig.Drivetrain.FWD
		"AWD": return VehicleConfig.Drivetrain.AWD
	return VehicleConfig.Drivetrain.RWD


static func build_config(entry: Dictionary) -> VehicleConfig:
	var config: VehicleConfig = BASE_CONFIG.duplicate(true) as VehicleConfig
	var body := str(entry.get("body", "sedan"))
	var mass := clampf(float(entry.get("mass_kg", 1450.0)), 700.0, 3500.0)
	config.mass_kg = mass
	config.engine_power_kw = clampf(float(entry.get("engine_power_kw", 200.0)), 45.0, 1600.0)
	config.engine_torque_nm = clampf(float(entry.get("engine_torque_nm", 300.0)), 70.0, 2000.0)
	config.wheelbase_m = clampf(float(entry.get("wheelbase_m", 2.7)), 2.15, 4.0)
	config.drivetrain = drivetrain_for(str(entry.get("drivetrain", "RWD")))
	config.tire_grip = clampf(float(entry.get("tire_grip", 1.2)), 0.8, 1.95)
	config.brake_force_n = maxf(mass * 8.0, float(entry.get("brake_force_n", 18000.0)))
	config.handbrake_force_n = mass * 3.6
	config.cornering_stiffness = mass * (69.0 if body in ["hyper", "exotic", "sport"] else 61.0)
	config.rear_grip_balance = 1.12 if body in ["sport", "exotic", "hyper"] else 1.04
	config.arcade_steering_assist = 0.76 if body in ["hyper", "exotic", "sport"] else 0.72
	config.arcade_cornering_accel = 31.0 if body in ["exotic", "hyper"] else 26.0
	config.yaw_damping = 1.55 if body in ["truck", "suv"] else 1.32
	config.front_weight = 0.58 if config.drivetrain == VehicleConfig.Drivetrain.FWD else \
		0.48 if body in ["suv", "truck"] else 0.43
	config.max_steer_degrees = clampf(float(entry.get("steer_degrees", 40.0)), 27.0, 50.0)
	config.high_speed_steer_degrees = 12.0 if body in ["truck", "suv"] else 14.0
	config.steering_response = 10.5 if body in ["truck", "suv"] else 12.5
	config.wheel_radius_m = 0.41 if body in ["truck", "suv"] else 0.34 if body in ["sedan", "hatch"] else 0.35
	config.drag_area = float(entry.get("width_m", 1.9)) * (0.52 if body in ["suv", "truck"] else 0.38)
	config.redline_rpm = 8900.0 if body in ["exotic", "hyper"] else 7800.0 if body == "sport" else 6700.0
	config.gear_ratios = PackedFloat32Array([3.50, 2.31, 1.64, 1.29, 1.00, 0.80])
	config.final_drive = 3.4 if body in ["hyper", "exotic"] else 3.7
	return config


static func texture_bounds(texture: Texture2D, key: String) -> Rect2i:
	if _bounds.has(key):
		return _bounds[key]
	var img: Image = texture.get_image()
	if img == null or img.is_empty():
		return Rect2i()
	var w := img.get_width()
	var h := img.get_height()
	var stride := maxi(2, ceili(float(maxi(w, h)) / 320.0))
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(0, h, stride):
		for x in range(0, w, stride):
			if img.get_pixel(x, y).a <= 0.17:
				continue
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
	var result := Rect2i(0, 0, w, h) if x1 < 0 else \
		Rect2i(x0, y0, maxi(1, x1 - x0 + stride), maxi(1, y1 - y0 + stride))
	_bounds[key] = result
	return result


static func build_appearance(entry: Dictionary) -> VehicleAppearanceProfile:
	var path := str(entry.texture)
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		push_warning("Vehicle artwork is missing: " + path)
		return null
	var rect := texture_bounds(texture, path)
	var image_size := Vector2(texture.get_width(), texture.get_height())
	var size := Vector2(rect.size)
	if size.x < 4.0 or size.y < 4.0:
		return null
	var profile := VehicleAppearanceProfile.new()
	profile.body_texture = texture
	var angle := float(entry.get("image_rotation_degrees", 180.0))
	var quarter_turn := absi(roundi(angle / 90.0)) % 2 == 1
	var target := Vector2(float(entry.get("width_m", 1.9)),
		float(entry.get("length_m", 4.7))) * PIXELS_PER_METER
	# Scale the visible alpha silhouette to its own authored dimensions,
	# not the generous transparent image canvas. Support rotated artwork.
	profile.sprite_scale = Vector2(
		(target.y if quarter_turn else target.x) / size.x,
		(target.x if quarter_turn else target.y) / size.y)
	profile.sprite_rotation_degrees = angle
	var offset_source := Vector2(rect.position) + size * 0.5 - image_size * 0.5
	profile.sprite_offset = -(offset_source * profile.sprite_scale).rotated(deg_to_rad(angle))
	var axle_fraction := clampf(float(entry.get("wheelbase_m", 2.7)) /
		maxf(2.5, float(entry.get("length_m", 4.7))), 0.45, 0.79)
	var front := 0.5 - axle_fraction * 0.5
	var rear := 0.5 + axle_fraction * 0.5
	var body := str(entry.get("body", "sedan"))
	var tire_x := 0.06 if body in ["sport", "exotic", "hyper"] else 0.08
	profile.front_left_uv = Vector2(tire_x, front)
	profile.front_right_uv = Vector2(1.0 - tire_x, front)
	profile.rear_left_uv = Vector2(tire_x, rear)
	profile.rear_right_uv = Vector2(1.0 - tire_x, rear)
	profile.tire_width_ratio = 0.22 if body in ["sport", "exotic", "hyper"] else 0.25
	profile.tire_length_ratio = 0.23 if body in ["suv", "truck"] else 0.20
	profile.minimum_tire_px = Vector2(8.0, 14.0)
	profile.maximum_tire_px = Vector2(18.0, 28.0)
	return profile
