extends SceneTree
## Sanity-check CC0 loop imports, family ownership, and runtime mixer.
const Bank = preload("res://scripts/audio/generic_recorded_engine.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Pending = preload("res://scripts/audio/pending_vehicle_audio.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	print("%s %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures.append(label)

func _run() -> void:
	var bank := Bank.new()
	root.add_child(bank)
	check("six_imported_voice_slots", bank.voices.size() == 6)
	for i in Bank.SOURCE_NAMES.size():
		var p: AudioStreamPlayer = bank.voices[i]
		check("imported_loop_%d" % i, p.stream is AudioStreamWAV
			and p.stream.get_length() > 0.1
			and (p.stream as AudioStreamWAV).loop_end > 0
			and (p.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD)
	bank.active = true
	bank.update_mix(2600.0,1.0,0.0,false,0.25)
	var audible := 0
	for player in bank.voices:
		if player.stream != null and player.volume_db > -70.0:
			audible += 1
	check("two_adjacent_recorded_bands",audible == 2)
	bank.update_mix(2600.0,1.0,0.0,true,1.0)
	check("mute_fades_all_voices",bank.voices.all(func(p: AudioStreamPlayer) -> bool:
		return p.volume_db < -70.0))
	var live := Catalog.all()
	var pending := Pending.all()
	check("live_vehicle_profiles_present",live.size() >= 89)
	check("pending_vehicle_audio_profiles_present",pending.size() >= 150)
	var rs3: Dictionary = Catalog.find_by_id("audi-rs3")
	check("starter_rs3_keeps_real_i5_family",str(rs3.get("audio_family","")) == "i5")
	check("electric_audio_family_exists",pending.any(func(p: Dictionary) -> bool:
		return str(p.get("audio_family","")) == "electric"))
	bank.queue_free()
	print("RECORDED ENGINE BANK: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
