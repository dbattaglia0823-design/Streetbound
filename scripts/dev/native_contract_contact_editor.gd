extends RefCounted
## Race-style, undoable job authoring attached to one roadside contact.
## The chosen target/dropoff, payouts, wanted heat and requirements are saved
## as map metadata, not editable through the live game HUD.
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
var fields: VBoxContainer
var style_input: OptionButton
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
	fields.add_theme_constant_override("separation",6)
	parent.add_child(fields)
	_caption(fields,"CONTRACT GIVER / APPEARANCE")
	style_input=_choice(fields,"NPC style",["street","business","mechanic","casual"])
	_caption(fields,"AVAILABLE JOBS / SELECT TO EDIT")
	job_picker=OptionButton.new()
	fields.add_child(job_picker)
	job_picker.item_selected.connect(_change_job)
	var action_bar:=HBoxContainer.new()
	fields.add_child(action_bar)
	var add:=Button.new()
	add.text="Add Contract"
	add.pressed.connect(_add_job)
	action_bar.add_child(add)
	var remove:=Button.new()
	remove.text="Delete Selected Contract"
	remove.pressed.connect(_delete_job)
	action_bar.add_child(remove)
	_caption(fields,"JOB TITLE")
	title_input=LineEdit.new()
	title_input.max_length=80
	fields.add_child(title_input)
	type_input=_choice(fields,"Mission type",Rules.KINDS)
	type_input.item_selected.connect(_on_kind_changed)
	difficulty_input=_choice(fields,"Difficulty",Rules.DIFFICULTIES)
	dropoff_input=_choice(fields,"Getaway / delivery destination",[])
	target_input=_choice(fields,"Robbery target (required for robbery jobs)",[])
	repeat_input=CheckBox.new()
	repeat_input.text="Repeatable contract"
	repeat_input.button_pressed=true
	fields.add_child(repeat_input)
	cash_input=_number(fields,"Cash reward ($)",0,10000,550)
	player_xp_input=_number(fields,"Driver XP reward",0,1500,180)
	car_xp_input=_number(fields,"Vehicle XP reward",0,1200,120)
	rep_input=_number(fields,"Underground reputation",0,30,0)
	wanted_input=_number(fields,"Wanted level",0,5,0)
	duration_input=_number(fields,"Time limit (seconds)",60,900,270)
	level_input=_number(fields,"Required driver level",1,100,1)
	required_rep_input=_number(fields,"Required underground reputation",0,100000,0)
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.text="Configure at least one connected road-accessible destination before saving."
	fields.add_child(status)
	_show_selected_controls(false)

func _show_selected_controls(enabled: bool) -> void:
	for element in [title_input,type_input,difficulty_input,dropoff_input,target_input,
			repeat_input,cash_input,player_xp_input,car_xp_input,rep_input,
			wanted_input,duration_input,level_input,required_rep_input]:
		if element is LineEdit:
			(element as LineEdit).editable=enabled
		elif element is SpinBox:
			(element as SpinBox).editable=enabled
		elif element is OptionButton:
			(element as OptionButton).disabled=not enabled
		elif element is CheckBox:
			(element as CheckBox).disabled=not enabled
	target_input.visible=enabled and _value(type_input)=="robbery"
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
	_pick(type_input,kind)
	_pick(difficulty_input,str(offer.get("difficulty","rookie")))
	_pick(dropoff_input,str(offer.get("destination_marker_id","")))
	_pick(target_input,str(offer.get("robbery_marker_id","")))
	repeat_input.button_pressed=bool(offer.get("repeatable",true))
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
	status.text="Job ID: "+str(offer.get("id",""))+" — stable for saved career progress."

func _commit_selected() -> void:
	if _reloading or selected_index<0 or selected_index>=offers.size():
		return
	var offer: Dictionary=offers[selected_index]
	offer.title=title_input.text.strip_edges()
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
	var job:=Rules.configured_reward("courier",{})
	job.id="job_%d"%number
	job.title="New Driving Contract"
	job.kind="courier"
	job.difficulty="rookie"
	job.destination_marker_id=""
	job.repeatable=true
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
	return {"contact_style":_value(style_input),"offers":offers.duplicate(true)}
