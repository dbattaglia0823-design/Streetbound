extends RefCounted
const Validation=preload("res://scripts/dev/world_validation.gd")
const Analysis=preload("res://scripts/dev/gameplay_authoring_analysis.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")
const Rules=preload("res://scripts/world/driving_contract_rules.gd")
const Network=preload("res://scripts/world/traffic_network.gd")
var compiled_key: String=""
var compiled_graph: Dictionary={}
var dialog: AcceptDialog

func _panel(e,title: String) -> VBoxContainer:
	if is_instance_valid(dialog):dialog.queue_free()
	dialog=AcceptDialog.new()
	dialog.title=title
	dialog.ok_button_text="Close"
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	e.root_ui.add_child(dialog)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(560,clampf(e.get_viewport().get_visible_rect().size.y-160.0,260.0,540.0))
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var panel:=VBoxContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
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
	if e.authoring.doc.get("junctionControls",[])!=e.authoring.initial.get("junctionControls",[]):return {}
	if not e.map_switcher.custom and e.traffic_preview.wanted_key.is_empty():
		return {"network":e.traffic_network,"data":e.world.data}
	if e.traffic_preview.is_current():
		# Draft preview currently does not split individual grade pieces.
		# Never use its flattened topology to author a stacked crossing.
		for road in e.authoring.doc.roads:
			if road.has("elevation"):return {}
		return {"network":e.traffic_preview.network,"data":e.traffic_preview.data}
	if not e.map_switcher.custom and e.traffic_preview.wanted_key.is_empty():
		return {"network":e.traffic_network,"data":e.world.data}
	return {}

## Build a private scratch archive using the production compiler. Never publish
## or overwrite the current source. Reuse the compiler's validated cache.
func _race_graph(e) -> Dictionary:
	if not e.map_switcher.custom:return _graph(e)
	var doc: Dictionary=e.authoring.doc
	var key:=JSON.stringify([doc.get("world",{}),doc.get("roads",[]),doc.get("regions",[]),doc.get("terrainHeight",{}),doc.get("junctionControls",[]),doc.get("gameplayZones",[])]).sha256_text()
	if key==compiled_key and not compiled_graph.is_empty():return compiled_graph
	var root:=ProjectSettings.globalize_path("user://gameplay-authoring-%d"%OS.get_process_id())
	var source:=root+".world.json"
	var output:=root+".stream.json"
	var stream:=FileAccess.open(source,FileAccess.WRITE)
	if stream==null:return {}
	stream.store_string(JSON.stringify(doc));stream.close()
	if FileAccess.file_exists(output):DirAccess.remove_absolute(output)
	var python: String="py" if OS.get_name()=="Windows" else "python3"
	var args:=PackedStringArray([ProjectSettings.globalize_path("res://tools/build_custom_test_world.py"),"--source",source,"--output",output,"--cache",root+".cache.json"])
	if OS.get_name()=="Windows":args.insert(0,"-3")
	var logs: Array=[]
	var code:=OS.execute(python,args,logs,true)
	DirAccess.remove_absolute(source)
	if code!=0 or not FileAccess.file_exists(output):
		e._notice("Route compile failed: "+str(logs).left(240));return {}
	var archive: Variant=JSON.parse_string(FileAccess.get_file_as_string(output))
	DirAccess.remove_absolute(output)
	if not archive is Dictionary:return {}
	var graph:=Network.new()
	graph.build(archive)
	compiled_key=key
	compiled_graph={"network":graph,"data":archive}
	return compiled_graph

