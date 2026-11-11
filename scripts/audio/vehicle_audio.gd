extends Node
## Fully layered Streetbound audio mixer. Source loops are original, seamless
## synthesised beds, or optionally supplied licensed recordings. The mixer
## never generates PCM in _process; it only envelopes AudioStreamPlayers.
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
const SampleBank = preload("res://scripts/audio/vehicle_audio_sample_bank.gd")
const AsphaltTires = preload("res://assets/audio/tire_asphalt.wav")
const LooseTires = preload("res://assets/audio/tire_loose.wav")

@export var engine_stream: AudioStream # Optional licensed power idle sample
@export var engine_low_stream: AudioStream
@export var engine_mid_stream: AudioStream
@export var engine_high_stream: AudioStream
@export var coast_idle_stream: AudioStream
@export var coast_low_stream: AudioStream
@export var coast_mid_stream: AudioStream
@export var coast_high_stream: AudioStream
@export var tire_stream: AudioStream
@export var loose_tire_stream: AudioStream
@export var shift_stream: AudioStream
@export var blowoff_stream: AudioStream
@export var flutter_stream: AudioStream
@export var exhaust_pop_stream: AudioStream
@export var ignition_stream: AudioStream
@export var shutdown_stream: AudioStream
@export var downshift_stream: AudioStream
@export var limiter_stream: AudioStream
@export var curb_stream: AudioStream
@export_range(-50.0,-10.0) var tire_volume_db: float = -27.0

var vehicle: VehicleController2D
# Kept public and named for preexisting HUD/runtime/audio test contracts.
var engine := AudioStreamPlayer.new()
var low := AudioStreamPlayer.new()
var mid := AudioStreamPlayer.new()
var high := AudioStreamPlayer.new()
var coast_idle := AudioStreamPlayer.new()
var coast_low := AudioStreamPlayer.new()
var coast_mid := AudioStreamPlayer.new()
var coast_high := AudioStreamPlayer.new()
var intake := AudioStreamPlayer.new()
var turbo := AudioStreamPlayer.new()
var gear_whine := AudioStreamPlayer.new()
var wind := AudioStreamPlayer.new()
var road := AudioStreamPlayer.new()
var driveline := AudioStreamPlayer.new()
## Real CC0 recorded engine bed: subtle organic texture beneath each
## vehicle's model-specific, RPM-correct power/coast synthesis.
var recorded_texture := AudioStreamPlayer.new()
var tires := AudioStreamPlayer.new()
var scrub := AudioStreamPlayer.new()
var shift := AudioStreamPlayer.new()
var blowoff := AudioStreamPlayer.new()
var flutter := AudioStreamPlayer.new()
var pop := AudioStreamPlayer.new()
var impact := AudioStreamPlayer.new()
var ignition := AudioStreamPlayer.new()
var shutdown := AudioStreamPlayer.new()
var downshift := AudioStreamPlayer.new()
var limiter := AudioStreamPlayer.new()
var curb := AudioStreamPlayer.new()

var muted := false
var tire_intensity := 0.0
var asphalt_mix := 1.0
var _loop_players: Array[AudioStreamPlayer] = []
var _all_players: Array[AudioStreamPlayer] = []
var _config_id := 0
var _profile_family := ""
var _profile_aggression := -1.0
var _profile_roughness := -1.0
var _profile_tone := 0.0
var _induction := ""
var _flutter_strength := 0.0
var _last_throttle := 0.0
var _last_boost := 0.0
var _last_rpm_fraction := 0.0
var _last_gear := 1
var _last_curb_height := 0.0
var _shift_dip_time := 0.0
var _limiter_dip_time := 0.0
var _release_cooldown := 0.0
var _pop_cooldown := 0.0
var _limiter_cooldown := 0.0
var _curb_cooldown := 0.0
var _overrun_clock := 0.0
var _clock := 0.0
var _started_once := false

# Diagnostics for headless regression and in-game audio tuning.
var releases_played := 0
var flutters_played := 0
var pops_played := 0
var downshifts_played := 0
var limiters_played := 0
var ignitions_played := 0
var curb_hits_played := 0


