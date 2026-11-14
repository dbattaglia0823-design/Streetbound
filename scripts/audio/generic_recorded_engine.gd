extends Node
## CC0 recording layer shared by unrecorded combustion engines.
## Six pitch variations of one field recording, NOT six OEM engine models.
## Existing car/family-specific recorded samples always take precedence.
const Mix = preload("res://scripts/audio/toolkit_rpm_mix.gd")
const ROOT := "res://assets/audio/engines/generic_cc0/"
const SOURCE_NAMES := [
	"loop_0.wav", "loop_1_0.wav", "loop_2_0.wav",
	"loop_3_0.wav", "loop_4_0.wav", "loop_5_0.wav"
]
# These are musical mix anchors, not asserted original recording RPMs.
const RPM_MIX_ANCHORS := [1000.0, 1850.0, 2750.0, 3900.0, 5400.0, 7000.0]
var active := false
var voices: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for file_name in SOURCE_NAMES:
		var voice := AudioStreamPlayer.new()
		voice.name = "CC0Engine_" + file_name.get_basename()
		voice.bus = "Streetbound Engine"
		voice.volume_db = -80.0
		add_child(voice)
		voices.append(voice)
		var source := load(ROOT + file_name) as AudioStreamWAV
		if source == null:
			push_warning("CC0 engine bed unavailable: " + file_name)
			continue
		# Do not modify shared imported WAVs; Godot requires a valid loop_end
		# frame rather than -1 when looping a WAV at runtime.
		var stream := source.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * float(stream.mix_rate))
		voice.stream = stream
		voice.play()

func update_mix(rpm: float, throttle: float, boost_fraction: float,
		silent: bool, dt: float) -> void:
	if voices.is_empty():
		return
	var weights := Mix.rpm_weights(rpm, RPM_MIX_ANCHORS)
	var gain := 0.46 + clampf(throttle,0.0,1.0)*0.38 + \
		clampf(boost_fraction,0.0,1.0)*0.16
	var alpha := 1.0 - exp(-maxf(0.0,dt)/0.075)
	for i in voices.size():
		var voice: AudioStreamPlayer = voices[i]
		if voice.stream == null:
			continue
		var target := -80.0
		if active and not silent:
			# Quiet real-world grit below the correct engine-family exhaust
			# synthesis; intentionally never masquerade as an exact vehicle.
			target = -22.0 + linear_to_db(maxf(0.0001, float(weights[i]) * gain))
		voice.volume_db = lerpf(voice.volume_db, target, alpha)
