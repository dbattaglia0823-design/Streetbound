class_name PlayerVehicleCatalog
extends RefCounted
## Explicit roster: Godot also includes these images in exported builds.
## Entries with source_model_unverified=true are provisional associations only.
const CATALOG_PATH := "res://data/player_vehicle_catalog.json"
const PPM := 20.0
static var _vehicles: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if not _vehicles.is_empty():
		return _vehicles
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("Player vehicle catalog missing or malformed")
		return _vehicles
	for value in parsed.get("vehicles", []):
		if value is Dictionary:
			_vehicles.append(value)
	return _vehicles


static func find_by_id(id: String) -> Dictionary:
	for entry in all():
		if str(entry.id) == id:
			return entry
	return {}


static func alpha_bounds(image: Image) -> Rect2i:
	if image == null or image.is_empty():
		return Rect2i()
	var dim := image.get_size()
	var stride := maxi(2, ceili(float(maxi(dim.x, dim.y)) / 280.0))
	var left := dim.x
	var top := dim.y
	var right := -1
	var bottom := -1
	for y in range(0, dim.y, stride):
		for x in range(0, dim.x, stride):
			if image.get_pixel(x, y).a < 0.20:
				continue
			left = mini(left, x)
			top = mini(top, y)
			right = maxi(right, x)
			bottom = maxi(bottom, y)
	if right < left:
		return image.get_used_rect()
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


static func make_configuration(entry: Dictionary) -> VehicleConfig:
	# A fresh baseline prevents an F1 tune or the previous car's stats from
	# accidentally carrying over to the next model.
	var stock: VehicleConfig = load("res://resources/sport_coupe.tres") as VehicleConfig
	var config := stock.duplicate(true) as VehicleConfig
	config.mass_kg = float(entry.mass_kg)
	config.engine_torque_nm = float(entry.torque_nm)
	config.engine_power_kw = float(entry.power_kw)
	config.wheelbase_m = float(entry.wheelbase_m)
	config.brake_force_n = float(entry.brake_force_n)
	config.tire_grip = float(entry.tire_grip)
	config.drag_area = float(entry.width_m) * 0.38
	config.drivetrain = {"FWD": VehicleConfig.Drivetrain.FWD,
		"RWD": VehicleConfig.Drivetrain.RWD,
		"AWD": VehicleConfig.Drivetrain.AWD}.get(str(entry.drivetrain),
		VehicleConfig.Drivetrain.RWD)
	match str(entry.kind):
		"truck", "suv":
			config.max_steer_degrees = 29.0
			config.high_speed_steer_degrees = 7.0
			config.rear_grip_balance = 1.06
			config.yaw_damping = 1.6
			config.engine_torque_nm *= 1.05
		"compact":
			config.max_steer_degrees = 38.0
			config.high_speed_steer_degrees = 11.0
			config.yaw_damping = 1.35
		"hyper":
			config.max_steer_degrees = 29.0
			config.high_speed_steer_degrees = 8.0
			config.rear_grip_balance = 1.20
			config.brake_force_n *= 1.12
		"sport":
			config.max_steer_degrees = 33.0
			config.high_speed_steer_degrees = 10.5
			config.rear_grip_balance = 1.16
		_:
			config.max_steer_degrees = 33.0
			config.high_speed_steer_degrees = 9.0
	# Keep driven tire size and acceleration consistent with vehicle class.
	config.wheel_radius_m = 0.37 if str(entry.kind) in ["truck", "suv"] else 0.34
	config.cornering_stiffness = 68000.0 * config.mass_kg / 1450.0
	return config


static func select(player: VehicleController2D, entry: Dictionary) -> bool:
	if entry.is_empty() or not is_instance_valid(player):
		return false
	var path := str(entry.get("texture", ""))
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		push_warning("Missing player vehicle artwork: " + path)
		return false
	var image: Image = texture.get_image()
	var rect := alpha_bounds(image)
	if rect.size.x < 4 or rect.size.y < 4:
		return false
	var sideways := rect.size.x > rect.size.y * 1.08
	var src_width := float(rect.size.y if sideways else rect.size.x)
	var src_length := float(rect.size.x if sideways else rect.size.y)
	# Sources come from different generations and were cropped at different
	# proportions. Fit width and length independently so the on-screen car,
	# wheel anchors and physical measurements describe the same footprint.
	var width_scale := float(entry.width_m) * PPM / src_width
	var length_scale := float(entry.length_m) * PPM / src_length
	var sprite_scale := Vector2(length_scale, width_scale) if sideways else \
		Vector2(width_scale, length_scale)
	var angle := -PI * 0.5 if sideways else 0.0
	var source_mid := Vector2(rect.get_center()) - Vector2(image.get_size()) * 0.5
	var appearance := VehicleAppearanceProfile.new()
	appearance.body_texture = texture
	appearance.sprite_scale = sprite_scale
	appearance.sprite_rotation_degrees = rad_to_deg(angle)
	appearance.sprite_offset = -Vector2(
		source_mid.x * sprite_scale.x, source_mid.y * sprite_scale.y).rotated(angle)
	appearance.front_left_uv = Vector2(0.055, 0.245)
	appearance.front_right_uv = Vector2(0.945, 0.245)
	appearance.rear_left_uv = Vector2(0.055, 0.755)
	appearance.rear_right_uv = Vector2(0.945, 0.755)
	appearance.tire_width_ratio = 0.18
	appearance.tire_length_ratio = 0.22
	appearance.minimum_tire_px = Vector2(8.0, 14.0)
	appearance.maximum_tire_px = Vector2(19.0, 32.0)
	var wheels := player.get_node_or_null("Art/Wheels")
	if wheels == null:
		return false
	var old_position := player.global_transform
	player.config = make_configuration(entry)
	player.reset_vehicle()
	player.global_transform = old_position
	wheels.apply_appearance(appearance)
	var collider := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collider != null:
		# Avoid changing the shared scene subresource in other instances.
		var shape := CapsuleShape2D.new()
		shape.radius = float(entry.width_m) * PPM * 0.425
		shape.height = maxf(shape.radius * 2.05, float(entry.length_m) * PPM * 0.88)
		collider.shape = shape
	player.reset_physics_interpolation()
	return true
