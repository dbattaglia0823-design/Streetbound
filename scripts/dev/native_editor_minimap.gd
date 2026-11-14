extends Control
## Native equivalent of the browser builder's click-to-navigate minimap.
var editor

func _ready() -> void:
	name="BuilderMiniMap";mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	tooltip_text="Click or drag to navigate the map"
	set_process(true)

func _process(_dt: float) -> void:
	if editor.active:queue_redraw()

func map_rect() -> Rect2:
	if not is_instance_valid(editor.overview_renderer):return Rect2()
	var extent: Vector2=editor.overview_renderer.extent_m
	var area:=size-Vector2(12,24)
	var fitted:=extent*minf(area.x/extent.x,area.y/extent.y)
	return Rect2(Vector2(6,18)+(area-fitted)*.5,fitted)

func _draw() -> void:
	draw_style_box(_skin(),Rect2(Vector2.ZERO,size))
	if not is_instance_valid(editor.overview_renderer):return
	var rect:=map_rect()
	draw_texture_rect(editor.overview_renderer.viewport.get_texture(),rect,false)
	var world_px: Vector2=editor.overview_renderer.extent_m*20.0
	var a: Vector2=editor._event_world_position(editor.canvas_rect.position)/world_px
	var b: Vector2=editor._event_world_position(editor.canvas_rect.end)/world_px
	var camera_rect:=Rect2(rect.position+a*rect.size,(b-a)*rect.size).intersection(rect)
	draw_rect(camera_rect,Color("#f4a667"),false,1.5)
	draw_string(ThemeDB.fallback_font,Vector2(7,12),"MORROW COAST",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("#eaf0f7"))

func _skin() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color("#0b111a")
	style.border_color=Color("#41536a");style.set_border_width_all(1);style.set_corner_radius_all(6)
	return style

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		navigate(event.position);accept_event()
	elif event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		navigate(event.position);accept_event()

func navigate(at: Vector2) -> void:
	var rect:=map_rect()
	if not rect.has_area():return
	var uv:=((at-rect.position)/rect.size).clamp(Vector2.ZERO,Vector2.ONE)
	editor.editor_camera.global_position=uv*editor.overview_renderer.extent_m*20.0
	editor._update_view(true)
