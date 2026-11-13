extends Control
## Lightweight startup title: no simulation, traffic or world archive is
## initialized until the player selects a mode.
const GOLD := Color("#edae72")
const PALE := Color("#ecf1eb")
const MUTED := Color("#aabeb9")
const NAVY := Color("#0b171d")
var panel: PanelContainer
var play_button: Button
var editor_button: Button
var multiplayer_button: Button
var feedback: Label

func _ready() -> void:
	name = "StreetboundMainMenu"
	get_tree().paused = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_menu()
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	call_deferred("_focus_play")

func _focus_play() -> void:
	if is_instance_valid(play_button) and is_inside_tree():
		play_button.grab_focus()

func _skin_button(button: Button, primary: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = GOLD if primary else Color("#182b32")
	normal.border_color = GOLD if primary else Color("#476269")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#f6c18e") if primary else Color("#2b454c")
	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = Color("#f4eac6")
	focused.set_border_width_all(3)
	var disabled_style := normal.duplicate() as StyleBoxFlat
	disabled_style.bg_color = Color("#172126")
	disabled_style.border_color = Color("#2c3b40")
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover)
	button.add_theme_stylebox_override("focus",focused)
	button.add_theme_stylebox_override("disabled",disabled_style)
	button.add_theme_color_override("font_color",NAVY if primary else PALE)
	button.add_theme_color_override("font_hover_color",NAVY if primary else Color.WHITE)
	button.add_theme_color_override("font_focus_color",NAVY if primary else PALE)
	button.add_theme_color_override("font_disabled_color",Color("#87959a"))
	button.add_theme_font_size_override("font_size",21)
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = 61

func _label(value: String, size_px: int, color: Color) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size",size_px)
	item.add_theme_color_override("font_color",color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func _action(value: String, mode: String, primary: bool = false) -> Button:
	var action := Button.new()
	action.name = mode.capitalize()+"Button"
	action.text = value
	_skin_button(action,primary)
	action.pressed.connect(_activate.bind(mode))
	return action

func _build_menu() -> void:
	panel = PanelContainer.new()
	panel.name = "StartMenuPanel"
	panel.size = Vector2(620,700)
	panel.custom_minimum_size = Vector2(620,700)
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.036,0.074,0.084,0.975)
	skin.border_color = Color(0.26,0.39,0.41,0.92)
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(23)
	skin.content_margin_left = 45
	skin.content_margin_right = 45
	skin.content_margin_top = 38
	skin.content_margin_bottom = 35
	panel.add_theme_stylebox_override("panel",skin)
	add_child(panel)
	var content := VBoxContainer.new()
	content.name = "MenuItems"
	content.add_theme_constant_override("separation",13)
	panel.add_child(content)
	content.add_child(_label("MORROW COAST   /   OPEN ROAD",17,GOLD))
	content.add_child(_label("STREETBOUND",58,PALE))
	content.add_child(_label("Drive the city. Find your line.",20,MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 26
	content.add_child(spacer)
	play_button = _action("PLAY   /   FREE ROAM","play",true)
	content.add_child(play_button)
	editor_button = _action("MAP EDITOR","map_editor")
	var flow: Node = get_node_or_null("/root/GameFlow")
	editor_button.disabled = not is_instance_valid(flow) or \
		not bool(flow.call("supports_native_editor"))
	editor_button.tooltip_text = "Available only in Godot development builds." if \
		editor_button.disabled else "Edit real roads and scenery in Godot."
	content.add_child(editor_button)
	multiplayer_button = _action("LOCAL MULTIPLAYER","multiplayer")
	multiplayer_button.tooltip_text = "Requires at least one controller for two-player split-screen."
	content.add_child(multiplayer_button)
	content.add_child(_action("QUIT GAME","quit"))
	feedback = _label("",14,Color("#f4bf88"))
	feedback.name = "MenuFeedback"
	feedback.custom_minimum_size.y = 22
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(feedback)
	var divider := HSeparator.new()
	content.add_child(divider)
	var footer := _label("SINGLE PLAYER  /  TWO-PLAYER SPLIT-SCREEN  /  WORLD EDITING",12,MUTED)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(footer)

func _activate(mode: String) -> void:
	if mode=="quit":
		get_tree().quit()
		return
	var flow: Node = get_node_or_null("/root/GameFlow")
	if not is_instance_valid(flow):
		feedback.text = "Launch Streetbound from its Godot project to enable modes."
	elif not bool(flow.call("start_game",mode)):
		feedback.text = str(flow.get("last_error"))
	else:
		feedback.text = ""

func _relayout() -> void:
	var dimensions := get_viewport_rect().size
	var scale_factor: float = minf(1.0,minf((dimensions.x-30.0)/650.0,
		(dimensions.y-20.0)/715.0))
	scale_factor = maxf(0.25,scale_factor)
	panel.scale = Vector2.ONE*scale_factor
	var width: float = panel.size.x*scale_factor
	var height: float = panel.size.y*scale_factor
	panel.position = Vector2(
		(dimensions.x-width)*0.12 if dimensions.x>1050 else
		(dimensions.x-width)*0.5,
		(dimensions.y-height)*0.5)
	queue_redraw()

func _draw() -> void:
	var dimensions := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO,dimensions),Color("#08151b"),true)
	# Muted top-down city geometry supplies atmosphere without loading
	# thousands of world chunks or creating a second traffic simulation.
	var block := maxf(53.0,dimensions.y/11.0)
	var start_x: float = dimensions.x*0.54
	for col in range(int(start_x/block),int(dimensions.x/block)+2):
		for row in range(int(dimensions.y/block)+2):
			var x := col*block+9.0
			var y := row*block+9.0
			var rect := Rect2(x,y,block-19.0,block-19.0)
			draw_rect(rect,Color("#152830") if (col+row)%3==0 else Color("#102127"),true)
			draw_rect(rect,Color(0.34,0.48,0.47,0.18),false,1.2)
	var highway := PackedVector2Array([
		Vector2(dimensions.x*0.81,-45),
		Vector2(dimensions.x*0.75,dimensions.y*0.20),
		Vector2(dimensions.x*0.78,dimensions.y*0.42),
		Vector2(dimensions.x*0.68,dimensions.y*0.66),
		Vector2(dimensions.x*0.71,dimensions.y+55)])
	var width: float = clampf(dimensions.x*0.075,48.0,140.0)
	draw_polyline(highway,Color("#415252"),width+20.0,true)
	draw_polyline(highway,Color("#1b2c33"),width,true)
	draw_polyline(highway,Color("#d9ae77"),2.0,true)
	draw_polyline(PackedVector2Array([
		Vector2(dimensions.x*0.90,-30),
		Vector2(dimensions.x*0.845,dimensions.y*0.20),
		Vector2(dimensions.x*0.87,dimensions.y*0.42),
		Vector2(dimensions.x*0.77,dimensions.y*0.66),
		Vector2(dimensions.x*0.80,dimensions.y+40)
	]),Color(0.94,0.84,0.60,0.35),1.7,true)
	draw_rect(Rect2(0,dimensions.y-5,dimensions.x,5),GOLD,true)
