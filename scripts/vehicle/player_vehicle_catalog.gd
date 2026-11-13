class_name PlayerVehicleCatalog
extends RefCounted
## Explicit roster: Godot also includes these images in exported builds.
## Entries with source_model_unverified=true are provisional associations only.
const PendingAudio = preload("res://scripts/audio/pending_vehicle_audio.gd")
# Explicit dependency so Godot cold-start parsing never needs the global class cache.
const AppearanceProfileScript = preload("res://scripts/vehicle/vehicle_appearance_profile.gd")
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
	config.boost_max_psi = maxf(0.0,float(entry.get("boost_max_psi",0.0)))
	config.audio_sample_id = str(entry.get("id",""))
	config.audio_family = str(entry.get("audio_family","v8_cross"))
	config.audio_aggression = clampf(float(entry.get("audio_aggression",0.7)),0.0,1.4)
	config.audio_induction = str(entry.get("audio_induction","naturally_aspirated"))
	config.audio_flutter = clampf(float(entry.get("audio_flutter",0.0)),0.0,1.0)
	config.audio_exhaust_roughness = clampf(
		float(entry.get("audio_exhaust_roughness",0.4)),0.0,1.0)
	config.audio_tone = clampf(float(entry.get("audio_tone",0.0)),-1.0,1.0)
	config.audio_intake_presence = clampf(float(entry.get("audio_intake_presence",0.8)),0.0,1.5)
	config.audio_driveline_presence = clampf(float(entry.get("audio_driveline_presence",0.5)),0.0,1.5)
	config.audio_lope = clampf(float(entry.get("audio_lope",0.1)),0.0,1.0)
	config.audio_overrun = clampf(float(entry.get("audio_overrun",0.35)),0.0,1.0)
	config.audio_turbo_presence = clampf(float(entry.get("audio_turbo_presence",0.0)),0.0,1.5)
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
	# Future dealership entries can omit authored sound settings if their
	# audio profile was prepared from streetbound_vehicle_list.txt.
	# These fallbacks are AUDIO ONLY and cannot add cars to the roster.
	if not entry.has("audio_family"):
		PendingAudio.apply_to_config(config,str(entry.id))
	return config


## Optional calibration fields live with the actual vehicle, not shared
## across manufacturer textures. Reject out-of-body anchors safely.
static func _wheel_uv(entry: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var raw: Variant = entry.get(key, null)
	if not raw is Array or raw.size() != 2:
		return fallback
	if typeof(raw[0]) not in [TYPE_FLOAT, TYPE_INT] or \
			typeof(raw[1]) not in [TYPE_FLOAT, TYPE_INT]:
		return fallback
	var uv := Vector2(float(raw[0]), float(raw[1]))
	if not is_finite(uv.x) or not is_finite(uv.y) or \
			uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return fallback
	return uv



static func _temporary_unverified_body() -> Texture2D:
	# Several catalog entries reference art that was never committed. Draw a
	# neutral, clearly provisional top-down shape rather than loading an
	# unavailable path or silently displaying another manufacturer's vehicle.
	var image := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.fill_rect(Rect2i(14, 6, 36, 116), Color(0.29, 0.33, 0.39, 1.0))
	image.fill_rect(Rect2i(18, 27, 28, 25), Color(0.13, 0.20, 0.28, 1.0))
	image.fill_rect(Rect2i(18, 77, 28, 19), Color(0.13, 0.20, 0.28, 1.0))
	image.fill_rect(Rect2i(15, 9, 34, 5), Color(0.53, 0.57, 0.61, 1.0))
	image.fill_rect(Rect2i(15, 115, 34, 5), Color(0.43, 0.09, 0.08, 1.0))
	return ImageTexture.create_from_image(image)


static func select(player: VehicleController2D, entry: Dictionary) -> bool:
	if entry.is_empty() or not is_instance_valid(player):
		return false
	var path := str(entry.get("texture", ""))
	# Avoid calling load() on a non-existent asset: on Godot 4.6 it logs a
	# resource ERROR even if the caller handles null, breaking render CI.
	var texture: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path, "Texture2D"):
		texture = load(path) as Texture2D
	if texture == null:
		push_warning("Using provisional silhouette for missing artwork: " + path)
		texture = _temporary_unverified_body()
	var image: Image = texture.get_image()
	var rect := alpha_bounds(image)
	if rect.size.x < 4 or rect.size.y < 4:
		return false
	# Source orientation and facing can be explicitly calibrated per car.
	# Never infer the front from the silhouette: a wide PNG can be a
	# landscape canvas, and identical proportions can face either way.
	var sideways: bool = bool(entry.get("sprite_sideways",
		rect.size.x > rect.size.y * 1.08))
	var src_width := float(rect.size.y if sideways else rect.size.x)
	var src_length := float(rect.size.x if sideways else rect.size.y)
	# Sources come from different generations and were cropped at different
	# proportions. Fit width and length independently so the on-screen car,
	# wheel anchors and physical measurements describe the same footprint.
	var width_scale := float(entry.width_m) * PPM / src_width
	var length_scale := float(entry.length_m) * PPM / src_length
	var sprite_scale := Vector2(length_scale, width_scale) if sideways else \
		Vector2(width_scale, length_scale)
	# Source vehicle sprites face toward +Y (down). The driving chassis faces
	# -Y (up), so turn the body 180 degrees by default. Preserve explicitly
	# calibrated angles (and the horizontal-art fallback) for exceptions.
	var angle: float = deg_to_rad(float(entry.get("sprite_rotation_degrees",
		90.0 if sideways else 180.0)))
	var source_mid := Vector2(rect.get_center()) - Vector2(image.get_size()) * 0.5
	var appearance: AppearanceProfileScript = AppearanceProfileScript.new()
	appearance.body_texture = texture
	appearance.sprite_scale = sprite_scale
	appearance.sprite_rotation_degrees = rad_to_deg(angle)
	appearance.sprite_offset = -Vector2(
		source_mid.x * sprite_scale.x, source_mid.y * sprite_scale.y).rotated(angle)
	# Front/rear axle spacing follows the modeled wheelbase, not a generic
	# compact-car UV preset. Keep axle centers slightly inset from body edges.
	var axle_fraction := clampf(float(entry.wheelbase_m) /
		maxf(0.1, float(entry.length_m)), 0.45, 0.78)
	var front_uv := 0.5 - axle_fraction * 0.5
	var rear_uv := 0.5 + axle_fraction * 0.5
	# Individual wheel hub positions can be calibrated using normalized
	# visible-body coordinates, independently of PNG resolution.
	appearance.front_left_uv = _wheel_uv(entry, "front_left_uv",
		Vector2(0.075, front_uv))
	appearance.front_right_uv = _wheel_uv(entry, "front_right_uv",
		Vector2(0.925, front_uv))
	appearance.rear_left_uv = _wheel_uv(entry, "rear_left_uv",
		Vector2(0.075, rear_uv))
	appearance.rear_right_uv = _wheel_uv(entry, "rear_right_uv",
		Vector2(0.925, rear_uv))
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
