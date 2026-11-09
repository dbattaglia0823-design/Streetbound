class_name VehicleAppearanceProfile
extends Resource
## Per-model visual data. Wheel anchors are fractions of the *visible* sprite
## silhouette (not its transparent PNG canvas), so art resolution is irrelevant.
## Car physics and collision use separate VehicleConfig and CollisionShape2D.
@export_group("Body artwork")
@export var body_texture: Texture2D
@export var sprite_scale := Vector2(0.054, 0.054)
@export_range(-180.0, 180.0, 1.0) var sprite_rotation_degrees := 180.0
@export var sprite_offset := Vector2.ZERO

@export_group("Axle centers in silhouette UV")
@export var front_left_uv := Vector2(0.04, 0.255)
@export var front_right_uv := Vector2(0.96, 0.255)
@export var rear_left_uv := Vector2(0.04, 0.755)
@export var rear_right_uv := Vector2(0.96, 0.755)

@export_group("Tire dimensions")
@export_range(0.05, 0.5, 0.005) var tire_width_ratio := 0.21
@export_range(0.05, 0.5, 0.005) var tire_length_ratio := 0.235
@export var minimum_tire_px := Vector2(8.0, 16.0)
@export var maximum_tire_px := Vector2(15.0, 26.0)

@export_group("Steering animation (visual only)")
@export_range(0.5, 2.0, 0.05) var steer_multiplier := 1.35
@export_range(10.0, 45.0, 1.0) var max_visual_steer_degrees := 38.0
@export_range(5.0, 40.0, 1.0) var steer_animation_speed := 20.0
