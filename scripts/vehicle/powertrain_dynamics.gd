extends RefCounted
## Shared engine and straight-line tire model for stock cars, upgrades and
## high-range F1 tuning. All inputs are SI (kW, Nm, rpm, metres, newtons).
## Never directly change position, road speed, gearbox ratio or vehicle mass.
const RPM_TO_RADIANS_PER_SECOND := TAU / 60.0
const DRIVE_EFFICIENCY := 0.90
const POWER_LIFT_START := 0.40
const POWER_LIFT_PEAK := 0.83
const MAX_HIGH_OUTPUT_TRACTION := 3.25
const MAX_HIGH_OUTPUT_ACCEL_G := 3.45


## Peak torque controls the low/midrange pull. Rated horsepower controls how
## hard the engine continues to pull near the redline. At extreme F1 values
## those two independent override sliders can describe an impossible dyno
## curve; construct a power-focused top end instead of silently ignoring HP.
static func crank_torque_nm(config: VehicleConfig, rpm: float,
		curve_factor: float = 1.0) -> float:
	var redline := maxf(config.redline_rpm, 1000.0)
	var normalized_rpm := clampf(rpm / redline, 0.0, 1.0)
	var low_mid_torque := maxf(0.0, config.engine_torque_nm) * maxf(0.0, curve_factor)
	var omega := maxf(rpm, config.idle_rpm) * RPM_TO_RADIANS_PER_SECOND
	var power_watts := maxf(0.0, config.engine_power_kw) * 1000.0
	# Only synthesize more high-rev torque when the selected HP figure is
	# genuinely above what the selected torque curve could normally supply.
	# Stock vehicles keep their calibrated torque response unchanged.
	var torque_limited_peak_kw := maxf(1.0,
		config.engine_torque_nm * redline * RPM_TO_RADIANS_PER_SECOND * 0.70 / 1000.0)
	var lift_strength := clampf(
		(power_watts / 1000.0 / torque_limited_peak_kw - 1.35) / 0.35, 0.0, 1.0)
	var power_torque := power_watts / maxf(
		redline * POWER_LIFT_PEAK * RPM_TO_RADIANS_PER_SECOND, 1.0)
	var lift := lift_strength * smoothstep(POWER_LIFT_START, POWER_LIFT_PEAK, normalized_rpm)
	var torque := lerpf(low_mid_torque, maxf(low_mid_torque, power_torque), lift)
	# Power is an independent hard upper bound. Correctly uses crank rpm
	# instead of road speed, avoiding wrong caps during wheelspin and shifts.
	return minf(torque, power_watts / maxf(omega, 1.0))


static func wheel_force_n(config: VehicleConfig, rpm: float, total_ratio: float,
		curve_factor: float = 1.0, boost_fraction: float = 1.0) -> float:
	var torque := crank_torque_nm(config, rpm, curve_factor)
	return torque * maxf(0.0, total_ratio) * DRIVE_EFFICIENCY * \
		clampf(boost_fraction, 0.0, 1.0) / maxf(config.wheel_radius_m, 0.1)


static func high_output_fraction(config: VehicleConfig) -> float:
	# Real sports cars do not silently gain grip. This affects only highly
	# modified engines (about 940+ hp / 900+ lb-ft and above).
	var power := clampf((config.engine_power_kw - 700.0) / 5500.0, 0.0, 1.0)
	var torque := clampf((config.engine_torque_nm - 1250.0) / 11000.0, 0.0, 1.0)
	return maxf(power, torque)


static func traction_force_n(config: VehicleConfig, driven_load_n: float,
		road_grip: float, longitudinal_grip: float = 1.0,
		road_name: String = "ASPHALT") -> float:
	var standard := maxf(0.0, driven_load_n * config.tire_grip *
		road_grip * longitudinal_grip)
	var output := high_output_fraction(config)
	# The F1 extreme performance envelope models a prepared, high-load
	# drag tire in the LONGITUDINAL direction. It does not give more
	# braking, lateral grip or invisible speed, and cannot bypass grass.
	if output <= 0.0 or road_name != "ASPHALT" or road_grip < 0.985:
		return standard
	var compound := lerpf(1.0, MAX_HIGH_OUTPUT_TRACTION, output)
	var limited := config.mass_kg * 9.81 * MAX_HIGH_OUTPUT_ACCEL_G
	return minf(standard * compound, maxf(standard, limited))


static func drive_wheelspin(request_n: float, capacity_n: float,
		rear_drive_fraction: float, rear_slide: float,
		drive_input: float) -> float:
	if rear_drive_fraction <= 0.0 or drive_input <= 0.01:
		return 0.0
	var usage := maxf(0.0, request_n) / maxf(capacity_n, 1.0)
	# Excess engine torque should visibly overwhelm the tires even in
	# a straight line and from a standstill, not only after an existing drift.
	var excess := maxf(0.0, usage - 0.98)
	return clampf(maxf(excess * 0.20, rear_slide * usage * 0.48),
		0.0, 0.92) * rear_drive_fraction
