class_name VehicleController2D
extends CharacterBody2D
signal impacted(strength: float)
## World-space collision details for speed-dependent crash visuals.
signal crash_contact(closing_speed_mps: float, contact_point_px: Vector2,
	surface_normal: Vector2, pre_impact_velocity_mps: Vector2)
signal vehicle_reset
const PIXELS_PER_METER := 20.0
const Powertrain = preload("res://scripts/vehicle/powertrain_dynamics.gd")
@export var config: VehicleConfig
var transmission := VehicleTransmission.new()
var surface_provider: Node
var surface := "ASPHALT"
var surface_grip := 1.0
var linear_velocity := Vector2.ZERO # metres / second, separate from CharacterBody velocity
var yaw_rate := 0.0
var steering := 0.0
var longitudinal_speed := 0.0
var lateral_speed := 0.0
var slip_angle := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := 0.0
var handbrake_grip_loss := 0.0 # Persistent rear tire slip after a moving wheel lock
var _previous_handbrake := 0.0 # Rising edge causes a physical moving handbrake rotation pulse
var wheel_spin := 0.0 # Driven-wheel overspeed estimate, independent of lateral slip
var engine_wheel_force_n := 0.0 # Unclipped driven wheel force, telemetry
var traction_limit_n := 0.0 # Road and tire delivery limit, telemetry
var delivered_wheel_force_n := 0.0 # After driven-wheel slip and shift cuts
var boost_psi := 0.0 # Modeled manifold charge pressure; zero for N/A engines
var nitrous_requested := false # Player N/button input; AI does not auto-use nitrous
var nitrous_active := false
var nitrous_fuel_seconds := 0.0
var _nitrous_kit_initialized := false
var arcade_assist_fraction := 0.0
var cornering_grip_fraction := 1.0 # Weighted lateral grip budget left after brake/drive demand
var front_cornering_grip_fraction := 1.0
var rear_cornering_grip_fraction := 1.0
var front_axle_load_n := 0.0
var rear_axle_load_n := 0.0
var longitudinal_accel_mps2 := 0.0 # Filtered signed acceleration from the prior physics tick
var reversing := false
var reverse_hold := 0.0
var spawn_transform := Transform2D.IDENTITY
var external_input := false
var command := Vector4.ZERO # throttle, brake, steer, handbrake; AI/test seam
var _traffic_impact_id := -1
var _traffic_impact_cooldown := 0.0

func _ready() -> void:
	config = config.duplicate(true)
	spawn_transform = transform
	transmission.reset(config)
	nitrous_fuel_seconds = maxf(0.0,config.nitrous_capacity_seconds)
	_nitrous_kit_initialized = nitrous_fuel_seconds > 0.0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

func reset_vehicle() -> void:
	transform = spawn_transform
	linear_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	yaw_rate = 0.0
	steering = 0.0
	longitudinal_speed = 0.0
	lateral_speed = 0.0
	slip_angle = 0.0
	throttle = 0.0
	brake = 0.0
	handbrake = 0.0
	handbrake_grip_loss = 0.0
	_previous_handbrake = 0.0
	wheel_spin = 0.0
	engine_wheel_force_n = 0.0
	traction_limit_n = 0.0
	delivered_wheel_force_n = 0.0
	boost_psi = 0.0
	nitrous_active = false
	nitrous_requested = false
	nitrous_fuel_seconds = maxf(0.0,config.nitrous_capacity_seconds)
	_nitrous_kit_initialized = nitrous_fuel_seconds > 0.0
	arcade_assist_fraction = 0.0
	cornering_grip_fraction = 1.0
	front_cornering_grip_fraction = 1.0
	rear_cornering_grip_fraction = 1.0
	front_axle_load_n = 0.0
	rear_axle_load_n = 0.0
	longitudinal_accel_mps2 = 0.0
	command = Vector4.ZERO
	_traffic_impact_id = -1
	_traffic_impact_cooldown = 0.0
	reverse_hold = 0.0
	reversing = false
	transmission.reset(config)
	reset_physics_interpolation()
	vehicle_reset.emit()

