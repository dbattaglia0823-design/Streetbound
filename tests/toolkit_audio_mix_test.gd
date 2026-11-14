extends SceneTree
## Pure regression coverage for the Toolkit-derived audio mixer.
const Mix = preload("res://scripts/audio/toolkit_rpm_mix.gd")
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL",label])
	if not condition:
		failures.append(label)

func _run() -> void:
	var refs: Array = Synth.REFERENCE_RPM
	check("supports_all_engine_families", Synth.family_supported("i5")
		and Synth.family_supported("v8_cross"))
	var idle := Mix.rpm_weights(900.0,refs)
	check("below_first_reference", idle.size() == 4 and
		is_equal_approx(idle[0],1.0) and is_equal_approx(idle[1],0.0))
	var maximum := Mix.rpm_weights(9000.0,refs)
	check("above_last_reference", is_equal_approx(maximum[3],1.0))
	for rpm in [1300.0,1800.0,2600.0,3200.0,4200.0,5800.0]:
		var bands := Mix.rpm_weights(rpm,refs)
		var energy := 0.0
		var active := 0
		for weight in bands:
			energy += weight*weight
			if weight > 0.001:
				active += 1
		check("band_energy_%d" % int(rpm), absf(energy-1.0)<0.001 and active<=2)
	var coasting := Mix.load_weights(0.0,0.0,0.6)
	var accelerating := Mix.load_weights(1.0,0.8,0.6)
	check("coasting_favors_overrun", coasting.y > coasting.x)
	check("acceleration_favors_power", accelerating.x > accelerating.y)
	check("load_crossfade_energy", absf(accelerating.length_squared()-1.0)<0.001)
	print("TOOLKIT AUDIO MIX: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
