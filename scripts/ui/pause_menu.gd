extends CanvasLayer
@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
## Streetbound adapter for Game-Dev-Toolkit's Functional UI v2 Pause/Settings
## templates and Godot layout renderer. Lives outside the paused world, so
## buttons, mouse, gamepad focus and Escape continue working when paused.
signal exit_requested
signal split_screen_requested
signal map_editor_requested
signal main_menu_requested

const ToolkitLayout = preload("res://addons/gdt/ui_layout.gd")
const ToolkitSettings = preload("res://addons/gdt/settings_store.gd")
const VehicleCatalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const PauseDashboard = preload("res://scripts/ui/pause_dashboard.gd")
@onready var controls_api: Variant = get_node("/root/Controls")
const DESIGN_SIZE := Vector2(800.0, 500.0)
const DISPLAY_MODES := ["windowed","borderless","fullscreen"]
# Keep windowed bounds across title/game scene changes and live mode switches.
static var last_windowed_position := Vector2i.ZERO
static var last_windowed_size := Vector2i(1280,800)
static var has_windowed_rect := false

var vehicle_audio
var driving_camera
var allow_quit := true
var menu_state := ""
var split_screen_active := false
var map_editor_available := false
var settings_back_to_title := false
var settings_store

var overlay: Control
var pause_screen
var settings_screen
var background: ColorRect
var settings_tab := "general"
var general_tab_button: Button
var controls_tab_button: Button
var graphics_tab_button: Button
var graphics_page: ScrollContainer
var graphics_controls: Dictionary={}
const GRAPHICS_DEFAULTS: Dictionary={"fps_limit":0,"vsync":true,"minimap_fps":0,"scenery_shadows":true,"rain_effects":100,"traffic_density":100,"adaptive_streaming":true,"optimized_ai":true,"performance_overlay":false}
var display_mode_label: Label
var display_mode_select: OptionButton
var controls_page: Control
var bindings_list: VBoxContainer
var binding_rows: Dictionary = {}
var capture_action := ""
var capture_device := ""
var binding_feedback: Label
var reset_bindings_button: Button
var quit_race_button: Button
var player_vehicle: Node2D
var vehicle_ownership
var quick_upgrades: CanvasLayer
var dashboard: Control
var vehicle_panel: Panel
var vehicle_preview: TextureRect
var vehicle_fallback: Label
var vehicle_name_label: Label
var vehicle_level_label: Label
var vehicle_power_label: Label
var vehicle_torque_label: Label
var vehicle_drivetrain_label: Label
var vehicle_weight_label: Label
var multiplayer_screen: Control
var local_split_button: Button
var multiplayer_feedback: Label
var confirmation_screen: Control
var confirmation_heading: Label
var confirmation_copy: Label
var confirmation_accept: Button
var confirmation_target := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	settings_store = ToolkitSettings.new("user://streetbound_pause_settings.cfg", {
		"sound": true,
		"volume": 80.0,
		"camera_follow": false,
		"minimap_shape": "square",
		"display_mode": "windowed"
	}.merged(GRAPHICS_DEFAULTS))
	overlay = Control.new()
	overlay.name = "PauseOverlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	background = ColorRect.new()
	background.name = "DimmedBackground"
	# A stronger backdrop keeps the driving HUD and traffic from competing
	# with pause menus and their footer text.
	background.color = Color(0.016, 0.035, 0.039, 0.76)
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(background)

	pause_screen = _load_screen("res://assets/ui/pause-menu.layout.json", "PauseScreen")
	settings_screen = _load_screen("res://assets/ui/pause-settings.layout.json", "SettingsScreen")
	_build_vehicle_panel()
	_build_multiplayer_screen()
	_build_confirmation_screen()
	quit_race_button=Button.new();quit_race_button.name="QuitRace";quit_race_button.text="Quit Race"
	quit_race_button.position=Vector2(51,158);quit_race_button.size=Vector2(290,42)
	quit_race_button.tooltip_text="End the current race without rewards and return to free driving."
	_button_skin(quit_race_button);pause_screen.add_child(quit_race_button)
	for style in ["normal","hover","pressed","focus"]:quit_race_button.add_theme_stylebox_override(style,pause_screen.controls["map_editor"].get_theme_stylebox(style))
	quit_race_button.add_theme_font_size_override("font_size",18)
	quit_race_button.pressed.connect(_quit_active_race)
	_update_race_button()
	_build_settings_tabs()
	_build_dashboard()
	settings_screen.visible = false
	multiplayer_screen.visible = false
	confirmation_screen.visible = false
	overlay.visible = false
	get_viewport().size_changed.connect(_resize_layout)
	_resize_layout()
	_apply_saved_settings()
	_apply_graphics_settings()
	_update_map_editor_button()
	get_node("/root/MenuNavigation").register_scope(overlay,20,_controller_back,func():return not capture_action.is_empty())

func _build_dashboard() -> void:
	# Preserve legacy layout action IDs and tests during this migration, but
	# remove their visual and mouse presence. The hub is the actual pause UI.
	pause_screen.modulate.a = 0.0
	pause_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in pause_screen.controls.values():
		if node is Control:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
	dashboard = Control.new()
	dashboard.set_script(PauseDashboard)
	dashboard.menu = self
	dashboard.vehicle = player_vehicle
	dashboard.economy = vehicle_ownership
	dashboard.map_hud = get_tree().get_first_node_in_group("streetbound_world_map_hud")
	dashboard.upgrades = quick_upgrades
	overlay.add_child(dashboard)
	dashboard.visible = false


func _load_screen(path: String, screen_name: String) -> Variant:
	var screen: Variant = ToolkitLayout.new()
	screen.name = screen_name
	overlay.add_child(screen)
	if not screen.load_from_file(path):
		push_error("Streetbound pause menu template could not be loaded: " + path)
		return screen
	screen.action_requested.connect(_handle_action)
	_style_screen(screen)
	return screen

