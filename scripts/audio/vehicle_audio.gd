extends Node
## Replace the exported streams with licensed recordings; telemetry mixing stays intact.
@export var engine_stream: AudioStream
@export var tire_stream: AudioStream
@export var shift_stream: AudioStream
@export var loose_tire_stream: AudioStream
@export_range(-50.0, -10.0) var tire_volume_db: float = -27.0
const AsphaltTires = preload("res://assets/audio/tire_asphalt.wav")
const LooseTires = preload("res://assets/audio/tire_loose.wav")
var vehicle: VehicleController2D
var engine := AudioStreamPlayer.new()
var tires := AudioStreamPlayer.new()
var scrub := AudioStreamPlayer.new()
var shift := AudioStreamPlayer.new()
var impact := AudioStreamPlayer.new()
var muted := false
var tire_intensity := 0.0
var asphalt_mix := 1.0

func _ready() -> void:
	for player in [engine, tires, scrub, shift, impact]:
		add_child(player)
	engine.stream = engine_stream if engine_stream else synth("engine", 1.0)
	tires.stream = tire_stream if tire_stream else looped(AsphaltTires)
	scrub.stream = loose_tire_stream if loose_tire_stream else looped(LooseTires)
	shift.stream = shift_stream if shift_stream else synth("shift", 0.1)
	impact.stream = synth("impact", 0.13)
	engine.volume_db = -25
	tires.volume_db = -80
	scrub.volume_db = -80
	engine.play()
	tires.play()
	scrub.play()
	vehicle.transmission.shifted.connect(func(_gear: int): shift.volume_db = -24; shift.play())
	vehicle.impacted.connect(func(strength: float):
		if strength > 2.0:
			impact.volume_db = clampf(-30.0 + strength, -28, -8)
			impact.play())

func _process(dt: float) -> void:
	if Input.is_action_just_pressed("mute"):
		muted = not muted
	var rpm_fraction := vehicle.transmission.rpm / vehicle.config.redline_rpm
	engine.pitch_scale = lerpf(0.65, 3.1, rpm_fraction)
	var engine_db := -28.0 + vehicle.throttle * 7.0 + rpm_fraction * 5.0
	engine.volume_db = lerpf(engine.volume_db, -80.0 if muted else engine_db, 1.0 - exp(-8 * dt))
	# Normal grip cornering stays quiet. Squeal builds progressively with actual
	# sliding/lock/spin, rather than sounding the same on every steering input.
	var speed := vehicle.linear_velocity.length()
	var speed_gate := smoothstep(2.0, 12.0, speed)
	var slip_sound := smoothstep(deg_to_rad(5.0), deg_to_rad(25.0), absf(vehicle.slip_angle))
	var skid := maxf(slip_sound, maxf(vehicle.handbrake * 0.65, vehicle.wheel_spin * 0.8)) * speed_gate
	var envelope_rate := 14.0 if skid > tire_intensity else 4.5
	tire_intensity = lerpf(tire_intensity, skid, 1.0 - exp(-envelope_rate * dt))
	asphalt_mix = lerpf(asphalt_mix, 1.0 if vehicle.surface == "ASPHALT" else 0.0, 1.0 - exp(-10.0 * dt))
	var tire_gain := db_to_linear(tire_volume_db) * pow(tire_intensity, 1.4) * asphalt_mix
	var loose_gain := db_to_linear(tire_volume_db - 3.0) * maxf(tire_intensity * 0.6, smoothstep(3.0, 30.0, speed) * 0.35) * (1.0 - asphalt_mix)
	tires.volume_db = -80.0 if muted else linear_to_db(maxf(tire_gain, 0.0001))
	scrub.volume_db = -80.0 if muted else linear_to_db(maxf(loose_gain, 0.0001))
	var tire_pitch := 0.93 + 0.10 * clampf(speed / 45.0, 0.0, 1.0) + 0.035 * tire_intensity
	tires.pitch_scale = lerpf(tires.pitch_scale, tire_pitch, 1.0 - exp(-5.0 * dt))
	shift.stream_paused = muted
	impact.stream_paused = muted

func looped(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

func synth(kind: String, seconds: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var rate := 22050
	data.resize(int(rate * seconds) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in int(rate * seconds):
		var t := float(i) / rate
		var sample: float
		if kind == "engine":
			sample = sin(TAU * 55 * t) * 0.42 + sin(TAU * 110 * t) * 0.25 + sin(TAU * 165 * t) * 0.12 + rng.randf_range(-0.03, 0.03)
		else:
			sample = (rng.randf_range(-0.8, 0.8) + sin(TAU * 90 * t) * 0.2) * pow(1.0 - t / seconds, 3)
		data.encode_s16(i * 2, int(clampf(sample, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if kind == "engine":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(rate * seconds)
	return stream
