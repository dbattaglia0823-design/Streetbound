extends RefCounted
class_name StreetboundImperialUnits
## Display-only conversions. Dynamics, Resource specs, saves and engine tuning
## remain in metric SI so speed, acceleration and handling are not changed.
const MPS_TO_MPH := 2.2369362920544
const KG_TO_LB := 2.2046226218488
const NM_TO_LB_FT := 0.73756214927727
const KW_TO_HP := 1.341022089595
const NEWTON_TO_LBF := 0.22480894309971

static func speed_mph(meters_per_second: float) -> float:
	return meters_per_second * MPS_TO_MPH

static func tune_value(property_name: String, native_value: float) -> float:
	match property_name:
		"mass_kg":
			return native_value * KG_TO_LB
		"engine_torque_nm":
			return native_value * NM_TO_LB_FT
		"engine_power_kw":
			return native_value * KW_TO_HP
		"brake_force_n", "cornering_stiffness":
			return native_value * NEWTON_TO_LBF
		_:
			return native_value

static func tune_text(property_name: String, native_value: float) -> String:
	var value: float = tune_value(property_name, native_value)
	match property_name:
		"mass_kg", "engine_torque_nm", "engine_power_kw", "brake_force_n", "cornering_stiffness":
			return "%.0f" % value
		_:
			return "%.2f" % value
