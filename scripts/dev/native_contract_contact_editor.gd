extends RefCounted
## Race-style, undoable job authoring attached to one roadside contact.
## The chosen target/dropoff, payouts, wanted heat and requirements are saved
## as map metadata, not editable through the live game HUD.
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
var fields: VBoxContainer
var style_input: OptionButton
var role_input: LineEdit
var greeting_input: LineEdit
var bio_input: LineEdit
var job_description_input: TextEdit
var arrival_radius_input: SpinBox
var robbery_wait_input: SpinBox
var job_picker: OptionButton
var title_input: LineEdit
var type_input: OptionButton
var difficulty_input: OptionButton
var dropoff_input: OptionButton
var target_input: OptionButton
var repeat_input: CheckBox
var cash_input: SpinBox
var player_xp_input: SpinBox
var car_xp_input: SpinBox
var rep_input: SpinBox
var wanted_input: SpinBox
var duration_input: SpinBox
var level_input: SpinBox
var required_rep_input: SpinBox
var status: Label
var offers: Array[Dictionary] = []
var selected_index := -1
var _reloading := false

func _pick(option: OptionButton, value: String) -> void:
	for i in option.item_count:
		if str(option.get_item_metadata(i))==value:
			option.select(i)
			return
	if option.item_count>0:option.select(0)

func _value(option: OptionButton) -> String:
	return str(option.get_selected_metadata()) if option.selected>=0 else ""

func _caption(parent: Node, title: String) -> void:
	var label:=Label.new()
	label.text=title
	parent.add_child(label)

func _number(parent: Node, title: String, lowest: int, highest: int, initial: int) -> SpinBox:
	_caption(parent,title)
	var input:=SpinBox.new()
	input.min_value=lowest
	input.max_value=highest
	input.step=1.0
	input.value=initial
	input.allow_greater=false
	input.allow_lesser=false
	parent.add_child(input)
	return input

func _choice(parent: Node, title: String, values: Array) -> OptionButton:
	_caption(parent,title)
	var selection:=OptionButton.new()
	for item in values:
		selection.add_item(str(item).capitalize())
		selection.set_item_metadata(selection.item_count-1,str(item))
	parent.add_child(selection)
	return selection

