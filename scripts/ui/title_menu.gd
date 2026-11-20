extends Control
@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
## Cinematic title scene; the same real gameplay, editor, settings and local
## split-screen modes are reached through controller-friendly menu buttons.
const GameplayScript = preload("res://scripts/main.gd")
const WorldPublication=preload("res://scripts/world/world_publication.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const BackgroundTexture = preload("res://assets/ui/title_neon_city.svg")
const FeaturedCar = preload("res://assets/Vehicles/McLaren/570S.png")

const DESIGN_SIZE := Vector2(1600.0, 900.0)
const ACCENT := Color("#ff8733")
const WHITE := Color("#f5f7fa")
const MUTED := Color("#b5c1cf")

var shell: Control
var card: PanelContainer
var main_page: VBoxContainer
var multiplayer_page: VBoxContainer
var friends_page: VBoxContainer
var friend_name: LineEdit
var friend_address: LineEdit
var friend_port: LineEdit
var friend_message: Label
var settings_adapter: CanvasLayer
var message: Label
var multiplayer_message: Label
var actions: Dictionary = {}

func _ready() -> void:
	name = "StreetboundMainMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	_build_background()
	_build_shell()
	settings_adapter = CanvasLayer.new()
	settings_adapter.name = "TitleSettings"
	settings_adapter.set_script(PauseMenuScript)
	add_child(settings_adapter)
	get_viewport().size_changed.connect(_resize_layout)
	_resize_layout()
	_refresh_buttons()
	online_session.status_changed.connect(_online_status)
	online_session.session_accepted.connect(_online_joined)
	actions["single_player"].grab_focus()

func _panel_style(color: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new()
	skin.bg_color = color
	skin.border_color = border
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(radius)
	return skin

func _label(value: String, font_size: int, tint: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var item := Label.new()
	item.text = value
	item.horizontal_alignment = align
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.add_theme_color_override("font_color", tint)
	item.add_theme_font_size_override("font_size", font_size)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "MenuBackground"
	background.texture = BackgroundTexture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

func _build_shell() -> void:
	shell = Control.new()
	shell.name = "MenuShell"
	shell.size = DESIGN_SIZE
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)

	# The same existing top-down car asset is featured in the title art.
	# It remains decorative; only the buttons respond to input.
	var featured := TextureRect.new()
	featured.name = "FeaturedVehicle"
	featured.texture = FeaturedCar
	featured.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	featured.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	featured.position = Vector2(930, 220)
	featured.size = Vector2(425, 480)
	featured.pivot_offset = featured.size * 0.5
	featured.rotation_degrees = -43.0
	featured.modulate = Color(1, 0.93, 0.87, 0.93)
	featured.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(featured)

	var left_scrim := ColorRect.new()
	left_scrim.name = "LeftMenuScrim"
	left_scrim.color = Color(0.025, 0.038, 0.057, 0.87)
	left_scrim.position = Vector2.ZERO
	left_scrim.size = Vector2(685, 900)
	left_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(left_scrim)

	var top_scrim := ColorRect.new()
	top_scrim.name = "TopRightScrim"
	top_scrim.color = Color(0.025, 0.037, 0.055, 0.61)
	top_scrim.position = Vector2(1260, 36)
	top_scrim.size = Vector2(284, 85)
	top_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(top_scrim)

	# A text logo, not baked pixels, remains sharp at every window size.
	var logo := HBoxContainer.new()
	logo.name = "StreetboundLogo"
	logo.position = Vector2(53, 48)
	logo.add_theme_constant_override("separation", 0)
	shell.add_child(logo)
	logo.add_child(_label("STREET", 70, WHITE))
	logo.add_child(_label("BOUND", 70, ACCENT))
	var underline := ColorRect.new()
	underline.name = "LogoUnderline"
	underline.color = ACCENT
	underline.position = Vector2(56, 139)
	underline.size = Vector2(553, 6)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(underline)
	var sub := _label("DRIVE  /  EXPLORE  /  BUILD", 18, MUTED)
	sub.position = Vector2(56, 157)
	sub.size = Vector2(530, 34)
	shell.add_child(sub)

	# Do not invent persistent profile balances before a profile system exists.
	var context := _label(str(WorldPublication.current().name).to_upper(), 21, WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	context.position = Vector2(1280, 44)
	context.size = Vector2(244, 34)
	shell.add_child(context)
	var context_sub := _label("OPEN-WORLD DRIVING", 13, Color("#83d3df"),
		HORIZONTAL_ALIGNMENT_RIGHT)
	context_sub.position = Vector2(1280, 78)
	context_sub.size = Vector2(244, 24)
	shell.add_child(context_sub)

	card = PanelContainer.new()
	card.name = "MainMenuPanel"
	card.position = Vector2(47, 233)
	card.size = Vector2(544, 600)
	card.custom_minimum_size = Vector2(544, 600)
	var panel := _panel_style(Color(0.025, 0.040, 0.055, 0.89),
		Color(0.51, 0.61, 0.67, 0.48), 17)
	panel.set_content_margin_all(24)
	panel.shadow_color = Color(0, 0, 0, 0.43)
	panel.shadow_size = 20
	card.add_theme_stylebox_override("panel", panel)
	shell.add_child(card)
	_build_main_page()
	_build_multiplayer_page()
	_build_friends_page()
	_show_main_menu(false)

	var note := _label("STREETBOUND  /  EARLY ACCESS", 13, Color("#9aaaba"),
		HORIZONTAL_ALIGNMENT_RIGHT)
	note.position = Vector2(1182, 843)
	note.size = Vector2(360, 24)
	shell.add_child(note)

func _build_main_page() -> void:
	main_page = VBoxContainer.new()
	main_page.name = "MainPage"
	main_page.add_theme_constant_override("separation", 10)
	card.add_child(main_page)
	var heading := _label("MAIN MENU", 15, Color("#eeb28e"))
	heading.custom_minimum_size.y = 28
	main_page.add_child(heading)
	_add_action(main_page, "single_player", "PLAY", "▶", true)
	_add_action(main_page, "multiplayer", "MULTIPLAYER", "◈")
	_add_action(main_page, "map_editor", "MAP BUILDER", "▤")
	_add_action(main_page, "settings", "SETTINGS", "⚙")
	_add_action(main_page, "quit", "QUIT", "⏻")
	message = _label("Choose a mode to continue.", 15, MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 66
	main_page.add_child(message)

func _build_multiplayer_page() -> void:
	multiplayer_page = VBoxContainer.new()
	multiplayer_page.name = "MultiplayerPage"
	multiplayer_page.add_theme_constant_override("separation", 13)
	card.add_child(multiplayer_page)
	var heading := _label("MULTIPLAYER", 30, WHITE)
	heading.custom_minimum_size.y = 55
	multiplayer_page.add_child(heading)
	var intro := _label("Choose how you want to play.", 17, MUTED)
	intro.custom_minimum_size.y = 43
	multiplayer_page.add_child(intro)
	_add_action(multiplayer_page, "local_multiplayer", "LOCAL MULTIPLAYER", "◈", true)
	_add_action(multiplayer_page, "online_multiplayer",
		"PLAY WITH FRIENDS (ONLINE)", "◈")
	_add_action(multiplayer_page, "back", "BACK", "‹")
	multiplayer_message = _label(
		"Local split-screen: keyboard + controller, or two controllers.",
		15, MUTED)
	multiplayer_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	multiplayer_message.custom_minimum_size.y = 90
	multiplayer_page.add_child(multiplayer_message)

func _friend_field(placeholder: String, default_text: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = default_text
	field.custom_minimum_size = Vector2(492, 44)
	field.add_theme_font_size_override("font_size", 19)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_page.add_child(field)
	return field

func _build_friends_page() -> void:
	friends_page = VBoxContainer.new()
	friends_page.name = "FriendsPage"
	friends_page.add_theme_constant_override("separation", 9)
	card.add_child(friends_page)
	var heading := _label("PLAY WITH FRIENDS", 27, WHITE)
	heading.custom_minimum_size.y = 45
	friends_page.add_child(heading)
	var info := _label("Host a session, or enter a friend's IP address and UDP port.", 15, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.y = 36
	friends_page.add_child(info)
	friend_name = _friend_field("Driver name", "Driver")
	friend_name.max_length = 24
	friend_address = _friend_field("Host IP or hostname (for joining)", "127.0.0.1")
	friend_port = _friend_field("UDP port (both players must match)", str(online_session.DEFAULT_PORT))
	for action in [
		["host_friend_session", "HOST FRIEND SESSION"],
		["join_friend_session", "JOIN FRIEND SESSION"],
		["friends_back", "BACK"]
	]:
		_add_action(friends_page, str(action[0]), str(action[1]), "›")
		var button := actions[str(action[0])] as Button
		button.custom_minimum_size = Vector2(492, 51)
	friend_message = _label("Direct connection. Internet hosting may require UDP port forwarding.", 14, MUTED)
	friend_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	friend_message.custom_minimum_size.y = 55
	friends_page.add_child(friend_message)

func _online_status(status: String) -> void:
	if is_instance_valid(friend_message):
		friend_message.text = status

func _online_joined() -> void:
	if is_inside_tree() and friends_page.visible and get_tree().current_scene == self:
		_start_game("online")

func _start_friends(host: bool) -> void:
	if not friend_port.text.is_valid_int():
		friend_message.text = "Enter a valid UDP port."
		return
	var port := int(friend_port.text)
	if host:
		if online_session.host_session(friend_name.text, port):
			_start_game("online")
	else:
		online_session.join_session(friend_address.text, friend_name.text, port)

func _add_action(parent: VBoxContainer, id: String, title: String,
		symbol: String, primary: bool = false, unavailable: bool = false) -> void:
	var button := Button.new()
	button.name = id
	button.text = "    %s    %s" % [symbol, title]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(492, 67)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 21 if not unavailable else 16)
	button.add_theme_constant_override("h_separation", 16)
	var bg := _panel_style(
		Color(0.87, 0.27, 0.065, 0.93) if primary else Color(0.12, 0.17, 0.21, 0.94),
		ACCENT if primary else Color(0.53, 0.62, 0.68, 0.66), 12)
	bg.set_border_width_all(2 if primary else 1)
	var hover := bg.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#ff773b") if primary else Color("#29485b")
	var down := hover.duplicate() as StyleBoxFlat
	down.bg_color = Color("#cc5926") if primary else Color("#142936")
	var focus := bg.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = WHITE
	focus.set_border_width_all(3)
	var disabled_style := bg.duplicate() as StyleBoxFlat
	disabled_style.bg_color = Color(0.085, 0.12, 0.16, 0.88)
	disabled_style.border_color = Color(0.29, 0.34, 0.39, 0.72)
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(style,
			bg if style == "normal" else hover if style == "hover" else
			down if style == "pressed" else focus if style == "focus" else
			disabled_style)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#8e9da9"))
	button.disabled = unavailable
	if unavailable:
		button.tooltip_text = "Online multiplayer has not been implemented yet."
	button.pressed.connect(_activate.bind(id))
	parent.add_child(button)
	actions[id] = button

func _resize_layout() -> void:
	if not is_instance_valid(shell):
		return
	var viewport_size := get_viewport_rect().size
	var factor := maxf(0.1, minf(viewport_size.x / DESIGN_SIZE.x,
		viewport_size.y / DESIGN_SIZE.y))
	shell.scale = Vector2.ONE * factor
	shell.position = (viewport_size - DESIGN_SIZE * factor) * 0.5

func _refresh_buttons() -> void:
	var editor_mode := OS.has_feature("debug") or OS.has_feature("editor")
	var editor_button: Button = actions["map_editor"]
	editor_button.disabled = not editor_mode
	editor_button.tooltip_text = (
		"Godot development builds only." if not editor_mode else
		"Open the map builder to edit, test and publish a custom game world.")
	if not editor_mode:
		message.text = "Map Builder is available in development builds only."

func _show_main_menu(restore_focus: bool = true) -> void:
	main_page.visible = true
	multiplayer_page.visible = false
	friends_page.visible = false
	if restore_focus:
		actions["multiplayer"].grab_focus()

func _show_multiplayer() -> void:
	main_page.visible = false
	multiplayer_page.visible = true
	friends_page.visible = false
	multiplayer_message.text = (
		"Local split-screen: keyboard + controller, or two controllers.")
	actions["local_multiplayer"].grab_focus()

func _show_friends() -> void:
	main_page.visible = false
	multiplayer_page.visible = false
	friends_page.visible = true
	friend_message.text = "Direct IP/UDP connection; no public matchmaking or automatic NAT traversal."
	actions["host_friend_session"].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not get_tree().paused and event.is_action_pressed("ui_cancel"):
		if friends_page.visible:
			online_session.leave_session()
			_show_multiplayer()
			get_viewport().set_input_as_handled()
		elif multiplayer_page.visible:
			_show_main_menu()
			get_viewport().set_input_as_handled()

func _activate(mode: String) -> void:
	match mode:
		"settings":
			settings_adapter.settings_back_to_title = true
			settings_adapter.open_settings()
		"quit":
			get_tree().quit()
		"multiplayer":
			_show_multiplayer()
		"back":
			_show_main_menu()
		"online_multiplayer":
			_show_friends()
		"friends_back":
			online_session.leave_session()
			_show_multiplayer()
		"host_friend_session":
			_start_friends(true)
		"join_friend_session":
			_start_friends(false)
		"local_multiplayer":
			if Input.get_connected_joypads().is_empty():
				multiplayer_message.text = (
					"Connect at least one controller to start local split-screen.")
				return
			_start_game("multiplayer")
		"map_editor":
			if not (OS.has_feature("debug") or OS.has_feature("editor")):
				message.text = "Map Builder requires a Godot development build."
				return
			get_tree().paused = false
			var outcome := get_tree().change_scene_to_file(
				"res://scenes/world_editor.tscn")
			if outcome != OK:
				message.text = "Could not open the standalone Map Builder."
		"single_player":
			_start_game(mode)

func _start_game(mode: String) -> void:
	GameplayScript.pending_launch_mode = mode if mode == "multiplayer" else ""
	get_tree().paused = false
	var outcome := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if outcome != OK:
		GameplayScript.pending_launch_mode = ""
		if mode == "online":
			online_session.leave_session()
		var feedback := friend_message if mode == "online" else \
			multiplayer_message if mode == "multiplayer" else message
		feedback.text = "Could not open the gameplay scene."
