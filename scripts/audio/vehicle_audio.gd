extends Node
## Engine sound follows simulated RPM, throttle, gear, and actual boost.
## Per-car combustion timbres are generated on vehicle selection, then played
## back with inexpensive layered AudioStreamPlayers. Replace these original
## synthesis loops with licensed recordings via the optional exported streams.
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
const AsphaltTires = preload("res://assets/audio/tire_asphalt.wav")
const LooseTires = preload("res://assets/audio/tire_loose.wav")
@export var engine_stream: AudioStream # Optional licensed idle loop.
@export var engine_low_stream: AudioStream
@export var engine_mid_stream: AudioStream
@export var engine_high_stream: AudioStream
@export var tire_stream: AudioStream
@export var loose_tire_stream: AudioStream
@export var shift_stream: AudioStream
@export var blowoff_stream: AudioStream
@export var flutter_stream: AudioStream
@export var exhaust_pop_stream: AudioStream
@export_range(-50.0,-10.0) var tire_volume_db: float = -27.0

var vehicle: VehicleController2D
var engine := AudioStreamPlayer.new() # Idle; preserved for existing callers.
var low := AudioStreamPlayer.new()
var mid := AudioStreamPlayer.new()
var high := AudioStreamPlayer.new()
var intake := AudioStreamPlayer.new()
var turbo := AudioStreamPlayer.new()
var gear_whine := AudioStreamPlayer.new()
var tires := AudioStreamPlayer.new()
var scrub := AudioStreamPlayer.new()
var shift := AudioStreamPlayer.new()
var blowoff := AudioStreamPlayer.new()
var flutter := AudioStreamPlayer.new()
var pop := AudioStreamPlayer.new()
var impact := AudioStreamPlayer.new()
var muted := false
var tire_intensity := 0.0
var asphalt_mix := 1.0

var _loop_players: Array[AudioStreamPlayer] = []
var _all_players: Array[AudioStreamPlayer] = []
var _config_id := 0
var _profile_family := ""
var _profile_aggression := -1.0
var _profile_roughness := -1.0
var _induction := ""
var _flutter_strength := 0.0
var _last_throttle := 0.0
var _last_boost := 0.0
var _last_rpm_fraction := 0.0
var _shift_dip_time := 0.0
var _release_cooldown := 0.0
var _pop_cooldown := 0.0
var _clock := 0.0
# Diagnostic event counters for strict headless regression coverage.
var releases_played := 0
var flutters_played := 0
var pops_played := 0


func _ready() -> void:
	name = "VehicleAudio"
	_loop_players.assign([engine,low,mid,high,intake,turbo,gear_whine,tires,scrub])
	_all_players.assign(_loop_players+[shift,blowoff,flutter,pop,impact])
	var names := ["EngineIdle","EngineLow","EngineMid","EngineHigh","Intake",
		"ForcedInduction","GearWhine","Tires","LooseTires","Shift",
		"BlowOff","CompressorFlutter","ExhaustPop","Impact"]
	for i in _all_players.size():
		var player: AudioStreamPlayer = _all_players[i]
		player.name = names[i]
		add_child(player)
		player.volume_db = -80.0
	tires.stream = tire_stream if tire_stream != null else looped(AsphaltTires)
	scrub.stream = loose_tire_stream if loose_tire_stream != null else looped(LooseTires)
	shift.stream = shift_stream if shift_stream != null else Synth.transient("shift")
	blowoff.stream = blowoff_stream if blowoff_stream != null else Synth.transient("bov")
	flutter.stream = flutter_stream if flutter_stream != null else Synth.transient("flutter")
	pop.stream = exhaust_pop_stream if exhaust_pop_stream != null else Synth.transient("pop")
	impact.stream = Synth.transient("impact")
	if is_instance_valid(vehicle):
		_configure_engine(true)
		vehicle.transmission.shifted.connect(_on_shift)
		vehicle.impacted.connect(_on_impact)
	for player in _loop_players:
		if player.stream != null and not player.playing:
			player.play()