func build(parent: Node) -> void:
	fields=VBoxContainer.new()
	parent.add_child(fields)
	var tabs:=TabContainer.new()
	tabs.name="ContractAuthoringTabs"
	tabs.custom_minimum_size=Vector2(468,520)
	fields.add_child(tabs)
	var identity_scroll:=ScrollContainer.new()
	identity_scroll.name="Contact & Personality"
	identity_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(identity_scroll)
	var persona:=VBoxContainer.new()
	persona.custom_minimum_size.x=445
	persona.add_theme_constant_override("separation",8)
	identity_scroll.add_child(persona)
	_caption(persona,"CONTRACT GIVER / APPEARANCE")
	style_input=_choice(persona,"NPC style",["street","business","mechanic","casual"])
	_caption(persona,"CONTACT ROLE / PERSONALITY")
	role_input=LineEdit.new()
	role_input.max_length=60
	role_input.placeholder_text="Blank uses the selected personality preset"
	persona.add_child(role_input)
	_caption(persona,"CONTACT GREETING")
	greeting_input=LineEdit.new()
	greeting_input.max_length=180
	greeting_input.placeholder_text="A short greeting heard when opening the jobs screen"
	persona.add_child(greeting_input)
	_caption(persona,"CONTACT BIOGRAPHY")
	bio_input=LineEdit.new()
	bio_input.max_length=240
	bio_input.placeholder_text="Their background and job specialties"
	persona.add_child(bio_input)
	var persona_hint:=Label.new()
	persona_hint.text="The NPC name and interaction radius are on the marker settings.\nStyle presets supply dialogue when fields are blank."
	persona_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	persona.add_child(persona_hint)
	var jobs_scroll:=ScrollContainer.new()
	jobs_scroll.name="Contracts & Rewards"
	jobs_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(jobs_scroll)
	var jobs:=VBoxContainer.new()
	jobs.custom_minimum_size.x=445
	jobs.add_theme_constant_override("separation",7)
	jobs_scroll.add_child(jobs)
	_caption(jobs,"CONTRACTS / EACH HAS A PERMANENT SAVE ID")
	job_picker=OptionButton.new()
	jobs.add_child(job_picker)
	job_picker.item_selected.connect(_change_job)
	var actions:=HBoxContainer.new()
	jobs.add_child(actions)
	var add:=Button.new()
	add.text="New job"
	add.pressed.connect(_add_job)
	actions.add_child(add)
	var duplicate:=Button.new()
	duplicate.text="Duplicate"
	duplicate.pressed.connect(_duplicate_job)
	actions.add_child(duplicate)
	var remove:=Button.new()
	remove.text="Delete"
	remove.pressed.connect(_delete_job)
	actions.add_child(remove)
	var ordering:=HBoxContainer.new()
	jobs.add_child(ordering)
	var up:=Button.new()
	up.text="Move up"
	up.pressed.connect(func():_move_job(-1))
	ordering.add_child(up)
	var down:=Button.new()
	down.text="Move down"
	down.pressed.connect(func():_move_job(1))
	ordering.add_child(down)
	_caption(jobs,"JOB TITLE")
	title_input=LineEdit.new()
	title_input.max_length=80
	jobs.add_child(title_input)
	_caption(jobs,"MISSION BRIEFING")
	job_description_input=TextEdit.new()
	job_description_input.custom_minimum_size.y=82
	job_description_input.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	jobs.add_child(job_description_input)
	type_input=_choice(jobs,"Mission type",Rules.KINDS)
	type_input.item_selected.connect(_on_kind_changed)
	difficulty_input=_choice(jobs,"Difficulty",Rules.DIFFICULTIES)
	var preset:=Button.new()
	preset.text="Apply suggested rewards for difficulty"
	preset.tooltip_text="Overrides reward values and heat, but keeps the job ID, targets and mission description."
	preset.pressed.connect(_apply_difficulty_preset)
	jobs.add_child(preset)
	dropoff_input=_choice(jobs,"Getaway / delivery destination",[])
	target_input=_choice(jobs,"Robbery target (robbery jobs only)",[])
	repeat_input=CheckBox.new()
	repeat_input.text="Repeatable contract"
	repeat_input.button_pressed=true
	jobs.add_child(repeat_input)
	_caption(jobs,"MISSION OBJECTIVES")
	arrival_radius_input=_number(jobs,"Arrival / drop-off radius (6-30 m)",6,30,12)
	robbery_wait_input=_number(jobs,"Robbery crew wait (3-30 seconds)",3,30,7)
	_caption(jobs,"REWARDS & HEAT")
	cash_input=_number(jobs,"Cash reward ($)",0,10000,550)
	player_xp_input=_number(jobs,"Driver XP reward",0,1500,180)
	car_xp_input=_number(jobs,"Vehicle XP reward",0,1200,120)
	rep_input=_number(jobs,"Underground reputation",0,30,0)
	wanted_input=_number(jobs,"Wanted level",0,5,0)
	duration_input=_number(jobs,"Time limit (seconds)",60,900,270)
	_caption(jobs,"UNLOCK REQUIREMENTS")
	level_input=_number(jobs,"Required driver level",1,100,1)
	required_rep_input=_number(jobs,"Required underground reputation",0,100000,0)
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.text="Place a drop-off marker first, then create your contract."
	jobs.add_child(status)
	_show_selected_controls(false)

func _show_selected_controls(enabled: bool) -> void:
	for element in [title_input,job_description_input,type_input,difficulty_input,dropoff_input,target_input,
			repeat_input,arrival_radius_input,robbery_wait_input,cash_input,player_xp_input,car_xp_input,rep_input,
			wanted_input,duration_input,level_input,required_rep_input]:
		if element is LineEdit:
			(element as LineEdit).editable=enabled
		elif element is SpinBox:
			(element as SpinBox).editable=enabled
		elif element is TextEdit:
			(element as TextEdit).editable=enabled
		elif element is OptionButton:
			(element as OptionButton).disabled=not enabled
		elif element is CheckBox:
			(element as CheckBox).disabled=not enabled
	target_input.visible=enabled and _value(type_input)=="robbery"
	robbery_wait_input.visible=enabled and _value(type_input)=="robbery"
	status.visible=true

func _populate_locations(e) -> void:
	for input in [dropoff_input,target_input]:
		input.clear()
		input.add_item("Select a map marker")
		input.set_item_metadata(0,"")
	for item in e.authoring.doc.get("markers",[]):
		var kind:=str(item.get("type",""))
		if kind not in ["contract_dropoff","robbery_target"]:
			continue
		var menu: OptionButton=target_input if kind=="robbery_target" else dropoff_input
		menu.add_item(str(item.get("name","Destination"))+"  ["+str(item.get("id",""))+"]")
		menu.set_item_metadata(menu.item_count-1,str(item.get("id","")))

func open_for(e, marker: Dictionary) -> void:
	_reloading=true
	offers.clear()
	var info: Dictionary=marker.get("properties",{})
	for job in info.get("offers",[]):
		if job is Dictionary:
			offers.append(job.duplicate(true))
	_pick(style_input,str(info.get("contact_style","street")))
	role_input.text=str(info.get("contact_role",""))
	greeting_input.text=str(info.get("contact_greeting",""))
	bio_input.text=str(info.get("contact_bio",""))
	_populate_locations(e)
	selected_index=0 if not offers.is_empty() else -1
	_rebuild_picker()
	_load_selected()
	_reloading=false

