extends CharacterBody2D
class_name StreetboundCar

## Arcade-realistic 2D bicycle-inspired vehicle, with explicit SI-to-pixel scaling.
## All inputs are passed to advance_physics() for repeatable testing and future AI/touch.
## Forward is negative Y. CharacterBody2D handles collisions after the physics step.

@export_group("Vehicle")
@export_range(500,4000,10) var mass_kg: float = 1510.0
@export_range(2,32,0.5) var pixels_per_meter: float = 8.0
@export_range(1.5,4,0.05) var wheelbase_m: float = 2.46
@export var vehicle_length_m: float = 4.63
@export var vehicle_width_m: float = 1.95
@export var visual_length_m: float = 4.95
@export_range(-180,180,1) var sprite_heading_offset_deg: float = 0.0
@export_group("Acceleration and braking")
@export var power_kw: float = 300.0
@export var maximum_speed_kph: float = 270.0
@export var maximum_reverse_kph: float = 34.0
@export var max_acceleration_mps2: float = 8.0
@export var reverse_acceleration_mps2: float = 3.2
@export var brake_deceleration_mps2: float = 12.0
@export var handbrake_deceleration_mps2: float = 5.0
@export var drag_area_m2: float = 0.72
@export var rolling_resistance: float = 0.015
@export_group("Steering and grip")
@export var low_speed_steer_deg: float = 34.0
@export var high_speed_steer_deg: float = 10.0
@export var steering_fade_kph: float = 160.0
@export var steer_response_deg_per_sec: float = 230.0
@export var normal_lateral_grip: float = 11.5
@export var handbrake_lateral_grip: float = 1.4
@export var max_lateral_acceleration_mps2: float = 9.3

var steer_angle: float = 0.0
var surface: String = "asphalt"
var surface_grip: float = 1.0
var world_query: Node
var _surface_timer: float = 0.0
var _spawn: Vector2
var _spawn_heading: float = 0.0

func _ready() -> void:
    motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
    var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
    if shape_node != null and shape_node.shape is RectangleShape2D:
        shape_node.shape = shape_node.shape.duplicate()
        (shape_node.shape as RectangleShape2D).size = Vector2(vehicle_width_m,vehicle_length_m) * pixels_per_meter
    var sprite: Sprite2D = get_node_or_null("Sprite2D")
    if sprite != null and sprite.texture != null:
        var native_height: float = float(sprite.texture.get_height())
        if native_height > 0.0:
            sprite.scale = Vector2.ONE * (visual_length_m * pixels_per_meter / native_height)
        sprite.rotation_degrees = sprite_heading_offset_deg

func set_world_query(node: Node) -> void:
    world_query = node
    _surface_timer = 0.0

func set_surface(new_surface: String) -> void:
    surface = new_surface
    match new_surface:
        "track": surface_grip = 1.08
        "asphalt": surface_grip = 1.0
        "concrete": surface_grip = 0.95
        "dirt": surface_grip = 0.65
        "gravel": surface_grip = 0.54
        "grass": surface_grip = 0.52
        "forest", "farmland": surface_grip = 0.48
        "beach": surface_grip = 0.36
        "mountain", "rock": surface_grip = 0.62
        "ocean", "lake": surface_grip = 0.1
        _: surface_grip = 0.65

func reset_vehicle(where: Vector2, heading: float = 0.0) -> void:
    global_position = where
    rotation = heading
    velocity = Vector2.ZERO
    steer_angle = 0.0
    _spawn = where
    _spawn_heading = heading

func reset_to_spawn() -> void:
    reset_vehicle(_spawn,_spawn_heading)

func get_speed_kph() -> float:
    return velocity.length() * 3.6 / maxf(pixels_per_meter,0.001)

func get_forward_speed_kph() -> float:
    return velocity.dot(Vector2.UP.rotated(rotation)) * 3.6 / maxf(pixels_per_meter,0.001)

