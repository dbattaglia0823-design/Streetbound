extends RefCounted
## Per-race routes and starting slots share native world-editor undo and saved data.
const Grid=preload("res://scripts/world/race_start_grid.gd")
const Catalog=preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
const OnlineRewards=preload("res://scripts/network/online_race_rewards.gd")
const VehicleOwnership=preload("res://scripts/vehicle/vehicle_ownership.gd")
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
# The compact sidebar is for route work; this separate window edits one
# placed race as a transaction, without committing partial form changes.
var edit_button: Button
var dialog: AcceptDialog
var dialog_race_id:=""
var dialog_name: LineEdit
var dialog_type: OptionButton
var dialog_laps: SpinBox
var dialog_radius: SpinBox
var dialog_start_radius: SpinBox
var dialog_time_limit: SpinBox
var dialog_opponents: SpinBox
var dialog_formation: OptionButton
var dialog_cash: SpinBox
var dialog_driver_xp: SpinBox
var dialog_car_xp: SpinBox
var dialog_tabs: TabContainer
var online_use_custom: CheckBox
var online_cash: SpinBox
var online_driver_xp: SpinBox
var online_car_xp: SpinBox
var online_part_chance: SpinBox
var online_preview: Label
var pool_search: LineEdit
var pool_list: ItemList
var pool_summary: Label
var dialog_message: Label
var selected_pool: Array[String]=[]
var pool_syncing:=false
var career_category: OptionButton
var career_difficulty: OptionButton
var career_level: SpinBox
var career_car_level: SpinBox
var career_repeatable: CheckBox
var career_first_cash: SpinBox
var career_first_driver_xp: SpinBox
var career_first_car_xp: SpinBox
var career_require_cars: ItemList
var career_prerequisites: ItemList
var _career_car_ids: Array[String]=[]
var _career_race_ids: Array[String]=[]
func build(e,parent: Node) -> void:
	e._btn("Street races & routes",parent,func():begin_route(e))
	panel=VBoxContainer.new();parent.add_child(panel)
	var heading:=Label.new();heading.text="RACE SETUP";panel.add_child(heading)
	race_list=OptionButton.new();panel.add_child(race_list)
	race_list.item_selected.connect(func(index):
		if updating:return
		var id:=str(race_list.get_item_metadata(index))
		if id.is_empty():begin_route(e);return
		e._choose_tool("move_prop");e.source_id=id;e.source_anchor=-1;e._refresh_authoring())
	edit_button=e._btn("Edit Race...",panel,func():open_selected(e))
	edit_button.tooltip_text="Open the full editor for the selected placed race, enemy vehicle pool, race format and rewards."
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
	_build_dialog(e)
func settings(e) -> Dictionary:
	return {"name":title.text.strip_edges(),"mode":e._option_value(mode),"laps":int(laps.value) if e._option_value(mode)=="circuit" else 1,
		"checkpoint_radius":radius.value,"start_radius":start_radius.value,"time_limit":time_limit.value,
		"opponent_count":0 if e._option_value(competition)=="time_trial" else maxi(1,int(opponents.value)),
		"formation":e._option_value(formation),
		"race_kind":"circuit" if e._option_value(mode)=="circuit" else ("time_trial" if e._option_value(competition)=="time_trial" else "point_to_point")}
func minimum_points(e) -> int:return 3 if e._option_value(mode)=="circuit" else 2
func begin_route(e,id: String="") -> void:
	if e._editing_locked() or not e.source_ready:return
	e._choose_tool("draw_race");editing_id=id
	e._notice("Click the actual roads in order: START, checkpoints, FINISH. Press Enter to save. Checkpoints snap to road centerlines.")
func begin_checkpoint(e) -> void:
	if e._editing_locked() or not e.source_ready:return
	var identity: String=e.source_id
	var after_gate: int=e.source_anchor
	if e.authoring.race_at_id(identity).is_empty():
		e._notice("Select a saved street race before adding checkpoints.")
		return
	e._choose_tool("race_checkpoint")
	e.source_id=identity
	e.source_anchor=after_gate
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
	edit_button.disabled=selected.is_empty() or e._editing_locked()
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


