extends RefCounted
const Analysis=preload("res://scripts/dev/gameplay_authoring_analysis.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")
const Rules=preload("res://scripts/world/driving_contract_rules.gd")
var dialog: AcceptDialog

func _panel(e,title: String) -> VBoxContainer:
	if is_instance_valid(dialog):dialog.queue_free()
	dialog=AcceptDialog.new()
	dialog.title=title
	dialog.ok_button_text="Close"
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	e.root_ui.add_child(dialog)
	var panel:=VBoxContainer.new()
	panel.custom_minimum_size=Vector2(520,340)
	dialog.add_child(panel)
	return panel

func _label(panel: Node,value: String) -> Label:
	var label:=Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	return label

func _ready(e) -> bool:
	return e.source_ready and not e._editing_locked() and e.pending_drag.is_empty() and e.draft_points.is_empty()

func _graph(e) -> Dictionary:
	if e.traffic_preview.is_current():
		# Draft preview currently does not split individual grade pieces.
		# Never use its flattened topology to author a stacked crossing.
		for road in e.authoring.doc.roads:
			if road.has("elevation"):return {}
		return {"network":e.traffic_preview.network,"data":e.traffic_preview.data}
	if not e.map_switcher.custom and e.traffic_preview.wanted_key.is_empty():
		return {"network":e.traffic_network,"data":e.world.data}
	return {}

