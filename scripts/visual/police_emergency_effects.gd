extends Node2D
## Local, cosmetic roof strobes and a synthesized positional siren.
# The siren should cut through the engine mix without drowning it out.
const SIREN_VOLUME_DB := -12.0
const SIREN_MUTED_VOLUME_DB := -80.0
const SIREN_RANGE_PX := 20.0 * 220.0
const SIREN_ATTENUATION := 0.7
const SIREN_LOOP_SECONDS := 3.0
static var siren_stream: AudioStreamWAV
var half_width := 10.0
var roof_y := 0.0
var blue_on_left := true
var clock := 0.0
var voice: AudioStreamPlayer2D

static func attach(car: Node2D, model: Dictionary) -> Node2D:
	var fx := Node2D.new()
	fx.set_script(load("res://scripts/visual/police_emergency_effects.gd"))
	fx.name = "EmergencyEffects"
	fx.set("half_width", float(model["width_m"])*20.0*0.30)
	fx.set("blue_on_left", is_zero_approx(float(model["sprite_rotation_degrees"])))
	fx.set("roof_y", float(model["length_m"])*20.0*float(model.get("lightbar_offset_fraction", 0.0)))
	car.add_child(fx)
	return fx

static func _stream() -> AudioStreamWAV:
	if siren_stream != null:
		return siren_stream
	var rate := 22050
	var count := int(rate * SIREN_LOOP_SECONDS)
	var data := PackedByteArray()
	data.resize(count*2)
	var phase := 0.0
	for i in count:
		var at := float(i)/float(rate)
		var hz := 780.0 + 470.0*(0.5-0.5*cos(TAU*at/SIREN_LOOP_SECONDS))
		phase += TAU*hz/float(rate)
		var sample := sin(phase)*0.66 + sin(phase*3.0)*0.13
		data.encode_s16(i*2,roundi(sample*22000.0))
	siren_stream = AudioStreamWAV.new()
	siren_stream.format = AudioStreamWAV.FORMAT_16_BITS
	siren_stream.mix_rate = rate
	siren_stream.data = data
	siren_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	siren_stream.loop_end = count
	return siren_stream

func _ready() -> void:
	z_index = 4
	process_priority = 10
	voice = AudioStreamPlayer2D.new()
	voice.stream = _stream()
	voice.name = "PursuitSiren"
	voice.volume_db = SIREN_VOLUME_DB
	voice.max_distance = SIREN_RANGE_PX
	voice.attenuation = SIREN_ATTENUATION
	add_child(voice)
	# Offset each unit so the fleet does not start in phase and sound like one
	# amplified siren. Use instance identity instead of the gameplay RNG.
	var offset := float((get_instance_id() * 997) % 3000) / 1000.0
	voice.play(offset)

func _process(dt: float) -> void:
	var art:=get_parent().get_node_or_null("Art") as Node2D
	if is_instance_valid(art):transform=art.transform
	clock += dt
	var muted := false
	for audio in get_tree().get_nodes_in_group("streetbound_player_audio"):
		muted = bool(audio.get("muted"))
		break
	# Apply the gain immediately as well as pausing playback; a newly started
	# positional stream may not have an active mixer voice until the next frame.
	voice.volume_db = SIREN_MUTED_VOLUME_DB if muted else SIREN_VOLUME_DB
	voice.stream_paused = muted
	queue_redraw()

func _draw() -> void:
	var blue := int(clock*8.0)%2 == 0
	for side in [-1,1]:
		var blue_side: bool = (side == -1) == blue_on_left
		var active := blue if blue_side else not blue
		if not active:
			continue
		var center := Vector2(float(side)*half_width*0.55,roof_y)
		var tint := Color(0.13,0.35,1.0) if blue_side else Color(1.0,0.08,0.08)
		draw_circle(center,half_width*1.5,Color(tint,0.13))
		draw_circle(center,half_width*0.65,Color(tint,0.42))
		draw_rect(Rect2(center-Vector2(half_width*0.42,2.0),Vector2(half_width*0.84,4.0)),tint)