func _rebuild_picker() -> void:
	job_picker.clear()
	if offers.is_empty():
		job_picker.add_item("No contracts configured")
	else:
		for job in offers:
			job_picker.add_item(str(job.get("title","New Job"))+" / "+str(job.get("kind","courier")).to_upper())
	if selected_index>=0 and selected_index<offers.size():
		job_picker.select(selected_index)
	else:
		job_picker.select(0)

func _load_selected() -> void:
	var enabled:=selected_index>=0 and selected_index<offers.size()
	_show_selected_controls(enabled)
	if not enabled:
		status.text="Add a contract and assign its dropoff on this map."
		return
	var offer: Dictionary=offers[selected_index]
	var kind:=str(offer.get("kind","courier"))
	title_input.text=str(offer.get("title","New Contract"))
	job_description_input.text=str(offer.get("description",""))
	_pick(type_input,kind)
	_pick(difficulty_input,str(offer.get("difficulty","rookie")))
	_pick(dropoff_input,str(offer.get("destination_marker_id","")))
	_pick(target_input,str(offer.get("robbery_marker_id","")))
	repeat_input.button_pressed=bool(offer.get("repeatable",true))
	arrival_radius_input.value=int(offer.get("arrival_radius_m",12))
	robbery_wait_input.value=int(offer.get("robbery_hold_seconds",7))
	var rewards: Dictionary=Rules.configured_reward(kind,offer)
	cash_input.value=int(rewards.cash)
	player_xp_input.value=int(rewards.player_xp)
	car_xp_input.value=int(rewards.car_xp)
	rep_input.value=int(rewards.underground_rep)
	wanted_input.value=Rules.configured_wanted(kind,offer)
	duration_input.value=Rules.configured_time(kind,offer)
	level_input.value=int(offer.get("required_player_level",1))
	required_rep_input.value=int(offer.get("required_underground_rep",0))
	target_input.visible=kind=="robbery"
	robbery_wait_input.visible=kind=="robbery"
	status.text="Job ID: "+str(offer.get("id",""))+" — stable for saved career progress."

func _commit_selected() -> void:
	if _reloading or selected_index<0 or selected_index>=offers.size():
		return
	var offer: Dictionary=offers[selected_index]
	offer.title=title_input.text.strip_edges()
	var detail:=job_description_input.text.strip_edges()
	if detail.is_empty():offer.erase("description")
	else:offer.description=detail
	offer.kind=_value(type_input)
	offer.difficulty=_value(difficulty_input)
	offer.repeatable=repeat_input.button_pressed
	offer.destination_marker_id=_value(dropoff_input)
	if offer.kind=="robbery":
		offer.robbery_marker_id=_value(target_input)
	else:
		offer.erase("robbery_marker_id")
	offer.cash=int(cash_input.value)
	offer.player_xp=int(player_xp_input.value)
	offer.car_xp=int(car_xp_input.value)
	offer.underground_rep=int(rep_input.value)
	offer.wanted_level=int(wanted_input.value)
	offer.time_limit_seconds=int(duration_input.value)
	offer.arrival_radius_m=int(arrival_radius_input.value)
	if offer.kind=="robbery":offer.robbery_hold_seconds=int(robbery_wait_input.value)
	else:offer.erase("robbery_hold_seconds")
	offer.required_player_level=int(level_input.value)
	offer.required_underground_rep=int(required_rep_input.value)
	offers[selected_index]=offer

func _change_job(index: int) -> void:
	if _reloading:return
	_commit_selected()
	selected_index=index
	_load_selected()

func _on_kind_changed(_index: int) -> void:
	if _reloading or selected_index<0:return
	var kind:=_value(type_input)
	var rewards: Dictionary=Rules.reward(kind)
	cash_input.value=int(rewards.cash)
	player_xp_input.value=int(rewards.player_xp)
	car_xp_input.value=int(rewards.car_xp)
	rep_input.value=int(rewards.underground_rep)
	wanted_input.value=Rules.wanted_level(kind)
	duration_input.value=Rules.time_limit(kind)
	target_input.visible=kind=="robbery"
	robbery_wait_input.visible=kind=="robbery"

