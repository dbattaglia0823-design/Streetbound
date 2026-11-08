extends Node
## Replace the exported streams with licensed recordings; telemetry mixing stays intact.
@export var engine_stream: AudioStream
@export var tire_stream: AudioStream
@export var shift_stream: AudioStream
var vehicle: VehicleController2D
var engine := AudioStreamPlayer.new()
var tires := AudioStreamPlayer.new()
var shift := AudioStreamPlayer.new()
var impact := AudioStreamPlayer.new()
var muted := false

func _ready() -> void:
	for player in [engine, tires, shift, impact]:
		add_child(player)
	engine.stream = engine_stream if engine_stream else synth("engine", 1.0)
	tires.stream = tire_stream if tire_stream else synth("tire", 1.0)
	shift.stream = shift_stream if shift_stream else synth("shift", 0.1)
	impact.stream = synth("impact", 0.13)
	engine.volume_db = -25
	tires.volume_db = -60
	engine.play()
	tires.play()
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
	var skid := clampf(absf(vehicle.slip_angle) * 2.0 + vehicle.handbrake * 0.65, 0.0, 1.0) * clampf(vehicle.linear_velocity.length() / 10, 0, 1)
	if vehicle.surface != "ASPHALT":
		skid = maxf(skid * 0.5, clampf(vehicle.linear_velocity.length() / 40, 0, 0.5))
	tires.volume_db = -80 if muted or skid < 0.08 else linear_to_db(skid * 0.18)
	tires.pitch_scale = 0.8 if vehicle.surface != "ASPHALT" else 1.1
	shift.stream_paused = muted
	impact.stream_paused = muted

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
		elif kind == "tire":
			sample = rng.randf_range(-0.45, 0.45) + sin(TAU * 920 * t) * 0.12
		else:
			sample = (rng.randf_range(-0.8, 0.8) + sin(TAU * 90 * t) * 0.2) * pow(1.0 - t / seconds, 3)
		data.encode_s16(i * 2, int(clampf(sample, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if kind in ["engine", "tire"]:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(rate * seconds)
	return stream