func open(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Gameplay authoring")
	_label(panel,"Generate directed-road time trials, link existing contract markers, audit authored gameplay and inspect estimated chunk load.")
	e._btn("Traffic / police districts",panel,func():open_controls(e,false))
	e._btn("Intersection controls",panel,func():open_controls(e,true))
	e._btn("Generate time trial",panel,func():open_race(e))
	e._btn("Contract creation wizard",panel,func():open_contract(e))
	e._btn("Gameplay coverage / performance heatmap",panel,func():open_analysis(e))
	_label(panel,"Test Drive from cursor: hover over the map and press Ctrl+F6. Use the road selection layer for elevated pavement.")
	dialog.popup_centered()

func open_race(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Generate connected time trial")
	_label(panel,"Choose start and finish coordinates in metres. Both must be within 15 m of a legal directed lane. Only single-level routes are generated.")
	var center: Vector2=e.editor_camera.global_position/20.0
	var w:=float(e.authoring.doc.world.width);var h:=float(e.authoring.doc.world.height)
	var x1: SpinBox=e._number(panel,"Start X",0,w,clampf(center.x,0,w))
	var y1: SpinBox=e._number(panel,"Start Y",0,h,clampf(center.y,0,h))
	var x2: SpinBox=e._number(panel,"Finish X",0,w,clampf(center.x+200,0,w))
	var y2: SpinBox=e._number(panel,"Finish Y",0,h,clampf(center.y,0,h))
	var level: SpinBox=e._number(panel,"Road layer",-2,2,0 if e.road_selection_layer==99 else e.road_selection_layer)
	level.step=1
	var title:=LineEdit.new();title.text="Generated time trial";title.max_length=80;panel.add_child(title)
	var status:=_label(panel,"")
	e._btn("Generate and save draft race",panel,func():
		if not _ready(e):return
		var graph:=_graph(e)
		if graph.is_empty() or graph.network==null:
			status.text="Wait for the current road preview, or bake elevated road edits before generating.";return
		var planner:=Planner.new()
		planner.setup(graph.network,graph.data)
		var route:=planner.plan(Vector2(x1.value,y1.value),Vector2(x2.value,y2.value),Vector2.ZERO,"","",int(level.value),int(level.value))
		var points:=Analysis.checkpoints(route,graph.network,int(level.value))
		if points.is_empty():
			status.text="No supported connected route. Select nearby legal lanes on the same road level.";return
		var id: String=e.authoring.save_race(points,{"name":title.text.strip_edges(),"mode":"sprint","race_kind":"time_trial","laps":1,"opponent_count":0,"formation":"single_file","checkpoint_radius":12,"start_radius":8,"objective_layer":int(level.value)})
		if id.is_empty():status.text=e.authoring.last_error;return
		dialog.hide()
		e._choose_tool("move_prop");e.source_id=id;e.source_anchor=-1;e._refresh_authoring()
		e._notice("Generated %d race objectives over %.0f m. Review and Test Drive."%[points.size(),float(route.length_m)]))
	dialog.popup_centered()

func _marker_choice(panel: Node,doc: Dictionary,kind: String,caption: String) -> OptionButton:
	_label(panel,caption)
	var choice:=OptionButton.new();panel.add_child(choice)
	choice.add_item("Select "+caption);choice.set_item_metadata(0,"")
	for marker in doc.get("markers",[]):
		if str(marker.get("type",""))!=kind:continue
		choice.add_item("%s (%s)"%[str(marker.get("name",marker.id)),str(marker.id)])
		choice.set_item_metadata(choice.item_count-1,str(marker.id))
	return choice

func _id(choice: OptionButton) -> String:
	return str(choice.get_item_metadata(choice.selected)) if choice.selected>=0 else ""

func open_contract(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Contract creation wizard")
	_label(panel,"Place contact, drop-off and optional robbery-target markers at businesses or destinations first. This wizard links those markers into an existing contact.")
	var contact:=_marker_choice(panel,e.authoring.doc,"contract_contact","Contact")
	var destination:=_marker_choice(panel,e.authoring.doc,"contract_dropoff","Destination")
	var target:=_marker_choice(panel,e.authoring.doc,"robbery_target","Robbery target (optional)")
	var kind:=OptionButton.new();kind.add_item("Courier");kind.add_item("Robbery");panel.add_child(kind)
	var title:=LineEdit.new();title.text="New driving contract";title.max_length=80;panel.add_child(title)
	var status:=_label(panel,"")
	e._btn("Create contract",panel,func():
		if not _ready(e):return
		var marker: Dictionary=e.authoring.marker_at_id(_id(contact))
		if marker.is_empty() or _id(destination).is_empty():
			status.text="Select a contact and destination.";return
		var properties: Dictionary=marker.get("properties",{}).duplicate(true)
		var offers: Array=properties.get("offers",[])
		if offers.size()>=Rules.MAX_OFFERS:status.text="Contact is full.";return
		var used: Dictionary={}
		for offer in offers:used[str(offer.id)]=true
		var number:=1
		while used.has("job_%d"%number):number+=1
		var job_kind: String="robbery" if kind.selected==1 else "courier"
		var job:=Rules.configured_reward(job_kind,{})
		job.merge({"id":"job_%d"%number,"title":title.text.strip_edges(),"kind":job_kind,"difficulty":"rookie","destination_marker_id":_id(destination),"repeatable":true},true)
		if job_kind=="robbery":job["robbery_marker_id"]=_id(target)
		var markers: Dictionary={}
		for item in e.authoring.doc.markers:markers[str(item.id)]=item
		if not Rules.valid_offer(job,marker,markers):
			status.text="Invalid title or marker links. Check target type and minimum/maximum trip distances.";return
		offers.append(job);properties["offers"]=offers
		if not e.authoring.update_marker(str(marker.id),{"properties":properties}):
			status.text=e.authoring.last_error;return
		dialog.hide()
		e._choose_tool("move_prop");e.source_id=str(marker.id);e.source_anchor=-1;e._refresh_authoring()
		e._notice("Contract created. Open the contact editor to customize rewards and requirements."))
	dialog.popup_centered()

func open_analysis(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Gameplay coverage and estimated chunk load")
	var graph:=_graph(e)
	var junctions: Array=graph.get("data",{}).get("junctions",[])
	var size: float=maxf(400.0,float(e.world.data.get("chunk_size",400)))
	var audit:=Analysis.analyze(e.authoring.doc,size,800.0,junctions)
	_label(panel,"Authored-source estimate · %.0f m cells · coverage within 800 m of cell centre (straight-line). Not a measured CPU/GPU profile."%size)
	if graph.is_empty():_label(panel,"Road graph is not current; intersection costs omitted.")
	var cells: Dictionary=audit.cells
	if cells.is_empty():
		_label(panel,"No authored roads or scenery.");dialog.popup_centered();return
	var width:=maxi(1,ceili(float(audit.bounds.x)/size))
	var height:=maxi(1,ceili(float(audit.bounds.y)/size))
	var image:=Image.create(width,height,false,Image.FORMAT_RGBA8)
	image.fill(Color("#19222d"))
	var peak:=1.0
	for row in cells.values():peak=maxf(peak,float(row.score))
	for key in cells:
		if key.x<0 or key.y<0 or key.x>=width or key.y>=height:continue
		var row: Dictionary=cells[key]
		var heat:=clampf(float(row.score)/peak,0,1)
		image.set_pixel(key.x,key.y,Color("#244d81").lerp(Color("#ff5e39"),heat))
	var map:=TextureRect.new()
	map.texture=ImageTexture.create_from_image(image);map.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	map.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;map.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map.custom_minimum_size=Vector2(480,180);panel.add_child(map)
	var list:=ItemList.new();list.custom_minimum_size=Vector2(480,220);panel.add_child(list)
	var keys:=cells.keys()
	keys.sort_custom(func(a,b):return float(cells[a].score)>float(cells[b].score))
	for key in keys:
		var row: Dictionary=cells[key]
		var missing:=(", ".join(row.missing)) if not row.missing.is_empty() else "none"
		list.add_item("Cell %s | %.0f load | %d props | missing: %s"%[str(key),float(row.score),int(row.props),missing])
		list.set_item_metadata(list.item_count-1,key)
	list.item_activated.connect(func(index: int):
		var key: Vector2i=list.get_item_metadata(index)
		dialog.hide()
		e.editor_camera.global_position=(Vector2(key)*size+Vector2.ONE*size*.5).clamp(Vector2.ZERO,audit.bounds)*20.0
		e._update_view(true))
	_label(panel,"Double-click a row to inspect that area in the editor. Empty space is excluded; blue is low estimated cost and orange is high.")
	dialog.popup_centered()

func _control_field(panel: Node,caption: String,value: float,lo: float,hi: float) -> SpinBox:
	var row:=HBoxContainer.new()
	panel.add_child(row)
	_label(row,caption)
	var spin:=SpinBox.new()
	spin.min_value=lo;spin.max_value=hi;spin.step=1;spin.value=value
	row.add_child(spin)
	return spin

func _control_choice(panel: Node,caption: String,options: Array) -> OptionButton:
	var row:=HBoxContainer.new()
	panel.add_child(row)
	_label(row,caption)
	var choice:=OptionButton.new()
	for option in options:choice.add_item(str(option))
	row.add_child(choice)
	return choice

func open_controls(e,junction: bool) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Intersection controls" if junction else "Traffic and police districts")
	if not e.map_switcher.custom:
		_label(panel,"These controls are available on custom maps.");dialog.popup_centered();return
	var category: String="junctionControls" if junction else "gameplayZones"
	var records: Array=e.authoring.doc.get(category,[]).duplicate(true)
	var list:=ItemList.new();list.custom_minimum_size=Vector2(460,100);panel.add_child(list)
	for z in records:list.add_item("%s @ %d, %d"%[str(z.get("name",z.get("control",""))),int(z.x),int(z.y)])
	var bounds: Dictionary=e.authoring.doc.world
	var center: Vector2=e.editor_camera.global_position/20.0
	var x:=_control_field(panel,"X (m)",center.x,0,float(bounds.width))
	var y:=_control_field(panel,"Y (m)",center.y,0,float(bounds.height))
	var name_field:=LineEdit.new()
	var fields: Dictionary={}
	var choices: OptionButton
	var turns: Array[CheckBox]=[]
	if junction:
		_label(panel,"Use the centre of a real intersection; matched during bake within 8 m on the selected level.")
		fields["layer"]=_control_field(panel,"Road level",0,-2,2)
		choices=_control_choice(panel,"Control",["stop","yield","signal","uncontrolled"])
		var row:=HBoxContainer.new();panel.add_child(row)
		for turn in ["left","straight","right"]:
			var check:=CheckBox.new();check.text=turn;check.button_pressed=true;row.add_child(check);turns.append(check)
	else:
		name_field.text="New district";panel.add_child(name_field)
		fields["w"]=_control_field(panel,"Width (m)",400,1,float(bounds.width))
		fields["h"]=_control_field(panel,"Height (m)",400,1,float(bounds.height))
		fields["density"]=_control_field(panel,"Traffic density (%)",100,0,200)
		fields["speed"]=_control_field(panel,"Speed cap (km/h, 0 default)",0,0,160)
		fields["patrol"]=_control_field(panel,"Patrol interval (0 off)",7,0,30)
		fields["response"]=_control_field(panel,"Police response capacity (%)",100,50,150)
		choices=_control_choice(panel,"Vehicles",["all","passenger","commercial"])
	var status:=_label(panel,"Later overlapping districts take precedence. Remove a selected row to replace it.")
	e._btn("Add control",panel,func():
		var z: Dictionary={"x":x.value,"y":y.value}
		for key in fields:z[key]=fields[key].value
		if junction:
			z["control"]=choices.get_item_text(choices.selected)
			z["turns"]=[]
			for check in turns:
				if check.button_pressed:z.turns.append(check.text)
		else:
			z["name"]=name_field.text;z["models"]=choices.get_item_text(choices.selected)
		var next:=records.duplicate(true);next.append(z)
		if e.authoring.set_gameplay_controls(category,next):e._update_view(true);open_controls(e,junction)
		else:status.text="Invalid control or district outside map bounds.")
	e._btn("Remove selected",panel,func():
		var selected:=list.get_selected_items()
		if selected.is_empty():return
		var next:=records.duplicate(true);next.remove_at(selected[0])
		if e.authoring.set_gameplay_controls(category,next):e._update_view(true);open_controls(e,junction))
	dialog.popup_centered()
