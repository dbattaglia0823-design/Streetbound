extends Control
## Standalone audio audition scene for future models. Run
## res://scenes/pending_audio_preview.tscn in the Godot editor (F6).
## No unpublished cars are added to game economy or world.
const Pending = preload("res://scripts/audio/pending_vehicle_audio.gd")
const CarScene = preload("res://scenes/vehicle.tscn")
const AudioScript = preload("res://scripts/audio/vehicle_audio.gd")

var car: VehicleController2D
var audio: Node
var profiles: Array[Dictionary]
var selector: OptionButton
var search: LineEdit
var info: Label
var rpm_slider: HSlider
var throttle_slider: HSlider
var boost_slider: HSlider
var speed_slider: HSlider
var rpm_value: Label
var throttle_value: Label
var boost_value: Label
var speed_value: Label
var mute_button: Button
var current_id := ""


func _ready() -> void:
	name = "FutureVehicleAudioPreview"
	# Keep the real vehicle/transmission/audio scripts, but never draw a
	# placeholder car or step real driving physics in this sound preview.
	car = CarScene.instantiate() as VehicleController2D
	car.visible = false
	add_child(car)
	car.set_physics_process(false)
	audio = Node.new()
	audio.set_script(AudioScript)
	audio.set("vehicle",car)
	add_child(audio)
	audio.set_process(false) # Slider telemetry drives the mixer manually.
	profiles = Pending.all()
	_build_screen()
	if not profiles.is_empty():
		_select_vehicle(str(profiles[0].id))


