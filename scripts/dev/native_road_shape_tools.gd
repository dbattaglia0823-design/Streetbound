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
var curve_fields: VBoxContainer
var circle_fields: VBoxContainer
var circle_resize_fields: VBoxContainer
var selected_id:=""
var revision:=-1

func build(e,parent: Node) -> void:
	curve_fields=VBoxContainer.new();parent.add_child(curve_fields)
	var title:=Label.new();title.text="RESHAPE ROAD";curve_fields.add_child(title)
	bend=e._number(curve_fields,"Bend m",0,2000,25);bend.step=1
	var row:=HBoxContainer.new();curve_fields.add_child(row)
	left=e._btn("Curve left",row,func():curve(e,1))
	right=e._btn("Curve right",row,func():curve(e,-1))
	for button in [left,right]:
		button.custom_minimum_size.x=80;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.tooltip_text="Reshape the selected road between its endpoints."
	straighten=e._btn("Straighten road",curve_fields,func():curve(e,0))
	circle_fields=VBoxContainer.new();parent.add_child(circle_fields)
	title=Label.new();title.text="CIRCULAR ROAD";circle_fields.add_child(title)
	radius=e._number(circle_fields,"Radius m",8,6000,30);radius.step=1
	circle_resize_fields=VBoxContainer.new();circle_fields.add_child(circle_resize_fields)
	row=HBoxContainer.new();circle_resize_fields.add_child(row)
	smaller=e._btn("− 5 m",row,func():resize(e,-5))
	larger=e._btn("+ 5 m",row,func():resize(e,5))
	for button in [smaller,larger]:button.custom_minimum_size.x=60;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	apply_radius=e._btn("Apply radius to circle",circle_resize_fields,func():resize(e))
	curve_fields.hide();circle_fields.hide()

func update(e) -> void:
	if radius==null:return
	var road: Dictionary=e.authoring.road_at_id(e.source_id) if e.source_ready else {}
	var circle:=Shapes.circle(road.get("points",[]))
	var closed: bool=not road.is_empty() and Shapes.point(road.points[0]).distance_to(Shapes.point(road.points[-1]))<2
	var editing: bool=e.tool_name in ["move_prop","anchor","select_box","inspect"]
	curve_fields.visible=editing and not road.is_empty() and not closed
	circle_fields.visible=e.tool_name=="place_circle_road" or (editing and not circle.is_empty())
	circle_resize_fields.visible=editing and not circle.is_empty()
	if not e.source_ready:return
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
