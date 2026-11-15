extends RefCounted
## Race setup uses the editor's existing draw, selection and undo workflows.
var panel: VBoxContainer
var race_list: OptionButton
var title: LineEdit
var mode: OptionButton
var laps: SpinBox
var radius: SpinBox
var start_radius: SpinBox
var time_limit: SpinBox
var editing_id:=""
var updating:=false
var list_stamp:=-1
func build(e,parent: Node) -> void:
	e._btn("Set up races",parent,func():begin_route(e))
	panel=VBoxContainer.new();parent.add_child(panel)
	var heading:=Label.new();heading.text="RACE SETUP";panel.add_child(heading)
	race_list=OptionButton.new();panel.add_child(race_list)
	race_list.item_selected.connect(func(index):
		if updating:return
		var id:=str(race_list.get_item_metadata(index))
		if id.is_empty():begin_route(e);return
		e._choose_tool("move_prop");e.source_id=id;e.source_anchor=-1;e._refresh_authoring())
	title=LineEdit.new();title.placeholder_text="Race name";title.text="New race";title.max_length=80;panel.add_child(title)
	mode=e._options(panel,"Format",["sprint","circuit"])
	laps=e._number(panel,"Laps",1,20,1)
	radius=e._number(panel,"Gate radius m",4,60,16)
	start_radius=e._number(panel,"Start circle m",3,30,8)
	time_limit=e._number(panel,"Limit sec (0=none)",0,7200,0)
	e._btn("Redraw race route",panel,func():begin_route(e,e.source_id if not e.authoring.race_at_id(e.source_id).is_empty() else ""))
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help.text="Click start, checkpoints, then finish. Enter saves the route. Circuits return to the start. Select a race to drag its checkpoints or edit settings."
	help.add_theme_font_size_override("font_size",11);panel.add_child(help)
	title.text_submitted.connect(func(_value):commit_settings(e))
	title.focus_exited.connect(func():commit_settings(e))
	mode.item_selected.connect(func(_index):commit_settings(e))
	for spin in [laps,radius,start_radius,time_limit]:spin.value_changed.connect(func(_value):commit_settings(e))
	panel.visible=false
func settings(e) -> Dictionary:
	return {"name":title.text.strip_edges(),"mode":e._option_value(mode),"laps":int(laps.value) if e._option_value(mode)=="circuit" else 1,
		"checkpoint_radius":radius.value,"start_radius":start_radius.value,"time_limit":time_limit.value}
func minimum_points(e) -> int:return 3 if e._option_value(mode)=="circuit" else 2
func begin_route(e,id: String="") -> void:
	if e._editing_locked() or not e.source_ready:return
	e._choose_tool("draw_race");editing_id=id
	e._notice("Click the start, then checkpoints and finish. Press Enter to save the race route.")
func update(e) -> void:
	if panel==null or not e.source_ready:return
	var selected: Dictionary=e.authoring.race_at_id(e.source_id)
	panel.visible=e.tool_name=="draw_race" or not selected.is_empty()
	updating=true
	var stamp: int=hash(e.authoring.doc.get("races",[]))
	if stamp!=list_stamp:
		list_stamp=stamp;race_list.clear();race_list.add_item("Draw a new race");race_list.set_item_metadata(0,"")
		for race in e.authoring.doc.get("races",[]):race_list.add_item(str(race.name));race_list.set_item_metadata(race_list.item_count-1,str(race.id))
	if not selected.is_empty() and e.tool_name!="draw_race":
		title.text=str(selected.name)
		mode.select(1 if selected.mode=="circuit" else 0)
		laps.value=float(selected.get("laps",1));radius.value=float(selected.get("checkpoint_radius",16))
		start_radius.value=float(selected.get("start_radius",8));time_limit.value=float(selected.get("time_limit",0))
		for i in race_list.item_count:
			if str(race_list.get_item_metadata(i))==e.source_id:race_list.select(i);break
	laps.editable=e._option_value(mode)=="circuit"
	updating=false
func commit_settings(e) -> void:
	if updating or not e.source_ready or e._editing_locked():return
	laps.editable=e._option_value(mode)=="circuit"
	if e.tool_name=="draw_race":e._update_context_panels();return
	var race: Dictionary=e.authoring.race_at_id(e.source_id)
	if race.is_empty():return
	var points: Array[Vector2]=[]
	for p in race.points:points.append(Vector2(p.x,p.y))
	if e.authoring.save_race(points,settings(e),e.source_id).is_empty():e._notice(e.authoring.last_error)
	e._refresh_authoring()
func finish(e) -> String:
	var id: String=e.authoring.save_race(e.draft_points,settings(e),editing_id)
	if not id.is_empty():editing_id=""
	return id