func open(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Gameplay authoring")
	_label(panel,"Generate directed-road time trials, link existing contract markers, audit authored gameplay and inspect estimated chunk load.")
	e._btn("Traffic / police districts",panel,func():open_controls(e,false))
	e._btn("Intersection controls",panel,func():open_controls(e,true))
	e._btn("Generate time trial",panel,func():open_race(e))
	e._btn("Contract creation wizard",panel,func():open_contract(e))
	e._btn("Gameplay coverage / performance heatmap",panel,func():open_analysis(e))
	e._btn("Measured Test Drive performance",panel,func():open_measured(e))
	_label(panel,"Test Drive from cursor: hover over the map and press Ctrl+F6. Use the road selection layer for elevated pavement.")
	dialog.popup_centered()

func open_race(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Generate connected time trial")
	_label(panel,"Choose start and finish coordinates and levels. Both must be within 15 m of a legal directed lane on supported pavement. Custom routes compile the exact current draft.")
	var center: Vector2=e.editor_camera.global_position/20.0
	var w:=float(e.authoring.doc.world.width);var h:=float(e.authoring.doc.world.height)
	var x1: SpinBox=e._number(panel,"Start X",0,w,clampf(center.x,0,w))
	var y1: SpinBox=e._number(panel,"Start Y",0,h,clampf(center.y,0,h))
	var x2: SpinBox=e._number(panel,"Finish X",0,w,clampf(center.x+200,0,w))
	var y2: SpinBox=e._number(panel,"Finish Y",0,h,clampf(center.y,0,h))
	var level: SpinBox=e._number(panel,"Road layer",-2,2,0 if e.road_selection_layer==99 else e.road_selection_layer)
	level.step=1
	var finish_level: SpinBox=e._number(panel,"Finish road layer",-2,2,level.value)
	finish_level.step=1
	var title:=LineEdit.new();title.text="Generated time trial";title.max_length=80;panel.add_child(title)
	var status:=_label(panel,"")
	e._btn("Generate and save draft race",panel,func():
		if not _ready(e):return
		var graph:=_race_graph(e)
		if graph.is_empty() or graph.network==null:
			status.text="Wait for the current road preview, or bake elevated road edits before generating.";return
		var planner:=Planner.new()
		planner.setup(graph.network,graph.data)
		var route:=planner.plan(Vector2(x1.value,y1.value),Vector2(x2.value,y2.value),Vector2.ZERO,"","",int(level.value),int(finish_level.value))
		var gates:=Analysis.graded_checkpoints(route,graph.network,int(level.value),int(finish_level.value))
		if gates.is_empty():
			status.text="No supported connected route. Select nearby legal lanes and valid level endpoints.";return
		var points: Array[Vector2]=[]
		var layers: Array=[]
		for gate in gates:
			points.append(gate.position);layers.append(gate.layer)
		var id: String=e.authoring.save_race(points,{"name":title.text.strip_edges(),"mode":"sprint","race_kind":"time_trial","laps":1,"opponent_count":0,"formation":"single_file","checkpoint_radius":12,"start_radius":8,"objective_layers":layers})
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

## An existing marker or an explicitly placed new location. The editor
## transaction commits all new markers and the offer together.
func _location_fields(e,panel: Node,kind: String,caption: String,at: Vector2) -> Dictionary:
	var section:=VBoxContainer.new();panel.add_child(section)
	var choice:=_marker_choice(section,e.authoring.doc,kind,caption)
	choice.set_item_text(0,"Create new "+caption.to_lower())
	var placement:=VBoxContainer.new();section.add_child(placement)
	var bounds: Dictionary=e.authoring.doc.world
	var name_field:=LineEdit.new();name_field.text=caption;name_field.max_length=120;placement.add_child(name_field)
	var x:=_control_field(placement,"X (m)",clampf(at.x,0,float(bounds.width)),0,float(bounds.width))
	var y:=_control_field(placement,"Y (m)",clampf(at.y,0,float(bounds.height)),0,float(bounds.height))
	var level:=_control_field(placement,"Road level",0 if e.road_selection_layer==99 else e.road_selection_layer,-2,2)
	e._btn("Use selected scenery location",placement,func():
		var prop: Dictionary=e.authoring.prop_at_id(e.source_id)
		if prop.is_empty():return
		var point:=Vector2(float(prop.x),float(prop.y))
		var road: Vector2=e._road_draw_point(point,true,true)
		if road.is_finite():point=road
		x.value=point.x;y.value=point.y;name_field.text=str(prop.get("name",caption)).left(120))
	choice.item_selected.connect(func(index: int):placement.visible=index==0)
	return {"choice":choice,"name":name_field,"x":x,"y":y,"layer":level,"kind":kind}

func _resolve_location(fields: Dictionary,draft: Dictionary) -> Dictionary:
	var chosen:=_id(fields.choice)
	if not chosen.is_empty():
		for marker in draft.markers:
			if str(marker.id)==chosen:return marker
		return {}
	var number:=0
	var used: Dictionary={}
	for marker in draft.markers:
		used[str(marker.id)]=true
		var raw:=str(marker.id).trim_prefix("marker-")
		if raw.is_valid_int():number=maxi(number,int(raw)+1)
	while used.has("marker-%d"%number):number+=1
	var properties: Dictionary={}
	var layer:=int(fields.layer.value)
	if layer!=0:properties["road_layer"]=layer
	var marker: Dictionary={"id":"marker-%d"%number,"name":str(fields.name.text).strip_edges(),"type":fields.kind,
		"x":fields.x.value,"y":fields.y.value,"rotation":0.0,"properties":properties}
	if str(marker.name).is_empty():return {}
	draft.markers.append(marker)
	return marker

func open_contract(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Contract creation wizard")
	_label(panel,"Choose existing markers or create locations directly. Select scenery before opening this wizard to copy its position. Confirm legal pavement access in Test Drive.")
	var center: Vector2=e.editor_camera.global_position/20.0
	var contact:=_location_fields(e,panel,"contract_contact","Contact",center)
	var destination:=_location_fields(e,panel,"contract_dropoff","Destination",center+Vector2(200,0))
	var kind:=OptionButton.new();kind.add_item("Courier");kind.add_item("Robbery");panel.add_child(kind)
	var target_container:=VBoxContainer.new();panel.add_child(target_container)
	var target:=_location_fields(e,target_container,"robbery_target","Robbery target",center+Vector2(100,100))
	target_container.visible=false
	kind.item_selected.connect(func(index: int):target_container.visible=index==1)
	var title:=LineEdit.new();title.text="New driving contract";title.max_length=80;panel.add_child(title)
	var status:=_label(panel,"")
	e._btn("Create contract and locations",panel,func():
		if not _ready(e):return
		var draft: Dictionary=e.authoring.doc.duplicate(true)
		var marker:=_resolve_location(contact,draft)
		var dropoff:=_resolve_location(destination,draft)
		var robbery:=kind.selected==1
		var robbery_target:=_resolve_location(target,draft) if robbery else {}
		if marker.is_empty() or dropoff.is_empty() or (robbery and robbery_target.is_empty()):
			status.text="Select or name each required location.";return
		var properties: Dictionary=marker.get("properties",{}).duplicate(true)
		var offers: Array=properties.get("offers",[])
		if offers.size()>=Rules.MAX_OFFERS:status.text="Contact is full.";return
		var used: Dictionary={}
		for offer in offers:used[str(offer.id)]=true
		var number:=1
		while used.has("job_%d"%number):number+=1
		var job_kind: String="robbery" if robbery else "courier"
		var job:=Rules.configured_reward(job_kind,{})
		job.merge({"id":"job_%d"%number,"title":title.text.strip_edges(),"kind":job_kind,"difficulty":"rookie","destination_marker_id":str(dropoff.id),"repeatable":true},true)
		if robbery:job["robbery_marker_id"]=str(robbery_target.id)
		var markers: Dictionary={}
		for item in draft.markers:markers[str(item.id)]=item
		if not Rules.valid_offer(job,marker,markers):
			status.text="Invalid title or marker links. Check target type and trip distances.";return
		offers.append(job);properties["offers"]=offers;marker["properties"]=properties
		if not e.authoring._commit(draft):
			status.text=e.authoring.last_error;return
		dialog.hide()
		e._choose_tool("move_prop");e.source_id=str(marker.id);e.source_anchor=-1;e._refresh_authoring()
		e._notice("Contract and locations created as one undoable edit."))
	dialog.popup_centered()

func open_measured(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Measured Test Drive performance")
	var report: Dictionary=e.get_tree().get_meta("streetbound_editor_performance_report",{})
	var hash: String=e.authoring._fingerprint(e.authoring.doc)
	if report.is_empty() or str(report.get("source_hash",""))!=hash:
		_label(panel,"No matching Test Drive profile. Drive through the current revision and return with F6.");dialog.popup_centered();return
	var cells: Dictionary=report.get("cells",{})
	if cells.is_empty():
		_label(panel,"No samples collected.");dialog.popup_centered();return
	var size:=float(report.get("chunk_m",192))
	_label(panel,"Measured chunk CPU build time and sampled frame/CPU process time. Draw calls are rendering workload, not GPU execution time. Unvisited cells remain blank.")
	var width:=maxi(1,ceili(float(e.authoring.doc.world.width)/size))
	var height:=maxi(1,ceili(float(e.authoring.doc.world.height)/size))
	var image:=Image.create(width,height,false,Image.FORMAT_RGBA8)
	image.fill(Color("#19222d"))
	var peak:=1.0
	for row in cells.values():peak=maxf(peak,maxf(float(row.get("build_usec",0))/1000.0,float(row.get("frame_peak_ms",0))))
	for key in cells:
		if key.x<0 or key.y<0 or key.x>=width or key.y>=height:continue
		var row: Dictionary=cells[key]
		var cost:=maxf(float(row.get("build_usec",0))/1000.0,float(row.get("frame_peak_ms",0)))
		image.set_pixel(key.x,key.y,Color("#244d81").lerp(Color("#ff5e39"),clampf(cost/peak,0,1)))
	var map:=TextureRect.new();map.texture=ImageTexture.create_from_image(image)
	map.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;map.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;map.custom_minimum_size=Vector2(480,180);panel.add_child(map)
	var list:=ItemList.new();list.custom_minimum_size=Vector2(480,220);panel.add_child(list)
	var keys:=cells.keys()
	keys.sort_custom(func(a,b):return maxf(float(cells[a].get("build_usec",0))/1000.0,float(cells[a].get("frame_peak_ms",0)))>maxf(float(cells[b].get("build_usec",0))/1000.0,float(cells[b].get("frame_peak_ms",0))))
	for key in keys:
		var row: Dictionary=cells[key]
		var count:=int(row.get("frames",0))
		list.add_item("%s | build %.2f ms | frame %.2f ms avg | CPU %.2f ms avg | draws %d | n=%d"%[str(key),float(row.get("build_usec",0))/1000.0,float(row.get("frame_sum_ms",0))/maxi(1,count),float(row.get("cpu_sum_ms",0))/maxi(1,count),int(row.get("draw_peak",0)),count])
		list.set_item_metadata(list.item_count-1,key)
	list.item_activated.connect(func(index: int):
		var key: Vector2i=list.get_item_metadata(index)
		dialog.hide();e.editor_camera.global_position=(Vector2(key)+Vector2.ONE*.5)*size*20.0;e._update_view(true))
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
	var category: String="junctionControls" if junction else "gameplayZones"
	var records: Array=e.authoring.doc.get(category,[]).duplicate(true)
	var list:=ItemList.new();list.custom_minimum_size=Vector2(460,100);panel.add_child(list)
	for z in records:list.add_item("%s @ %d, %d%s"%[str(z.get("name",z.get("control",""))),int(z.x),int(z.y)," / arm %d lane %d"%[int(z.get("approach",-1)),int(z.get("lane",-1))] if junction else ""])
	var bounds: Dictionary=e.authoring.doc.world
	var center: Vector2=e.editor_camera.global_position/20.0
	var x:=_control_field(panel,"X (m)",center.x,0,float(bounds.width))
	var y:=_control_field(panel,"Y (m)",center.y,0,float(bounds.height))
	var name_field: LineEdit
	var fields: Dictionary={}
	var choices: OptionButton
	var turns: Array[CheckBox]=[]
	if junction:
		_label(panel,"Use the centre of a real intersection; matched during bake within 8 m on the selected level.")
		fields["layer"]=_control_field(panel,"Road level",0 if e.road_selection_layer==99 else e.road_selection_layer,-2,2)
		fields["approach"]=_control_field(panel,"Approach index (-1 all)",-1,-1,31)
		fields["lane"]=_control_field(panel,"Lane index (-1 all; turns only)",-1,-1,5)
		choices=_control_choice(panel,"Control",["stop","yield","signal","uncontrolled"])
		var row:=HBoxContainer.new();panel.add_child(row)
		for turn in ["left","straight","right"]:
			var check:=CheckBox.new();check.text=turn;check.button_pressed=true;row.add_child(check);turns.append(check)
	else:
		name_field=LineEdit.new();name_field.text="New district";panel.add_child(name_field)
		fields["w"]=_control_field(panel,"Width (m)",400,1,float(bounds.width))
		fields["h"]=_control_field(panel,"Height (m)",400,1,float(bounds.height))
		fields["density"]=_control_field(panel,"Traffic density (%)",100,0,200)
		fields["speed"]=_control_field(panel,"Speed cap (km/h, 0 default)",0,0,160)
		fields["patrol"]=_control_field(panel,"Patrol interval (0 off)",7,0,30)
		fields["response"]=_control_field(panel,"Police response capacity (%)",100,50,150)
		choices=_control_choice(panel,"Vehicles",["all","passenger","commercial"])
	var status:=_label(panel,"Later overlapping districts take precedence. Select a row to edit or use Add control.")
	list.item_selected.connect(func(index: int):
		var item: Dictionary=records[index]
		x.value=float(item.x);y.value=float(item.y)
		for key in fields:fields[key].value=float(item.get(key,-1))
		if junction:
			choices.select(["stop","yield","signal","uncontrolled"].find(str(item.control)))
			for check in turns:check.button_pressed=check.text in item.turns
		else:
			name_field.text=str(item.name);choices.select(["all","passenger","commercial"].find(str(item.models))))
	var save_control:=func(replace: bool):
		if not _ready(e):return
		var z: Dictionary={"x":x.value,"y":y.value}
		for key in fields:z[key]=fields[key].value
		if junction:
			z["control"]=choices.get_item_text(choices.selected)
			z["turns"]=[]
			for check in turns:
				if check.button_pressed:z.turns.append(check.text)
		else:
			z["name"]=name_field.text;z["models"]=choices.get_item_text(choices.selected)
		var next:=records.duplicate(true)
		if replace:
			if list.get_selected_items().is_empty():status.text="Select an existing rule.";return
			next[list.get_selected_items()[0]]=z
		else:next.append(z)
		if e.authoring.set_gameplay_controls(category,next):e._refresh_authoring();open_controls(e,junction)
		else:status.text="Invalid control or district outside map bounds."
	e._btn("Add control",panel,func():save_control.call(false))
	e._btn("Update selected",panel,func():save_control.call(true))
	e._btn("Remove selected",panel,func():
		var selected:=list.get_selected_items()
		if selected.is_empty():return
		var next:=records.duplicate(true);next.remove_at(selected[0])
		if e.authoring.set_gameplay_controls(category,next):e._refresh_authoring();open_controls(e,junction))
	dialog.popup_centered()

func open_validation(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"World Validation Center — Phase 6")
	_label(panel,"Checks the current source, directed lane topology, authored gameplay links and matching Test Drive samples. Static checks do not replace physical driving.")
	var summary:=_label(panel,"Preparing audit…")
	var list:=ItemList.new()
	list.custom_minimum_size=Vector2(500,220);panel.add_child(list)
	var state: Dictionary={"report":{},"hash":""}
	var run:=func():
		if not _ready(e):return
		var hash: String=e.authoring._fingerprint(e.authoring.doc)
		var compiled: Dictionary={}
		# Morrow uses only the exact baked graph, never a flattened draft.
		if e.map_switcher.custom:
			compiled=_race_graph(e)
		elif e.authoring.doc.get("roads",[])==e.authoring.initial.get("roads",[]) and e.authoring.doc.get("junctionControls",[])==e.authoring.initial.get("junctionControls",[]):
			compiled=_graph(e)
		var profile: Dictionary=e.get_tree().get_meta("streetbound_editor_performance_report",{})
		var report:=Validation.audit(e.authoring.doc,compiled,profile,hash)
		var drive: Dictionary=e.get_tree().get_meta("streetbound_validation_drive_report",{})
		if str(drive.get("source_hash",""))==hash:report["physical_drive"]=drive
		state.report=report;state.hash=hash
		summary.text="%s | %d errors, %d warnings | %d/%d route legs | %d road components\nPerformance: %s (physical simulation not run)"%[report.status,report.counts.error,report.counts.warning,report.route_passes,report.route_checks,int(report.get("components",0)),str(report.performance)]
		if report.has("physical_drive"):
			summary.text+="\nPhysical drive: "+str(report.physical_drive)
		list.clear()
		for row in report.issues:
			list.add_item("%s · %s"%[str(row.severity).to_upper(),row.message])
			list.set_item_metadata(list.item_count-1,row)
		for row in report.get("scenarios",[]):
			list.add_item("%s demand screen: %d/%d high-demand lanes; %d patrol-disabled lanes"%[row.scenario,row.high_demand_lanes,row.lanes,row.patrol_disabled_lanes])
		if report.truncated:list.add_item("Issue list truncated; counts include additional findings.")
	list.item_activated.connect(func(index: int):
		var row: Variant=list.get_item_metadata(index)
		if not row is Dictionary:return
		dialog.hide()
		e.editor_camera.global_position=Vector2(row.position[0],row.position[1])*20.0
		e._update_view(true))
	e._btn("Run / refresh checks",panel,run)
	var apply:=func(all: bool):
		if not _ready(e) or state.hash!=e.authoring._fingerprint(e.authoring.doc):
			summary.text="Source changed. Refresh validation first.";return
		var fixes: Array=[]
		if all:
			for row in state.report.get("issues",[]):
				if not row.fix.is_empty():fixes.append(row.fix)
		else:
			var chosen:=list.get_selected_items()
			if not chosen.is_empty():
				var row: Variant=list.get_item_metadata(chosen[0])
				if row is Dictionary and not row.fix.is_empty():fixes.append(row.fix)
		if fixes.is_empty():summary.text="No eligible endpoint repairs selected.";return
		var next:=Validation.repaired(e.authoring.doc,fixes)
		if next.is_empty() or not e.authoring._commit(next):
			summary.text="Repair rejected: "+e.authoring.last_error;return
		e._refresh_authoring()
		run.call()
	e._btn("Repair selected small endpoint gap",panel,func():apply.call(false))
	e._btn("Repair all proposed small endpoint gaps (one undo)",panel,func():apply.call(true))
	e._btn("Export JSON readiness report",panel,func():
		if state.report.is_empty() or state.hash!=e.authoring._fingerprint(e.authoring.doc):
			summary.text="Refresh validation before export.";return
		var path: String="user://world-validation-report.json"
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file==null:summary.text="Unable to save report.";return
		file.store_string(JSON.stringify(state.report,"  "));file.close()
		summary.text="Saved "+ProjectSettings.globalize_path(path))
	e._btn("Directed navigation preview",panel,func():open_validation_route(e))
	e._btn("Measured performance details",panel,func():open_measured(e))
	_label(panel,"Double-click a finding to locate it. Repairs are proposals; review connections before applying. Demand screens and patrol coverage are estimates, not simulated queue lengths or response times.")
	dialog.popup_centered()
	run.call()

func open_validation_route(e) -> void:
	if not _ready(e):return
	var panel:=_panel(e,"Directed navigation preview")
	var center: Vector2=e.editor_camera.global_position/20.0
	var w:=float(e.authoring.doc.world.width);var h:=float(e.authoring.doc.world.height)
	var x1: SpinBox=e._number(panel,"Start X",0,w,clampf(center.x,0,w))
	var y1: SpinBox=e._number(panel,"Start Y",0,h,clampf(center.y,0,h))
	var x2: SpinBox=e._number(panel,"Finish X",0,w,clampf(center.x+200,0,w))
	var y2: SpinBox=e._number(panel,"Finish Y",0,h,clampf(center.y,0,h))
	var l1:=_control_field(panel,"Start level",0,-2,2)
	var l2:=_control_field(panel,"Finish level",0,-2,2)
	var status:=_label(panel,"Select endpoints within 25 m of legal lanes.")
	var canvas:=Control.new()
	canvas.custom_minimum_size=Vector2(480,180);panel.add_child(canvas)
	var scenario:=_control_choice(panel,"Physical test scenario",["Normal","Rush hour","Heavy","Police"])
	var state: Dictionary={"points":PackedVector2Array(),"route":{},"spec":{},"hash":""}
	canvas.draw.connect(func():
		canvas.draw_rect(Rect2(Vector2.ZERO,canvas.size),Color("#19222d"))
		var points: PackedVector2Array=state.points
		if points.size()<2:return
		var bounds:=Rect2(points[0],Vector2.ZERO)
		for p in points:bounds=bounds.expand(p)
		var scale_factor:=minf((canvas.size.x-24)/maxf(1.0,bounds.size.x),(canvas.size.y-24)/maxf(1.0,bounds.size.y))
		var scaled:=PackedVector2Array()
		for p in points:scaled.append((p-bounds.position)*scale_factor+Vector2(12,12))
		canvas.draw_polyline(scaled,Color("#64c8fa"),3.0,true)
		canvas.draw_circle(scaled[0],5,Color.GREEN)
		canvas.draw_circle(scaled[-1],5,Color.ORANGE))
	e._btn("Find legal route",panel,func():
		state.points=PackedVector2Array();state.route={};canvas.queue_redraw()
		if not _ready(e):return
		var compiled: Dictionary={}
		if e.map_switcher.custom:compiled=_race_graph(e)
		elif e.authoring.doc.get("roads",[])==e.authoring.initial.get("roads",[]) and e.authoring.doc.get("junctionControls",[])==e.authoring.initial.get("junctionControls",[]):compiled=_graph(e)
		if compiled.is_empty():status.text="Current graph unavailable. Bake Morrow road edits first.";return
		var planner:=Planner.new();planner.setup(compiled.network,compiled.data)
		var route:=Validation.route(planner,{"x":x1.value,"y":y1.value,"road_layer":int(l1.value)},{"x":x2.value,"y":y2.value,"road_layer":int(l2.value)})
		if route.is_empty():status.text="Unreachable on selected road levels.";return
		state.points=route.points_m;state.route=route
		state.spec={"start":{"x":x1.value,"y":y1.value,"road_layer":int(l1.value)},"finish":{"x":x2.value,"y":y2.value,"road_layer":int(l2.value)}}
		state.hash=e.authoring._fingerprint(e.authoring.doc)
		canvas.queue_redraw()
		status.text="%.0f m | %d directed edges | access %.1f / %.1f m"%[route.length_m,route.edges.size(),route.start_access_distance_m,route.access_distance_m])
	e._btn("Launch physical AI Test Drive (flat route)",panel,func():
		if not _ready(e) or state.route.is_empty() or state.hash!=e.authoring._fingerprint(e.authoring.doc):
			status.text="Find a route for the current revision first.";return
		if state.spec.start.road_layer!=0 or state.spec.finish.road_layer!=0:
			status.text="Physical validation currently requires ground-level endpoints.";return
		var route: Dictionary=state.route
		if float(route.length_m)<20.0 or float(route.length_m)>5000.0:
			status.text="Choose a route between 20 and 5000 m.";return
		var pts: PackedVector2Array=route.points_m
		var spec: Dictionary=state.spec.duplicate(true)
		spec["scenario"]=scenario.get_item_text(scenario.selected)
		dialog.hide()
		e._test_drive({"position":pts[0]*20.0,"layer":0,"rotation":(pts[1]-pts[0]).angle()+PI*.5,"validation":spec}))
	dialog.popup_centered()
