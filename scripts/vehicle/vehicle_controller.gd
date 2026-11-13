class_name VehicleController2D
extends CharacterBody2D
signal impacted(strength: float)
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
var cornering_grip_fraction := 1.0 # Fraction of lateral grip remaining after braking
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
	command = Vector4.ZERO
	_traffic_impact_id = -1
	_traffic_impact_cooldown = 0.0
	reverse_hold = 0.0
	reversing = false
	transmission.reset(config)
	reset_physics_interpolation()

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
	var steer_input := clampf(controls.z, -1.0, 1.0)
	# Brake first, then require a deliberate hold at rest before engaging reverse.
	if brake > 0.1 and throttle < 0.1 and absf(longitudinal_speed) < 0.8:
		reverse_hold += dt
	else:
		reverse_hold = 0.0
	if reverse_hold > 0.12:
		reversing = true
	if throttle > 0.1 and longitudinal_speed > -1.1:
		reversing = false
	var drive_input := brake if reversing else throttle
	var stopping_input := throttle if reversing else brake
	var speed := linear_velocity.length()
	# Preserve tire slip after a moving rear-wheel lock. This is contact recovery,
	# not a launch cooldown: lifting and higher surface grip help it settle.
	var recovery_rate := maxf(surface_grip, 0.2) * (1.0 - wheel_spin * 0.15) / maxf(config.handbrake_grip_recovery_seconds, 0.05)
	handbrake_grip_loss = maxf(handbrake * smoothstep(1.0, 5.0, speed), move_toward(handbrake_grip_loss, 0.0, recovery_rate * dt))
	var rear_sliding := maxf(handbrake, handbrake_grip_loss)
	# Steering aids only help settled tires. Releasing Space must not instantly
	# redirect momentum while the rear is still sliding or spinning under power.
	var settled_tires := 1.0 - smoothstep(deg_to_rad(6.0), deg_to_rad(18.0), absf(slip_angle))
	var arcade := config.arcade_steering_assist * surface_grip * (1.0 - rear_sliding) * (1.0 - wheel_spin) * settled_tires
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
	# Sliding tires are no longer artificially locked to the stable-turn envelope.
	var slide_request := maxf(handbrake * smoothstep(2.0, 7.0, speed),
		smoothstep(deg_to_rad(9.0), deg_to_rad(24.0), absf(slip_angle)))
	max_steer = minf(max_steer, lerpf(safe_steer, deg_to_rad(26.0), slide_request))
	max_steer = minf(max_steer * brake_turn, deg_to_rad(70.0))
	var assist := clampf(slip_angle * config.countersteer_assist, -0.18, 0.18) * clampf(speed / 8.0, 0.0, 1.0)
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
	var front_load := mass * 9.81 * config.front_weight
	var rear_load := mass * 9.81 * (1.0 - config.front_weight)
	var traction_load := rear_load
	if config.drivetrain == VehicleConfig.Drivetrain.FWD:
		traction_load = front_load
	elif config.drivetrain == VehicleConfig.Drivetrain.AWD:
		traction_load = front_load + rear_load
	var curve_factor := config.torque_curve.sample_baked(
		transmission.rpm / config.redline_rpm) if config.torque_curve else 1.0
	# Compute shaft torque from actual crank RPM and the requested horsepower.
	# Rated HP is not a soft vehicle-speed cap, so extreme F1 settings continue
	# to pull after shifting into taller gears.
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
	# Tire response is independent from crank output. Extreme F1 horsepower
	# builds can use the same prepared, loaded drag-tire longitudinal envelope
	# instead of hitting the stock street-tire acceleration ceiling at ~500hp.
	# Braking, steering grip and off-road contact are deliberately unaffected.
	var drive_grip := lerpf(1.0,config.handbrake_drive_grip,
		rear_sliding * rear_drive_share)
	var traction_capacity := Powertrain.traction_force_n(
		config,traction_load,surface_grip,drive_grip,surface)
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
	var braking := minf(config.brake_force_n * stopping_input + config.handbrake_force_n * handbrake, mass * 9.81 * grip)
	var resistance := 0.5 * 1.225 * config.drag_area * longitudinal_speed * absf(longitudinal_speed)
	resistance += signf(longitudinal_speed) * mass * 9.81 * (config.rolling_resistance + (1.0 - surface_grip) * 0.045) * minf(absf(longitudinal_speed), 1.0)
	var drive_accel := (engine_force - resistance) / mass
	var new_long := longitudinal_speed + drive_accel * dt
	new_long = move_toward(new_long, 0.0, braking / mass * dt)
	# Bicycle axle forces. Saturation produces understeer; rear grip loss produces oversteer.
	var front_arm := config.wheelbase_m * (1.0 - config.front_weight)
	var rear_arm := config.wheelbase_m * config.front_weight
	var denominator := maxf(absf(longitudinal_speed), 4.0)
	var travel_sign := signf(longitudinal_speed) if absf(longitudinal_speed) > 0.1 else 1.0
	var front_slip := atan2(lateral_speed + yaw_rate * front_arm, denominator) - steering * travel_sign
	var rear_slip := atan2(lateral_speed - yaw_rate * rear_arm, denominator)
	# Axle-only setups share the tire budget realistically. Arcade setups retain
	# cornering grip under the service brake so S + steering helps the car turn.
	var brake_usage := clampf(braking / maxf(mass * 9.81 * grip, 1.0), 0.0, 1.0)
	var cornering_budget := sqrt(maxf(0.0, 1.0 - brake_usage * brake_usage))
	cornering_budget = lerpf(cornering_budget, 1.0, arcade * stopping_input)
	cornering_grip_fraction = cornering_budget
	var front_limit := front_load * grip * cornering_budget
	var rear_limit := rear_load * grip * config.rear_grip_balance * lerpf(1.0, config.handbrake_rear_grip, rear_sliding) * (1.0 - wheel_spin * rear_drive_share * 0.2) * cornering_budget
	# Driven wheels also spend part of the friction budget on acceleration.
	var drive_fraction := clampf(absf(engine_force) / maxf(traction_load * grip, 1.0), 0.0, 1.0)
	if config.drivetrain != VehicleConfig.Drivetrain.RWD:
		front_limit *= sqrt(maxf(0.35, 1.0 - drive_fraction * drive_fraction * 0.55))
	if config.drivetrain != VehicleConfig.Drivetrain.FWD:
		rear_limit *= sqrt(maxf(0.4, 1.0 - drive_fraction * drive_fraction * 0.5))
	var front_force := clampf(-config.cornering_stiffness * front_slip, -front_limit, front_limit)
	var rear_force := clampf(-config.cornering_stiffness * config.rear_cornering_stiffness_ratio * rear_slip, -rear_limit, rear_limit)
	var dynamic_blend := smoothstep(2.0, 7.0, absf(longitudinal_speed))
	var inertia := mass * config.wheelbase_m * config.wheelbase_m * 0.3
	var dynamic_yaw := yaw_rate + (front_force * front_arm - rear_force * rear_arm) / inertia * dt
	# Preserve angular inertia when the rear axle loses lateral grip.
	var breakaway := clampf(maxf(maxf(rear_sliding,
		wheel_spin * rear_drive_share),
		smoothstep(deg_to_rad(10.0), deg_to_rad(32.0), absf(slip_angle))), 0.0, 1.0)
	dynamic_yaw *= exp(-config.yaw_damping * lerpf(1.0, 0.24, breakaway) * dt)
	var kinematic_yaw := new_long / config.wheelbase_m * tan(steering)
	yaw_rate = lerpf(kinematic_yaw, dynamic_yaw, maxf(dynamic_blend, breakaway * 0.96))
	# While sliding, committed steering and rear grip loss continue rotating the
	# chassis rather than snapping its heading to the current travel direction.
	# Low-speed handbrake turns can now pass 90/180 degrees, with rate limited.
	var committed_turn := absf(steer_input) * smoothstep(2.5, 8.0, speed)
	var turn_sign := signf(steer_input) * travel_sign
	var oversteer_drive := committed_turn * breakaway * (0.85 + 0.65 * handbrake)
	yaw_rate += turn_sign * oversteer_drive * dt
	if absf(steer_input) < 0.05 and breakaway < 0.25:
		yaw_rate = move_toward(yaw_rate, kinematic_yaw, 0.5 * dt)
	if arcade > 0.0:
		var arcade_yaw_limit := minf(1.9, config.arcade_cornering_accel * surface_grip * brake_turn / maxf(speed, 4.0))
		var desired_yaw := clampf(kinematic_yaw, -arcade_yaw_limit, arcade_yaw_limit)
		yaw_rate = lerpf(yaw_rate, desired_yaw, 1.0 - exp(-12.0 * arcade * dt))
	yaw_rate = clampf(yaw_rate, -3.0, 3.0)
	var new_lateral := lateral_speed + (front_force + rear_force) / mass * dt
	new_lateral = lerpf(lateral_speed * exp(-12.0 * grip * lerpf(1.0, 0.20, breakaway) * dt), new_lateral, maxf(dynamic_blend, breakaway))
	if arcade > 0.0:
		# Scrub lateral velocity with a bounded, opposing tire force. Unlike
		# rotating the velocity vector, this costs lateral kinetic energy and
		# cannot convert a sideways slide into a full-speed launch along the nose.
		var extra_grip := maxf(0.0, config.arcade_cornering_accel * surface_grip - absf(front_force + rear_force) / mass)
		var correction := absf(new_lateral) * (1.0 - exp(-config.arcade_lateral_grip * arcade * dt))
		new_lateral = move_toward(new_lateral, 0.0, minf(correction, extra_grip * arcade * dt))
	linear_velocity = forward * new_long + right * new_lateral
	rotation += yaw_rate * dt
	velocity = linear_velocity * PIXELS_PER_METER
	var collision := move_and_collide(velocity * dt)
	if collision:
		var normal := collision.get_normal()
		var impact_speed := -linear_velocity.dot(normal)
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
			else:
				# Buildings and barriers stay hard, with the original response.
				linear_velocity += normal * impact_speed * (1.0 + config.collision_restitution)
				linear_velocity *= 0.88
				yaw_rate *= 0.4
				impacted.emit(impact_speed)
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