func _form_label(parent: Node, text_value: String) -> Label:
	var label:=Label.new()
	label.text=text_value
	label.add_theme_font_size_override("font_size",12)
	parent.add_child(label)
	return label

func _form_column(parent: Node, width: float) -> VBoxContainer:
	var column:=VBoxContainer.new()
	column.custom_minimum_size.x=width
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",6)
	parent.add_child(column)
	return column

func _build_dialog(e) -> void:
	dialog=AcceptDialog.new()
	dialog.name="EditRaceDialog"
	dialog.title="Edit Race — Routes, Career & Multiplayer Rewards"
	dialog.ok_button_text="Cancel"
	dialog.min_size=Vector2i(980,675)
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	e.add_child(dialog)
	var body:=VBoxContainer.new()
	body.custom_minimum_size=Vector2(940,595)
	dialog.add_child(body)
	var tabs:=TabContainer.new()
	tabs.name="RaceEditTabs"
	dialog_tabs=tabs
	tabs.custom_minimum_size=Vector2(940,550)
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var columns:=HBoxContainer.new()
	columns.name="Race Setup"
	columns.add_theme_constant_override("separation",13)
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tabs.add_child(columns)
	var basics:=_form_column(columns,260)
	_form_label(basics,"RACE SETTINGS")
	dialog_name=LineEdit.new();dialog_name.max_length=80
	dialog_name.placeholder_text="Race name";basics.add_child(dialog_name)
	_form_label(basics,"Race type")
	dialog_type=OptionButton.new()
	for pair in [["Point to point","point_to_point"],["Circuit","circuit"],["Time trial (solo)","time_trial"]]:
		dialog_type.add_item(pair[0])
		dialog_type.set_item_metadata(dialog_type.item_count-1,pair[1])
	basics.add_child(dialog_type)
	dialog_type.item_selected.connect(func(_index: int)->void:_update_dialog_type())
	dialog_laps=e._number(basics,"Laps (circuit)",1,20,1);dialog_laps.step=1
	dialog_opponents=e._number(basics,"AI opponents (0-6)",0,Grid.MAX_RIVALS,2);dialog_opponents.step=1
	_form_label(basics,"Starting grid")
	dialog_formation=e._options(basics,"Formation",Grid.FORMATIONS)
	dialog_radius=e._number(basics,"Checkpoint radius m",4,60,16)
	dialog_start_radius=e._number(basics,"Start circle m",3,30,8)
	dialog_time_limit=e._number(basics,"Time limit sec (0=off)",0,7200,0)
	var route_note:=_form_label(basics,"Routes and checkpoint positions are edited on the map. Circuits need at least three gates.")
	route_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var enemies:=_form_column(columns,335)
	_form_label(enemies,"POSSIBLE ENEMY VEHICLES")
	pool_search=LineEdit.new()
	pool_search.placeholder_text="Search the live vehicle catalog..."
	pool_search.text_changed.connect(func(_value: String)->void:_refresh_pool())
	enemies.add_child(pool_search)
	pool_list=ItemList.new()
	pool_list.select_mode=ItemList.SELECT_MULTI
	pool_list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	pool_list.custom_minimum_size.y=365
	enemies.add_child(pool_list)
	pool_list.multi_selected.connect(_pool_selected)
	var pool_actions:=HBoxContainer.new();enemies.add_child(pool_actions)
	e._btn("All shown",pool_actions,_select_visible_pool)
	e._btn("Clear pool",pool_actions,_clear_pool)
	pool_summary=_form_label(enemies,"No models selected — match the player's car")
	var pool_hint:=_form_label(enemies,"Ctrl-click to add/remove models. Enemy vehicles are drawn from this pool each race; their stats and artwork use the current car catalog.")
	pool_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var awards:=_form_column(columns,230)
	_form_label(awards,"REWARDS ON WIN")
	dialog_cash=e._number(awards,"Cash $",0,1000000,0);dialog_cash.step=1
	dialog_driver_xp=e._number(awards,"Driver XP",0,100000,0);dialog_driver_xp.step=1
	dialog_car_xp=e._number(awards,"Vehicle XP",0,100000,0);dialog_car_xp.step=1
	e._btn("Set Multiplayer Rewards...",awards,func():tabs.current_tab=2).tooltip_text="Configure first-place multiplayer cash, driver XP, car XP and upgrade-part drop chance on this race."
	var win_hint:=_form_label(awards,"Paid once per completed run: beat the AI or finish a solo time trial. Losses, false starts and quit runs award nothing.")
	win_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var career:=HBoxContainer.new()
	career.name="Career & Unlocks"
	career.add_theme_constant_override("separation",20)
	tabs.add_child(career)
	var rules:=_form_column(career,345)
	_form_label(rules,"CAREER PROGRESSION")
	career_category=e._options(rules,"Event category",EventRules.CATEGORIES)
	career_difficulty=e._options(rules,"Difficulty",EventRules.DIFFICULTIES)
	career_level=e._number(rules,"Minimum driver level",1,100,1);career_level.step=1
	career_car_level=e._number(rules,"Minimum car level",1,50,1);career_car_level.step=1
	career_repeatable=CheckBox.new()
	career_repeatable.text="Repeatable after first win"
	career_repeatable.button_pressed=true
	rules.add_child(career_repeatable)
	_form_label(rules,"FIRST WIN BONUS (added to normal rewards)")
	career_first_cash=e._number(rules,"Cash $",0,1000000,0);career_first_cash.step=1
	career_first_driver_xp=e._number(rules,"Driver XP",0,100000,0);career_first_driver_xp.step=1
	career_first_car_xp=e._number(rules,"Vehicle XP",0,100000,0);career_first_car_xp.step=1
	var locks:=_form_column(career,540)
	_form_label(locks,"REQUIRED PREVIOUS RACES (all must be won)")
	career_prerequisites=ItemList.new()
	career_prerequisites.select_mode=ItemList.SELECT_MULTI
	career_prerequisites.custom_minimum_size.y=162
	career_prerequisites.multi_selected.connect(func(index: int,chosen: bool)->void:
		var id: String=str(career_prerequisites.get_item_metadata(index))
		if chosen and not _career_race_ids.has(id):_career_race_ids.append(id)
		elif not chosen:_career_race_ids.erase(id))
	locks.add_child(career_prerequisites)
	_form_label(locks,"ELIGIBLE PLAYER VEHICLES (none = all owned cars)")
	career_require_cars=ItemList.new()
	career_require_cars.select_mode=ItemList.SELECT_MULTI
	career_require_cars.custom_minimum_size.y=208
	career_require_cars.multi_selected.connect(func(index: int,chosen: bool)->void:
		var id: String=str(career_require_cars.get_item_metadata(index))
		if chosen and not _career_car_ids.has(id):_career_car_ids.append(id)
		elif not chosen:_career_car_ids.erase(id))
	locks.add_child(career_require_cars)
	var note:=_form_label(locks,"Ctrl-click to select multiple. Prerequisite chains must be acyclic. First-win bonuses are paid only once; repeat rewards apply on every subsequent win.")
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var multiplayer_tab:=HBoxContainer.new()
	multiplayer_tab.name="Multiplayer Rewards"
	multiplayer_tab.add_theme_constant_override("separation",30)
	tabs.add_child(multiplayer_tab)
	var online_fields:=_form_column(multiplayer_tab,385)
	_form_label(online_fields,"FRIEND RACE REWARDS")
	online_use_custom=CheckBox.new()
	online_use_custom.text="Use custom multiplayer prizes for this race"
	online_fields.add_child(online_use_custom)
	online_cash=e._number(online_fields,"First-place cash $",0,OnlineRewards.MAX_EXACT_REWARD,0)
	online_cash.step=1
	online_driver_xp=e._number(online_fields,"First-place driver XP",0,OnlineRewards.MAX_EXACT_REWARD,0)
	online_driver_xp.step=1
	online_car_xp=e._number(online_fields,"First-place vehicle XP",0,OnlineRewards.MAX_EXACT_REWARD,0)
	online_car_xp.step=1
	online_part_chance=e._number(online_fields,"First-place upgrade drop %",0,100,100)
	online_part_chance.step=1
	var online_hint:=_form_label(online_fields,"Lower places scale automatically. A 0 reward disables that currency or item chance. Only 2–4 player races that finish and pass the host's checkpoint validation can claim prizes.")
	online_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for field in [online_cash, online_driver_xp, online_car_xp]:
		field.tooltip_text="No gameplay reward cap. Enter a nonnegative whole number; values must remain exactly representable when saved to the published world."
	var online_right:=_form_column(multiplayer_tab,490)
	_form_label(online_right,"LIVE 1ST–4TH PLACE PREVIEW")
	online_preview=_form_label(online_right,"")
	online_preview.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var online_notice:=_form_label(online_right,"Multiplayer prizes are separate from the solo race rewards and career first-win bonuses. Uncheck custom prizes to keep the game's default values for this track. Save Race Settings, then Save to Game / publish the map. Every online player must run the same published world build.")
	online_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	online_use_custom.toggled.connect(func(_enabled: bool):_update_online_rewards())
	for spin in [online_cash,online_driver_xp,online_car_xp,online_part_chance]:
		spin.value_changed.connect(func(_value: float):_update_online_rewards())
	var foot:=HBoxContainer.new();body.add_child(foot)
	dialog_message=_form_label(foot,"")
	dialog_message.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	e._btn("Save Race Settings",foot,func():_save_dialog(e))