func _style_screen(screen: Variant) -> void:
	for entry in screen.layout.get("nodes", []):
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("id", ""))
		var role: String = str(entry.get("role", ""))
		var node: Control = screen.controls.get(id)
		if node == null:
			continue
		if node is Panel:
			var panel_style := StyleBoxFlat.new()
			panel_style.bg_color = Color(0.027, 0.052, 0.069, 0.94)
			panel_style.border_color = Color(0.39, 0.50, 0.59, 0.72)
			panel_style.set_border_width_all(1)
			panel_style.set_corner_radius_all(20)
			node.add_theme_stylebox_override("panel", panel_style)
		elif node is Label:
			var label_node := node as Label
			label_node.add_theme_font_size_override("font_size", 34 if role == "screen_title" else 15)
			label_node.add_theme_color_override("font_color", Color("#eff3e8"))
			label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if id == "pause_heading" else HORIZONTAL_ALIGNMENT_CENTER
		elif node is Button:
			var button := node as Button
			var primary: bool = role == "primary_action"
			var danger: bool = role == "danger_action"
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color("#ff8733") if primary else Color("#342b2c") if danger else Color("#1b2b36")
			normal.border_color = Color("#ff8733") if primary else Color("#9d686b") if danger else Color("#536775")
			normal.set_border_width_all(1)
			normal.set_corner_radius_all(11)
			var hover := normal.duplicate() as StyleBoxFlat
			hover.bg_color = Color("#ff9c5b") if primary else Color("#4d3839") if danger else Color("#2b4557")
			var pressed := hover.duplicate() as StyleBoxFlat
			pressed.bg_color = Color("#cf602c") if primary else Color("#624044") if danger else Color("#15292c")
			var focus := StyleBoxFlat.new()
			focus.draw_center = false
			focus.border_color = Color("#f5f7fa")
			focus.set_border_width_all(2)
			focus.set_corner_radius_all(11)
			button.add_theme_stylebox_override("normal", normal)
			button.add_theme_stylebox_override("hover", hover)
			button.add_theme_stylebox_override("pressed", pressed)
			button.add_theme_stylebox_override("focus", focus)
			button.add_theme_color_override("font_color", Color("#ffffff"))
			button.add_theme_color_override("font_hover_color", Color("#ffffff"))
			button.add_theme_color_override("font_pressed_color", Color("#132325") if primary else Color("#ffffff"))
			button.add_theme_font_size_override("font_size", 19)
			button.focus_mode = Control.FOCUS_ALL
		elif node is CheckBox:
			node.add_theme_color_override("font_color", Color("#e8eee4"))
			node.add_theme_font_size_override("font_size", 16)
		elif node is HSlider:
			node.add_theme_stylebox_override("slider", _track_style())
			node.add_theme_stylebox_override("grabber_area", _filled_track_style())

