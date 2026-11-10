class_name VehicleTransmission
extends RefCounted
signal shifted(gear: int)
var automatic := true
var gear := 1
var rpm := 950.0
var shift_timer := 0.0
var last_reversing := false

func reset(config: VehicleConfig) -> void:
	gear = 1
	rpm = config.idle_rpm
	shift_timer = 0.0
	last_reversing = false

func shift(direction: int, config: VehicleConfig, auto_triggered := false) -> void:
	if shift_timer > 0.0:
		return
	var next := clampi(gear + direction, 1, config.gear_ratios.size())
	if next != gear:
		gear = next
		# Quick automatics keep manual shifts at their chosen duration.
		shift_timer = minf(config.shift_duration, config.auto_shift_duration) if auto_triggered else config.shift_duration
		shifted.emit(gear)

func update(dt: float, speed: float, throttle: float, reversing: bool, config: VehicleConfig) -> float:
	# Selecting reverse or Drive from a near-stop is a range change, not a
	# long multi-gear shift. Never resume forward driving in 3rd/4th gear
	# after backing up, even if the driver previously stopped in high gear.
	if reversing != last_reversing:
		last_reversing = reversing
		if gear != 1:
			gear = 1
			shifted.emit(gear)
		shift_timer = 0.0
		rpm = maxf(config.idle_rpm, minf(rpm, config.idle_rpm + 450.0))
	shift_timer = maxf(0.0, shift_timer - dt)
	var ratio := config.reverse_ratio if reversing else config.gear_ratios[gear - 1]
	var coupled_rpm := absf(speed) / config.wheel_radius_m * ratio * config.final_drive * 60.0 / TAU
	if automatic and not reversing and shift_timer <= 0.0:
		if coupled_rpm > config.redline_rpm * 0.88 and gear < config.gear_ratios.size():
			shift(1, config, true)
		elif gear > 1 and coupled_rpm < config.redline_rpm * 0.36:
			shift(-1, config, true)
		# Apply the selected gear on this same simulation frame, not a
		# frame later; RPM and delivered torque agree with the selected gear.
		ratio = config.gear_ratios[gear - 1]
		coupled_rpm = absf(speed) / config.wheel_radius_m * ratio * config.final_drive * 60.0 / TAU
	var target_rpm := maxf(config.idle_rpm + throttle * 1300.0, coupled_rpm)
	rpm = lerpf(rpm, clampf(target_rpm, config.idle_rpm, config.redline_rpm),
		1.0 - exp(-22.0 * dt))
	return ratio * config.final_drive