func _update_dialog_type() -> void:
	var kind:=str(dialog_type.get_selected_metadata())
	var solo:=kind=="time_trial"
	dialog_laps.editable=kind=="circuit"
	dialog_opponents.editable=not solo
	dialog_formation.disabled=solo
	pool_list.mouse_filter=Control.MOUSE_FILTER_IGNORE if solo else Control.MOUSE_FILTER_STOP
	pool_summary.text="Solo time trial — no enemy cars" if solo else ("%d available vehicle models"%selected_pool.size() if not selected_pool.is_empty() else "No pool — opponents copy player car")
	_update_online_rewards()

func _update_online_rewards() -> void:
	if not is_instance_valid(online_use_custom) or not is_instance_valid(online_preview):
		return
	var custom: bool=online_use_custom.button_pressed
	for field in [online_cash,online_driver_xp,online_car_xp,online_part_chance]:
		field.editable=custom
	var kind: String="circuit" if str(dialog_type.get_selected_metadata())=="circuit" else "street"
	var rules: Dictionary={
		"multiplayer_reward_custom":custom,
		"multiplayer_reward_cash":int(online_cash.value),
		"multiplayer_reward_player_xp":int(online_driver_xp.value),
		"multiplayer_reward_car_xp":int(online_car_xp.value),
		"multiplayer_reward_part_chance":int(online_part_chance.value)}
	online_preview.text="Custom first-place prizes" if custom else "Standard multiplayer prizes (unchanged)"
	for place in range(1,5):
		var payout: Dictionary=OnlineRewards.payouts(kind,place,rules)
		online_preview.text+="\n%d.  %s  /  %d DRIVER XP  /  %d CAR XP  /  %d%% PART" % [
			place,VehicleOwnership.dollars(int(payout.get("cash",0))),
			int(payout.get("player_xp",0)),int(payout.get("car_xp",0)),
			OnlineRewards.part_chance(place,rules)]