func _ready() -> void:
	name = "VehicleAudio"
	_loop_players.assign([engine,low,mid,high,coast_idle,coast_low,
		coast_mid,coast_high,intake,turbo,gear_whine,wind,road,driveline,
		tires,scrub,recorded_texture])
	_all_players.assign(_loop_players+[shift,blowoff,flutter,pop,impact,
		ignition,shutdown,downshift,limiter,curb])
	var names := ["EngineIdle","EngineLow","EngineMid","EngineHigh",
		"CoastIdle","CoastLow","CoastMid","CoastHigh","Intake",
		"ForcedInduction","GearWhine","Wind","Road","Driveline",
		"Tires","LooseTires","RecordedEngineTexture","Shift","BlowOff","CompressorFlutter",
		"ExhaustPop","Impact","Ignition","Shutdown","DownshiftBlip",
		"RevLimiter","CurbContact"]
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
	ignition.stream = ignition_stream if ignition_stream != null else Synth.transient("ignition")
	shutdown.stream = shutdown_stream if shutdown_stream != null else Synth.transient("shutdown")
	downshift.stream = downshift_stream if downshift_stream != null else Synth.transient("blip")
	limiter.stream = limiter_stream if limiter_stream != null else Synth.transient("limiter")
	curb.stream = curb_stream if curb_stream != null else Synth.transient("curb")
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
	var tone := clampf(cfg.audio_tone,-1.0,1.0)
	var induction := str(cfg.audio_induction)
	if induction == "turbo" and cfg.boost_max_psi <= 0.05:
		induction = "naturally_aspirated"
	if not force and _config_id == cfg.get_instance_id() and \
		_profile_family == family and \
		is_equal_approx(_profile_aggression,aggression) and \
		is_equal_approx(_profile_roughness,roughness) and \
		is_equal_approx(_profile_tone,tone) and _induction == induction:
		_flutter_strength = clampf(cfg.audio_flutter,0.0,1.0)
		return
	var switching_car := _started_once and _config_id != cfg.get_instance_id()
	_config_id = cfg.get_instance_id()
	_profile_family = family
	_profile_aggression = aggression
	_profile_roughness = roughness
	_profile_tone = tone
	_induction = induction
	_flutter_strength = clampf(cfg.audio_flutter,0.0,1.0)
	_last_throttle = 0.0
	_last_boost = 0.0
	_last_rpm_fraction = 0.0
	_last_gear = vehicle.transmission.gear
	_overrun_clock = 0.0
	_shift_dip_time = 0.0
	var streams: Array[AudioStream] = []
	var explicit_power: Array[AudioStream] = [
		engine_stream,engine_low_stream,engine_mid_stream,engine_high_stream]
	var explicit_coast: Array[AudioStream] = [
		coast_idle_stream,coast_low_stream,coast_mid_stream,coast_high_stream]
	var band_names := ["idle","low","mid","high"]
	for i in 4:
		streams.append(_engine_recording_or_original(cfg,
			"power_"+band_names[i],explicit_power[i],family,i,true,
			aggression,roughness,tone))
	for i in 4:
		streams.append(_engine_recording_or_original(cfg,
			"coast_"+band_names[i],explicit_coast[i],family,i,false,
			aggression,roughness,tone))
	streams.append(Synth.texture_loop("intake"))
	streams.append(Synth.texture_loop(
		"blower" if induction == "supercharger" else "turbo"))
	streams.append(Synth.texture_loop("gear"))
	streams.append(Synth.texture_loop("wind"))
	streams.append(Synth.texture_loop("road"))
	streams.append(Synth.texture_loop("drivetrain"))

	for i in streams.size():
		var player: AudioStreamPlayer = _loop_players[i]
		player.stop()
		player.stream = streams[i]
		player.volume_db = -80.0
		player.play()
	# One-shots can also be replaced by a cleared model or family sample.
	var fx_players: Array[AudioStreamPlayer] = [
		shift,blowoff,flutter,pop,ignition,shutdown,downshift,limiter,curb]
	var fx_slots := ["shift","blowoff","flutter","pop","ignition",
		"shutdown","downshift","limiter","curb"]
	var fx_overrides: Array[AudioStream] = [
		shift_stream,blowoff_stream,flutter_stream,exhaust_pop_stream,
		ignition_stream,shutdown_stream,downshift_stream,limiter_stream,curb_stream]
	var fx_fallbacks := ["shift","bov","flutter","pop","ignition",
		"shutdown","blip","limiter","curb"]
	# Recorded references share an acoustic family, never an invented exact
	# make/model identity. A future per-car recording overrides that family.
	var recording: AudioStream = SampleBank.resolve(
		cfg.audio_sample_id,family,"recorded_texture")
	if recorded_texture.stream != recording:
		recorded_texture.stop()
		recorded_texture.stream = recording
		if recording is AudioStreamOggVorbis:
			(recording as AudioStreamOggVorbis).loop = true
		elif recording is AudioStreamMP3:
			(recording as AudioStreamMP3).loop = true
		elif recording is AudioStreamWAV:
			(recording as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		if recording != null:
			recorded_texture.volume_db = -80.0
			recorded_texture.play()
	for i in fx_players.size():
		var resolved: AudioStream = SampleBank.resolve(cfg.audio_sample_id,
			family,fx_slots[i],fx_overrides[i])
		if resolved == null:
			resolved = Synth.transient(fx_fallbacks[i])
		if fx_players[i].stream != resolved:
			fx_players[i].stop()
			fx_players[i].stream = resolved
	if not muted and (not _started_once or switching_car):
		if switching_car:
			shutdown.volume_db = -38.0+_profile_aggression*5.0
			shutdown.play()
		ignition.volume_db = -34.0+_profile_aggression*7.0
		ignition.play()
		ignitions_played += 1
	_started_once = true


func _engine_recording_or_original(cfg: VehicleConfig, slot: String,
		override: AudioStream, family: String, stage: int, loaded: bool,
		aggression: float, roughness: float, tone: float) -> AudioStream:
	var sample: AudioStream = SampleBank.resolve(
		cfg.audio_sample_id,family,slot,override)
	if sample != null:
		return sample
	return Synth.engine_loop(family,stage,aggression,roughness,loaded,tone)


func _on_shift(new_gear: int) -> void:
	var downshifted := new_gear < _last_gear
	_last_gear = new_gear
	_shift_dip_time = 0.125 if not downshifted else 0.075
	if muted:
		return
	shift.volume_db = -25.0+3.0*_profile_aggression
	shift.pitch_scale = 1.2 if downshifted else 0.95
	shift.play()
	if downshifted and is_instance_valid(vehicle):
		# Rev-match blip on manual and sequential downshifts. The audio-only
		# transient does not modify the gearbox or wheel torque.
		downshift.volume_db = -33.0+_profile_aggression*8.0
		downshift.pitch_scale = clampf(0.82+vehicle.transmission.rpm/10000.0,
			0.88,1.6)
		downshift.play()
		downshifts_played += 1
	if _induction == "turbo" and is_instance_valid(vehicle) and \
		vehicle.boost_psi >= 2.5 and _release_cooldown <= 0.0:
		_release_pressure(vehicle.boost_psi,true)
	if _profile_aggression >= 0.8 and _last_rpm_fraction >= 0.72 and \
		_pop_cooldown <= 0.0 and not downshifted:
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
	_release_cooldown = 0.28
	# Strong turbo tunes chatter, while mild recirculated valves produce
	# shorter air discharge. Pressure and cooldown prevent fake releases.
	var flutter_strength := _flutter_strength*(0.82 if during_shift else 1.0)
	if flutter_strength >= 0.52 and ratio > 0.26:
		flutter.pitch_scale = clampf(0.78+ratio*0.42,0.75,1.4)
		flutter.volume_db = -32.0+ratio*8.0+_profile_aggression*2.0
		flutter.play()
		flutters_played += 1
	else:
		blowoff.pitch_scale = 0.84+ratio*0.32
		blowoff.volume_db = -30.0+ratio*10.0+_profile_aggression*1.5
		blowoff.play()
		releases_played += 1


func _play_pop(intensity: float) -> void:
	if muted or _pop_cooldown > 0.0:
		return
	_pop_cooldown = 0.38
	pop.volume_db = -37.0+clampf(intensity,0.0,1.0)*13.0+ \
		_profile_aggression*2.5
	pop.pitch_scale = 0.88+0.12*sin(_clock*7.4)
	pop.play()
	pops_played += 1


func _limiter_tick() -> void:
	if muted or _limiter_cooldown > 0.0:
		return
	_limiter_dip_time = 0.054
	_limiter_cooldown = 0.145
	limiter.volume_db = -34.0+_profile_aggression*9.0
	limiter.pitch_scale = 0.85+clampf(_profile_tone,-1.0,1.0)*0.08
	limiter.play()
	limiters_played += 1


func _curb_contact(dt: float) -> void:
	if not is_instance_valid(vehicle) or _curb_cooldown > 0.0:
		return
	var art := vehicle.get_node_or_null("Art")
	if not is_instance_valid(art) or not art.get("curb_heave") is float:
		return
	var height := clampf(float(art.curb_heave),0.0,1.0)
	if _last_curb_height < 0.12 and height >= 0.12 and \
		vehicle.linear_velocity.length() >= 4.0 and not muted:
		curb.volume_db = clampf(-34.0+vehicle.linear_velocity.length()*0.14,
			-34.0,-22.0)
		curb.play()
		curb_hits_played += 1
		_curb_cooldown = 0.45
	_last_curb_height = height


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("mute"):
		muted = not muted
	if not is_instance_valid(vehicle) or vehicle.config == null:
		return
	_configure_engine()
	var delta := clampf(dt,0.0,0.1)
	_clock += delta
	_shift_dip_time = maxf(0.0,_shift_dip_time-delta)
	_limiter_dip_time = maxf(0.0,_limiter_dip_time-delta)
	_release_cooldown = maxf(0.0,_release_cooldown-delta)
	_pop_cooldown = maxf(0.0,_pop_cooldown-delta)
	_limiter_cooldown = maxf(0.0,_limiter_cooldown-delta)
	_curb_cooldown = maxf(0.0,_curb_cooldown-delta)
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
	# Actual redline fuel cut: stuttering layer and dry mechanical ticks.
	if revs >= 0.985 and throttle > 0.82 and \
		vehicle.transmission.shift_timer <= 0.0:
		_limiter_tick()
	# Restrained overrun crackles on performance-oriented cars only. Do
	# not create endless pops from low-rev traffic, braking or idle.
	if throttle < 0.14 and revs > 0.45 and \
		vehicle.linear_velocity.length() > 9.0 and cfg.audio_overrun >= 0.42:
		_overrun_clock += delta*cfg.audio_overrun
		if _overrun_clock > 1.4 and _pop_cooldown <= 0.0:
			_overrun_clock = 0.0
			_play_pop(0.35+0.5*cfg.audio_overrun)
	else:
		_overrun_clock = 0.0
	_curb_contact(delta)
	# Engine load and overrun are real different timbres, not just volume.
	var shift_gain := 0.46 if _shift_dip_time > 0.0 else 1.0
	var limiter_gain := 0.33 if _limiter_dip_time > 0.0 else 1.0
	var engine_load := (0.46+throttle*0.54)*shift_gain*limiter_gain
	var power_mix := clampf(0.16+throttle*0.84,0.0,1.0)
	if revs < 0.11 and vehicle.linear_velocity.length() < 2.0:
		power_mix = maxf(power_mix,0.30)
	var weight := PackedFloat32Array([
		1.0-smoothstep(0.06,0.27,revs),
		smoothstep(0.05,0.24,revs)*(1.0-smoothstep(0.40,0.60,revs)),
		smoothstep(0.35,0.54,revs)*(1.0-smoothstep(0.74,0.88,revs)),
		smoothstep(0.68,0.87,revs)
	])
	var smoothing := 1.0-exp(-11.0*delta)
	var idle_pulse := 1.0
	if revs <= 0.13 and throttle < 0.2:
		idle_pulse += cfg.audio_lope*0.085*sin(_clock*9.1)
	for i in 4:
		var reference_rpm := float(Synth.REFERENCE_RPM[i])
		var target_pitch := clampf(rpm/reference_rpm,0.48,1.75)* \
			(1.0+cfg.audio_lope*0.002*sin(_clock*6.1))
		for side in 2:
			var player: AudioStreamPlayer = _loop_players[i+side*4]
			player.pitch_scale = lerpf(player.pitch_scale,target_pitch,
				1.0-exp(-16.0*delta))
			var mix := power_mix if side == 0 else (1.0-power_mix)
			var gain := float(weight[i])*engine_load*mix*idle_pulse
			var db := -25.5+_profile_aggression*3.3+revs*2.8+ \
				linear_to_db(maxf(gain,0.0001))
			player.volume_db = lerpf(player.volume_db,
				-80.0 if muted else maxf(-80.0,db),smoothing)
	var intake_volume := -54.0+throttle*17.0+revs*10.0+ \
		cfg.audio_intake_presence*5.0
	intake.pitch_scale = 0.76+revs*1.15
	intake.volume_db = lerpf(intake.volume_db,
		-80.0 if muted else intake_volume,1.0-exp(-9.0*delta))
	var turbo_db := -80.0
	if _induction == "turbo" and cfg.boost_max_psi > 0.05:
		var pressure := clampf(boost/cfg.boost_max_psi,0.0,1.0)
		turbo_db = -63.0+pressure*23.0+throttle*6.0+revs*6.0+ \
			cfg.audio_turbo_presence*4.0
		turbo.pitch_scale = 0.95+revs*1.7+pressure*1.2
	elif _induction == "supercharger":
		turbo_db = -54.0+revs*15.0+throttle*10.0+ \
			cfg.audio_turbo_presence*2.5
		turbo.pitch_scale = 0.92+revs*2.0
	turbo.volume_db = lerpf(turbo.volume_db,
		-80.0 if muted else turbo_db,1.0-exp(-13.0*delta))
	var speed := vehicle.linear_velocity.length()
	gear_whine.pitch_scale = clampf(0.65+speed/34.0,0.65,2.4)
	gear_whine.volume_db = lerpf(gear_whine.volume_db,
		-80.0 if muted or speed < 4.0 else \
			-59.0+smoothstep(4.0,45.0,speed)*13.0+ \
			cfg.audio_driveline_presence*7.0,1.0-exp(-9.0*delta))
	driveline.pitch_scale = clampf(0.7+speed/37.0,0.7,2.4)
	driveline.volume_db = lerpf(driveline.volume_db,
		-80.0 if muted or speed < 5.0 else \
			-59.0+smoothstep(5.0,60.0,speed)*14.0+ \
			cfg.audio_driveline_presence*4.0,1.0-exp(-7.0*delta))
	# Full-vehicle airflow and road-contact beds keep coasting audible
	# independently of engine load, especially during long highway drives.
	wind.pitch_scale = clampf(0.73+speed/62.0,0.73,2.2)
	var wind_db := -80.0 if speed < 7.0 else \
		-67.0+smoothstep(7.0,65.0,speed)*29.0
	wind.volume_db = lerpf(wind.volume_db,
		-80.0 if muted else wind_db,1.0-exp(-5.0*delta))
	var surface_roughness := 0.0 if vehicle.surface == "ASPHALT" else \
		(1.0 if vehicle.surface in ["GRAVEL","DIRT"] else 0.45)
	road.pitch_scale = clampf(0.74+speed/58.0,0.74,2.2)
	var road_db := -80.0 if speed < 3.0 else \
		-63.0+smoothstep(3.0,40.0,speed)*21.0+surface_roughness*10.0
	road.volume_db = lerpf(road.volume_db,
		-80.0 if muted else road_db,1.0-exp(-7.0*delta))
	# One family-matched CC0 field texture is mixed underneath the accurate
	# engine synth, rather than passing a generic recording off as each car.
	# Pitch follows its real RPM, but a single recording is NOT treated as a
	# multi-RPM OEM pack. Its restrained level preserves tonal identity.
	if recorded_texture.stream != null:
		var texture_pitch := clampf(0.71+revs*0.92,0.7,1.7)
		recorded_texture.pitch_scale = lerpf(recorded_texture.pitch_scale,
			texture_pitch,1.0-exp(-8.0*delta))
		var recorded_db := -40.0+throttle*8.0+revs*2.5+ \
			cfg.audio_aggression*1.5
		recorded_texture.volume_db = lerpf(recorded_texture.volume_db,
			-80.0 if muted else recorded_db,1.0-exp(-9.0*delta))
	# Surface-reactive tyres remain quiet unless actual loss of grip occurs.
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
	for player in [shift,blowoff,flutter,pop,impact,ignition,
			shutdown,downshift,limiter,curb]:
		player.stream_paused = muted


func looped(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length()*stream.mix_rate)
	return stream
