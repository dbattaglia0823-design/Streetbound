extends CanvasLayer
## Neighborhood navigator plus a zoomable field atlas sharing cached geometry.
const Model = preload("res://scripts/world/coast_map_model.gd")
const MapView = preload("res://scripts/world/coast_map_view.gd")
var world: Node2D
var vehicle: VehicleController2D
var driving_hud: CanvasLayer
var model: RefCounted
var mini: PanelContainer
var full: PanelContainer
var mini_view: Control
var full_view: Control
var mini_cursor: Polygon2D
var full_cursor: Polygon2D
var district_label: Label
var road_label: Label
var scale_label: Label
var atlas_scale_label: Label
var refresh := 0.0
var large := false

func panel(at: Vector2, dimensions: Vector2) -> PanelContainer:
	var node := PanelContainer.new()
	node.position=at
	node.custom_minimum_size=dimensions
	var style := StyleBoxFlat.new()
	style.bg_color=Color("16302f")
	style.border_color=Color("526c61")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left=16
	style.content_margin_right=16
	style.content_margin_top=12
	style.content_margin_bottom=12
	node.add_theme_stylebox_override("panel",style)
	add_child(node)
	return node

func text(parent: Node, value: String, size := 14, color := Color("e6e6cb")) -> Label:
	var label := Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func button(parent: Node, title: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text=title
	node.add_theme_font_size_override("font_size",14)
	node.custom_minimum_size.y=32
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func map_view(parent: Node, dimensions: Vector2, miniature: bool) -> Control:
	var node := Control.new()
	node.set_script(MapView)
	node.model=model
	node.miniature=miniature
	node.custom_minimum_size=dimensions
	node.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	parent.add_child(node)
	return node

func _ready() -> void:
	layer=2
	model=Model.new(world.data)
	mini=panel(Vector2(1100,24),Vector2(316,340))
	var column := VBoxContainer.new()
	mini.add_child(column)
	district_label=text(column,"MORROW COAST",16)
	mini_view=map_view(column,Vector2(284,244),true)
	mini_cursor=mini_view.cursor
	road_label=text(column,"Laurel Motor House access",13)
	road_label.custom_minimum_size.x=284
	road_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	scale_label=text(column,"N ↑    LOCAL STREETS    ·    TAB ATLAS",11,Color("b8c9ad"))
	full=panel(Vector2(52,30),Vector2(1336,840))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	full.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var heading := text(header,"MORROW COAST / FIELD ATLAS",25)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(header,"−",func():full_view.zoom_at(1/1.3,full_view.custom_minimum_size*.5))
	button(header,"+",func():full_view.zoom_at(1.3,full_view.custom_minimum_size*.5))
	button(header,"Fit region",func():full_view.fit_region())
	button(header,"Find car",func():
		full_view.focus_on(vehicle.position/20,full_view.fit_scale*5)
		full_view.follow_car=true)
	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation",14)
	body.add_child(contents)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x=236
	contents.add_child(sidebar)
	text(sidebar,"DESTINATIONS",15,Color("c9d7b4"))
	text(sidebar,"Select a place to inspect its roads.",12)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(236,494)
	sidebar.add_child(scroll)
	var destinations := VBoxContainer.new()
	for poi in world.data.pois:
		var code: String = model.poi_type(poi)
		var tag: String = {"garage":"G","workshop":"W","fuel":"F","race":"R","dealer":"D","marina":"M","view":"V"}.get(code,"•")
		var entry := button(destinations,"[%s] %s"%[tag,poi.name],func():full_view.focus_on(model.v(poi.position),full_view.fit_scale*5))
		entry.custom_minimum_size=Vector2(216,31)
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT
		entry.add_theme_font_size_override("font_size",12)
		entry.tooltip_text=poi.category
	scroll.add_child(destinations)
	text(sidebar,"ROAD KEY",14,Color("c9d7b4"))
	text(sidebar,"Gold  Parkway / main travel\nIvory  Streets & scenic routes\nRust  Motorsport circuit\nTan  Gravel backroads",12)
	text(sidebar,"G garage   W workshop   F fuel\nR racing   D dealer   M marina\nV viewpoint / landmark",11,Color("bfccb6"))
	var right := VBoxContainer.new()
	contents.add_child(right)
	full_view=map_view(right,Vector2(1040,704),false)
	full_cursor=full_view.cursor
	atlas_scale_label=text(right,"N ↑  NORTH UP  /  Wheel to zoom · Drag to pan",12)
	full_view.view_changed.connect(_update_scale)
	text(body,"TAB close   ·   Wheel zooms toward the pointer   ·   Drag to explore   ·   Find car restores tracking",12,Color("c5d0ba"))
	full.visible=false
	_update_scale()

func _update_scale() -> void:
	if atlas_scale_label==null or full_view==null: return
	atlas_scale_label.text="NORTH UP    ·    %.1f× detail    ·    Scroll to zoom / drag to pan"%[full_view.pixels_per_m/full_view.fit_scale]

func _input(event: InputEvent) -> void:
	if not driving_hud.waiting_action.is_empty(): return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_TAB:
		large=not large
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	mini.visible=not driving_hud.tuning.visible and not large
	full.visible=large and not driving_hud.tuning.visible
	for view in [mini_view,full_view]:
		view.player_m=vehicle.global_position/20
		view.player_heading=vehicle.rotation
	refresh-=dt
	if refresh<=0:
		refresh=.25
		var district: Dictionary = world.location_at(vehicle.global_position)
		district_label.text=district.name
		road_label.text=model.nearest_road(vehicle.global_position/20)
		scale_label.text="N ↑    LOCAL VIEW ~1,500 ft    ·    TAB ATLAS"
