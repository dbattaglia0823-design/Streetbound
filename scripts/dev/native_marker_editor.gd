extends RefCounted
## Editor-specific, undoable marker configuration. Game play uses the same
## authored ID links, not approximated marker/category labels.
const Rules=preload("res://scripts/world/authored_marker_rules.gd")
var dialog: AcceptDialog
var marker_id: String=""
var name_input: LineEdit
var type_input: OptionButton
var enabled_input: CheckBox
var radius_input: SpinBox
var weight_input: SpinBox
var race_input: OptionButton
var required_input: OptionButton
var dealer_input: OptionButton
var feedback: Label
var edit_button: Button

func _text_label(parent: Node,label_text: String) -> void:
	var label:=Label.new()
	label.text=label_text
	parent.add_child(label)

func build(e,panel: Node) -> void:
	edit_button=e._btn("Edit Selected Marker...",panel,func():open_for(e,e.source_id))
	edit_button.tooltip_text="Edit spawn, race/mission links, fast travel, traffic and access conditions."
	dialog=AcceptDialog.new()
	dialog.name="EditMarkerDialog"
	dialog.title="Edit Game Marker"
	dialog.ok_button_text="Cancel"
	dialog.min_size=Vector2i(530,600)
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	e.add_child(dialog)
	var form:=VBoxContainer.new()
	form.custom_minimum_size=Vector2(490,535)
	form.add_theme_constant_override("separation",8)
	dialog.add_child(form)
	_text_label(form,"MARKER NAME")
	name_input=LineEdit.new()
	name_input.max_length=120
	form.add_child(name_input)
	type_input=e._options(form,"Marker type",Rules.TYPES)
	enabled_input=CheckBox.new()
	enabled_input.text="Enabled in gameplay"
	enabled_input.button_pressed=true
	form.add_child(enabled_input)
	radius_input=e._number(form,"Activation radius (metres)",4,50,12)
	radius_input.step=1
	weight_input=e._number(form,"Traffic spawn priority (1–10)",1,10,3)
	weight_input.step=1
	_text_label(form,"Linked race / mission (optional for waypoint markers)")
	race_input=OptionButton.new();form.add_child(race_input)
	_text_label(form,"Unlock after event victory (optional)")
	required_input=OptionButton.new();form.add_child(required_input)
	_text_label(form,"Linked dealership (optional; requires its real forecourt)")
	dealer_input=OptionButton.new();form.add_child(dealer_input)
	feedback=Label.new()
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.text="Mission markers start their linked race. Fast travel is available between unlocked travel markers while stationary."
	form.add_child(feedback)
	e._btn("Save Marker Settings",form,func():save(e))

func _select_value(control: OptionButton,value: String) -> void:
	for index in control.item_count:
		if str(control.get_item_metadata(index))==value:
			control.select(index)
			return
	control.select(0)

func _populate_links(e,source: Dictionary) -> void:
	for option in [race_input,required_input,dealer_input]:
		option.clear()
		option.add_item("None")
		option.set_item_metadata(0,"")
	for race in e.authoring.doc.get("races",[]):
		for option in [race_input,required_input]:
			option.add_item(str(race.name)+"  ["+str(race.id)+"]")
			option.set_item_metadata(option.item_count-1,str(race.id))
	for dealer in e.authoring.doc.get("dealerships",[]):
		dealer_input.add_item(str(dealer.get("name",dealer.id))+"  ["+str(dealer.id)+"]")
		dealer_input.set_item_metadata(dealer_input.item_count-1,str(dealer.id))
	var info: Dictionary=source.get("properties",{})
	_select_value(race_input,str(info.get("race_id","")))
	_select_value(required_input,str(info.get("required_race","")))
	_select_value(dealer_input,str(info.get("dealer_id","")))

func open_for(e,id: String) -> void:
	if not e.source_ready or e._editing_locked():return
	var marker: Dictionary=e.authoring.marker_at_id(id)
	if marker.is_empty():
		e._notice("Place or select a game marker to configure it.")
		return
	marker_id=id
	name_input.text=str(marker.get("name",""))
	_select_value(type_input,str(marker.get("type","custom")))
	var info: Dictionary=marker.get("properties",{})
	enabled_input.button_pressed=bool(info.get("enabled",true))
	radius_input.value=float(info.get("radius_m",12))
	weight_input.value=float(info.get("traffic_weight",3))
	_populate_links(e,marker)
	feedback.text="Mission markers launch the linked race; fast travel requires an unlocked marker and a stopped car."
	dialog.popup_centered()

func update(e) -> void:
	if not is_instance_valid(edit_button):return
	edit_button.disabled=e.authoring.marker_at_id(e.source_id).is_empty() or e._editing_locked()

func save(e) -> void:
	if e._editing_locked():return
	var source: Dictionary=e.authoring.marker_at_id(marker_id)
	if source.is_empty():return
	var info: Dictionary=source.get("properties",{}).duplicate(true)
	info["enabled"]=enabled_input.button_pressed
	info["radius_m"]=radius_input.value
	info["traffic_weight"]=int(weight_input.value)
	for pair in [[race_input,"race_id"],[required_input,"required_race"],[dealer_input,"dealer_id"]]:
		var chosen: String=str(pair[0].get_selected_metadata())
		if chosen.is_empty():info.erase(pair[1])
		else:info[pair[1]]=chosen
	if e.authoring.update_marker(marker_id,{
		"name":name_input.text.strip_edges(),
		"type":str(type_input.get_selected_metadata()),
		"properties":info
	}):
		e.source_id=marker_id
		e._refresh_authoring()
		dialog.hide()
		e._notice("Game marker saved. Undo restores its previous configuration.")
	else:
		feedback.text=e.authoring.last_error
