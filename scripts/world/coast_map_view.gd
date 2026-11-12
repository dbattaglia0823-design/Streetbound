extends Control
## A clipped, smoothly translated cartographic viewport with bounded detail caches.
signal view_changed
const Ink = preload("res://scripts/world/coast_map_ink.gd")
const Scale = preload("res://scripts/world/coast_map_scale.gd")
const RaceGuidance = preload("res://scripts/world/race_guidance.gd")
var model: RefCounted
var world: MorrowCoast
var ink: Node2D
var cursor: Polygon2D
var scale_bar: Node2D
var race_overlay: Node2D
var center_m := Vector2.ZERO
var pixels_per_m := 0.15
var fit_scale := 0.15
var miniature := false
var follow_car := false
var dragging := false
var player_m := Vector2.ZERO
var player_heading := 0.0

func _ready() -> void:
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_IGNORE if miniature else Control.MOUSE_FILTER_STOP
	ink=Node2D.new()
	ink.set_script(Ink)
	ink.model=model
	ink.world=world
	ink.miniature=miniature
	add_child(ink)
	race_overlay = Node2D.new()
	race_overlay.name = "RaceMapRoute"
	race_overlay.set_script(RaceGuidance)
	race_overlay.set("on_map", true)
	race_overlay.set("map_view", self)
	add_child(race_overlay)
	cursor=Polygon2D.new()
	cursor.polygon=PackedVector2Array([Vector2(0,-9),Vector2(6,6),Vector2(0,3),Vector2(-6,6)])
	cursor.color=Color("f6c36e")
	var outline := Line2D.new()
	outline.points=PackedVector2Array([Vector2(0,-10),Vector2(7,7),Vector2(0,4),Vector2(-7,7),Vector2(0,-10)])
	outline.default_color=Color("233f40")
	outline.width=2
	cursor.add_child(outline)
	add_child(cursor)
	scale_bar=Node2D.new()
	scale_bar.set_script(Scale)
	scale_bar.dimensions=custom_minimum_size
	add_child(scale_bar)
	fit_scale=minf(custom_minimum_size.x/model.extent.x,custom_minimum_size.y/model.extent.y)*.95
	if miniature:
		pixels_per_m=custom_minimum_size.x/460.0
	else:
		pixels_per_m=fit_scale
		center_m=model.extent*.5
	redraw_map()

func redraw_map() -> void:
	if ink==null: return
	ink.configure(center_m,pixels_per_m,custom_minimum_size)
	scale_bar.ppm=pixels_per_m
	scale_bar.queue_redraw()
	view_changed.emit()

func focus_on(point: Vector2, scale_value := -1.0) -> void:
	follow_car=false
	center_m=point.clamp(Vector2.ZERO,model.extent)
	if scale_value>0: pixels_per_m=clampf(scale_value,fit_scale,fit_scale*18)
	redraw_map()

func fit_region() -> void:
	follow_car=false
	center_m=model.extent*.5
	pixels_per_m=fit_scale
	redraw_map()

func zoom_at(factor: float, mouse: Vector2) -> void:
	var before := center_m+(mouse-custom_minimum_size*.5)/pixels_per_m
	pixels_per_m=clampf(pixels_per_m*factor,fit_scale,fit_scale*18)
	center_m=(before-(mouse-custom_minimum_size*.5)/pixels_per_m).clamp(Vector2.ZERO,model.extent)
	follow_car=false
	redraw_map()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom_at(1.3,event.position)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom_at(1/1.3,event.position)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			dragging=event.pressed
			if event.pressed: follow_car=false
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		center_m=(center_m-event.relative/pixels_per_m).clamp(Vector2.ZERO,model.extent)
		_update_translation()
		view_changed.emit()
		accept_event()

func _process(_dt: float) -> void:
	if miniature or follow_car: center_m=player_m
	_update_translation()
	if cursor!=null:
		cursor.position=(player_m-center_m)*pixels_per_m+custom_minimum_size*.5
		cursor.rotation=player_heading
		cursor.visible=Rect2(Vector2.ZERO,custom_minimum_size).grow(8).has_point(cursor.position)

func _update_translation() -> void:
	if ink==null: return
	ink.position=(ink.center-center_m)*pixels_per_m
	var overview := not miniature and pixels_per_m<.35
	if not overview:
		var drift: Vector2 = (center_m-ink.center)*pixels_per_m
		if absf(drift.x)>70 or absf(drift.y)>70: redraw_map()