func _button_skin(button: Button, selected: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#573820") if selected else Color("#1b2b36")
	normal.border_color = Color("#ff8733") if selected else Color("#536775")
	normal.set_border_width_all(2 if selected else 1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#345551")
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color("#f5f7fa")
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover)
	button.add_theme_stylebox_override("focus",focus)
	button.add_theme_color_override("font_color",Color("#f0efe6"))
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_font_size_override("font_size",13)
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true


func _settings_label(parent: Control, text_value: String, at: Vector2,
		dimensions: Vector2, size_px: int = 13) -> Label:
	var node := Label.new()
	node.text = text_value
	node.position = at
	node.size = dimensions
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size",size_px)
	node.add_theme_color_override("font_color",Color("#e5efe5"))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _build_settings_tabs() -> void:
	# Keep the original Toolkit layout as the General tab. The Controls tab
	# is a scrollable native Godot panel so it works with keyboard, mouse,
	# controller focus, and compact windows without a separate screen.
	controls_page = Control.new()
	controls_page.name = "ControlsTabContent"
	controls_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_screen.add_child(controls_page)
	general_tab_button = Button.new()
	general_tab_button.name = "GeneralTab"
	general_tab_button.text = "GENERAL"
	general_tab_button.position = Vector2(166,135)
	general_tab_button.size = Vector2(150,39)
	general_tab_button.pressed.connect(_set_settings_tab.bind("general"))
	settings_screen.add_child(general_tab_button)
	controls_tab_button = Button.new()
	controls_tab_button.name = "ControlsTab"
	controls_tab_button.text = "CONTROLS"
	controls_tab_button.position = Vector2(324,135)
	controls_tab_button.size = Vector2(150,39)
	controls_tab_button.pressed.connect(_set_settings_tab.bind("controls"))
	settings_screen.add_child(controls_tab_button)
	_settings_label(controls_page,"CONTROL",Vector2(171,180),Vector2(130,26),11)
	_settings_label(controls_page,"KEYBOARD / MOUSE",Vector2(307,180),Vector2(161,26),10)
	_settings_label(controls_page,"CONTROLLER",Vector2(476,180),Vector2(146,26),11)
	var scroller := ScrollContainer.new()
	scroller.name = "BindingsScroll"
	scroller.position = Vector2(166,210)
	scroller.size = Vector2(470,185)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.mouse_filter = Control.MOUSE_FILTER_STOP
	controls_page.add_child(scroller)
	bindings_list = VBoxContainer.new()
	bindings_list.name = "BindingsList"
	bindings_list.add_theme_constant_override("separation",5)
	bindings_list.custom_minimum_size.x = 440.0
	bindings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(bindings_list)
	for action in controls_api.ACTIONS:
		var row := HBoxContainer.new()
		row.name = "BindingRow_"+action
		row.custom_minimum_size.y = 40
		row.add_theme_constant_override("separation",6)
		bindings_list.add_child(row)
		var action_label := Label.new()
		action_label.text = str(controls_api.LABELS.get(action,action.capitalize()))
		action_label.custom_minimum_size.x = 137
		action_label.add_theme_font_size_override("font_size",12)
		action_label.add_theme_color_override("font_color",Color("#e5efe5"))
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action_label.clip_text = true
		row.add_child(action_label)
		var kb := Button.new()
		kb.name = "Keyboard_"+action
		kb.custom_minimum_size = Vector2(144,36)
		kb.pressed.connect(_start_binding.bind(action,"keyboard"))
		_button_skin(kb)
		row.add_child(kb)
		var pad := Button.new()
		pad.name = "Controller_"+action
		pad.custom_minimum_size = Vector2(143,36)
		pad.pressed.connect(_start_binding.bind(action,"controller"))
		_button_skin(pad)
		row.add_child(pad)
		binding_rows[action] = {"keyboard":kb,"controller":pad}
	binding_feedback = _settings_label(controls_page,
		"Select a binding; Esc cancels, Backspace clears.",
		Vector2(169,396),Vector2(456,23),11)
	binding_feedback.clip_text = true
	reset_bindings_button = Button.new()
	reset_bindings_button.name = "RestoreDefaultBindings"
	reset_bindings_button.text = "RESTORE DEFAULTS"
	reset_bindings_button.position = Vector2(166,423)
	reset_bindings_button.size = Vector2(202,40)
	reset_bindings_button.pressed.connect(_restore_binding_defaults)
	_button_skin(reset_bindings_button)
	controls_page.add_child(reset_bindings_button)
	# Available on both title screen and gameplay via the shared Settings UI.
	display_mode_label = _settings_label(settings_screen,
		"Display mode",Vector2(206,353),Vector2(181,38),13)
	display_mode_label.name="DisplayModeLabel"
	display_mode_select = OptionButton.new()
	display_mode_select.name="DisplayModeSelect"
	display_mode_select.position=Vector2(390,354)
	display_mode_select.size=Vector2(189,36)
	_button_skin(display_mode_select)
	display_mode_select.tooltip_text="Windowed, borderless maximized window, or exclusive fullscreen"
	for item in [["Windowed","windowed"],["Borderless Window","borderless"],["Fullscreen","fullscreen"]]:
		display_mode_select.add_item(item[0])
		display_mode_select.set_item_metadata(display_mode_select.item_count-1,item[1])
	display_mode_select.item_selected.connect(_select_display_mode)
	settings_screen.add_child(display_mode_select)
	_build_graphics_page()
	_set_settings_tab("general")


func _set_settings_tab(tab: String) -> void:
	if tab not in ["general","controls","graphics"]:
		return
	_cancel_capture(false)
	settings_tab = tab
	var general := tab == "general"
	for id in ["sfx_toggle","volume_label","volume_slider","camera_toggle",
			"minimap_shape_label","minimap_shape_button"]:
		var element: Control = settings_screen.controls.get(id)
		if is_instance_valid(element):
			element.visible = general
	controls_page.visible = tab=="controls"
	graphics_page.visible = tab=="graphics"
	display_mode_label.visible = general
	display_mode_select.visible = general
	_button_skin(general_tab_button,general)
	_button_skin(controls_tab_button,tab=="controls")
	_button_skin(graphics_tab_button,tab=="graphics")
	var back: Button = settings_screen.controls.get("back")
	if is_instance_valid(back):
		back.position = Vector2(295,411) if general else Vector2(417,423)
		back.size = Vector2(210,46) if general else Vector2(213,40)
	if tab=="controls":
		_refresh_binding_buttons()
	elif tab=="graphics":_sync_graphics_controls()


func _build_graphics_page() -> void:
	graphics_tab_button=Button.new()
	graphics_tab_button.name="GraphicsTab"
	graphics_tab_button.text="GRAPHICS"
	graphics_tab_button.position=Vector2(482,135)
	graphics_tab_button.size=Vector2(150,39)
	graphics_tab_button.pressed.connect(_set_settings_tab.bind("graphics"))
	settings_screen.add_child(graphics_tab_button)
	graphics_page=ScrollContainer.new()
	graphics_page.name="GraphicsPerformanceContent"
	graphics_page.position=Vector2(166,181);graphics_page.size=Vector2(470,235)
	graphics_page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	settings_screen.add_child(graphics_page)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	graphics_page.add_child(column)
	var preset:=OptionButton.new()
	preset.name="PerformancePreset";preset.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for label in ["Custom","High quality","Balanced","Performance"]:preset.add_item(label)
	preset.item_selected.connect(_select_graphics_preset)
	_button_skin(preset)
	column.add_child(preset)
	graphics_controls["preset"]=preset
	_graphics_option(column,"Frame rate limit","fps_limit",[["Unlimited",0],["30 FPS",30],["60 FPS",60],["120 FPS",120],["144 FPS",144],["240 FPS",240]])
	_graphics_option(column,"Minimap refresh","minimap_fps",[["Every frame",0],["60 FPS",60],["30 FPS",30]])
	_graphics_option(column,"Ambient traffic density (solo)","traffic_density",[["100%",100],["75%",75],["50%",50],["25%",25]])
	_graphics_option(column,"Rain visual density","rain_effects",[["100%",100],["75%",75],["50%",50],["25%",25]])
	for entry in [["Vertical sync","vsync"],["Scenery shadows","scenery_shadows"],["Adaptive streaming","adaptive_streaming"],["Optimized remote AI scans","optimized_ai"],["Performance overlay (F7)","performance_overlay"]]:
		var toggle:=CheckButton.new()
		toggle.text=str(entry[0]);toggle.name=str(entry[1])
		toggle.toggled.connect(_graphics_toggle.bind(str(entry[1])))
		column.add_child(toggle);graphics_controls[str(entry[1])]=toggle

func _graphics_option(column: VBoxContainer,label: String,key: String,choices: Array) -> void:
	var row:=HBoxContainer.new();column.add_child(row)
	var title_label:=Label.new();title_label.text=label;title_label.custom_minimum_size.x=220
	row.add_child(title_label)
	var picker:=OptionButton.new();picker.name=key;picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for entry in choices:
		picker.add_item(str(entry[0]));picker.set_item_metadata(picker.item_count-1,int(entry[1]))
	picker.item_selected.connect(_graphics_pick.bind(key,picker))
	_button_skin(picker);row.add_child(picker);graphics_controls[key]=picker

func _graphics_pick(index: int,key: String,picker: OptionButton) -> void:
	settings_store.set_setting(key,int(picker.get_item_metadata(index)))
	graphics_controls.preset.select(0)
	_apply_graphics_settings()

func _graphics_toggle(value: bool,key: String) -> void:
	settings_store.set_setting(key,value)
	graphics_controls.preset.select(0)
	_apply_graphics_settings()

func _select_graphics_preset(index: int) -> void:
	if index==0:return
	var values:=GRAPHICS_DEFAULTS.duplicate()
	if index==2:
		values.fps_limit=60;values.minimap_fps=60;values.rain_effects=75
	elif index==3:
		values.fps_limit=60;values.minimap_fps=30;values.rain_effects=50;values.traffic_density=75;values.scenery_shadows=false
	# Do not silently change the diagnostic overlay or display preference.
	values.performance_overlay=settings_store.get_setting("performance_overlay")
	values.vsync=settings_store.get_setting("vsync")
	for key in values:settings_store.set_setting(key,values[key])
	_sync_graphics_controls()
	graphics_controls.preset.select(index)
	_apply_graphics_settings()

func _sync_graphics_controls() -> void:
	for key in GRAPHICS_DEFAULTS:
		var control: Control=graphics_controls.get(key)
		if control is CheckButton:control.set_pressed_no_signal(bool(settings_store.get_setting(key)))
		elif control is OptionButton:
			for i in control.item_count:
				if control.get_item_metadata(i)==settings_store.get_setting(key):
					control.select(i);break

func _apply_graphics_settings() -> void:
	Engine.max_fps=clampi(int(settings_store.get_setting("fps_limit")),0,240)
	if DisplayServer.get_name()!="headless" and not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings_store.get_setting("vsync")) else DisplayServer.VSYNC_DISABLED)
	var map_hud: Node=get_tree().get_first_node_in_group("streetbound_world_map_hud")
	if is_instance_valid(map_hud):map_hud.set("minimap_fps_limit",clampi(int(settings_store.get_setting("minimap_fps")),0,60))
	if not is_instance_valid(player_vehicle):return
	var ground: Node=get_parent().get("ground") if get_parent().get_script()==load("res://scripts/main.gd") else null
	if not is_instance_valid(ground):return
	if ground.has_method("set_scenery_shadows"):
		ground.call("set_scenery_shadows",bool(settings_store.get_setting("scenery_shadows")))
		ground.set("adaptive_streaming",bool(settings_store.get_setting("adaptive_streaming")))
		ground.call("set_performance_debug",bool(settings_store.get_setting("performance_overlay")))
	var traffic:=ground.get_node_or_null("AmbientTraffic")
	if is_instance_valid(traffic):
		traffic.set("optimized_ai",bool(settings_store.get_setting("optimized_ai")))
		traffic.set("user_density_factor",1.0 if online_session.active else clampf(float(settings_store.get_setting("traffic_density"))/100.0,.25,1.0))
	var wet:=ground.get_node_or_null("WetRoadEffects")
	if is_instance_valid(wet):wet.set("effects_scale",clampf(float(settings_store.get_setting("rain_effects"))/100.0,.25,1.0))

