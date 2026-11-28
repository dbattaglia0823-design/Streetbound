extends RefCounted
## Shared racing-menu presentation; no changes to navigation or saved settings.
const INK := Color("#12161c")
const PANEL := Color("#1b2027")
const EDGE := Color("#48515c")
const TEXT := Color("#f5f6f8")
const MUTED := Color("#aab2bd")
const ACCENT := Color("#ff8b24")
const ACTIVE := Color("#a94b0b")

static func surface(fill: Color, edge: Color, radius: int = 5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

static func button(button_node: Button, selected: bool = false, font_px: int = 16, danger: bool = false) -> void:
	var normal := surface(ACTIVE if selected else Color("#252b33") if not danger else Color("#38292b"), ACCENT if selected else EDGE)
	normal.set_content_margin_all(6)
	if selected:
		normal.border_width_left = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#c75d0b") if selected else Color("#39414a")
	hover.border_color = ACCENT
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#803908") if selected else Color("#1a1f25")
	var focus := surface(Color.TRANSPARENT, ACCENT, 5)
	focus.draw_center = false
	focus.set_border_width_all(2)
	var disabled := surface(Color("#181c21"), Color("#343a42"))
	disabled.set_content_margin_all(6)
	button_node.add_theme_stylebox_override("normal",normal)
	button_node.add_theme_stylebox_override("hover",hover)
	button_node.add_theme_stylebox_override("pressed",pressed)
	button_node.add_theme_stylebox_override("focus",focus)
	button_node.add_theme_stylebox_override("disabled",disabled)
	for color_key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button_node.add_theme_color_override(color_key,TEXT)
	button_node.add_theme_color_override("font_disabled_color",Color("#8b949f"))
	button_node.add_theme_font_size_override("font_size",font_px)
	button_node.focus_mode=Control.FOCUS_ALL
	button_node.clip_text=true

static var _icons: Dictionary={}
static func _svg_icon(key: String, svg: String) -> Texture2D:
	if not _icons.has(key):
		var image := Image.new()
		if image.load_svg_from_string(svg)!=OK:return null
		_icons[key]=ImageTexture.create_from_image(image)
	return _icons[key] as Texture2D

static func toggle(node: CheckBox) -> void:
	button(node,false,15)
	var on := _svg_icon("on",'<svg xmlns="http://www.w3.org/2000/svg" width="38" height="20"><rect x="1" y="1" width="36" height="18" rx="9" fill="#e87613"/><circle cx="27" cy="10" r="7" fill="#ffffff"/></svg>')
	var off := _svg_icon("off",'<svg xmlns="http://www.w3.org/2000/svg" width="38" height="20"><rect x="1" y="1" width="36" height="18" rx="9" fill="#454d57"/><circle cx="11" cy="10" r="7" fill="#d4d8df"/></svg>')
	if on!=null and off!=null:
		node.add_theme_icon_override("checked",on)
		node.add_theme_icon_override("unchecked",off)
		node.add_theme_icon_override("checked_disabled",on)
		node.add_theme_icon_override("unchecked_disabled",off)
	node.layout_direction=Control.LAYOUT_DIRECTION_RTL

static func slider(node: HSlider) -> void:
	var track := surface(Color("#434b55"),Color.TRANSPARENT,3)
	track.content_margin_top=3
	track.content_margin_bottom=3
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color=ACCENT
	node.add_theme_stylebox_override("slider",track)
	node.add_theme_stylebox_override("grabber_area",filled)
	node.add_theme_stylebox_override("grabber_area_highlight",filled)
	var thumb := _svg_icon("thumb",'<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="7" fill="#ffffff" stroke="#ff8b24" stroke-width="2"/></svg>')
	if thumb!=null:
		node.add_theme_icon_override("grabber",thumb)
		node.add_theme_icon_override("grabber_highlight",thumb)
