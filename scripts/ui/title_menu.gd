extends Control
@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
@onready var lan_discovery: Node = get_node_or_null("/root/LanDiscovery")
## Cinematic title scene; the same real gameplay, editor, settings and local
## split-screen modes are reached through controller-friendly menu buttons.
const LanDiscoveryScript = preload("res://scripts/network/lan_discovery.gd")
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
var lan_page: VBoxContainer
var lan_name: LineEdit
var lan_games: ItemList
var lan_message: Label
var lan_records: Array[Dictionary] = []
var friend_name: LineEdit
var friend_address: LineEdit
var friend_port: LineEdit
var friend_code: LineEdit
var friend_message: Label
var settings_adapter: CanvasLayer
var message: Label
var multiplayer_message: Label
var actions: Dictionary = {}
var _launch_thread: Thread
var _launch_mode: String=""
var _loading_label: Label
var _launch_started:=0

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
	if lan_discovery != null:
		lan_discovery.room_found.connect(_on_lan_room_found)
		lan_discovery.status_changed.connect(_on_lan_status)
		lan_discovery.scan_finished.connect(_on_lan_scan_finished)
	get_node("/root/MenuNavigation").register_scope(shell,0,_controller_back)
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
	_build_lan_page()
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
	_add_action(multiplayer_page, "lan_multiplayer", "FIND / HOST LAN GAME", "◈")
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
	var info := _label("Host with a reachable address or join using a private invitation.", 15, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.y = 36
	friends_page.add_child(info)
	friend_name = _friend_field("Driver name", "Driver")
	friend_name.max_length = 24
	friend_address = _friend_field("Host IP / DNS (use Tailscale address for remote friends)",
		LanDiscoveryScript.local_ipv4())
	friend_port = _friend_field("Host UDP port", str(online_session.DEFAULT_PORT))
	friend_code = _friend_field("Paste a friend's invitation here", "")
	friend_code.max_length = 600
	for action in [
		["host_friend_session", "HOST FRIEND SESSION"],
		["join_friend_session", "JOIN FRIEND SESSION"],
		["friends_back", "BACK"]
	]:
		_add_action(friends_page, str(action[0]), str(action[1]), "›")
		var button := actions[str(action[0])] as Button
		button.custom_minimum_size = Vector2(492, 51)
	friend_message = _label("Invite codes work over LAN, or via a reachable WAN address with UDP forwarding.", 14, MUTED)
	friend_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	friend_message.custom_minimum_size.y = 55
	friends_page.add_child(friend_message)

func _build_lan_page() -> void:
	lan_page = VBoxContainer.new()
	lan_page.name = "LANPage"
	lan_page.add_theme_constant_override("separation", 8)
	card.add_child(lan_page)
	var heading := _label("PLAY TOGETHER ON LAN", 26, WHITE)
	heading.custom_minimum_size.y = 48
	lan_page.add_child(heading)
	var description := _label(
		"Host a game while you play, or find hosts on the same network.", 15, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 44
	lan_page.add_child(description)
	lan_name = LineEdit.new()
	lan_name.name = "LANDriverName"
	lan_name.placeholder_text = "Your driver name"
	lan_name.text = "Driver"
	lan_name.max_length = 24
	lan_name.custom_minimum_size.y = 40
	lan_page.add_child(lan_name)
	_add_action(lan_page, "host_lan_game", "HOST LAN GAME", "◈")
	_add_action(lan_page, "scan_lan_games", "FIND LAN GAMES", "⌕")
	for id in ["host_lan_game", "scan_lan_games"]:
		(actions[id] as Button).custom_minimum_size.y = 44
	lan_games = ItemList.new()
	lan_games.name = "LANGameResults"
	lan_games.custom_minimum_size = Vector2(492, 110)
	lan_games.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_games.item_activated.connect(_join_selected_lan_game.unbind(1))
	lan_page.add_child(lan_games)
	_add_action(lan_page, "join_lan_game", "JOIN SELECTED LAN GAME", "›")
	_add_action(lan_page, "lan_back", "BACK", "‹")
	for id in ["join_lan_game", "lan_back"]:
		(actions[id] as Button).custom_minimum_size.y = 44
	lan_message = _label(
		"LAN games are visible to anyone on your Wi-Fi/local subnet.", 14, MUTED)
	lan_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lan_message.custom_minimum_size.y = 50
	lan_page.add_child(lan_message)

func _on_lan_room_found(record: Dictionary) -> void:
	if not is_instance_valid(lan_games):
		return
	lan_records.append(record)
	lan_games.add_item("%s   %d/%d   (%s)" % [
		str(record.name), int(record.players), online_session.MAX_PLAYERS,
		str(record.ip)])
	if lan_games.item_count == 1:
		lan_games.select(0)

func _on_lan_status(status: String) -> void:
	if is_instance_valid(lan_message):
		lan_message.text = status

func _on_lan_scan_finished() -> void:
	if is_instance_valid(lan_games) and lan_games.item_count == 0:
		lan_message.text = "No LAN hosts found. Check Wi-Fi, guest network and firewall."

func _host_lan_game() -> void:
	if not online_session.host_session(lan_name.text, online_session.DEFAULT_PORT,
			LanDiscoveryScript.local_ipv4()):
		lan_message.text = str(online_session.last_message)
		return
	# Explicit opt-in: the admission key appears in LAN discovery responses.
	if not lan_discovery.start_advertising():
		online_session.leave_session()
		lan_message.text = "Could not make your game discoverable; use a direct invite."
		return
	_start_game("online")

func _scan_lan_games() -> void:
	lan_records.clear()
	lan_games.clear()
	if not lan_discovery.scan():
		lan_message.text = str(lan_discovery.last_message)

func _join_selected_lan_game() -> void:
	var chosen: PackedInt32Array = lan_games.get_selected_items()
	if chosen.is_empty() or int(chosen[0]) >= lan_records.size():
		lan_message.text = "Select a LAN game first."
		return
	var record: Dictionary = lan_records[int(chosen[0])]
	if int(record.players) >= online_session.MAX_PLAYERS:
		lan_message.text = "That LAN game is full."
		return
	lan_discovery.cancel_scan()
	online_session.join_invite(str(record.invite), lan_name.text)

func _online_status(status: String) -> void:
	if is_instance_valid(friend_message):
		friend_message.text = status
	if is_instance_valid(lan_message):
		lan_message.text = status

func _online_joined() -> void:
	if is_inside_tree() and (friends_page.visible or lan_page.visible) and get_tree().current_scene == self:
		_start_game("online")

func _start_friends(host: bool) -> void:
	if host:
		if not friend_port.text.is_valid_int():
			friend_message.text = "Enter a valid UDP port."
			return
		var port := int(friend_port.text)
		if online_session.host_session(friend_name.text, port, friend_address.text):
			_start_game("online")
	else:
		online_session.join_invite(friend_code.text, friend_name.text)

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
	lan_page.visible = false
	if restore_focus:
		actions["multiplayer"].grab_focus()

func _show_multiplayer() -> void:
	main_page.visible = false
	multiplayer_page.visible = true
	friends_page.visible = false
	lan_page.visible = false
	multiplayer_message.text = (
		"Local split-screen: keyboard + controller, or two controllers.")
	actions["local_multiplayer"].grab_focus()

func _show_friends() -> void:
	main_page.visible = false
	multiplayer_page.visible = false
	friends_page.visible = true
	lan_page.visible = false
	friend_message.text = "For friends at another house, use Tailscale or a reachable UDP address."
	actions["host_friend_session"].grab_focus()

func _show_lan() -> void:
	main_page.visible = false
	multiplayer_page.visible = false
	friends_page.visible = false
	lan_page.visible = true
	lan_message.text = "LAN visibility is opt-in. A LAN host stays online only while playing."
	actions["scan_lan_games"].grab_focus()

func _controller_back() -> void:
	if _launch_thread!=null:return
	if friends_page.visible or lan_page.visible:
		lan_discovery.cancel_scan()
		online_session.leave_session()
		_show_multiplayer()
	elif multiplayer_page.visible:
		_show_main_menu()

func _unhandled_input(event: InputEvent) -> void:
	if _launch_thread!=null:return
	if not get_tree().paused and event.is_action_pressed("ui_cancel"):
		if friends_page.visible or lan_page.visible:
			lan_discovery.cancel_scan()
			online_session.leave_session()
			_show_multiplayer()
			get_viewport().set_input_as_handled()
		elif multiplayer_page.visible:
			_show_main_menu()
			get_viewport().set_input_as_handled()

func _activate(mode: String) -> void:
	if _launch_thread!=null:return
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
		"lan_multiplayer":
			_show_lan()
		"lan_back":
			lan_discovery.cancel_scan()
			_show_multiplayer()
		"host_lan_game":
			_host_lan_game()
		"scan_lan_games":
			_scan_lan_games()
		"join_lan_game":
			_join_selected_lan_game()
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
	if _launch_thread!=null:return
	_launch_mode=mode
	_launch_started=Time.get_ticks_msec()
	for button in actions.values():button.disabled=true
	_loading_label=Label.new()
	_loading_label.text="Preparing world archive…"
	_loading_label.position=Vector2(30,30)
	_loading_label.add_theme_font_size_override("font_size",24)
	add_child(_loading_label)
	var selected: Dictionary=WorldPublication.current()
	var path: String=str(selected.archive)
	_launch_thread=Thread.new()
	var result:=_launch_thread.start(_read_archive.bind(path))
	if result!=OK:
		_launch_thread=null
		_enter_game(mode)
	else:
		ResourceLoader.load_threaded_request("res://scenes/main.tscn")

static func _read_archive(path: String) -> Dictionary:
	var raw:=FileAccess.get_file_as_string(path)
	var parsed: Variant=JSON.parse_string(raw)
	return {"path":path,"sha":raw.sha256_text(),"data":parsed}

func _process(_dt: float) -> void:
	if _launch_thread==null:return
	_loading_label.text="Preparing world archive… %.1f s"%((Time.get_ticks_msec()-_launch_started)/1000.0)
	if _launch_thread.is_alive():return
	var state:=ResourceLoader.load_threaded_get_status("res://scenes/main.tscn")
	if state==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_loading_label.text="Loading game resources…"
		return
	var prepared: Dictionary=_launch_thread.wait_to_finish()
	_launch_thread=null
	if prepared.data is Dictionary:get_tree().set_meta("streetbound_prepared_archive",prepared)
	var scene: PackedScene
	if state==ResourceLoader.THREAD_LOAD_LOADED:scene=ResourceLoader.load_threaded_get("res://scenes/main.tscn") as PackedScene
	_enter_game(_launch_mode,scene)

func _exit_tree() -> void:
	if _launch_thread!=null and _launch_thread.is_started():_launch_thread.wait_to_finish()

func _enter_game(mode: String, scene: PackedScene=null) -> void:
	get_tree().set_meta("streetbound_title_launch_mode",mode if mode=="multiplayer" else "")
	get_tree().paused = false
	var outcome := get_tree().change_scene_to_packed(scene) if scene!=null else get_tree().change_scene_to_file("res://scenes/main.tscn")
	if outcome != OK:
		get_tree().remove_meta("streetbound_title_launch_mode")
		if get_tree().has_meta("streetbound_prepared_archive"):get_tree().remove_meta("streetbound_prepared_archive")
		if is_instance_valid(_loading_label):_loading_label.queue_free()
		for button in actions.values():button.disabled=false
		_refresh_buttons()
		if mode == "online":
			online_session.leave_session()
		var feedback := (lan_message if mode == "online" and lan_page.visible else
			friend_message if mode == "online" else
			multiplayer_message if mode == "multiplayer" else message)
		feedback.text = "Could not open the gameplay scene."
