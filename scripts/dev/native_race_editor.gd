extends RefCounted
## Per-race routes and starting slots share native world-editor undo and saved data.
const Grid=preload("res://scripts/world/race_start_grid.gd")
var panel: VBoxContainer
var race_list: OptionButton
var title: LineEdit
var mode: OptionButton
var competition: OptionButton
var laps: SpinBox
var radius: SpinBox
var start_radius: SpinBox
var time_limit: SpinBox
var opponents: SpinBox
var formation: OptionButton
var grid_slot: OptionButton
var slot_rotation: SpinBox
var editing_id:=""
var grid_race_id:=""
var updating:=false
var list_stamp:=-1
var slots_stamp:=""
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
	mode=e._options(panel,"Route format",["sprint","circuit"])
	competition=e._options(panel,"Race type",["ai_race","time_trial"])
	competition.set_item_text(0,"Race vs AI")
	competition.set_item_text(1,"Time trial (solo)")
	laps=e._number(panel,"Laps",1,20,1)
	radius=e._number(panel,"Gate radius m",4,60,16)
	start_radius=e._number(panel,"Start circle m",3,30,8)
	time_limit=e._number(panel,"Limit sec (0=none)",0,7200,0)
	var grid_label:=Label.new();grid_label.text="STARTING GRID";panel.add_child(grid_label)
	opponents=e._number(panel,"AI opponents",1,Grid.MAX_RIVALS,2)
	opponents.step=1
	formation=e._options(panel,"Formation",Grid.FORMATIONS)
	grid_slot=OptionButton.new();grid_slot.tooltip_text="Select the player or a specific AI grid slot to move.";panel.add_child(grid_slot)
	slot_rotation=e._number(panel,"Facing °",-180,180,0)
	slot_rotation.step=1
	e._btn("Place grid slot on map",panel,func():begin_grid(e)).tooltip_text="Click the map to place the chosen player or AI starting position. Drag an existing grid marker to move it."
	e._btn("Auto-arrange grid",panel,func():auto_grid(e)).tooltip_text="Reset all positions to the selected formation behind/alongside the route start."
	e._btn("Add checkpoint on road",panel,func():begin_checkpoint(e)).tooltip_text="Select a gate then click a road to insert the next checkpoint in that order. A sprint keeps its finish last."
	e._btn("Move checkpoint earlier",panel,func():shift_checkpoint(e,-1))
	e._btn("Move checkpoint later",panel,func():shift_checkpoint(e,1))
	e._btn("Redraw race route",panel,func():begin_route(e,e.source_id if not e.authoring.race_at_id(e.source_id).is_empty() else ""))
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help.text="Click roads in route order: start, checkpoints, finish. Enter saves. Select a saved race to drag gates or place more checkpoints. Set AI opponents to race, or choose Time trial for a solo run."
	help.add_theme_font_size_override("font_size",11);panel.add_child(help)
	title.text_submitted.connect(func(_value):commit_settings(e))
	title.focus_exited.connect(func():commit_settings(e))
	mode.item_selected.connect(func(_index):commit_settings(e))
	competition.item_selected.connect(func(_index):change_competition(e))
	formation.item_selected.connect(func(_index):commit_settings(e))
	for spin in [laps,radius,start_radius,time_limit,opponents]:spin.value_changed.connect(func(_value):commit_settings(e))
	grid_slot.item_selected.connect(func(_index):_sync_rotation(e))
	slot_rotation.value_changed.connect(func(_value):commit_grid_rotation(e))
	panel.visible=false
func settings(e) -> Dictionary:
	return {"name":title.text.strip_edges(),"mode":e._option_value(mode),"laps":int(laps.value) if e._option_value(mode)=="circuit" else 1,
		"checkpoint_radius":radius.value,"start_radius":start_radius.value,"time_limit":time_limit.value,
		"opponent_count":0 if e._option_value(competition)=="time_trial" else maxi(1,int(opponents.value)),
		"formation":e._option_value(formation)}
func minimum_points(e) -> int:return 3 if e._option_value(mode)=="circuit" else 2
func begin_route(e,id: String="") -> void:
	if e._editing_locked() or not e.source_ready:return
	e._choose_tool("draw_race");editing_id=id
	e._notice("Click the actual roads in order: START, checkpoints, FINISH. Press Enter to save. Checkpoints snap to road centerlines.")
func begin_checkpoint(e) -> void:
	if e._editing_locked() or not e.source_ready:return
	var identity: String=e.source_id
	if e.authoring.race_at_id(identity).is_empty():
		e._notice("Select a saved street race before adding checkpoints.")
		return
	e._choose_tool("race_checkpoint")
	e.source_id=identity
	e._refresh_authoring()
	e._notice("Click a road to insert the next checkpoint after the selected gate. Press Esc when finished.")

func shift_checkpoint(e,direction: int) -> void:
	if e._editing_locked() or not e.source_ready:return
	if e.authoring.reorder_race_checkpoint(e.source_id,e.source_anchor,direction):
		e.source_anchor+=direction
		e._refresh_authoring()
	else:e._notice(e.authoring.last_error)