func _refresh_binding_buttons() -> void:
	if binding_rows.is_empty():
		return
	for action in controls_api.ACTIONS:
		for kind in ["keyboard","controller"]:
			var button: Button = binding_rows[action][kind]
			var listening: bool = capture_action == str(action) and capture_device == kind
			button.text = ("PRESS KEY / MOUSE" if kind=="keyboard" else
				"PRESS CONTROLLER") if listening else controls_api.binding_text(action,kind)
			button.tooltip_text = "Press to change the %s binding for %s" % [
				"keyboard/mouse" if kind=="keyboard" else "controller",
				str(controls_api.LABELS.get(action,action))]
			_button_skin(button,listening)


func _start_binding(action: String, kind: String) -> void:
	capture_action = action
	capture_device = kind
	binding_feedback.text = "Press input for %s  ·  Esc cancel  ·  Backspace clear" % [
		str(controls_api.LABELS.get(action,action))]
	_refresh_binding_buttons()
	get_viewport().gui_release_focus()


func _cancel_capture(reset_feedback: bool = true) -> void:
	capture_action = ""
	capture_device = ""
	if reset_feedback and is_instance_valid(binding_feedback):
		binding_feedback.text = "Select a binding; Esc cancels, Backspace clears."
	_refresh_binding_buttons()


func _restore_binding_defaults() -> void:
	_cancel_capture(false)
	if controls_api.restore_defaults():
		binding_feedback.text = "Restored all keyboard, mouse and controller defaults."
	else:
		binding_feedback.text = "Could not save default bindings."
	_refresh_binding_buttons()