func on_upgrade_config_changed(_previous_capacity: float = 0.0) -> void:
	# Parts can be installed mid-drive. Do not reset the vehicle or top up
	# nitrous on repeated unequip/re-equip attempts during one drive.
	var capacity := maxf(0.0,config.nitrous_capacity_seconds)
	if capacity > 0.0 and not _nitrous_kit_initialized:
		nitrous_fuel_seconds = capacity
		_nitrous_kit_initialized = true
	elif capacity > 0.0:
		nitrous_fuel_seconds = minf(nitrous_fuel_seconds,capacity)
	nitrous_active = false
	boost_psi = minf(boost_psi,maxf(0.0,config.boost_max_psi))


## Two-axle longitudinal load transfer; no invented left/right wheel model.
## Signed forward acceleration unloads the nose, braking loads it. Keep a
## nonzero contact patch on each axle even during hard impacts/upgrades.
static func axle_loads_n(vehicle_config: VehicleConfig, forward_accel_mps2: float) -> Vector2:
	var mass := maxf(vehicle_config.mass_kg, 20.0)
	var total := mass * 9.81
	var front_fraction := clampf(vehicle_config.front_weight, 0.3, 0.7)
	var height := clampf(vehicle_config.center_of_gravity_height_m, 0.25, 1.1)
	var transfer := mass * clampf(forward_accel_mps2, -13.0, 13.0) * \
		height / maxf(vehicle_config.wheelbase_m, 1.4)
	var front := clampf(total * front_fraction - transfer, total * 0.18, total * 0.82)
	return Vector2(front, total - front)


## Combined tire demand in a simplified friction circle. Reserve a modest
## lateral contact budget at the absolute limit for responsive arcade steering.
static func lateral_grip_budget(load_n: float, grip: float, longitudinal_n: float) -> float:
	var capacity := maxf(1.0, load_n * maxf(grip, 0.0))
	var fraction := clampf(absf(longitudinal_n) / capacity, 0.0, 0.93)
	return sqrt(maxf(0.0, 1.0 - fraction * fraction))


func _physics_process(dt: float) -> void:
	if not external_input:
		nitrous_requested = Input.is_action_pressed("nitrous")
		command = Vector4(Input.get_action_strength("throttle"), Input.get_action_strength("brake"), Input.get_axis("left", "right"), Input.get_action_strength("handbrake"))
		if Input.is_action_just_pressed("reset"):
			reset_vehicle()
		if Input.is_action_just_pressed("transmission"):
			transmission.automatic = not transmission.automatic
		if Input.is_action_just_pressed("shift_up"):
			transmission.shift(1, config)
		if Input.is_action_just_pressed("shift_down"):
			transmission.shift(-1, config)
	step_vehicle(dt, command)

