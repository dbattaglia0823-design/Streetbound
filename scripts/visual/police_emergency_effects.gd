extends Node2D
## Local, cosmetic roof strobes and a synthesized positional siren.
static var siren_stream: AudioStreamWAV
var half_width := 10.0
var roof_y := 0.0
var clock := 0.0
var voice: AudioStreamPlayer2D

static func attach(car: Node2D, model: Dictionary) -> Node2D:
	var fx := Node2D.new()
	fx.set_script(load("res://scripts/visual/police_emergency_effects.gd"))
	fx.name = "EmergencyEffects"
	fx.set("half_width", float(model["width_m"])*20.0*0.30)
	fx.set("roof_y", float(model["length_m"])*20.0*float(model.get("lightbar_offset_fraction", 0.0)))
	car.add_child(fx)
	return fx

static func _stream() -> AudioStreamWAV:
	if siren_stream != null:
		return siren_stream
	var rate := 22050
	var count := rate*3
	var data := PackedByteArray()
	data.resize(count*2)
	var phase := 0.0
	for i in count:
		var at := float(i)/float(rate)
		var hz := 780.0 + 470.0*(0.5-0.5*cos(TAU*at/3.0))
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
	voice = AudioStreamPlayer2D.new()
	voice.stream = _stream()
	voice.volume_db = -20.0
	voice.max_distance = 20.0*150.0
	add_child(voice)
	voice.play()

func _process(dt: float) -> void:
	clock += dt
	var muted := false
	for audio in get_tree().get_nodes_in_group("streetbound_player_audio"):
		muted = bool(audio.get("muted"))
		break
	voice.stream_paused = muted
	queue_redraw()

func _draw() -> void:
	var blue := int(clock*8.0)%2 == 0
	for side in [-1,1]:
		var active := blue if side == -1 else not blue
		if not active:
			continue
		var center := Vector2(float(side)*half_width*0.55,roof_y)
		var tint := Color(0.13,0.35,1.0) if side == -1 else Color(1.0,0.08,0.08)
		draw_circle(center,half_width*1.5,Color(tint,0.13))
		draw_circle(center,half_width*0.65,Color(tint,0.42))
		draw_rect(Rect2(center-Vector2(half_width*0.42,2.0),Vector2(half_width*0.84,4.0)),tint)