func _input(event: InputEvent) -> void:
	if menu_state != "settings" or settings_tab != "controls" or capture_action.is_empty():
		return
	var candidate: InputEvent
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return
		if key.keycode in [KEY_BACKSPACE,KEY_DELETE]:
			var cleared: bool = bool(controls_api.clear_binding(capture_action,capture_device))
			binding_feedback.text = "Binding cleared." if cleared else "Could not clear binding."
			_cancel_capture(false)
			get_viewport().set_input_as_handled()
			return
		if capture_device == "keyboard":
			candidate = key
	elif event is InputEventMouseButton and capture_device == "keyboard":
		var mouse: InputEventMouseButton = event
		if mouse.pressed and mouse.button_index < MOUSE_BUTTON_WHEEL_UP:
			candidate = mouse
	elif event is InputEventJoypadButton and capture_device == "controller":
		var button_event: InputEventJoypadButton = event
		if button_event.pressed:
			candidate = button_event
	elif event is InputEventJoypadMotion and capture_device == "controller":
		var motion_event: InputEventJoypadMotion = event
		if absf(motion_event.axis_value) >= 0.7:
			candidate = motion_event
	if candidate == null:
		return
	var action := capture_action
	var result: Dictionary = controls_api.rebind(action,capture_device,candidate)
	if str(result.get("status","")) == "bound":
		var exchanged := str(result.get("swapped_action",""))
		binding_feedback.text = ("Saved %s. Swapped with %s." % [
			str(controls_api.LABELS.get(action,action)),
			str(controls_api.LABELS.get(exchanged,exchanged))]) if exchanged != "" else (
			"Saved binding for %s." % str(controls_api.LABELS.get(action,action)))
		_cancel_capture(false)
	else:
		binding_feedback.text = "Cannot assign that input. Try another button."
	_refresh_binding_buttons()
	get_viewport().set_input_as_handled()



func _info_label(parent: Control, node_name: String, value: String,
		at: Vector2, dimensions: Vector2, size_px: int, tint: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.position = at
	label.size = dimensions
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", tint)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _neon_panel(parent: Control, name_value: String, at: Vector2, dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = name_value
	panel.position = at
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.026, 0.051, 0.071, 0.94)
	skin.border_color = Color(0.38, 0.51, 0.61, 0.76)
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(16)
	skin.shadow_color = Color(0, 0, 0, 0.37)
	skin.shadow_size = 13
	panel.add_theme_stylebox_override("panel", skin)
	parent.add_child(panel)
	return panel


func _native_button(parent: Control, name_value: String, value: String,
		at: Vector2, dimensions: Vector2, primary: bool = false) -> Button:
	var button := Button.new()
	button.name = name_value
	button.text = value
	button.position = at
	button.size = dimensions
	_button_skin(button, primary)
	button.add_theme_font_size_override("font_size", 18)
	parent.add_child(button)
	return button


# The preview reads the selected vehicle's real catalog art and active stats.
func _build_vehicle_panel() -> void:
	_info_label(pause_screen, "PauseBrand", "STREETBOUND  /  GAME PAUSED",
		Vector2(51, 37), Vector2(288, 19), 11, Color("#ff9c5b"))
	_info_label(pause_screen, "PauseShortcut", "ESC  /  RESUME DRIVING",
		Vector2(51, 449), Vector2(288, 18), 10, Color("#9aabb7"))
	vehicle_panel = _neon_panel(pause_screen, "VehicleInfoPanel",
		Vector2(420, 88), Vector2(355, 350))
	_info_label(vehicle_panel, "VehicleCaption", "CURRENT VEHICLE",
		Vector2(18, 13), Vector2(315, 23), 12, Color("#ff9c5b"))
	vehicle_name_label = _info_label(vehicle_panel, "VehicleName", "YOUR VEHICLE",
		Vector2(18, 39), Vector2(318, 32), 23, Color("#f5f7fa"))
	var preview_back := ColorRect.new()
	preview_back.name = "VehiclePreviewBackdrop"
	preview_back.position = Vector2(17, 78)
	preview_back.size = Vector2(321, 137)
	preview_back.color = Color("#12222e")
	preview_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vehicle_panel.add_child(preview_back)
	vehicle_preview = TextureRect.new()
	vehicle_preview.name = "EquippedCarPreview"
	vehicle_preview.position = Vector2(26, 83)
	vehicle_preview.size = Vector2(303, 126)
	vehicle_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vehicle_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vehicle_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vehicle_panel.add_child(vehicle_preview)
	vehicle_fallback = _info_label(vehicle_panel, "PreviewUnavailable",
		"PREVIEW UNAVAILABLE", Vector2(35, 123), Vector2(282, 38),
		13, Color("#90a1ad"))
	vehicle_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label(vehicle_panel, "PowerCaption", "POWER", Vector2(21, 223),
		Vector2(144, 17), 11, Color("#9eafbe"))
	_info_label(vehicle_panel, "DriveCaption", "DRIVETRAIN", Vector2(188, 223),
		Vector2(140, 17), 11, Color("#9eafbe"))
	vehicle_power_label = _info_label(vehicle_panel, "VehiclePower", "—",
		Vector2(21, 242), Vector2(144, 27), 20, Color("#f5f7fa"))
	vehicle_drivetrain_label = _info_label(vehicle_panel, "VehicleDrivetrain", "—",
		Vector2(188, 242), Vector2(140, 27), 20, Color("#f5f7fa"))
	_info_label(vehicle_panel, "TorqueCaption", "TORQUE", Vector2(21, 275),
		Vector2(144, 17), 11, Color("#9eafbe"))
	_info_label(vehicle_panel, "WeightCaption", "WEIGHT", Vector2(188, 275),
		Vector2(140, 17), 11, Color("#9eafbe"))
	vehicle_torque_label = _info_label(vehicle_panel, "VehicleTorque", "—",
		Vector2(21, 292), Vector2(144, 27), 19, Color("#f5f7fa"))
	vehicle_weight_label = _info_label(vehicle_panel, "VehicleWeight", "—",
		Vector2(188, 292), Vector2(140, 27), 19, Color("#f5f7fa"))
	vehicle_level_label = _info_label(vehicle_panel, "VehicleLevels", "",
		Vector2(21, 323), Vector2(318, 17), 11, Color("#ffad76"))