func step_vehicle(dt: float, controls: Vector4) -> void:
	_traffic_impact_cooldown = maxf(0.0, _traffic_impact_cooldown - dt)
	var forward := Vector2.UP.rotated(rotation)
	# Godot's orthogonal() points left for Vector2.UP. Axle forces and slip
	# must use the actual right vector or steering pushes against the turn.
	var right := Vector2.RIGHT.rotated(rotation)
	longitudinal_speed = linear_velocity.dot(forward)
	lateral_speed = linear_velocity.dot(right)
	slip_angle = atan2(lateral_speed, maxf(absf(longitudinal_speed), 1.0))
	if surface_provider:
		var info: Dictionary = surface_provider.surface_at(global_position)
		surface = info.name
		surface_grip = info.grip
	else:
		surface = "ASPHALT"
		surface_grip = 1.0
	# External AI/touch commands are untrusted inputs; prevent extra grip/torque
	# when a caller supplies values outside the intended normalized range.
	throttle = clampf(controls.x, 0.0, 1.0)
	brake = clampf(controls.y, 0.0, 1.0)
	handbrake = clampf(controls.w, 0.0, 1.0)
	var handbrake_edge := maxf(0.0, handbrake - _previous_handbrake)
	_previous_handbrake = handbrake
	var steer_input := clampf(controls.z, -1.0, 1.0)
	# Brake first, then require a deliberate hold at rest before engaging reverse.
	# Brake-only reverse is intentional, but holding the handbrake must
	# never turn a parked car into a reversing car by itself.
	if brake > 0.1 and throttle < 0.1 and handbrake < 0.1 and \
			absf(longitudinal_speed) < 0.8:
		reverse_hold += dt
	else:
		reverse_hold = 0.0
	if reverse_hold > 0.12:
		reversing = true
	if throttle > 0.1 and longitudinal_speed > -1.1:
		reversing = false
	var drive_input := brake if reversing else throttle
	var stopping_input := throttle if reversing else brake
	# Throttle + service brake + handbrake is not a valid rolling burnout:
	# the service brake wins while the handbrake is also applied. This avoids
	# opposing full engine torque against two brakes and creating fake motion.
	# Gas + handbrake alone still supports controlled powered slides.
	if handbrake > 0.1 and brake > 0.1:
		drive_input = 0.0
		stopping_input = brake
	# Service-brake priority also applies to handbrake rotation. Pressing all
	# three pedals while moving must *stop*, not pivot into a powered slide.
	var handbrake_yaw_input := handbrake * (1.0 - smoothstep(0.05,0.45,stopping_input))
	var speed := linear_velocity.length()
	# Preserve tire slip after a moving rear-wheel lock. This is contact recovery,
	# not a launch cooldown: lifting and higher surface grip help it settle.
	var recovery_rate := maxf(surface_grip, 0.2) * (1.0 - wheel_spin * 0.15) / maxf(config.handbrake_grip_recovery_seconds, 0.05)
	handbrake_grip_loss = maxf(handbrake * smoothstep(1.0, 5.0, speed), move_toward(handbrake_grip_loss, 0.0, recovery_rate * dt))
	var rear_sliding := maxf(handbrake, handbrake_grip_loss)
	# Steering aids only help settled tires. Releasing Space must not instantly
	# redirect momentum while the rear is still sliding or spinning under power.
	var settled_tires := 1.0 - smoothstep(deg_to_rad(6.0), deg_to_rad(18.0), absf(slip_angle))
	# Road/race builds get a limited high-speed contact aid. It is absent on
	# low-grip surfaces and *disengages* as soon as the rear slides, so a grip
	# tune never auto-corrects the driver's deliberate drift.
	var race_stability := clampf(config.high_speed_stability,0.0,0.65) * \
		smoothstep(12.0,32.0,speed) * pow(clampf(surface_grip,0.0,1.0),2.0) * \
		(1.0-rear_sliding) * (1.0-wheel_spin) * settled_tires
	var arcade := clampf(config.arcade_steering_assist * surface_grip * \
		(1.0-rear_sliding) * (1.0-wheel_spin) * settled_tires + \
		race_stability * 0.16,0.0,1.0)
	arcade_assist_fraction = arcade
	var brake_turn := 1.0 + config.brake_turn_boost * stopping_input * arcade
	var ratio := transmission.update(dt, longitudinal_speed * (1.0 + wheel_spin * 0.18), drive_input, reversing, config)
	# Nitrous is temporary additional wheel torque, limited by the same
	# traction/wheelspin model as ordinary engine power. It has a finite tank
	# and refills outside of use; no kit means no nitrous advantage.
	var nitrous_capacity := maxf(0.0,config.nitrous_capacity_seconds)
	nitrous_active = nitrous_capacity > 0.01 and nitrous_requested and \
		drive_input > 0.2 and not reversing and transmission.shift_timer <= 0.0 and \
		nitrous_fuel_seconds > 0.0
	if nitrous_active:
		nitrous_fuel_seconds = maxf(0.0,nitrous_fuel_seconds-dt)
	else:
		nitrous_fuel_seconds = minf(nitrous_capacity,
			nitrous_fuel_seconds+dt*nitrous_capacity / \
			maxf(1.0,config.nitrous_recharge_seconds))
	# Pressure is simulated only for a configured turbo engine. Power and
	# torque stats already represent boosted peak output; spool temporarily
	# reduces available torque rather than applying a fictitious extra gain.
	if config.boost_max_psi > 0.05:
		var pressure_start := config.idle_rpm + 300.0
		var pressure_full := maxf(pressure_start + 500.0,config.redline_rpm * 0.65)
		var spool := smoothstep(pressure_start,pressure_full,transmission.rpm)
		var target_boost := config.boost_max_psi * drive_input * spool
		if reversing or transmission.shift_timer > 0.0:
			target_boost = 0.0
		var response := 7.0 if target_boost < boost_psi else \
			1.0 / maxf(config.boost_spool_seconds,0.1)
		boost_psi = lerpf(boost_psi,target_boost,1.0-exp(-response*dt))
	else:
		boost_psi = 0.0
	var max_steer := deg_to_rad(lerpf(config.max_steer_degrees, config.high_speed_steer_degrees, clampf(speed / 55.0, 0.0, 1.0)))
	# Keep high-speed steering requests close to the tire envelope instead of
	# demanding impossible slip angles. Handbrake deliberately relaxes this aid.
	var tire_envelope := atan(config.tire_grip * surface_grip * 9.81 * config.wheelbase_m / maxf(speed * speed, 1.0))
	var safe_steer := (tire_envelope * lerpf(1.8, 3.5, handbrake) + deg_to_rad(1.5)) * config.high_speed_steer_degrees / 9.0
	# High-speed grip tuning gently extends usable steer without bypassing
	# the physical tire envelope or allowing a one-input hairpin at 200 km/h.
	safe_steer *= 1.0 + race_stability * 0.50
	# Sliding tires are no longer artificially locked to the stable-turn envelope.
	var slide_request := maxf(handbrake * smoothstep(2.0, 7.0, speed),
		smoothstep(deg_to_rad(9.0), deg_to_rad(24.0), absf(slip_angle)))
	max_steer = minf(max_steer, lerpf(safe_steer, deg_to_rad(26.0), slide_request))
	max_steer = minf(max_steer * brake_turn, deg_to_rad(70.0))
	var drift_engagement := smoothstep(4.0,12.0,speed) * maxf(
		rear_sliding * 0.90, smoothstep(deg_to_rad(9.0),deg_to_rad(25.0),absf(slip_angle)))
	var drift_aid := clampf(config.drift_control,0.0,0.70) * \
		drift_engagement * clampf(surface_grip,0.0,1.0)
	var assist := clampf(slip_angle * config.countersteer_assist * \
		(1.0 + drift_aid * 0.65), -0.24, 0.24) * clampf(speed / 8.0, 0.0, 1.0)
	if absf(steer_input) < 0.02:
		# Overdamped self-aligning spring: restoring torque is proportional to
		# wheel angle, with stronger centering as road speed builds. Do not let
		# countersteer assistance keep the wheels turned after input is released.
		var centering := config.steering_return_strength * lerpf(1.0, 1.6, clampf(speed / 35.0, 0.0, 1.0))
		steering *= exp(-centering * dt)
		if absf(steering) < deg_to_rad(0.05):
			steering = 0.0
	else:
		var steer_target := steer_input * max_steer + assist * signf(longitudinal_speed)
		steering = lerpf(steering, steer_target, 1.0 - exp(-config.steering_response * dt))
	var mass := maxf(config.mass_kg, 20.0)
	var grip := config.tire_grip * surface_grip
	# One tick of filtered acceleration gives stable, frame-rate independent
	# pitch-load response without predicting tire forces in a feedback loop.
	var loads := axle_loads_n(config, longitudinal_accel_mps2)
	var front_load := loads.x
	var rear_load := loads.y
	front_axle_load_n = front_load
	rear_axle_load_n = rear_load
	var traction_load := rear_load
	if config.drivetrain == VehicleConfig.Drivetrain.FWD:
		traction_load = front_load
	elif config.drivetrain == VehicleConfig.Drivetrain.AWD:
		traction_load = front_load + rear_load
	var curve_factor := config.torque_curve.sample_baked(
		transmission.rpm / config.redline_rpm) if config.torque_curve else 1.0
	# Compute shaft torque from actual crank RPM and the requested horsepower.
	# Rated horsepower is not a soft vehicle-speed cap; the crank torque
	# curve still governs acceleration at the selected RPM.
	var boost_factor := 1.0
	if config.boost_max_psi > 0.05:
		boost_factor = lerpf(0.85,1.0,
			clampf(boost_psi / config.boost_max_psi,0.0,1.0))
	var engine_force := Powertrain.wheel_force_n(config,transmission.rpm,
		ratio,curve_factor,boost_factor)
	engine_wheel_force_n = engine_force
	# At five-figure builds, a linear throttle saturates street tires with
	# barely any pedal input. Progressive pedal response keeps part throttle
	# usable; full throttle still requests the full real engine output.
	var high_output := Powertrain.high_output_fraction(config)
	var pedal := pow(drive_input, 1.0 + high_output * 1.9)
	var requested_force := engine_force * pedal * \
		(1.0+config.nitrous_torque_fraction if nitrous_active else 1.0)
	var rear_drive_share := 1.0 if config.drivetrain == VehicleConfig.Drivetrain.RWD else 0.0
	if config.drivetrain == VehicleConfig.Drivetrain.AWD:
		rear_drive_share = 0.5
	# Tire response is independent from crank output. Extremely high-output
	# upgrade builds retain their prepared drag-tire longitudinal envelope.
	# Braking, steering grip and off-road contact are deliberately unaffected.
	var drive_grip := lerpf(1.0,config.handbrake_drive_grip,
		rear_sliding * rear_drive_share)
	var traction_capacity := Powertrain.traction_force_n(
		config,traction_load,surface_grip,drive_grip,surface,speed)
	traction_limit_n = traction_capacity
	# Overwhelming a tire actually makes the wheel spin, even before a
	# handbrake/drift starts. Visual wheel animation and grip recovery now
	# communicate the added torque rather than hiding it at a silent clamp.
	var spin_target := Powertrain.drive_wheelspin(requested_force,
		traction_capacity,rear_drive_share,rear_sliding,drive_input)
	var spin_rate := 12.0 if spin_target > wheel_spin else \
		config.wheel_spin_recovery_rate * (2.0 - drive_input)
	wheel_spin = lerpf(wheel_spin,spin_target,1.0 - exp(-spin_rate * dt))
	if wheel_spin < 0.001 and spin_target == 0.0:
		wheel_spin = 0.0
	engine_force = minf(requested_force,traction_capacity) * \
		(1.0 - wheel_spin * rear_drive_share * 0.12)
	if transmission.shift_timer > 0.0 or transmission.rpm >= config.redline_rpm * 0.995:
		engine_force *= 0.12
	if reversing:
		engine_force *= -0.65
		if longitudinal_speed < -13.0:
			engine_force = 0.0
	delivered_wheel_force_n = engine_force
	# Allocate service braking by axle; the handbrake acts on the rear only.
	# Clamp braking by each axle's dynamically loaded tire capacity instead
	# of treating the whole vehicle as one contact patch.
	var front_capacity := maxf(front_load * grip, 0.0)
	var rear_capacity := maxf(rear_load * grip, 0.0)
	var service_brake := maxf(config.brake_force_n, 0.0) * stopping_input
	var bias := clampf(config.brake_bias_front, 0.45, 0.80)
	var front_braking := minf(service_brake * bias, front_capacity)
	var rear_braking := minf(service_brake * (1.0 - bias) +
		maxf(config.handbrake_force_n, 0.0) * handbrake, rear_capacity)
	var braking := front_braking + rear_braking
	var resistance := 0.5 * 1.225 * config.drag_area * longitudinal_speed * absf(longitudinal_speed)
	resistance += signf(longitudinal_speed) * mass * 9.81 * (config.rolling_resistance + (1.0 - surface_grip) * 0.045) * minf(absf(longitudinal_speed), 1.0)
	var drive_accel := (engine_force - resistance) / mass
	var new_long := longitudinal_speed + drive_accel * dt
	new_long = move_toward(new_long, 0.0, braking / mass * dt)
	# Use an acceleration filter rather than directly coupling noisy surface
	# contact or collision impulses to the next tick's axle loads.
	var acceleration := (new_long - longitudinal_speed) / maxf(dt, 0.0001)
	longitudinal_accel_mps2 = lerpf(longitudinal_accel_mps2,
		clampf(acceleration, -13.0, 13.0), 1.0 - exp(-13.0 * dt))
	# Bicycle axle forces. Saturation produces understeer; rear grip loss produces oversteer.
	var front_arm := config.wheelbase_m * (1.0 - config.front_weight)
	var rear_arm := config.wheelbase_m * config.front_weight
	var denominator := maxf(absf(longitudinal_speed), 4.0)
	var travel_sign := signf(longitudinal_speed) if absf(longitudinal_speed) > 0.1 else 1.0
	var front_slip := atan2(lateral_speed + yaw_rate * front_arm, denominator) - steering * travel_sign
	var rear_slip := atan2(lateral_speed - yaw_rate * rear_arm, denominator)
	# Both service braking and delivered drive torque consume lateral grip
	# on the axle actually supplying that longitudinal force. Avoid applying
	# the same global brake penalty to front and rear, or penalizing twice.
	var front_longitudinal := front_braking + absf(engine_force) * (1.0 - rear_drive_share)
	var rear_longitudinal := rear_braking + absf(engine_force) * rear_drive_share
	var front_budget := lateral_grip_budget(front_load, grip, front_longitudinal)
	var rear_budget := lateral_grip_budget(rear_load, grip, rear_longitudinal)
	# Assistance restores a controlled fraction of cornering authority during
	# braking; it never changes mass, longitudinal braking, or axle load.
	front_budget = lerpf(front_budget, 1.0, arcade * stopping_input)
	rear_budget = lerpf(rear_budget, 1.0, arcade * stopping_input)
	front_cornering_grip_fraction = front_budget
	rear_cornering_grip_fraction = rear_budget
	cornering_grip_fraction = front_budget * config.front_weight + \
		rear_budget * (1.0 - config.front_weight)
	# Tire load sensitivity: increasing normal force does not increase lateral
	# grip one-for-one. This limits destabilizing rear unload in long
	# trail-braking corners without hiding longitudinal weight transfer.
	var static_front_load := mass * 9.81 * clampf(config.front_weight, 0.3, 0.7)
	var static_rear_load := mass * 9.81 - static_front_load
	var front_lateral_load := static_front_load * pow(
		front_load / maxf(static_front_load, 1.0), 0.58)
	var rear_lateral_load := static_rear_load * pow(
		rear_load / maxf(static_rear_load, 1.0), 0.58)
	var front_limit := front_lateral_load * grip * front_budget * (1.0 + race_stability * 0.19)
	var rear_limit := rear_lateral_load * grip * config.rear_grip_balance * \
		lerpf(1.0, config.handbrake_rear_grip, rear_sliding) * \
		(1.0 - wheel_spin * rear_drive_share * 0.2) * rear_budget * \
		(1.0 + race_stability * 0.10) * (1.0 - drift_aid * 0.25)
	# A stationary wheel can turn in place but cannot create lateral tyre
	# force or yaw without the body rolling. The old low-speed slip denominator
	# produced a nonzero lateral impulse solely from steering at zero speed.
	# Fade the bicycle tyre forces in only after real vehicle motion begins.
	var rolling_contact := smoothstep(0.05, 2.0, speed)
	var front_force := clampf(-config.cornering_stiffness * front_slip, -front_limit, front_limit) * rolling_contact
	var rear_force := clampf(-config.cornering_stiffness * config.rear_cornering_stiffness_ratio * rear_slip, -rear_limit, rear_limit) * rolling_contact
	var dynamic_blend := smoothstep(2.0, 7.0, absf(longitudinal_speed))
	var inertia := mass * config.wheelbase_m * config.wheelbase_m * 0.3
	var dynamic_yaw := yaw_rate + (front_force * front_arm - rear_force * rear_arm) / inertia * dt
	# Preserve angular inertia when the rear axle loses lateral grip.
	var breakaway := clampf(maxf(maxf(rear_sliding,
		wheel_spin * rear_drive_share),
		smoothstep(deg_to_rad(10.0), deg_to_rad(32.0), absf(slip_angle))), 0.0, 1.0)
	dynamic_yaw *= exp(-config.yaw_damping * lerpf(1.0, 0.24, breakaway) * \
		(1.0 - drift_aid * 0.35) * dt)
	var kinematic_yaw := new_long / config.wheelbase_m * tan(steering)
	yaw_rate = lerpf(kinematic_yaw, dynamic_yaw, maxf(dynamic_blend, breakaway * 0.96))
	# While sliding, committed steering and rear grip loss continue rotating the
	# chassis rather than snapping its heading to the current travel direction.
	# Low-speed handbrake turns can now pass 90/180 degrees, with rate limited.
	var committed_turn := absf(steer_input) * smoothstep(2.5, 8.0, speed)
	# During a 180 the body can point against its momentum: longitudinal
	# speed changes sign even though the player is *not* in reverse. Do not
	# reverse the requested handbrake yaw halfway through the slide.
	var turn_sign := signf(steer_input) * (-1.0 if reversing else 1.0)
	var oversteer_drive := committed_turn * breakaway * (0.85 + 0.65 * handbrake)
	# A rear-wheel lock transfers the remaining rolling momentum into yaw.
	# A moving, steered handbrake can bring a *stock* car through 180 degrees;
	# the speed gate avoids resurrecting the parked-handbrake steering exploit.
	var moving_lock := smoothstep(2.0,10.0,speed) * handbrake_yaw_input * \
		clampf(surface_grip,0.0,1.0) * clampf(config.handbrake_rotation_boost,0.2,1.8)
	oversteer_drive += committed_turn * moving_lock * 2.0
	# Add a one-time turn initiation impulse; holding the button does not
	# reapply it each frame. Steering is still required to rotate the car.
	yaw_rate += turn_sign * absf(steer_input) * handbrake_edge * \
		moving_lock * 1.17
	# Drift suspension/tires preserve steering authority after releasing the
	# handbrake, instead of snapping the car back onto the original trajectory.
	oversteer_drive += committed_turn * drift_aid * (1.0 - handbrake) * 0.65
	yaw_rate += turn_sign * oversteer_drive * dt
	# With the rear wheels locked, the usual front-axle bicycle forces tend
	# to cancel yaw before a stock handbrake turn can reach 180 degrees.
	# Apply a bounded *angular* tire response toward the steered rotation:
	# this neither adds linear speed nor turns a stationary vehicle.
	if handbrake_yaw_input > 0.05 and absf(steer_input) > 0.08 and speed > 2.0:
		var pivot_target := turn_sign * absf(steer_input) * \
			(0.75 + clampf(config.handbrake_rotation_boost,0.2,1.8) * 1.2) * \
			(0.35 + 0.65 * smoothstep(2.0,10.0,speed))
		# First-order rear-lock response can overcome the opposing front
		# axle force at speed, yet decays naturally with tire momentum.
		yaw_rate = lerpf(yaw_rate,pivot_target,
			1.0 - exp(-96.0 * moving_lock * dt))
	if absf(steer_input) < 0.05 and breakaway < 0.25:
		yaw_rate = move_toward(yaw_rate, kinematic_yaw, 0.5 * dt)
	if arcade > 0.0:
		var arcade_yaw_limit := minf(1.9, config.arcade_cornering_accel * surface_grip * \
			brake_turn * (1.0 + race_stability * 0.13) / maxf(speed, 4.0))
		var desired_yaw := clampf(kinematic_yaw, -arcade_yaw_limit, arcade_yaw_limit)
		yaw_rate = lerpf(yaw_rate, desired_yaw, 1.0 - exp(-12.0 * arcade * dt))
	# A braking tire has less remaining cornering force than a coasting one.
	# Do not let the arcade steering target demand a yaw rate above the axle
	# forces' braking envelope. Preserve explicit rear-lock drifting and the
	# existing brake-turn upgrade effect inside this bounded envelope.
	if stopping_input > 0.1 and handbrake < 0.05 and rear_sliding < 0.15:
		var lateral_accel_budget := maxf(0.0, front_limit + rear_limit) / mass
		var brake_yaw_envelope := lateral_accel_budget / maxf(speed, 4.0) * \
			(0.70 + clampf(config.brake_turn_boost, 0.0, 1.0) * arcade * 0.40)
		var brake_blend := smoothstep(0.1, 0.4, stopping_input)
		var allowed_yaw := lerpf(3.0, brake_yaw_envelope, brake_blend)
		yaw_rate = clampf(yaw_rate, -allowed_yaw, allowed_yaw)
	yaw_rate = clampf(yaw_rate, -3.0, 3.0)
	# Static tyre friction arrests residual rotational inertia at rest. A
	# handbrake and steering input are not a motor that can rotate the body.
	if speed < 0.35 and absf(new_long) < 0.35:
		yaw_rate = 0.0
	var new_lateral := lateral_speed + (front_force + rear_force) / mass * dt
	new_lateral = lerpf(lateral_speed * exp(-12.0 * grip * lerpf(1.0, 0.20, breakaway) * dt), new_lateral, maxf(dynamic_blend, breakaway))
	if arcade > 0.0:
		# Scrub lateral velocity with a bounded, opposing tire force. Unlike
		# rotating the velocity vector, this costs lateral kinetic energy and
		# cannot convert a sideways slide into a full-speed launch along the nose.
		var extra_grip := maxf(0.0, config.arcade_cornering_accel * surface_grip - absf(front_force + rear_force) / mass)
		var correction := absf(new_lateral) * (1.0 - exp(-config.arcade_lateral_grip * \
			(1.0 + race_stability * 0.15) * arcade * dt))
		new_lateral = move_toward(new_lateral, 0.0, minf(correction, extra_grip * arcade * dt))
	linear_velocity = forward * new_long + right * new_lateral
	rotation += yaw_rate * dt
	velocity = linear_velocity * PIXELS_PER_METER
	var collision := move_and_collide(velocity * dt)
	if collision:
		var normal := collision.get_normal()
		var impact_speed := -linear_velocity.dot(normal)
		var pre_impact_velocity: Vector2 = linear_velocity
		if impact_speed > 0.0:
			var other: Object = collision.get_collider()
			var is_traffic := false
			if is_instance_valid(other) and other is Node:
				is_traffic = other.is_in_group("traffic_vehicle") or other.is_in_group("race_opponent") or other is VehicleController2D
			if is_traffic:
				# A shallow sideswipe should retain tangential speed; a direct
				# impact transfers more energy. The collider itself still prevents
				# the player from passing through the traffic car.
				var frontal := absf(normal.dot(forward))
				var loss := lerpf(0.18, 0.56, frontal)
				linear_velocity += normal * impact_speed * loss
				linear_velocity *= 0.985
				# Off-center contacts produce a small, limited rotation rather
				# than the same fixed yaw penalty for every contact angle.
				var lever := (collision.get_position() - global_position).dot(right)
				var off_center := clampf(lever / maxf(1.0, config.wheelbase_m *
					PIXELS_PER_METER * 0.5), -1.0, 1.0)
				yaw_rate = clampf(yaw_rate * 0.84 + off_center * impact_speed * 0.012,
					-2.4, 2.4)
				# Multiple physics contacts in a single crash should not apply
				# a fresh full-strength shove or play an impact effect each tick.
				var contact_id := other.get_instance_id()
				var fresh_contact := contact_id != _traffic_impact_id or \
					_traffic_impact_cooldown <= 0.0
				if fresh_contact:
					_traffic_impact_id = contact_id
					_traffic_impact_cooldown = 0.18
					if impact_speed > 0.7 and other.has_method("receive_impact"):
						var weight_factor := clampf(mass / (mass + 1200.0) * 2.0,
							0.8, 1.35)
						other.receive_impact(-normal * minf(impact_speed, 22.0) *
							PIXELS_PER_METER * 1.25 * weight_factor)
					impacted.emit(impact_speed)
					crash_contact.emit(impact_speed,collision.get_position(),normal,pre_impact_velocity)
			else:
				# Buildings and barriers stay hard, with the original response.
				linear_velocity += normal * impact_speed * (1.0 + config.collision_restitution)
				linear_velocity *= 0.88
				yaw_rate *= 0.4
				impacted.emit(impact_speed)
				crash_contact.emit(impact_speed,collision.get_position(),normal,pre_impact_velocity)
		move_and_collide(collision.get_remainder().slide(normal))
	if linear_velocity.length() < 0.04 and drive_input < 0.01:
		linear_velocity = Vector2.ZERO
	# Publish the post-impact state immediately. Previously CharacterBody2D.velocity
	# retained the pre-collision vector and HUD/marks kept stale slip telemetry
	# until the next physics frame.
	velocity = linear_velocity * PIXELS_PER_METER
	var final_forward := Vector2.UP.rotated(rotation)
	var final_right := Vector2.RIGHT.rotated(rotation)
	longitudinal_speed = linear_velocity.dot(final_forward)
	lateral_speed = linear_velocity.dot(final_right)
	slip_angle = atan2(lateral_speed, maxf(absf(longitudinal_speed), 1.0))
