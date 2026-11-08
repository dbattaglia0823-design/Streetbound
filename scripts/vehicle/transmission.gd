class_name VehicleTransmission
extends RefCounted
signal shifted(gear: int)
var automatic := true
var gear := 1
var rpm := 950.0
var shift_timer := 0.0

func reset(config: VehicleConfig) -> void:
	gear = 1
	rpm = config.idle_rpm
	shift_timer = 0.0

func shift(direction: int, config: VehicleConfig) -> void:
	if shift_timer > 0.0:
		return
	var next := clampi(gear + direction, 1, config.gear_ratios.size())
	if next != gear:
		gear = next
		shift_timer = config.shift_duration
		shifted.emit(gear)

func update(dt: float, speed: float, throttle: float, reversing: bool, config: VehicleConfig) -> float:
	shift_timer = maxf(0.0, shift_timer - dt)
	var ratio := config.reverse_ratio if reversing else config.gear_ratios[gear - 1]
	var coupled_rpm := absf(speed) / config.wheel_radius_m * ratio * config.final_drive * 60.0 / TAU
	var target_rpm := maxf(config.idle_rpm + throttle * 1300.0, coupled_rpm)
	rpm = lerpf(rpm, clampf(target_rpm, config.idle_rpm, config.redline_rpm), 1.0 - exp(-18.0 * dt))
	if automatic and not reversing:
		if coupled_rpm > config.redline_rpm * 0.88:
			shift(1, config)
		elif gear > 1 and coupled_rpm < config.redline_rpm * 0.36:
			shift(-1, config)
	return ratio * config.final_drive