func _refresh_vehicle_panel() -> void:
	if not is_instance_valid(vehicle_panel):
		return
	vehicle_panel.visible = is_instance_valid(player_vehicle)
	if not vehicle_panel.visible:
		return
	var config: VehicleConfig = player_vehicle.get("config") as VehicleConfig
	if config == null:
		vehicle_name_label.text = "VEHICLE UNAVAILABLE"
		vehicle_preview.texture = null
		vehicle_fallback.visible = true
		return
	var active_id := str(config.audio_sample_id)
	if is_instance_valid(vehicle_ownership):
		active_id = str(vehicle_ownership.active_id)
	var entry: Dictionary = VehicleCatalog.find_by_id(active_id)
	vehicle_name_label.text = str(entry.get("display_name", "CURRENT VEHICLE"))
	vehicle_power_label.text = "%.0f HP" % (config.engine_power_kw * 1.341022)
	vehicle_torque_label.text = "%.0f Nm" % config.engine_torque_nm
	vehicle_weight_label.text = "%.0f kg" % config.mass_kg
	var drives := ["FWD", "RWD", "AWD"]
	var index := int(config.drivetrain)
	vehicle_drivetrain_label.text = drives[index] if index >= 0 and index < drives.size() else "—"
	vehicle_level_label.text = ("DRIVER LV %d   /   CAR LV %d" % [
		vehicle_ownership.player_level(), vehicle_ownership.active_car_level()
	]) if is_instance_valid(vehicle_ownership) else "FREE DRIVE"
	var texture_path := str(entry.get("texture", ""))
	vehicle_preview.texture = (load(texture_path) as Texture2D) if (
		not texture_path.is_empty() and ResourceLoader.exists(texture_path, "Texture2D")) else null
	vehicle_fallback.visible = vehicle_preview.texture == null


func _build_multiplayer_screen() -> void:
	multiplayer_screen = Control.new()
	multiplayer_screen.name = "PauseMultiplayerScreen"
	multiplayer_screen.size = DESIGN_SIZE
	overlay.add_child(multiplayer_screen)
	var card := _neon_panel(multiplayer_screen, "MultiplayerPanel",
		Vector2(154, 71), Vector2(492, 355))
	_info_label(card, "MultiplayerEyebrow", "STREETBOUND  /  GAME MODES",
		Vector2(32, 22), Vector2(432, 24), 12, Color("#ff9c5b"))
	_info_label(card, "MultiplayerHeading", "MULTIPLAYER",
		Vector2(32, 53), Vector2(432, 49), 33, Color("#f5f7fa"))
	local_split_button = _native_button(card, "LocalSplitScreen",
		"LOCAL SPLIT-SCREEN", Vector2(32, 124), Vector2(428, 54), true)
	local_split_button.pressed.connect(_request_local_multiplayer)
	var online := _native_button(card, "OnlineComingSoon",
		"ONLINE MULTIPLAYER  —  COMING SOON",
		Vector2(32, 189), Vector2(428, 51))
	online.add_theme_font_size_override("font_size", 15)
	online.disabled = true
	online.tooltip_text = "Online multiplayer is not implemented yet."
	var back := _native_button(card, "BackToPause", "BACK",
		Vector2(32, 261), Vector2(428, 46))
	back.pressed.connect(back_to_pause)
	multiplayer_feedback = _info_label(card, "MultiplayerFeedback",
		"Keyboard + controller, or two controllers.",
		Vector2(32, 315), Vector2(428, 26), 12, Color("#bac8d3"))


func _refresh_multiplayer_page() -> void:
	if not is_instance_valid(local_split_button):
		return
	local_split_button.text = "EXIT SPLIT-SCREEN" if split_screen_active else "LOCAL SPLIT-SCREEN"
	local_split_button.disabled = online_session.active
	multiplayer_feedback.text = ("Online friends session active. Leave via Main Menu." if online_session.active
		else "Return to single-player driving." if split_screen_active
		else "Keyboard + controller, or two controllers.")


func _request_local_multiplayer() -> void:
	split_screen_requested.emit()


func _build_confirmation_screen() -> void:
	confirmation_screen = Control.new()
	confirmation_screen.name = "PauseConfirmationScreen"
	confirmation_screen.size = DESIGN_SIZE
	overlay.add_child(confirmation_screen)
	var panel := _neon_panel(confirmation_screen, "ConfirmationPanel",
		Vector2(178, 119), Vector2(444, 266))
	confirmation_heading = _info_label(panel, "ConfirmTitle", "LEAVE RACE?",
		Vector2(27, 20), Vector2(387, 46), 31, Color("#f5f7fa"))
	confirmation_copy = _info_label(panel, "ConfirmMessage",
		"Leaving will forfeit this race and its rewards.",
		Vector2(27, 77), Vector2(390, 56), 15, Color("#bac8d3"))
	confirmation_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation_accept = _native_button(panel, "ConfirmLeave", "LEAVE",
		Vector2(27, 148), Vector2(390, 43), true)
	confirmation_accept.pressed.connect(_accept_confirmation)
	var cancel := _native_button(panel, "CancelLeave", "KEEP DRIVING",
		Vector2(27, 200), Vector2(390, 43))
	cancel.pressed.connect(back_to_pause)


func _show_confirmation(target: String) -> void:
	confirmation_target = target
	confirmation_heading.text = "QUIT RACE?" if target == "quit" else "RETURN TO MENU?"
	confirmation_copy.text = "Your current race will end without rewards. Continue?"
	confirmation_accept.text = "QUIT GAME" if target == "quit" else "MAIN MENU"
	_show_page("confirm")


func _accept_confirmation() -> void:
	var target := confirmation_target
	confirmation_target = ""
	if target == "main_menu":
		main_menu_requested.emit()
	elif target == "quit":
		_request_quit()

func _track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#283f42")
	style.set_corner_radius_all(7)
	return style

func _filled_track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#ff8733")
	style.set_corner_radius_all(7)
	return style