func _physics_process(delta: float) -> void:
    var drive: float = 0.0
    var steer: float = 0.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        drive += 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        drive -= 1.0
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        steer -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        steer += 1.0
    _surface_timer -= delta
    if _surface_timer <= 0.0 and is_instance_valid(world_query):
        _surface_timer = 0.14
        set_surface(str(world_query.call("get_surface_at",global_position)))
    advance_physics(delta,drive,steer,Input.is_key_pressed(KEY_SPACE))
    move_and_slide()

## Deterministic handling state: accel capped by power/mass; drag v^2;
## steer range decreases with speed; tire grip damps sideways momentum.
func advance_physics(delta: float, drive: float, steer: float, handbrake: bool) -> void:
    var dt: float = clampf(delta,0.0,0.05)
    if dt == 0.0:
        return
    drive = clampf(drive,-1.0,1.0)
    steer = clampf(steer,-1.0,1.0)
    var front: Vector2 = Vector2.UP.rotated(rotation)
    var right: Vector2 = Vector2.RIGHT.rotated(rotation)
    var ppm: float = maxf(pixels_per_meter,0.001)
    var forward_speed: float = velocity.dot(front) / ppm
    var lateral_speed: float = velocity.dot(right) / ppm
    var brake_force: float = minf(brake_deceleration_mps2,11.5 * surface_grip)
    if drive > 0.0:
        if forward_speed < -0.25:
            forward_speed = move_toward(forward_speed,0.0,brake_force * drive * dt)
        else:
            var power_limited: float = (power_kw * 1000.0) / (maxf(4.5,absf(forward_speed)) * mass_kg)
            forward_speed += minf(max_acceleration_mps2,power_limited) * minf(1.0,surface_grip) * drive * dt
    elif drive < 0.0:
        if forward_speed > 0.25:
            forward_speed = move_toward(forward_speed,0.0,brake_force * -drive * dt)
        else:
            forward_speed -= reverse_acceleration_mps2 * minf(1.0,surface_grip) * -drive * dt
    var air_drag: float = 0.5 * 1.225 * drag_area_m2 * forward_speed * forward_speed / mass_kg
    var rolling: float = rolling_resistance * 9.81 * minf(1.0,surface_grip)
    forward_speed = move_toward(forward_speed,0.0,(air_drag+rolling) * dt)
    if handbrake:
        forward_speed = move_toward(forward_speed,0.0,handbrake_deceleration_mps2 * surface_grip * dt)
    if absf(drive) < 0.01 and absf(forward_speed) < 0.07:
        forward_speed = 0.0
    forward_speed = clampf(forward_speed,-maximum_reverse_kph/3.6,maximum_speed_kph/3.6)
    var speed_fraction: float = clampf(absf(forward_speed)*3.6/maxf(steering_fade_kph,1.0),0.0,1.0)
    var steer_limit: float = lerpf(low_speed_steer_deg,high_speed_steer_deg,speed_fraction)
    steer_angle = move_toward(steer_angle,deg_to_rad(steer * steer_limit),deg_to_rad(steer_response_deg_per_sec)*dt)
    var ideal_yaw: float = forward_speed * tan(steer_angle) / maxf(wheelbase_m,0.5)
    var yaw_limit: float = max_lateral_acceleration_mps2 * surface_grip / maxf(absf(forward_speed),1.0)
    var yaw_rate: float = clampf(ideal_yaw,-yaw_limit,yaw_limit)
    if handbrake:
        yaw_rate *= 0.85
    # Maintain inertia when facing changes, allowing visible drift at low grip.
    var momentum: Vector2 = front * forward_speed + right * lateral_speed
    rotation += yaw_rate * dt
    var after_front: Vector2 = Vector2.UP.rotated(rotation)
    var after_right: Vector2 = Vector2.RIGHT.rotated(rotation)
    var new_forward: float = momentum.dot(after_front)
    var new_lateral: float = momentum.dot(after_right)
    var grip: float = handbrake_lateral_grip if handbrake else normal_lateral_grip
    new_lateral *= exp(-grip * surface_grip * dt)
    velocity = (after_front * new_forward + after_right * new_lateral) * ppm
    velocity = velocity.limit_length(maximum_speed_kph/3.6 * ppm * 1.12)
