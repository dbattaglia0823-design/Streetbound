extends RefCounted
const Shapes=preload("res://scripts/dev/road_shape_geometry.gd")
var bend: SpinBox
var radius: SpinBox
var left: Button
var right: Button
var straighten: Button
var apply_radius: Button
var smaller: Button
var larger: Button
var selected_id:=""
var revision:=-1

func build(e,parent: Node) -> void:
	parent.add_child(HSeparator.new())
	var title:=Label.new();title.text="ROAD SHAPES";parent.add_child(title)
	bend=e._number(parent,"Bend m",0,2000,25);bend.step=1
	var row:=HBoxContainer.new();parent.add_child(row)
	left=e._btn("Curve left",row,func():curve(e,1))
	right=e._btn("Curve right",row,func():curve(e,-1))
	for button in [left,right]:
		button.custom_minimum_size.x=80;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.tooltip_text="Reshape the selected road between its first and last point. Bend is the sideways offset at the middle. Attached junction endpoints follow."
	straighten=e._btn("Straighten road",parent,func():curve(e,0))
	e._btn("Place circular road",parent,func():e._choose_tool("place_circle_road"))
	radius=e._number(parent,"Radius m",8,6000,30);radius.step=1
	row=HBoxContainer.new();parent.add_child(row)
	smaller=e._btn("− 5 m",row,func():resize(e,-5))
	larger=e._btn("+ 5 m",row,func():resize(e,5))
	for button in [smaller,larger]:button.custom_minimum_size.x=60;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	apply_radius=e._btn("Apply radius to circle",parent,func():resize(e))
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.add_theme_font_size_override("font_size",11)
	help.text="Select a road to curve it. Left/right follows point 1 → last. To make a roundabout, set its radius and click its center. Select a circle to resize it. All shape edits support Undo."
	parent.add_child(help)

func update(e) -> void:
	if radius==null or not e.source_ready:return
	var road: Dictionary=e.authoring.road_at_id(e.source_id) if e.source_ready else {}
	var circle:=Shapes.circle(road.get("points",[]))
	var closed: bool=not road.is_empty() and Shapes.point(road.points[0]).distance_to(Shapes.point(road.points[-1]))<2
	for button in [left,right,straighten]:button.disabled=road.is_empty() or closed
	for button in [smaller,larger,apply_radius]:button.disabled=circle.is_empty()
	if selected_id!=e.source_id or revision!=e.authoring.edit_revision:
		selected_id=e.source_id
		revision=e.authoring.edit_revision
		if not circle.is_empty():radius.value=roundf(circle.radius*100)/100

func curve(e,direction: int) -> void:
	if e._editing_locked() or not e.source_ready:return
	if e.authoring.bend_road(e.source_id,bend.value*direction):
		e.source_anchor=-1;e._refresh_authoring();e._notice("Road reshaped. Endpoints stay connected; Ctrl+Z undoes the change.")
	else:e._notice(e.authoring.last_error)

func resize(e,change: float=0) -> void:
	if e._editing_locked() or not e.source_ready:return
	var circle:=Shapes.circle(e.authoring.road_at_id(e.source_id).get("points",[]))
	if circle.is_empty():return
	var wanted: float=radius.value if change==0 else float(circle.radius)+change
	if e.authoring.resize_circle_road(e.source_id,wanted):
		radius.value=wanted;e.source_anchor=-1;e._refresh_authoring();e._notice("Circle radius updated. Connected road endpoints follow the circle.")
	else:e._notice(e.authoring.last_error)

func place(e,center: Vector2) -> void:
	var id: String=e.authoring.add_circle_road(center,radius.value,{"roadClass":e._option_value(e.road_class),
		"surface":e._option_value(e.road_surface),"width":e.road_width.value,"lanes":int(e.road_lanes.value)})
	if id.is_empty():e._notice(e.authoring.last_error);return
	e._choose_tool("move_prop");e.source_id=id;e.source_anchor=-1;e._refresh_authoring()
	e._notice("Circular road created. Drag to move; set Radius and Apply, or use −/+ 5 m to resize.")
