class_name VehicleConfig
extends Resource
## SI units throughout; the controller alone converts metres to world pixels.
enum Drivetrain { FWD, RWD, AWD }
@export_group("Powertrain")
@export var mass_kg: float = 1450.0
@export var engine_torque_nm: float = 470.0
@export var engine_power_kw: float = 360.0
@export var torque_curve: Curve
@export var drivetrain: Drivetrain = Drivetrain.RWD
@export var gear_ratios: PackedFloat32Array = [3.2, 2.1, 1.55, 1.2, 0.98, 0.8]
@export var final_drive: float = 3.7
@export var reverse_ratio: float = 3.0
@export var wheel_radius_m: float = 0.34
@export var idle_rpm: float = 950.0
@export var redline_rpm: float = 8500.0
## Positive only for explicitly modeled turbocharged configurations.
## Rated power/torque figures already include full boost.
@export var boost_max_psi: float = 0.0
@export var boost_spool_seconds: float = 0.65
@export_group("Sound character")
## Original sound-design profile; individual trims may differ from these
## modeled family defaults. All values only affect audio, never horsepower.
@export var audio_family: String = "v8_cross"
@export var audio_aggression: float = 0.75
@export var audio_induction: String = "naturally_aspirated"
@export var audio_flutter: float = 0.0
@export var audio_exhaust_roughness: float = 0.4
## Art-directed recording-inspired mix controls; no physics impact.
@export var audio_tone: float = 0.0 # -1 dark bass to +1 bright rasp.
@export var audio_intake_presence: float = 0.8
@export var audio_driveline_presence: float = 0.5
@export var audio_lope: float = 0.1 # Low-speed cam/firing pulse modulation.
@export var audio_overrun: float = 0.35 # Coast-burble/backfire probability.
@export var audio_turbo_presence: float = 0.0
@export var shift_duration: float = 0.18
## Automatic power-on changes need only a short torque interruption.
@export_range(0.03, 0.3, 0.005) var auto_shift_duration: float = 0.085
@export_group("Chassis and tires")
@export var wheelbase_m: float = 2.65
@export_range(0.3, 0.7) var front_weight: float = 0.43
@export var tire_grip: float = 1.15
@export var cornering_stiffness: float = 68000.0
@export var rear_cornering_stiffness_ratio: float = 1.0
@export var rear_grip_balance: float = 1.12
@export var yaw_damping: float = 1.2
@export var countersteer_assist: float = 0.45
@export_range(0.1, 1.0) var handbrake_rear_grip: float = 0.28
## Longitudinal bite is separate from the lateral grip used to initiate a slide.
@export_range(0.1, 1.0) var handbrake_drive_grip: float = 0.75
## Tire contact relaxes after a rear-wheel lock; throttle wheelspin slows recovery.
@export var handbrake_grip_recovery_seconds: float = 0.9
@export var wheel_spin_recovery_rate: float = 3.0
@export_group("Steering and braking")
@export var max_steer_degrees: float = 32.0
@export var high_speed_steer_degrees: float = 9.0
@export var steering_response: float = 12.0
## Self-aligning spring rate (1/s); independent of the driver's turn-in response.
@export var steering_return_strength: float = 18.0
@export var brake_force_n: float = 18500.0
@export var handbrake_force_n: float = 5000.0
@export_group("Arcade handling")
## Zero preserves the axle-only model; one gives full steering assistance.
@export_range(0.0, 1.0) var arcade_steering_assist: float = 0.0
@export var arcade_lateral_grip: float = 7.0
@export var arcade_cornering_accel: float = 28.0
@export_range(0.0, 1.0) var brake_turn_boost: float = 0.4
@export_group("Resistance and impact")
@export var drag_area: float = 0.7
@export var rolling_resistance: float = 0.015
@export var collision_restitution: float = 0.16