func open_selected(e) -> void:
	open_for(e,e.source_id)

func open_for(e,id: String) -> void:
	if not e.source_ready or e._editing_locked():return
	var race: Dictionary=e.authoring.race_at_id(id)
	if race.is_empty():
		e._notice("Place or select a race before opening Edit Race.")
		return
	dialog_race_id=id
	dialog_name.text=str(race.name)
	var rival_count: int=race.get("enemy_starts",[]).size()
	var race_kind: String=str(race.get("race_kind","circuit" if str(race.mode)=="circuit" else ("time_trial" if rival_count==0 else "point_to_point")))
	dialog_type.select(["point_to_point","circuit","time_trial"].find(race_kind))
	dialog_laps.value=float(race.get("laps",1))
	dialog_opponents.value=float(rival_count)
	for i in dialog_formation.item_count:
		if str(dialog_formation.get_item_metadata(i))==str(race.get("formation","single_file")):
			dialog_formation.select(i)
			break
	dialog_radius.value=float(race.get("checkpoint_radius",16))
	dialog_start_radius.value=float(race.get("start_radius",8))
	dialog_time_limit.value=float(race.get("time_limit",0))
	dialog_cash.value=float(race.get("reward_cash",0))
	dialog_driver_xp.value=float(race.get("reward_player_xp",0))
	dialog_car_xp.value=float(race.get("reward_car_xp",0))
	var online_kind: String="circuit" if race.get("mode","")=="circuit" else "street"
	online_use_custom.button_pressed=bool(race.get("multiplayer_reward_custom",false))
	var standard: Dictionary=OnlineRewards.payouts(online_kind,1)
	online_cash.value=float(race.get("multiplayer_reward_cash",standard.get("cash",0)))
	online_driver_xp.value=float(race.get("multiplayer_reward_player_xp",standard.get("player_xp",0)))
	online_car_xp.value=float(race.get("multiplayer_reward_car_xp",standard.get("car_xp",0)))
	online_part_chance.value=float(race.get("multiplayer_reward_part_chance",100))
	for i in career_category.item_count:
		if str(career_category.get_item_metadata(i))==str(race.get("category","street")):career_category.select(i)
	for i in career_difficulty.item_count:
		if str(career_difficulty.get_item_metadata(i))==str(race.get("difficulty","rookie")):career_difficulty.select(i)
	career_level.value=float(race.get("required_player_level",1))
	career_car_level.value=float(race.get("required_car_level",1))
	career_repeatable.button_pressed=bool(race.get("repeatable",true))
	career_first_cash.value=float(race.get("first_win_reward_cash",0))
	career_first_driver_xp.value=float(race.get("first_win_reward_player_xp",0))
	career_first_car_xp.value=float(race.get("first_win_reward_car_xp",0))
	_career_race_ids.clear()
	for other in race.get("prerequisite_races",[]):_career_race_ids.append(str(other))
	_career_car_ids.clear()
	for car in race.get("required_vehicle_ids",[]):_career_car_ids.append(str(car))
	career_prerequisites.clear()
	for other in e.authoring.doc.get("races",[]):
		if str(other.id)==id:continue
		career_prerequisites.add_item(str(other.name)+"  ("+str(other.id)+")")
		var index:=career_prerequisites.item_count-1
		career_prerequisites.set_item_metadata(index,str(other.id))
		if _career_race_ids.has(str(other.id)):career_prerequisites.select(index,false)
	career_require_cars.clear()
	for car in Catalog.all():
		career_require_cars.add_item(str(car.get("display_name",car.id)))
		var index:=career_require_cars.item_count-1
		career_require_cars.set_item_metadata(index,str(car.id))
		if _career_car_ids.has(str(car.id)):career_require_cars.select(index,false)
	selected_pool.clear()
	for vehicle_id in race.get("opponent_pool",[]):
		selected_pool.append(str(vehicle_id))
	pool_search.clear()
	dialog_message.text=""
	_refresh_pool()
	_update_dialog_type()
	dialog_tabs.current_tab=0
	dialog.popup_centered()