func _label(parent: Node, value: String, size: int = 15,
		color: Color = Color("#c7d6d3")) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size",size)
	result.add_theme_color_override("font_color",color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result


func _build_screen() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#09141b")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",26)
	margin.add_theme_constant_override("margin_right",26)
	margin.add_theme_constant_override("margin_top",20)
	margin.add_theme_constant_override("margin_bottom",22)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation",12)
	scroll.add_child(col)
	_label(col,"STREETBOUND  /  FUTURE CAR AUDIO LAB",25,Color("#f1bf83"))
	_label(col,"154 prepared vehicle sound identities. No new cars or unlicensed OEM recordings are added to gameplay.",13)
	search = LineEdit.new()
	search.name = "FilterVehicleSounds"
	search.placeholder_text = "Search manufacturer or model"
	search.text_changed.connect(_apply_filter)
	col.add_child(search)
	selector = OptionButton.new()
	selector.name = "PreviewModel"
	selector.custom_minimum_size.y = 40
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.item_selected.connect(_on_model_selected)
	col.add_child(selector)
	_apply_filter("")
	info = _label(col,"",14,Color("#a6d5ca"))
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation",8)
	col.add_child(controls)
	var a: Dictionary = _slider(controls,"Engine / motor RPM",100)
	rpm_slider = a.slider
	rpm_value = a.readout
	var b: Dictionary = _slider(controls,"Throttle (%)",100)
	throttle_slider = b.slider
	throttle_value = b.readout
	var c: Dictionary = _slider(controls,"Modeled boost (psi)",30)
	boost_slider = c.slider
	boost_value = c.readout
	var d: Dictionary = _slider(controls,"Road speed (m/s)",75)
	speed_slider = d.slider
	speed_value = d.readout
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",9)
	actions.set("alignment",BoxContainer.ALIGNMENT_BEGIN)
	col.add_child(actions)
	for pair in [["IDLE","idle"],["CRUISE","cruise"],["FULL PULL","full"],
			["LIFT OFF","coast"],["SHIFT","shift"]]:
		var btn := Button.new()
		btn.text = str(pair[0])
		btn.custom_minimum_size = Vector2(110,38)
		btn.pressed.connect(_preset.bind(str(pair[1])))
		actions.add_child(btn)
	mute_button = Button.new()
	mute_button.text = "MUTE AUDIO"
	mute_button.custom_minimum_size = Vector2(140,38)
	mute_button.pressed.connect(_toggle_mute)
	actions.add_child(mute_button)
	_label(col,"Real CC0 recordings are mixed only where a matching broad engine-family sample exists. New boxer, rotary, inline-five, V16 and EV signatures use original synthesis until suitably licensed recordings are available.",13)


func _slider(parent: Node, caption: String, maximum: float) -> Dictionary:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation",3)
	parent.add_child(group)
	var row := HBoxContainer.new()
	group.add_child(row)
	var label := _label(row,caption,15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := _label(row,"0",14,Color("#f0c385"))
	readout.custom_minimum_size.x = 85
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = maximum
	slider.step = 1.0
	slider.custom_minimum_size.y = 30
	group.add_child(slider)
	return {"slider":slider,"readout":readout}


func _apply_filter(term: String) -> void:
	if selector == null:
		return
	var previously := current_id
	selector.clear()
	for profile in profiles:
		var name := str(profile.display_name)
		if not term.is_empty() and not name.to_lower().contains(term.to_lower()):
			continue
		selector.add_item(name)
		selector.set_item_metadata(selector.item_count-1,str(profile.id))
	if selector.item_count > 0:
		var found := 0
		for i in selector.item_count:
			if str(selector.get_item_metadata(i)) == previously:
				found = i
				break
		selector.select(found)
	else:
		selector.text = "No matching vehicles"


func _on_model_selected(index: int) -> void:
	if index >= 0 and index < selector.item_count:
		_select_vehicle(str(selector.get_item_metadata(index)))


func _select_vehicle(id: String) -> void:
	var profile := Pending.find_by_id(id)
	if profile.is_empty():
		return
	current_id = id
	var config := Pending.make_preview_configuration(id)
	if config == null:
		return
	car.config = config
	car.transmission.reset(config)
	car.linear_velocity = Vector2.ZERO
	car.throttle = 0.0
	car.boost_psi = 0.0
	audio._configure_engine(true)
	rpm_slider.value = 0
	throttle_slider.value = 0
	speed_slider.value = 0
	boost_slider.max_value = maxf(0.0,config.boost_max_psi)
	boost_slider.value = 0
	info.text = "%s   /   %s   /   %s%s\n%s" % [
		str(profile.display_name).to_upper(),str(profile.audio_family).to_upper(),
		str(profile.audio_induction).replace("_"," ").to_upper(),
		"  +  ELECTRIC ASSIST" if config.audio_hybrid_assist > 0.2 else "",
		str(profile.get("review_note","PREPARED AUDIO ONLY — representative year/trim; not in dealership"))]


func _preset(kind: String) -> void:
	match kind:
		"idle":
			rpm_slider.value = 0.02
			throttle_slider.value = 0
			speed_slider.value = 0
			boost_slider.value = 0
		"cruise":
			rpm_slider.value = 37
			throttle_slider.value = 28
			speed_slider.value = 19
			boost_slider.value = 0
		"full":
			rpm_slider.value = 84
			throttle_slider.value = 100
			speed_slider.value = 45
			boost_slider.value = boost_slider.max_value*0.78
		"coast":
			throttle_slider.value = 0
			rpm_slider.value = 72
			boost_slider.value = 0
		"shift":
			audio._on_shift(car.transmission.gear+1)


func _toggle_mute() -> void:
	audio.muted = not bool(audio.muted)
	mute_button.text = "UNMUTE AUDIO" if audio.muted else "MUTE AUDIO"


func _process(delta: float) -> void:
	if not is_instance_valid(car) or not is_instance_valid(audio) or \
		rpm_slider == null:
		return
	var cfg: VehicleConfig = car.config
	var fraction := float(rpm_slider.value)/100.0
	var rpm := lerpf(cfg.idle_rpm,cfg.redline_rpm,fraction)
	car.transmission.rpm = rpm
	car.throttle = float(throttle_slider.value)/100.0
	car.boost_psi = float(boost_slider.value)
	car.linear_velocity = Vector2.UP*float(speed_slider.value)
	audio._process(minf(delta,0.05))
	rpm_value.text = "%d rpm" % roundi(rpm)
	throttle_value.text = "%d%%" % roundi(throttle_slider.value)
	boost_value.text = "%.1f psi" % boost_slider.value
	speed_value.text = "%d m/s" % roundi(speed_slider.value)
