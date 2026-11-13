class_name UpgradeParts
extends RefCounted
## Authoritative, data-driven part templates shared by garage, loot and physics.
## All parts have fixed rolled stats, not random unbounded modifiers.
const PATH := "res://data/upgrade_parts.json"
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const SLOTS := ["engine","ecu","intake","exhaust","suspension","tires","brakes","transmission","turbo","nitrous"]
const RARITIES := ["Common","Uncommon","Rare","Epic","Legendary"]
const FIELD_LABELS := {
	"engine_power_kw":"POWER","engine_torque_nm":"TORQUE",
	"redline_rpm":"REDLINE","mass_kg":"WEIGHT",
	"cornering_stiffness":"CORNERING","rear_grip_balance":"REAR GRIP",
	"yaw_damping":"STABILITY","max_steer_degrees":"STEERING ANGLE",
	"steering_response":"TURN-IN","countersteer_assist":"COUNTERSTEER",
	"tire_grip":"TIRE GRIP","handbrake_drive_grip":"SLIDE TRACTION",
	"brake_force_n":"BRAKES","handbrake_force_n":"HANDBRAKE",
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
	return all().get(template_id,{})


static func in_slot(slot: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in all().values():
		if str(part.slot) == slot:
			result.append(part)
	return result


static func slot_name(slot: String) -> String:
	if slot == "ecu":
		return "ECU"
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
				"boost_spool_seconds": value = clampf(value,0.10,2.0)
				"mass_kg": value = clampf(value,650.0,5000.0)
				"engine_power_kw": value = clampf(value,40.0,1800.0)
				"engine_torque_nm": value = clampf(value,60.0,3000.0)
				"redline_rpm": value = clampf(value,3500.0,14000.0)
				"tire_grip": value = clampf(value,0.5,3.0)
				"rear_grip_balance": value = clampf(value,0.55,1.8)
				"cornering_stiffness": value = clampf(value,30000.0,250000.0)
				"yaw_damping": value = clampf(value,0.5,3.5)
				"countersteer_assist": value = clampf(value,0.0,0.8)
				"max_steer_degrees": value = clampf(value,20.0,60.0)
				"steering_response": value = clampf(value,4.0,30.0)
				"handbrake_drive_grip": value = clampf(value,0.25,1.0)
				"brake_force_n": value = clampf(value,6000.0,55000.0)
				"handbrake_force_n": value = clampf(value,2000.0,16000.0)
				"shift_duration": value = clampf(value,0.035,0.55)
				"auto_shift_duration": value = clampf(value,0.03,0.35)
				"final_drive": value = clampf(value,2.0,6.0)
			config.set(key,value)
		# Exhaust inventory changes the sound of the equipped engine as well
		# as the vehicle stats, and restores cleanly when the part is removed.
		if str(part.get("slot","")) == "exhaust":
			var upgrade_fraction := maxf(0.0,
				float(mods.get("engine_power_kw",0.0)))
			config.audio_aggression = clampf(
				config.audio_aggression+upgrade_fraction*7.0,0.0,1.4)
			config.audio_exhaust_roughness = clampf(
				config.audio_exhaust_roughness+upgrade_fraction*5.0,0.0,1.0)
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


static func reward_template(race_id: String, car_level: int) -> Dictionary:
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
		if str(part.rarity) == rarity and \
				bool(part.get("race_drop_enabled",true)):
			eligible.append(part)
	if eligible.is_empty():
		return {}
	return eligible[rng.randi_range(0,eligible.size()-1)]