func _resize_layout() -> void:
	if overlay == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available: Vector2 = Vector2(maxf(viewport_size.x - 20.0, 100.0), maxf(viewport_size.y - 20.0, 100.0))
	var factor: float = minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	var screen_position: Vector2 = (viewport_size - DESIGN_SIZE * factor) * 0.5
	for screen in [pause_screen, settings_screen, multiplayer_screen, confirmation_screen]:
		if screen != null:
			screen.position = screen_position
			screen.scale = Vector2.ONE * factor
	if is_instance_valid(dashboard):
		var hub_size := Vector2(1440, 800)
		var hub_scale := minf(available.x / hub_size.x, available.y / hub_size.y)
		dashboard.position = (viewport_size - hub_size * hub_scale) * 0.5
		dashboard.scale = Vector2.ONE * hub_scale

func _apply_saved_settings() -> void:
	var volume: float = clampf(float(settings_store.get_setting("volume")), 0.0, 100.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume / 100.0, 0.0001)))
	if is_instance_valid(vehicle_audio):
		vehicle_audio.muted = not bool(settings_store.get_setting("sound"))
	if is_instance_valid(driving_camera):
		driving_camera.follow_heading = bool(settings_store.get_setting("camera_follow"))
	_apply_minimap_shape()
	_apply_display_mode()

func _apply_minimap_shape() -> void:
	var map_hud: Node = get_tree().get_first_node_in_group("streetbound_world_map_hud")
	if is_instance_valid(map_hud) and map_hud.has_method("set_minimap_shape"):
		map_hud.call("set_minimap_shape", str(settings_store.get_setting("minimap_shape")))


func _selected_display_mode() -> String:
	var value: String=str(settings_store.get_setting("display_mode"))
	return value if value in DISPLAY_MODES else "windowed"


func _select_display_mode(index: int) -> void:
	if not is_instance_valid(display_mode_select):return
	var choice: String=str(display_mode_select.get_item_metadata(index))
	if choice not in DISPLAY_MODES:return
	settings_store.set_setting("display_mode",choice)
	_apply_display_mode()
	_sync_settings()


func _apply_display_mode() -> void:
	# Do not attempt desktop mode changes in headless tests or web exports.
	if DisplayServer.get_name()=="headless" or OS.has_feature("web"):return
	var mode: String=_selected_display_mode()
	var current: int=DisplayServer.window_get_mode()
	var borderless: bool=DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	if current==DisplayServer.WINDOW_MODE_WINDOWED and not borderless:
		last_windowed_size=DisplayServer.window_get_size()
		last_windowed_position=DisplayServer.window_get_position()
		has_windowed_rect=true
	# Applying the same preference when changing scenes must not interrupt a
	# window that the player has manually resized or maximized.
	if mode=="windowed" and current in [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_MAXIMIZED] and not borderless:return
	if mode=="borderless" and current==DisplayServer.WINDOW_MODE_MAXIMIZED and borderless:return
	if mode=="fullscreen" and current==DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:return
	match mode:
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,false)
			if has_windowed_rect:
				DisplayServer.window_set_size(last_windowed_size)
				DisplayServer.window_set_position(last_windowed_position)
		"borderless":
			# Maximize a borderless OS window, not an exclusive display mode.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _sync_settings() -> void:
	var sound: bool = bool(settings_store.get_setting("sound"))
	var camera_follow: bool = bool(settings_store.get_setting("camera_follow"))
	if is_instance_valid(vehicle_audio):
		sound = not vehicle_audio.muted
	if is_instance_valid(driving_camera):
		camera_follow = driving_camera.follow_heading
	if is_instance_valid(display_mode_select):
		var active_mode: String=_selected_display_mode()
		for i in display_mode_select.item_count:
			if str(display_mode_select.get_item_metadata(i))==active_mode:
				display_mode_select.select(i)
				break
	settings_screen.set_data({"settings": {
		"sound": sound,
		"volume": float(settings_store.get_setting("volume")),
		"camera_follow": camera_follow,
		"minimap_shape": "Circle" if str(settings_store.get_setting("minimap_shape")) == "circle" else "Square"
	}})

func set_split_screen_active(enabled: bool) -> void:
	split_screen_active = enabled
	_update_map_editor_button()
	var action: Button = pause_screen.controls.get("local_multiplayer")
	if is_instance_valid(action):
		action.text = "Multiplayer"
	if is_instance_valid(local_split_button):
		local_split_button.text = "EXIT SPLIT-SCREEN" if enabled else "LOCAL SPLIT-SCREEN"
	var title: Label = pause_screen.controls.get("pause_heading")
	if is_instance_valid(title):
		title.text = "PAUSED"


func set_map_editor_available(enabled: bool) -> void:
	map_editor_available = enabled
	_update_map_editor_button()


func _update_map_editor_button() -> void:
	if not is_instance_valid(pause_screen):
		return
	var action: Button = pause_screen.controls.get("map_editor")
	if not is_instance_valid(action):
		return
	action.disabled = not map_editor_available or split_screen_active
	action.tooltip_text = ("Map Editor is available in development builds only."
		if not map_editor_available else
		"Exit split-screen to edit the world." if split_screen_active else
		"Inspect and edit the real Godot world; changes are validated before rebuilding.")


func show_split_screen_error(message: String) -> void:
	var title: Label = pause_screen.controls.get("pause_heading")
	if is_instance_valid(title):
		title.text = "CONNECT A GAMEPAD"
	var action: Button = pause_screen.controls.get("local_multiplayer")
	if is_instance_valid(action):
		action.tooltip_text = message
	if is_instance_valid(multiplayer_feedback):
		multiplayer_feedback.text = message