func _refresh_pool() -> void:
	if not is_instance_valid(pool_list):return
	pool_syncing=true
	pool_list.clear()
	var query:=pool_search.text.to_lower().strip_edges()
	for vehicle in Catalog.all():
		var id:=str(vehicle.get("id",""))
		var label_text:=str(vehicle.get("display_name",id))
		if not query.is_empty() and not (label_text+" "+id).to_lower().contains(query):
			continue
		pool_list.add_item(label_text)
		var index:=pool_list.item_count-1
		pool_list.set_item_metadata(index,id)
		if selected_pool.has(id):pool_list.select(index,false)
	pool_syncing=false
	_update_dialog_type()

func _pool_selected(index: int,is_selected: bool) -> void:
	if pool_syncing:return
	var id:=str(pool_list.get_item_metadata(index))
	if is_selected and not selected_pool.has(id):selected_pool.append(id)
	elif not is_selected:selected_pool.erase(id)
	_update_dialog_type()

func _select_visible_pool() -> void:
	if str(dialog_type.get_selected_metadata())=="time_trial":return
	for i in pool_list.item_count:
		var id:=str(pool_list.get_item_metadata(i))
		if not selected_pool.has(id):selected_pool.append(id)
	_refresh_pool()

func _clear_pool() -> void:
	selected_pool.clear()
	_refresh_pool()