func _configure_engine(force := false) -> void:
	if not is_instance_valid(vehicle) or vehicle.config == null:
		return
	var cfg: VehicleConfig = vehicle.config
	var family := cfg.audio_family if Synth.family_supported(cfg.audio_family) else "v8_cross"
	var aggression := clampf(cfg.audio_aggression,0.0,1.4)
	var roughness := clampf(cfg.audio_exhaust_roughness,0.0,1.0)
	var induction := str(cfg.audio_induction)
	if induction == "turbo" and cfg.boost_max_psi <= 0.05:
		induction = "naturally_aspirated"
	if not force and _config_id == cfg.get_instance_id() and \
		_profile_family == family and \
		is_equal_approx(_profile_aggression,aggression) and \
		is_equal_approx(_profile_roughness,roughness) and \
		_induction == induction:
		_flutter_strength = clampf(cfg.audio_flutter,0.0,1.0)
		return
	_config_id = cfg.get_instance_id()
	_profile_family = family
	_profile_aggression = aggression
	_profile_roughness = roughness
	_induction = induction
	_flutter_strength = clampf(cfg.audio_flutter,0.0,1.0)
	_last_throttle = 0.0
	_last_boost = 0.0
	_last_rpm_fraction = 0.0
	_shift_dip_time = 0.0
	var streams: Array[AudioStream] = [
		engine_stream if engine_stream != null else \
			Synth.engine_loop(family,0,aggression,roughness),
		engine_low_stream if engine_low_stream != null else \
			Synth.engine_loop(family,1,aggression,roughness),
		engine_mid_stream if engine_mid_stream != null else \
			Synth.engine_loop(family,2,aggression,roughness),
		engine_high_stream if engine_high_stream != null else \
			Synth.engine_loop(family,3,aggression,roughness),
		Synth.texture_loop("intake"),
		Synth.texture_loop("blower" if induction == "supercharger" else "turbo"),
		Synth.texture_loop("gear")]
	for i in streams.size():
		var player: AudioStreamPlayer = _loop_players[i]
		player.stop()
		player.stream = streams[i]
		player.volume_db = -80.0
		player.play()


func _on_shift(_gear: int) -> void:
	_shift_dip_time = 0.13
	if muted:
		return
	shift.volume_db = -22.0+2.0*_profile_aggression
	shift.play()
	if _induction == "turbo" and is_instance_valid(vehicle) and \
		vehicle.boost_psi >= 2.5 and _release_cooldown <= 0.0:
		_release_pressure(vehicle.boost_psi,true)
	# High-rev sports exhaust occasionally crackles across a fast shift.
	if _profile_aggression >= 0.8 and _last_rpm_fraction >= 0.72 and \
		_pop_cooldown <= 0.0:
		_play_pop(0.7)


func _on_impact(strength: float) -> void:
	if strength > 2.0 and not muted:
		impact.volume_db = clampf(-30.0+strength,-28.0,-8.0)
		impact.play()


func _release_pressure(psi: float, during_shift := false) -> void:
	if muted or _induction != "turbo" or _release_cooldown > 0.0 or \
		not is_instance_valid(vehicle) or vehicle.config.boost_max_psi <= 0.05:
		return
	var ratio := clampf(psi/maxf(vehicle.config.boost_max_psi,0.1),0.0,1.0)
	if psi < 2.0 or ratio < 0.16:
		return
	_release_cooldown = 0.22
	# Modified, hard-lift turbo tunes chatter, while recirculating systems
	# produce a softer valve hiss. Both obey real manifold charge pressure.
	var flutter_probability := _flutter_strength * \
		(1.0 if not during_shift else 0.82)
	if flutter_probability >= 0.52 and ratio > 0.26:
		flutter.pitch_scale = clampf(0.83+ratio*0.35,0.8,1.35)
		flutter.volume_db = -29.0+ratio*8.0+_profile_aggression*1.8
		flutter.play()
		flutters_played += 1
	else:
		blowoff.pitch_scale = 0.85+ratio*0.27
		blowoff.volume_db = -28.5+ratio*9.5+_profile_aggression*1.5
		blowoff.play()
		releases_played += 1


