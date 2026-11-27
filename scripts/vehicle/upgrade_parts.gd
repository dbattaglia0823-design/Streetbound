class_name UpgradeParts
extends RefCounted
## Authoritative, data-driven part templates shared by garage, loot and physics.
## All parts have fixed rolled stats, not random unbounded modifiers.
const PATH := "res://data/upgrade_parts.json"
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const SLOTS := ["engine","turbo","transmission","tires","suspension","nitrous"]
# Separate purchase-only slots preserve the 120-template race loot catalog.
const BLACK_MARKET_SLOTS := ["chassis","bumpers","protection","cargo"]
const BLACK_MARKET := {
	"bm-chassis-reinforced": {
		"id": "bm-chassis-reinforced",
		"slot": "chassis",
		"name": "Reinforced Chassis",
		"rarity": "Common",
		"required_rep": 60,
		"price_usd": 18000,
		"modifiers": {
			"max_health_points": 0.25,
			"mass_kg": 0.045
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	},
	"bm-chassis-heavy": {
		"id": "bm-chassis-heavy",
		"slot": "chassis",
		"name": "Heavy Reinforced Chassis",
		"rarity": "Legendary",
		"required_rep": 250,
		"price_usd": 65000,
		"modifiers": {
			"max_health_points": 0.55,
			"mass_kg": 0.09
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	},
	"bm-bumper-reinforced": {
		"id": "bm-bumper-reinforced",
		"slot": "bumpers",
		"name": "Reinforced Bumpers",
		"rarity": "Common",
		"required_rep": 60,
		"price_usd": 12000,
		"modifiers": {
			"impact_damage_factor": -0.15,
			"mass_kg": 0.025
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	},
	"bm-bumper-heavy": {
		"id": "bm-bumper-heavy",
		"slot": "bumpers",
		"name": "Heavy Impact Bumpers",
		"rarity": "Legendary",
		"required_rep": 250,
		"price_usd": 42000,
		"modifiers": {
			"impact_damage_factor": -0.3,
			"mass_kg": 0.05
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	},
	"bm-engine-shield": {
		"id": "bm-engine-shield",
		"slot": "protection",
		"name": "Engine Shielding",
		"rarity": "Common",
		"required_rep": 60,
		"price_usd": 14000,
		"modifiers": {
			"critical_power_loss_factor": -0.25,
			"mass_kg": 0.015
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	},
	"bm-engine-heavy": {
		"id": "bm-engine-heavy",
		"slot": "protection",
		"name": "Advanced Engine Shielding",
		"rarity": "Legendary",
		"required_rep": 250,
		"price_usd": 48000,
		"modifiers": {
			"critical_power_loss_factor": -0.5,
			"mass_kg": 0.03
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	},
	"bm-cargo-light": {
		"id": "bm-cargo-light",
		"slot": "cargo",
		"name": "Lightweight Cargo Storage",
		"rarity": "Common",
		"required_rep": 60,
		"price_usd": 10000,
		"modifiers": {
			"mission_cargo_mass_factor": -0.1,
			"cargo_capacity_kg": 0.1
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	},
	"bm-cargo-advanced": {
		"id": "bm-cargo-advanced",
		"slot": "cargo",
		"name": "Advanced Cargo Storage",
		"rarity": "Legendary",
		"required_rep": 250,
		"price_usd": 36000,
		"modifiers": {
			"mission_cargo_mass_factor": -0.2,
			"cargo_capacity_kg": 0.2
		},
		"specialty": "Black market",
		"race_drop_enabled": false,
		"black_market": true
	}
}
static func all_slots() -> Array:
	return SLOTS + BLACK_MARKET_SLOTS

static func is_black_market(template: Dictionary) -> bool:
	return bool(template.get("black_market",false))

const RARITIES := ["Common","Uncommon","Rare","Epic","Legendary"]
## Tags are future event types, not active rotation rules.
const EVENT_TYPES := ["street","circuit","drag","drift","highway","sprint","technical","endurance"]
const FIELD_LABELS := {
	"engine_power_kw":"POWER","engine_torque_nm":"TORQUE",
	"redline_rpm":"REDLINE","mass_kg":"WEIGHT",
	"max_health_points":"HEALTH","impact_damage_factor":"IMPACT DAMAGE",
	"critical_power_loss_factor":"CRITICAL POWER LOSS","mission_cargo_mass_factor":"CARGO WEIGHT",
	"cargo_capacity_kg":"CARGO CAPACITY",
	"cornering_stiffness":"CORNERING","rear_grip_balance":"REAR GRIP",
	"yaw_damping":"STABILITY","max_steer_degrees":"STEERING ANGLE",
	"steering_response":"TURN-IN","countersteer_assist":"COUNTERSTEER",
	"tire_grip":"TIRE GRIP","handbrake_drive_grip":"SLIDE TRACTION",
	"launch_grip_bonus":"LAUNCH GRIP",
	"high_speed_stability":"HIGH-SPEED STABILITY",
	"drift_control":"DRIFT CONTROL",
	"handbrake_rotation_boost":"HANDBRAKE ROTATION",
	"shift_duration":"SHIFT TIME","auto_shift_duration":"AUTO SHIFT",
	"final_drive":"FINAL DRIVE",
	"boost_max_psi":"TURBO BOOST (PSI)","boost_spool_seconds":"SPOOL TIME",
	"nitrous_torque_fraction":"NITROUS TORQUE","nitrous_capacity_seconds":"NITROUS (SEC)",
	"nitrous_recharge_seconds":"REFILL (SEC)"
}
static var _templates: Dictionary = {}


static func all() -> Dictionary:
	if not _templates.is_empty():
		return _templates
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_error("Upgrade part catalog missing")
		return {}
	for raw in parsed.get("parts",[]):
		if raw is Dictionary and SLOTS.has(str(raw.get("slot",""))) and \
			RARITIES.has(str(raw.get("rarity",""))) and \
			raw.get("modifiers",{}) is Dictionary:
			_templates[str(raw.id)] = raw
	return _templates


static func get_part(template_id: String) -> Dictionary:
	return BLACK_MARKET[template_id].duplicate(true) if BLACK_MARKET.has(template_id) else all().get(template_id,{})


static func in_slot(slot: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog: Dictionary = BLACK_MARKET if slot in BLACK_MARKET_SLOTS else all()
	for part in catalog.values():
		if str(part.slot) == slot:
			result.append(part)
	return result


static func slot_name(slot: String) -> String:
	return slot.capitalize()


static func rarity_color(rarity: String) -> Color:
	match rarity:
		"Uncommon": return Color("#9adaaa")
		"Rare": return Color("#81c8f3")
		"Epic": return Color("#d6adf8")
		"Legendary": return Color("#f9c881")
	return Color("#d6ddd5")


static func summary(template: Dictionary) -> String:
	if template.is_empty():
		return "STOCK"
	var pieces: PackedStringArray = []
	var mods: Dictionary = template.get("modifiers",{})
	for key in mods:
		var fraction := float(mods[key])
		var label: String = FIELD_LABELS.get(str(key),str(key).to_upper())
		if str(key) in ["boost_max_psi","nitrous_capacity_seconds"]:
			pieces.append("%s +%.1f" % [label,fraction])
		elif str(key) == "nitrous_recharge_seconds":
			pieces.append("%s %.1f" % [label,fraction])
		else:
			pieces.append("%s %+.1f%%" % [label,fraction*100.0])
	return "   /   ".join(pieces)


static func apply_to_config(config: VehicleConfig, parts: Array[Dictionary]) -> void:
	# Always apply to a *fresh catalog baseline*, never to an already tuned
	# config. Repeated UI refreshes and equip actions must not stack bonuses.
	for part in parts:
		var mods: Dictionary = part.get("modifiers",{})
		for raw_key in mods:
			var key := str(raw_key)
			if not FIELD_LABELS.has(key):
				continue
			var base: Variant = config.get(key)
			if typeof(base) != TYPE_FLOAT and typeof(base) != TYPE_INT:
				continue
			var fraction := clampf(float(mods[raw_key]),-0.55,0.75)
			var value := float(base) * (1.0 + fraction)
			# A naturally aspirated engine has zero boost; nitrous has zero
			# capacity without a kit. These are explicit *absolute* stats,
			# not percentages of zero. Legacy modifiers stay multiplicative.
			match key:
				"boost_max_psi": value = clampf(float(base)+float(mods[raw_key]),0.0,24.0)
				"nitrous_torque_fraction": value = clampf(
					float(base)+float(mods[raw_key]),0.0,0.45)
				"nitrous_capacity_seconds": value = clampf(
					float(base)+float(mods[raw_key]),0.0,12.0)
				"nitrous_recharge_seconds": value = clampf(
					float(mods[raw_key]),6.0,45.0)
				"launch_grip_bonus": value = clampf(
					float(base)+float(mods[raw_key]),0.0,0.35)
				# The new handling assists add flat normalized increments, not a
				# percentage of zero. Do not stack on previous tune when reloading.
				"high_speed_stability": value = clampf(
					float(base)+float(mods[raw_key]),0.0,0.65)
				"drift_control": value = clampf(
					float(base)+float(mods[raw_key]),0.0,0.70)
				"handbrake_rotation_boost": value = clampf(value,0.2,1.8)
				"boost_spool_seconds": value = clampf(value,0.10,2.0)
				"engine_power_kw": value = clampf(value,40.0,1800.0)
				"engine_torque_nm": value = clampf(value,60.0,3000.0)
				"redline_rpm": value = clampf(value,3500.0,14000.0)
				"mass_kg": value = clampf(value,650.0,5000.0)
				"max_health_points": value = clampf(value,1.0,10000.0)
				"cargo_capacity_kg": value = clampf(value,0.0,2000.0)
				"impact_damage_factor": value = clampf(value,0.5,1.0)
				"critical_power_loss_factor": value = clampf(value,0.5,1.0)
				"mission_cargo_mass_factor": value = clampf(value,0.8,1.0)
				"tire_grip": value = clampf(value,0.5,3.0)
				"rear_grip_balance": value = clampf(value,0.55,1.8)
				"cornering_stiffness": value = clampf(value,30000.0,250000.0)
				"yaw_damping": value = clampf(value,0.5,3.5)
				"countersteer_assist": value = clampf(value,0.0,0.8)
				"max_steer_degrees": value = clampf(value,20.0,60.0)
				"steering_response": value = clampf(value,4.0,30.0)
				"handbrake_drive_grip": value = clampf(value,0.25,1.0)
				"shift_duration": value = clampf(value,0.035,0.55)
				"auto_shift_duration": value = clampf(value,0.03,0.35)
				"final_drive": value = clampf(value,2.0,6.0)
			if typeof(base) == TYPE_INT:
				config.set(key,roundi(value))
			else:
				config.set(key,value)
		if str(part.get("slot","")) == "turbo" and config.boost_max_psi > 0.05:
			# A turbo kit on an N/A car gets true spool and induction audio.
			# Stock turbo and supercharged cars retain their authored profile.
			var extra_psi := maxf(0.0,float(mods.get("boost_max_psi",0.0)))
			config.audio_turbo_presence = clampf(
				config.audio_turbo_presence+extra_psi/20.0,0.0,1.5)
			config.audio_flutter = clampf(
				config.audio_flutter+extra_psi/40.0,0.0,1.0)
			if config.audio_induction == "naturally_aspirated":
				config.audio_induction = "turbo"


static func reward_template(race_id: String, car_level: int,
		event_type: String = "") -> Dictionary:
	# Empty event_type preserves all existing races and their drop pools.
	# A future event rotation system can pass its typed event category.
	# Filter before rolling a template, and never fall back to an unrelated
	# reward when a requested event has no enabled parts.
	if not event_type.is_empty() and not EVENT_TYPES.has(event_type):
		return {}
	# Deterministic local race loot: a completed unique race rolls one part.
	# Late-game rarity is genuinely scarce and cannot drop far ahead of
	# the car's achievable installation tier.
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(race_id.hash()) & 0x7fffffff) + clampi(car_level,1,50)*1021
	var roll := rng.randf()*100.0
	var rarity_index := 0
	if roll >= 99.3:
		rarity_index = 4
	elif roll >= 95.0:
		rarity_index = 3
	elif roll >= 84.0:
		rarity_index = 2
	elif roll >= 57.0:
		rarity_index = 1
	var max_index := 0
	for i in range(1,RARITIES.size()):
		if car_level >= int(Progress.RARITY_THRESHOLDS[RARITIES[i]]) - 8:
			max_index = i
	rarity_index = mini(rarity_index,max_index)
	var rarity := str(RARITIES[rarity_index])
	var eligible: Array[Dictionary] = []
	for part in all().values():
		var sources: Array = part.get("reward_sources",[])
		if str(part.rarity) == rarity and \
				bool(part.get("race_drop_enabled",true)) and \
				(event_type.is_empty() or sources.has(event_type)):
			eligible.append(part)
	if eligible.is_empty():
		return {}
	return eligible[rng.randi_range(0,eligible.size()-1)]