func change_competition(e) -> void:
	if updating:return
	var has_ai: bool=e._option_value(competition)=="ai_race"
	opponents.editable=has_ai
	if has_ai and opponents.value<1:opponents.value=2
	commit_settings(e)

func selected_slot() -> int:
	if grid_slot.item_count==0 or grid_slot.selected<0:return -1
	return int(grid_slot.get_item_metadata(grid_slot.selected))
func begin_grid(e) -> void:
	if e._editing_locked() or not e.source_ready:return
	var id: String=e.source_id
	if e.authoring.race_at_id(id).is_empty():
		e._notice("Select a saved race before editing its starting grid.")
		return
	grid_race_id=id
	e._choose_tool("race_grid")
	e.source_id=id;e.source_anchor=-1
	e._refresh_authoring()
	e._notice("Click to place %s. Drag its existing marker to adjust; Esc returns to Select/Edit."%("PLAYER" if selected_slot()==-1 else "AI %d"%(selected_slot()+1)))
func place_grid_slot(e,at_m: Vector2) -> bool:
	var id: String=grid_race_id if e.tool_name=="race_grid" else e.source_id
	if e.authoring.race_at_id(id).is_empty():return false
	var index:=selected_slot()
	var ok: bool=e.authoring.set_race_grid_slot(id,index,e._snap_point(at_m),slot_rotation.value)
	if ok:
		e.source_id=id;e._refresh_authoring()
		e._notice("Saved %s grid start. Ctrl+Z undoes this placement."%("player" if index==-1 else "AI %d"%(index+1)))
	else:e._notice(e.authoring.last_error)
	return ok
func commit_grid_rotation(e) -> void:
	if updating or e._editing_locked() or not e.source_ready:return
	var race: Dictionary=e.authoring.race_at_id(e.source_id)
	if race.is_empty():return
	var slot: Dictionary=Grid.player_slot(race) if selected_slot()==-1 else race.get("enemy_starts",[])[clampi(selected_slot(),0,maxi(0,race.get("enemy_starts",[]).size()-1))]
	if slot.is_empty():return
	if not e.authoring.set_race_grid_slot(e.source_id,selected_slot(),Grid.point(slot),slot_rotation.value):
		e._notice(e.authoring.last_error)
	e._refresh_authoring()
func _sync_rotation(e) -> void:
	var race: Dictionary=e.authoring.race_at_id(e.source_id)
	if race.is_empty():return
	var index:=selected_slot()
	var slot: Dictionary={}
	if index==-1:slot=Grid.player_slot(race)
	elif index<race.get("enemy_starts",[]).size():slot=race.enemy_starts[index]
	if slot.is_empty():return
	updating=true;slot_rotation.value=float(slot.get("rotation",0));updating=false
	e.gizmos.queue_redraw()
func auto_grid(e) -> void:
	if e._editing_locked() or not e.source_ready:return
	var id: String=e.source_id
	if e.authoring.race_at_id(id).is_empty():
		e._notice("Select a race first.");return
	if e.authoring.reset_race_grid(id,e._option_value(formation)):
		e._refresh_authoring()
		e._notice("Reset race grid to %s. Ctrl+Z undoes it."%e._option_value(formation))
	else:e._notice(e.authoring.last_error)
func update(e) -> void:
	if panel==null or not e.source_ready:return
	var selected: Dictionary=e.authoring.race_at_id(e.source_id)
	panel.visible=e.tool_name in ["draw_race","race_grid","race_checkpoint"] or not selected.is_empty()
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
		var rival_count: int=selected.get("enemy_starts",[]).size()
		competition.select(1 if rival_count==0 else 0)
		opponents.value=float(maxi(1,rival_count))
		for i in formation.item_count:
			if str(formation.get_item_metadata(i))==str(selected.get("formation","single_file")):formation.select(i);break
		for i in race_list.item_count:
			if str(race_list.get_item_metadata(i))==e.source_id:race_list.select(i);break
		var signature: String=str(e.source_id)+":"+str(selected.get("enemy_starts",[]).size())
		if signature!=slots_stamp:
			slots_stamp=signature
			grid_slot.clear();grid_slot.add_item("Player start");grid_slot.set_item_metadata(0,-1)
			for i in selected.get("enemy_starts",[]).size():
				grid_slot.add_item("AI %d start"%(i+1));grid_slot.set_item_metadata(i+1,i)
			grid_slot.select(clampi(grid_slot.selected,0,maxi(0,grid_slot.item_count-1)))
		var slot_index:=selected_slot()
		var slot: Dictionary=Grid.player_slot(selected) if slot_index==-1 else selected.enemy_starts[clampi(slot_index,0,maxi(0,selected.enemy_starts.size()-1))]
		slot_rotation.value=float(slot.get("rotation",0))
	laps.editable=e._option_value(mode)=="circuit"
	opponents.editable=e._option_value(competition)=="ai_race"
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