func _play_pop(intensity: float) -> void:
	if muted or _pop_cooldown > 0.0:
		return
	_pop_cooldown = 0.35
	pop.volume_db = -34.0+clampf(intensity,0.0,1.0)*12.0+ \
		_profile_aggression*2.0
	pop.pitch_scale = 0.88+0.15*sin(_clock*7.4)
	pop.play()
	pops_played += 1


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("mute"):
		muted = not muted
	if not is_instance_valid(vehicle) or vehicle.config == null:
		return
	_configure_engine()
	var delta := clampf(dt,0.0,0.1)
	_clock += delta
	_shift_dip_time = maxf(0.0,_shift_dip_time-delta)
	_release_cooldown = maxf(0.0,_release_cooldown-delta)
	_pop_cooldown = maxf(0.0,_pop_cooldown-delta)
	var cfg: VehicleConfig = vehicle.config
	var rpm := clampf(vehicle.transmission.rpm,cfg.idle_rpm,cfg.redline_rpm)
	var revs := clampf((rpm-cfg.idle_rpm)/maxf(1.0,cfg.redline_rpm-cfg.idle_rpm),
		0.0,1.0)
	var throttle := clampf(vehicle.brake if vehicle.reversing else vehicle.throttle,
		0.0,1.0)
	var boost := maxf(0.0,vehicle.boost_psi)
	if _last_throttle-throttle > 0.27 and _last_throttle >= 0.47 and \
		_last_boost >= 2.4:
		_release_pressure(_last_boost,false)
	if _last_throttle-throttle > 0.35 and _last_throttle >= 0.58 and \
		_last_rpm_fraction > 0.60 and _profile_aggression >= 0.68:
		_play_pop(revs)
	_last_throttle = throttle
	_last_boost = boost
	_last_rpm_fraction = revs
	# Shift torque interruptions are short, rather than a pitch spike.
	var shift_gain := 0.46 if _shift_dip_time > 0.0 else 1.0
	var engine_load := (0.48+throttle*0.52)*shift_gain
	var weight := PackedFloat32Array([
		1.0-smoothstep(0.06,0.27,revs),
		smoothstep(0.05,0.24,revs)*(1.0-smoothstep(0.40,0.60,revs)),
		smoothstep(0.35,0.54,revs)*(1.0-smoothstep(0.74,0.88,revs)),
		smoothstep(0.68,0.87,revs)
	])
	var smoothing := 1.0-exp(-11.0*delta)
	for i in 4:
		var player: AudioStreamPlayer = _loop_players[i]
		var ref_rpm := float(Synth.REFERENCE_RPM[i])
		var target_pitch := clampf(rpm/ref_rpm,0.48,1.75)
		player.pitch_scale = lerpf(player.pitch_scale,target_pitch,
			1.0-exp(-16.0*delta))
		var gain := float(weight[i])*engine_load
		var db := -26.0+_profile_aggression*3.3+revs*3.0+ \
			linear_to_db(maxf(gain,0.0001))
		player.volume_db = lerpf(player.volume_db,-80.0 if muted else maxf(-80.0,db),
			smoothing)
	var intake_volume := -48.0+throttle*13.0+revs*9.0+_profile_aggression*2.0
	intake.pitch_scale = 0.76+revs*1.15
	intake.volume_db = lerpf(intake.volume_db,
		-80.0 if muted else intake_volume,1.0-exp(-9.0*delta))
	var turbo_db := -80.0
	if _induction == "turbo" and cfg.boost_max_psi > 0.05:
		var pressure := clampf(boost/cfg.boost_max_psi,0.0,1.0)
		turbo_db = -52.0+pressure*20.0+throttle*7.0+revs*5.5
		turbo.pitch_scale = 0.95+revs*1.7+pressure*1.2
	elif _induction == "supercharger":
		turbo_db = -51.0+revs*15.0+throttle*10.0
		turbo.pitch_scale = 0.92+revs*2.0
	turbo.volume_db = lerpf(turbo.volume_db,
		-80.0 if muted else turbo_db,1.0-exp(-13.0*delta))
	var speed := vehicle.linear_velocity.length()
	gear_whine.pitch_scale = clampf(0.65+speed/34.0,0.65,2.4)
	gear_whine.volume_db = lerpf(gear_whine.volume_db,
		-80.0 if muted or speed < 4.0 else \
			-54.0+smoothstep(4.0,45.0,speed)*13.0+_profile_aggression*2.5,
			1.0-exp(-9.0*delta))
	# Existing surface-reactive tire layers remain distinct from exhaust/
	# turbo; tire audio only plays when a tire actually skids or scrubs.
	var speed_gate := smoothstep(2.0,12.0,speed)
	var slip_sound := smoothstep(deg_to_rad(5.0),
		deg_to_rad(25.0),absf(vehicle.slip_angle))
	var skid := maxf(slip_sound,maxf(vehicle.handbrake*0.65,
		vehicle.wheel_spin*0.8))*speed_gate
	var envelope_rate := 14.0 if skid > tire_intensity else 4.5
	tire_intensity = lerpf(tire_intensity,skid,
		1.0-exp(-envelope_rate*delta))
	asphalt_mix = lerpf(asphalt_mix,
		1.0 if vehicle.surface == "ASPHALT" else 0.0,
		1.0-exp(-10.0*delta))
	var tire_gain := db_to_linear(tire_volume_db)*pow(tire_intensity,1.4)*asphalt_mix
	var loose_gain := db_to_linear(tire_volume_db-3.0)*maxf(tire_intensity*0.6,
		smoothstep(3.0,30.0,speed)*0.35)*(1.0-asphalt_mix)
	tires.volume_db = -80.0 if muted else linear_to_db(maxf(tire_gain,0.0001))
	scrub.volume_db = -80.0 if muted else linear_to_db(maxf(loose_gain,0.0001))
	var tire_pitch := 0.93+0.10*clampf(speed/45.0,0.0,1.0)+ \
		0.035*tire_intensity
	tires.pitch_scale = lerpf(tires.pitch_scale,tire_pitch,
		1.0-exp(-5.0*delta))
	for player in [shift,blowoff,flutter,pop,impact]:
		player.stream_paused = muted


func looped(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length()*stream.mix_rate)
	return stream