func _show_page(page: String) -> void:
	if page=="paused":
		set_split_screen_active(split_screen_active)
		_update_race_button()
		_refresh_vehicle_panel()
		if is_instance_valid(dashboard):
			dashboard.vehicle = player_vehicle
			dashboard.economy = vehicle_ownership
			dashboard.upgrades = quick_upgrades
			dashboard.refresh_on_open()
	elif page == "multiplayer":
		_refresh_multiplayer_page()
	menu_state = page
	overlay.visible = true
	pause_screen.visible = page == "paused"
	if is_instance_valid(dashboard):
		dashboard.visible = page == "paused"
		dashboard.set_render_active(page == "paused")
	settings_screen.visible = page == "settings"
	multiplayer_screen.visible = page == "multiplayer"
	confirmation_screen.visible = page == "confirm"
	if page == "settings":
		_sync_settings()
		_set_settings_tab("general")
	var focused: Button
	match page:
		"paused":
			focused = dashboard.nav_buttons.get("resume") if is_instance_valid(dashboard) else pause_screen.controls.get("resume")
		"settings":
			focused = settings_screen.controls.get("back")
		"multiplayer":
			focused = local_split_button
		"confirm":
			focused = confirmation_accept
	if is_instance_valid(focused):
		focused.grab_focus()

func pause_game() -> void:
	if online_session.active:
		# Online UI pause must never stop the host's shared simulation.
		if not menu_state.is_empty():
			return
		if is_instance_valid(player_vehicle):
			player_vehicle.external_input = true
			player_vehicle.command = Vector4.ZERO
			player_vehicle.nitrous_requested = false
		_show_page("paused")
		return
	if get_tree().paused:
		return
	get_tree().paused = true
	_show_page("paused")

func resume_game() -> void:
	if is_instance_valid(dashboard):
		dashboard.set_render_active(false)
	overlay.visible = false
	menu_state = ""
	_cancel_capture()
	get_viewport().gui_release_focus()
	if online_session.active and is_instance_valid(player_vehicle) and not split_screen_active:
		player_vehicle.external_input = false
	get_tree().paused = false

func open_settings() -> void:
	if not get_tree().paused and menu_state.is_empty():
		pause_game()
	_show_page("settings")

func back_to_pause() -> void:
	if settings_back_to_title:
		settings_back_to_title = false
		resume_game()
		return
	_show_page("paused")

func _request_quit() -> void:
	exit_requested.emit()
	if allow_quit:
		get_tree().quit()

func active_race() -> Node:
	for race in get_tree().get_nodes_in_group("streetbound_race"):
		if str(race.get("state")) in ["countdown","running"] and race.has_method("quit_race"):return race
	return null

func _update_race_button() -> void:
	if not is_instance_valid(quit_race_button):return
	var racing:=is_instance_valid(active_race())
	quit_race_button.visible=racing
	if racing:
		var order: Array = [pause_screen.controls.resume, quit_race_button]
		for id in ["local_multiplayer","map_editor","settings","main_menu","quit"]:
			order.append(pause_screen.controls[id])
		for i in order.size():
			order[i].position.y = 108 + i * 47
			order[i].size.y = 42
	else:
		for entry in pause_screen.layout.nodes:
			var control: Control=pause_screen.controls.get(str(entry.get("id","")))
			if control is Button:control.position.y=float(entry.y);control.size.y=float(entry.h)

func _quit_active_race() -> void:
	var race:=active_race()
	if is_instance_valid(race):race.call("quit_race")
	_update_race_button()
	resume_game()

func _handle_action(action_id: String, payload: Dictionary) -> void:
	match action_id:
		"game.resume":
			resume_game()
		"game.local_multiplayer":
			# Kept for existing direct calls; the visible button opens the submenu.
			split_screen_requested.emit()
		"nav.multiplayer":
			_show_page("multiplayer")
		"game.map_editor":
			if map_editor_available and not split_screen_active:
				map_editor_requested.emit()
		"nav.main_menu":
			if is_instance_valid(active_race()):
				_show_confirmation("main_menu")
			else:
				main_menu_requested.emit()
		"nav.settings":
			open_settings()
		"nav.back":
			back_to_pause()
		"game.quit":
			if is_instance_valid(active_race()):
				_show_confirmation("quit")
			else:
				_request_quit()
		"settings.sfx_changed":
			var sound: bool = bool(payload.get("value", true))
			settings_store.set_setting("sound", sound)
			if is_instance_valid(vehicle_audio):
				vehicle_audio.muted = not sound
		"settings.volume_changed":
			var volume: float = clampf(float(payload.get("value", 80.0)), 0.0, 100.0)
			settings_store.set_setting("volume", volume)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume / 100.0, 0.0001)))
		"settings.camera_changed":
			var enabled: bool = bool(payload.get("value", false))
			settings_store.set_setting("camera_follow", enabled)
			if is_instance_valid(driving_camera):
				driving_camera.follow_heading = enabled
		"settings.minimap_shape_toggle":
			var current: String = str(settings_store.get_setting("minimap_shape"))
			settings_store.set_setting("minimap_shape",
				"square" if current == "circle" else "circle")
			_apply_minimap_shape()
			_sync_settings()

func _controller_back() -> void:
	if menu_state=="settings" and settings_tab in ["controls","graphics"]:
		_set_settings_tab("general")
	elif menu_state in ["settings","multiplayer","confirm"]:
		back_to_pause()
	elif not menu_state.is_empty():
		resume_game()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
	var emergency_escape := event is InputEventKey and (
		(event as InputEventKey).keycode == KEY_ESCAPE or
		(event as InputEventKey).physical_keycode == KEY_ESCAPE)
	if not event.is_action_pressed("pause") and not emergency_escape:
		return
	get_viewport().set_input_as_handled()
	# A remapped Pause/Menu button also works on gamepads. Escape always
	# remains the fail-safe to reach the settings menu again.
	var menu_open: bool = get_tree().paused or (bool(online_session.active) and not menu_state.is_empty())
	if menu_open and menu_state.is_empty():
		return
	if not menu_open:
		pause_game()
	elif menu_state == "settings" and settings_tab == "controls":
		_set_settings_tab("general")
	elif menu_state in ["settings", "multiplayer", "confirm"]:
		back_to_pause()
	else:
		resume_game()