func _save_dialog(e) -> void:
	if e._editing_locked() or not e.source_ready:return
	var race: Dictionary=e.authoring.race_at_id(dialog_race_id)
	if race.is_empty():
		dialog_message.text="Race no longer exists. Select another race."
		return
	var kind:=str(dialog_type.get_selected_metadata())
	if kind=="circuit" and race.points.size()<3:
		dialog_message.text="Add a checkpoint on the road before switching to Circuit."
		return
	var options: Dictionary={
		"name":dialog_name.text.strip_edges(),
		"mode":"circuit" if kind=="circuit" else "sprint",
		"race_kind":kind,
		"laps":int(dialog_laps.value) if kind=="circuit" else 1,
		"checkpoint_radius":dialog_radius.value,
		"start_radius":dialog_start_radius.value,
		"time_limit":dialog_time_limit.value,
		"opponent_count":0 if kind=="time_trial" else int(dialog_opponents.value),
		"formation":str(dialog_formation.get_selected_metadata()),
		"opponent_pool":selected_pool.duplicate(),
		"reward_cash":int(dialog_cash.value),
		"reward_player_xp":int(dialog_driver_xp.value),
		"reward_car_xp":int(dialog_car_xp.value),
		"multiplayer_reward_custom":online_use_custom.button_pressed,
		"multiplayer_reward_cash":int(online_cash.value),
		"multiplayer_reward_player_xp":int(online_driver_xp.value),
		"multiplayer_reward_car_xp":int(online_car_xp.value),
		"multiplayer_reward_part_chance":int(online_part_chance.value),
		"category":str(career_category.get_selected_metadata()),
		"difficulty":str(career_difficulty.get_selected_metadata()),
		"required_player_level":int(career_level.value),
		"required_car_level":int(career_car_level.value),
		"repeatable":career_repeatable.button_pressed,
		"first_win_reward_cash":int(career_first_cash.value),
		"first_win_reward_player_xp":int(career_first_driver_xp.value),
		"first_win_reward_car_xp":int(career_first_car_xp.value),
		"prerequisite_races":_career_race_ids.duplicate(),
		"required_vehicle_ids":_career_car_ids.duplicate()}
	var points: Array[Vector2]=[]
	for p in race.points:points.append(Vector2(float(p.x),float(p.y)))
	if e.authoring.save_race(points,options,dialog_race_id).is_empty():
		dialog_message.text="Cannot save: "+e.authoring.last_error+" (check prerequisite chain)"
		return
	e.source_id=dialog_race_id
	e.source_anchor=-1
	e._refresh_authoring()
	dialog.hide()
	e._notice("Race settings saved. Undo restores the previous setup; Save to Game applies it.")