func _add_job() -> void:
	_commit_selected()
	if offers.size()>=Rules.MAX_OFFERS:
		status.text="Maximum eight contracts per contact."
		return
	var number:=1
	var used: Dictionary={}
	for offer in offers:
		used[str(offer.get("id",""))]=true
	while used.has("job_%d"%number):
		number+=1
	var target_id:=_value(dropoff_input)
	if target_id.is_empty() and dropoff_input.item_count>1:
		target_id=str(dropoff_input.get_item_metadata(1))
	if target_id.is_empty():
		status.text="Place a contract drop-off marker before creating a job."
		return
	var job:=Rules.configured_reward("courier",{})
	job.id="job_%d"%number
	job.title="New Driving Contract"
	job.kind="courier"
	job.difficulty="rookie"
	job.destination_marker_id=target_id
	job.repeatable=true
	job.arrival_radius_m=12
	job.wanted_level=0
	job.time_limit_seconds=270
	job.required_player_level=1
	job.required_underground_rep=0
	offers.append(job)
	selected_index=offers.size()-1
	_reloading=true
	_rebuild_picker()
	_load_selected()
	_reloading=false

func _duplicate_job() -> void:
	_commit_selected()
	if selected_index<0 or selected_index>=offers.size() or offers.size()>=Rules.MAX_OFFERS:
		status.text="Select a job to duplicate (maximum eight)."
		return
	var source: Dictionary=offers[selected_index]
	var copy: Dictionary=source.duplicate(true)
	var number:=1
	var used: Dictionary={}
	for offer in offers:used[str(offer.get("id",""))]=true
	while used.has("job_%d"%number):number+=1
	copy.id="job_%d"%number
	copy.title=str(source.get("title","Contract")).substr(0,73)+" Copy"
	offers.insert(selected_index+1,copy)
	selected_index+=1
	_reloading=true
	_rebuild_picker()
	_load_selected()
	_reloading=false

func _move_job(direction: int) -> void:
	_commit_selected()
	var next_index:=selected_index+direction
	if selected_index<0 or next_index<0 or next_index>=offers.size():return
	var current: Dictionary=offers[selected_index]
	offers[selected_index]=offers[next_index]
	offers[next_index]=current
	selected_index=next_index
	_reloading=true
	_rebuild_picker()
	_load_selected()
	_reloading=false

func _apply_difficulty_preset() -> void:
	if selected_index<0 or selected_index>=offers.size():return
	var difficulty:=_value(difficulty_input)
	var base:=Rules.configured_reward(_value(type_input),{})
	var multiplier: float=float({"rookie":0.7,"amateur":1.0,"pro":1.45,"elite":1.85}.get(difficulty,1.0))
	for pair in [[cash_input,"cash",10000],[player_xp_input,"player_xp",1500],
			[car_xp_input,"car_xp",1200],[rep_input,"underground_rep",30]]:
		var spin: SpinBox=pair[0]
		spin.value=mini(int(pair[2]),roundi(float(base.get(pair[1],0))*multiplier))
	var starting_heat:=Rules.wanted_level(_value(type_input))
	var heat_offset: int=int({"rookie":-1,"amateur":0,"pro":1,"elite":2}.get(difficulty,0))
	wanted_input.value=clampi(starting_heat+heat_offset,0,5)
	level_input.value={"rookie":1,"amateur":8,"pro":20,"elite":40}.get(difficulty,1)
	status.text="Applied "+difficulty+" values. Job ID, destinations and description remain unchanged."

func validation_errors(contact: Dictionary, available: Array) -> Array[String]:
	_commit_selected()
	var map_markers: Dictionary={}
	for marker in available:
		if marker is Dictionary:
			map_markers[str(marker.get("id",""))]=marker
	var candidate: Dictionary=contact.duplicate(true)
	var props: Dictionary=candidate.get("properties",{}).duplicate(true)
	props.merge(save_fields(),true)
	candidate["properties"]=props
	map_markers[str(candidate.get("id",""))]=candidate
	var errors: Array[String]=[]
	for offer in offers:
		var title_value:=str(offer.get("title","Contract"))
		if not Rules.valid_offer(offer,candidate,map_markers):
			errors.append(title_value+": check job title, rewards, target/drop-off links and 100m spacing.")
	if not Rules.valid_contact(candidate,map_markers):
		if errors.is_empty() and not offers.is_empty():
			errors.append("Duplicate job IDs or invalid contract data.")
	return errors

func _delete_job() -> void:
	if selected_index<0 or selected_index>=offers.size():
		return
	offers.remove_at(selected_index)
	selected_index=mini(selected_index,offers.size()-1)
	_reloading=true
	_rebuild_picker()
	_load_selected()
	_reloading=false

func save_fields() -> Dictionary:
	_commit_selected()
	return {
		"contact_style":_value(style_input),
		"contact_role":role_input.text.strip_edges(),
		"contact_greeting":greeting_input.text.strip_edges(),
		"contact_bio":bio_input.text.strip_edges(),
		"offers":offers.duplicate(true)
	}
