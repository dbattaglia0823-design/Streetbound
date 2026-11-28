extends Node
## Scene-owned ambient mixer: cached finite PCM beds, no per-sample work
## during gameplay. Menu events never spawn police or consume gameplay RNG.
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
const Emergency = preload("res://scripts/visual/police_emergency_effects.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const RATE := 11025
const FRAMES := RATE * 8
const FADE_FRAMES := 1024
const SILENT_DB := -80.0
const BEDS := ["city","wind","surf","rain"]
static var _beds: Dictionary = {}
var menu_mode := false
var world: Node
var listener: Node2D
var player_audio: Node
var muted := false
var voices: Dictionary = {}
var gains: Dictionary = {}
var targets: Dictionary = {}
var idle: AudioStreamPlayer
var siren: AudioStreamPlayer
var siren_wait := 0.0
var siren_elapsed := 0.0
var siren_duration := 0.0
var _probe_clock := 0.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()

static func bed_stream(kind: String) -> AudioStreamWAV:
	if _beds.has(kind):return _beds[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = 56102 + kind.hash()
	var samples := PackedFloat32Array()
	samples.resize(FRAMES+FADE_FRAMES)
	var low := 0.0
	var middle := 0.0
	for i in samples.size():
		var t := float(i)/RATE
		var white := rng.randf_range(-1.0,1.0)
		low=lerpf(low,white,.012)
		middle=lerpf(middle,white,.14)
		var value := 0.0
		match kind:
			"city":
				# Distant rolling traffic, low mechanical hum and passing swells.
				var swell := .55+.25*sin(TAU*t/4.0)+.12*sin(TAU*t/2.7)
				value=(low*2.2+middle*.30+sin(TAU*57.0*t)*.035+sin(TAU*83.0*t)*.025)*swell
			"wind":
				var gust := .48+.26*sin(TAU*t/5.0)+.16*sin(TAU*t/2.9)
				value=(low*1.8+middle*.26)*gust
			"surf":
				var wave := pow(.5+.5*sin(TAU*t/4.0-.8),2.0)
				value=(middle*.70+low*1.2+white*.08)*(.17+.72*wave)
			"rain":
				value=white*.10+middle*.32+low*.28
		samples[i]=clampf(value,-.85,.85)
	# Crossfade the extra tail onto the loop beginning. The first sample
	# continues the last sample's waveform instead of jumping to a new noise seed.
	var data := PackedByteArray()
	data.resize(FRAMES*2)
	for i in FRAMES:
		var value := float(samples[i])
		if i<FADE_FRAMES:
			var blend := smoothstep(0.0,1.0,float(i)/FADE_FRAMES)
			value=lerpf(float(samples[FRAMES+i]),value,blend)
		data.encode_s16(i*2,roundi(value*32767.0))
	var stream := AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=RATE
	stream.data=data
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_end=FRAMES
	_beds[kind]=stream
	return stream

func _voice(id: String, stream: AudioStream) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.name=id
	voice.stream=stream
	voice.volume_db=SILENT_DB
	add_child(voice)
	return voice

func _ready() -> void:
	name="AmbientAudio"
	# Title settings pause the tree; audio still needs to honor mute immediately.
	# Gameplay is explicitly silenced while paused, without changing physics.
	process_mode=Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for kind in BEDS:
		if menu_mode and kind in ["surf","rain"]:continue
		var voice := _voice(kind.capitalize(),bed_stream(kind))
		voices[kind]=voice
		gains[kind]=0.0
		targets[kind]=0.0
		voice.play()
	if menu_mode:
		var entry := Catalog.find_by_id("mclaren-570s")
		var stream := Synth.engine_loop(str(entry.get("audio_family","v8_cross")),0,
			float(entry.get("audio_aggression",.74)),float(entry.get("audio_exhaust_roughness",.36)),false,float(entry.get("audio_tone",.07)))
		idle=_voice("FeaturedCarIdle",stream)
		idle.pitch_scale=.72
		idle.play()
		siren=_voice("DistantPoliceSiren",Emergency._stream())
		siren_wait=_rng.randf_range(14.0,26.0)
	_update_targets()
	_apply_mute()

func _update_targets() -> void:
	if menu_mode:
		targets.city=.22
		targets.wind=.10
		return
	var style := "rural"
	var wet := 0.0
	if is_instance_valid(world) and is_instance_valid(listener):
		if world.has_method("environment_style_at"):
			style=str(world.call("environment_style_at",listener.global_position/20.0,"residential"))
		if world.has_method("rain_at_position"):
			wet=clampf(float(world.call("rain_at_position",listener.global_position)),0.0,1.0)
		elif world.has_method("get_rain_intensity"):
			wet=clampf(float(world.call("get_rain_intensity")),0.0,1.0)
	targets.city=.25 if style=="downtown" else (.18 if style=="industrial" else (.11 if style=="residential" else .035))
	targets.wind=.22 if style in ["rural","coastal"] else .10
	targets.surf=.24 if style=="coastal" else 0.0
	targets.rain=wet*.27

func set_muted(value: bool) -> void:
	muted=value
	_apply_mute()

func _apply_mute() -> void:
	if not muted:return
	for voice in voices.values():voice.volume_db=SILENT_DB
	if is_instance_valid(idle):idle.volume_db=SILENT_DB
	if is_instance_valid(siren):
		siren.stop()
		siren_elapsed=0.0
		siren_duration=0.0
		siren_wait=_rng.randf_range(18.0,36.0)

func _process(dt: float) -> void:
	if is_instance_valid(player_audio):
		var current := bool(player_audio.get("muted"))
		if current!=muted:set_muted(current)
	if muted or (not menu_mode and get_tree().paused):
		for voice in voices.values():voice.volume_db=SILENT_DB
		if is_instance_valid(idle):idle.volume_db=SILENT_DB
		return
	var delta := clampf(dt,0.0,.25)
	_clock+=delta
	_probe_clock+=delta
	if _probe_clock>=.5:
		_probe_clock=0.0
		_update_targets()
	for kind in voices:
		var voice: AudioStreamPlayer=voices[kind]
		var gain := move_toward(float(gains[kind]),float(targets[kind]),delta*.22)
		gains[kind]=gain
		voice.volume_db=linear_to_db(maxf(gain,.0001))
	if menu_mode:
		idle.volume_db=-20.0+sin(_clock*1.7)*.65
		idle.pitch_scale=.72+sin(_clock*1.23)*.008
		_tick_siren(delta)

func _tick_siren(dt: float) -> void:
	if siren_duration>0.0:
		siren_elapsed+=dt
		if siren_elapsed>=siren_duration:
			siren.stop()
			siren.volume_db=SILENT_DB
			siren_duration=0.0
			siren_elapsed=0.0
			siren_wait=_rng.randf_range(22.0,48.0)
			return
		var at := siren_elapsed/siren_duration
		# Passing emergency vehicle: gradual approach and retreat, subtle
		# Doppler-like pitch movement, never louder than the foreground car.
		var envelope := pow(sin(PI*at),1.5)
		siren.volume_db=linear_to_db(maxf(.0001,envelope*.075))
		siren.pitch_scale=lerpf(.94,.79,at)
		return
	siren_wait-=dt
	if siren_wait<=0.0:
		siren_duration=_rng.randf_range(4.0,7.0)
		siren_elapsed=0.0
		siren.volume_db=SILENT_DB
		siren.pitch_scale=.94
		siren.play(_rng.randf_range(0.0,2.9))

func _exit_tree() -> void:
	for voice in voices.values():
		if is_instance_valid(voice):voice.stop()
	if is_instance_valid(idle):idle.stop()
	if is_instance_valid(siren):siren.stop()
