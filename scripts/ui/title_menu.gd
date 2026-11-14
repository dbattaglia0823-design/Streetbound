extends Control
## Launcher for Streetbound's real Godot gameplay scene. Keeping this as a
## separate startup scene ensures tests can instantiate main.tscn directly.
const GameplayScript = preload("res://scripts/main.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const CARD_SIZE := Vector2(500,635)
const ACCENT := Color("#f2b277")

var card: PanelContainer
var settings_adapter: CanvasLayer
var message: Label
var actions: Dictionary = {}

func _ready() -> void:
	name = "StreetboundMainMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	_build_background()
	_build_card()
	settings_adapter = CanvasLayer.new()
	settings_adapter.name = "TitleSettings"
	settings_adapter.set_script(PauseMenuScript)
	add_child(settings_adapter)
	get_viewport().size_changed.connect(_resize_card)
	_resize_card()
	_refresh_buttons()
	actions["single_player"].grab_focus()

func _panel_style(color: Color, border: Color, radius: int = 16) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new()
	skin.bg_color = color
	skin.border_color = border
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(radius)
	return skin

func _label(value: String, size_px: int, tint: Color, alignment: HorizontalAlignment) -> Label:
	var item := Label.new()
	item.text = value
	item.horizontal_alignment = alignment
	item.add_theme_color_override("font_color",tint)
	item.add_theme_font_size_override("font_size",size_px)
	return item

func _build_background() -> void:
	var background := ColorRect.new()
	background.name = "MenuBackground"
	background.color = Color("#09151b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var stripe := ColorRect.new()
	stripe.name = "AccentStripe"
	stripe.color = Color("#e6a46a")
	stripe.anchor_right = 1.0
	stripe.offset_top = 0
	stripe.offset_bottom = 4
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(stripe)
	var lower := ColorRect.new()
	lower.color = Color("#123037")
	lower.anchor_top = 0.8
	lower.anchor_right = 1.0
	lower.anchor_bottom = 1.0
	lower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(lower)

func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "MainMenuPanel"
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	var panel := _panel_style(Color("#11232b"),Color("#46616a"),20)
	panel.shadow_color = Color(0,0,0,0.34)
	panel.shadow_size = 18
	panel.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel",panel)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	card.add_child(column)
	var kicker := _label("STREETBOUND  /  MORROW COAST",13,
		Color("#93b8b9"),HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(kicker)
	var title := _label("STREETBOUND",46,ACCENT,HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(title)
	var subtitle := _label("DRIVE  ·  EXPLORE  ·  BUILD",15,
		Color("#e2ebe8"),HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(subtitle)
	var divider := HSeparator.new()
	divider.add_theme_constant_override("separation",17)
	column.add_child(divider)
	_add_action(column,"single_player","Single Player",true)
	_add_action(column,"multiplayer","Local Multiplayer")
	_add_action(column,"map_editor","Map Editor")
	_add_action(column,"settings","Settings")
	_add_action(column,"quit","Quit")
	var bottom_divider := HSeparator.new()
	bottom_divider.add_theme_constant_override("separation",13)
	column.add_child(bottom_divider)
	message = _label("Choose a mode to continue.",13,
		Color("#abc1c3"),HORIZONTAL_ALIGNMENT_CENTER)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 48
	column.add_child(message)

func _add_action(parent: VBoxContainer, id: String, text_value: String,
		primary: bool = false) -> void:
	var button := Button.new()
	button.name = id
	button.text = text_value
	button.custom_minimum_size = Vector2(410,56)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size",20)
	var bg := _panel_style(Color("#d4b282") if primary else Color("#203a43"),
		Color("#edc696") if primary else Color("#47616a"),11)
	var hover := bg.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#f4c995") if primary else Color("#2d525d")
	var down := hover.duplicate() as StyleBoxFlat
	down.bg_color = Color("#b99469") if primary else Color("#152e36")
	var focus := bg.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = Color("#ffffff")
	focus.set_border_width_all(2)
	for style in ["normal","hover","pressed","focus"]:
		button.add_theme_stylebox_override(style,
			bg if style=="normal" else hover if style=="hover" else
			down if style=="pressed" else focus)
	button.add_theme_color_override("font_color",
		Color("#14232b") if primary else Color("#f0f4ef"))
	button.add_theme_color_override("font_hover_color",
		Color("#14232b") if primary else Color("#ffffff"))
	button.pressed.connect(_activate.bind(id))
	parent.add_child(button)
	actions[id] = button

func _resize_card() -> void:
	if not is_instance_valid(card):
		return
	var viewport := get_viewport_rect().size
	var factor := clampf(minf((viewport.x-24.0)/CARD_SIZE.x,
		(viewport.y-24.0)/CARD_SIZE.y),0.38,1.25)
	card.scale = Vector2.ONE * factor
	card.position = (viewport-CARD_SIZE*factor)*0.5

func _refresh_buttons() -> void:
	var editor_mode := OS.has_feature("debug") or OS.has_feature("editor")
	var button: Button = actions["map_editor"]
	button.disabled = not editor_mode
	button.tooltip_text = ("Godot development builds only." if not editor_mode else
		"Edit Morrow Coast in a dedicated scene without traffic or gameplay physics.")
	if not editor_mode:
		message.text = "Map Editor is available in development builds only."

func _activate(mode: String) -> void:
	match mode:
		"settings":
			settings_adapter.settings_back_to_title = true
			settings_adapter.open_settings()
		"quit":
			get_tree().quit()
		"multiplayer":
			if Input.get_connected_joypads().is_empty():
				message.text = "Connect at least one controller to start local split-screen."
				return
			_start_game(mode)
		"map_editor":
			if not (OS.has_feature("debug") or OS.has_feature("editor")):
				message.text = "Map Editor requires a local Godot development build."
				return
			get_tree().paused = false
			var outcome := get_tree().change_scene_to_file("res://scenes/world_editor.tscn")
			if outcome != OK:
				message.text = "Could not open the standalone World Editor."
		"single_player":
			_start_game(mode)

func _start_game(mode: String) -> void:
	GameplayScript.pending_launch_mode = "" if mode=="single_player" else mode
	get_tree().paused = false
	var outcome := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if outcome != OK:
		GameplayScript.pending_launch_mode = ""
		message.text = "Could not open the gameplay scene."
