extends Node
const Rules=preload("res://scripts/world/living_world_rules.gd")
const Objective=preload("res://scripts/world/objective_road_layer.gd")
const PPM:=20.0
var host: Node
var world: Node2D
var player: VehicleController2D
var traffic: Node
var garage: Node
var markers: Node
var persist:=true
var seconds:=Rules.START
var seed_value:=1847
var save_path: String=""
var save_clock:=0.0
var ui_clock:=0.0
var light: CanvasModulate
var canvas: CanvasLayer
var clock_label: Label
var rest_button: Button
var dialog: AcceptDialog
var rest_status: Label
var home: Dictionary={}
var event_slot: int=-1
var event: Dictionary={}
var original_rain:=0.0
var _closing:=false

func _ready() -> void:
	name="LivingWorld"
	process_mode=Node.PROCESS_MODE_ALWAYS
	var identity:=str(world.data.get("editor_world_id",world.data.get("name","morrow-coast")))
	save_path="user://living-world-"+identity.sha256_text().left(24)+".cfg"
	seed_value=int(world.data.get("seed",1847))+int(identity.hash())
	original_rain=float(world.get("rain_intensity"))
	if persist:
		var config:=ConfigFile.new()
		if config.load(save_path)==OK:
			var raw: Variant=config.get_value("world","seconds",Rules.START)
			if Rules.valid_time(raw):seconds=float(raw)
	world.set("living_world",self)
	_find_home()
	light=CanvasModulate.new();light.name="WorldDaylight";host.add_child(light)
	canvas=CanvasLayer.new();canvas.layer=7;add_child(canvas)
	clock_label=Label.new()
	clock_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	clock_label.position=Vector2(-150,8)
	clock_label.custom_minimum_size=Vector2(300,24)
	clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	clock_label.add_theme_color_override("font_color",Color("#ecf1f6"))
	clock_label.add_theme_color_override("font_shadow_color",Color("#172027"))
	clock_label.add_theme_constant_override("shadow_offset_x",1)
	clock_label.add_theme_constant_override("shadow_offset_y",2)
	canvas.add_child(clock_label)
	rest_button=Button.new();rest_button.text="REST / SKIP TIME"
	rest_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	rest_button.position=Vector2(-100,-84)
	rest_button.custom_minimum_size=Vector2(200,36)
	rest_button.visible=false;rest_button.pressed.connect(open_rest)
	canvas.add_child(rest_button)
	dialog=AcceptDialog.new();dialog.title="Rest at home or garage"
	dialog.ok_button_text="Cancel";dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	dialog.confirmed.connect(_close_rest)
	dialog.canceled.connect(_close_rest)
	add_child(dialog)
	var panel:=VBoxContainer.new();panel.custom_minimum_size=Vector2(340,230);dialog.add_child(panel)
	rest_status=Label.new();rest_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(rest_status)
	for hours in [1,3,6,12]:
		var button:=Button.new();button.text="Wait %d hour%s"%[hours,"" if hours==1 else "s"]
		button.pressed.connect(_skip.bind(float(hours)*3600.0));panel.add_child(button)
	for target in [6,12,18,0]:
		var button:=Button.new();button.text="Rest until %02d:00"%target
		button.pressed.connect(_skip_until.bind(target));panel.add_child(button)
	_refresh()

func _shared() -> bool:
	var online: Node=get_node_or_null("/root/OnlineSession")
	if is_instance_valid(online) and (bool(online.get("active")) or bool(online.get("joining"))):return true
	var split: Node=host.get("local_split_screen")
	return is_instance_valid(split) and bool(split.get("active"))

func _busy() -> bool:
	if is_instance_valid(markers) and bool(markers.call("_is_busy")):return true
	for race in get_tree().get_nodes_in_group("streetbound_race"):
		if str(race.get("state")) in ["countdown","running"]:return true
	var police: Node=host.get("police_pursuit")
	if is_instance_valid(police) and (int(police.get("wanted_level"))>0 or float(police.get("bust_timer"))>0.0):return true
	var jobs: Node=host.get("driving_contracts")
	return is_instance_valid(jobs) and not (jobs.get("active") as Dictionary).is_empty()

func _find_home() -> void:
	# Stock map has one designated residence near the player-owned Laurel
	# garage. Never grant access from every arbitrary house.
	if not is_instance_valid(garage) or not bool(garage.get("available")):return
	var origin: Vector2=garage.global_position/PPM
	var best:=150.0
	for prop in world.data.get("props",[]):
		if str(prop.get("kind","")) not in ["house","coastal_house","lodge"] or prop.get("p",[]).size()!=2:continue
		var p:=Vector2(float(prop.p[0]),float(prop.p[1]))
		var distance:=origin.distance_to(p)
		if distance<best:
			best=distance;home={"point":p,"radius":22.0}

func rest_location() -> String:
	if not is_instance_valid(player) or player.road_layer!=0:return ""
	if is_instance_valid(garage) and bool(garage.call("can_switch")):return "Laurel garage"
	if is_instance_valid(markers):
		for marker in markers.get("markers"):
			if str(marker.type) not in ["home","garage"] or not bool(markers.call("_enabled",marker)):continue
			if not Objective.matches(player,Objective.marker_layer(marker)):continue
			var p:=Vector2(float(marker.x),float(marker.y))
			if player.global_position.distance_to(p*PPM)/PPM<=float(marker.get("properties",{}).get("radius_m",12.0)):
				return str(marker.get("name","Home / garage"))
	if not home.is_empty() and player.global_position.distance_to(Vector2(home.point)*PPM)/PPM<=float(home.radius):
		return "Laurel residence"
	return ""

func _allowed() -> bool:
	return is_instance_valid(player) and Rules.can_rest(player.linear_velocity.length()<=1.0,not rest_location().is_empty(),_busy(),_shared())

func open_rest() -> void:
	if get_tree().paused or not _allowed():return
	rest_status.text=rest_location()+"\n"+Rules.clock_text(seconds)+"\nTime skip does not refill fuel, repair your car, pay rewards or clear cooldowns."
	dialog.popup_centered()
	get_tree().paused=true

func _close_rest() -> void:
	if _closing:return
	_closing=true
	dialog.hide()
	get_tree().paused=false
	_closing=false

func _skip_until(target: int) -> void:
	_skip(Rules.until_hour(seconds,target))

func _skip(amount: float) -> void:
	if not dialog.visible or not _allowed() or amount<=0.0 or amount>Rules.DAY:return
	var previous:=seconds
	seconds=minf(Rules.MAX_TIME,seconds+amount)
	if not _save():
		seconds=previous;rest_status.text="Unable to save game time.";return
	_close_rest()
	event_slot=-1
	_refresh()

func _save() -> bool:
	if not persist:return true
	var config:=ConfigFile.new();config.set_value("world","seconds",seconds)
	return config.save(save_path)==OK

func _exit_tree() -> void:
	if not save_path.is_empty():_save()

func rain_at(point_px: Vector2) -> float:
	return original_rain if _shared() else Rules.rain(seconds,point_px/PPM,seed_value,original_rain)

func business_open(kind: String) -> bool:
	return _shared() or Rules.open_at(seconds,kind)

func rotation_clock() -> int:
	return -1 if _shared() else Rules.rotation_seconds(seconds)

func _process(dt: float) -> void:
	if get_tree().paused:return
	if not _shared():
		seconds=minf(Rules.MAX_TIME,seconds+dt*Rules.RATE)
		save_clock+=dt
		if save_clock>=30.0:save_clock=0.0;_save()
	ui_clock+=dt
	if ui_clock>=.25:
		ui_clock=0.0;_refresh()

func _refresh() -> void:
	var shared:=_shared()
	light.color=Color.WHITE if shared else Rules.tint(seconds)
	canvas.visible=not shared
	rest_button.visible=not get_tree().paused and _allowed()
	var wet:=rain_at(player.global_position)
	var weather: String="HEAVY RAIN" if wet>.65 else ("RAIN" if wet>.05 else "CLEAR")
	if is_instance_valid(traffic):
		traffic.set("time_density_factor",1.0 if shared else Rules.traffic_factor(seconds))
	_update_event(shared)
	var advisory: String=""
	if not event.is_empty():advisory="  /  "+str(event.title)
	clock_label.text=Rules.clock_text(seconds)+"  /  "+weather+advisory

## A bounded traffic diversion on a nearby, ordinary road. Never inject
## solid blockers into live physics, race checkpoints or police routes.
func _update_event(shared: bool) -> void:
	if not is_instance_valid(traffic):return
	if shared or _busy():
		traffic.set("event_closed_road",-1);event={};event_slot=-1;return
	var slot:=floori(seconds/7200.0)
	if slot==event_slot:return
	event_slot=slot
	event={}
	traffic.set("event_closed_road",-1)
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value+slot*293
	if rng.randf()>.45:return
	var graph: RefCounted=traffic.get("network")
	if graph==null:return
	var choices: Array[int]=[]
	for raw in graph.nearby_edges(player.global_position,400.0):
		var edge: Dictionary=graph.edges[int(raw)]
		if bool(edge.connector) or str(edge.kind) not in ["local","arterial","rural"] or absf(float(edge.get("start_height_m",0)))>.1 or absf(float(edge.get("end_height_m",0)))>.1:continue
		var path: PackedVector2Array=edge.points
		var distance:=path[path.size()/2].distance_to(player.global_position)/PPM
		if distance>=140.0 and distance<=400.0 and not choices.has(int(edge.road)):choices.append(int(edge.road))
	if choices.is_empty():return
	var road:=choices[rng.randi_range(0,choices.size()-1)]
	var title: String=["ROADWORK","DISABLED VEHICLE","ROAD INSPECTION"][rng.randi_range(0,2)]
	event={"road":road,"title":title+" / "+str(world.data.roads[road].name)}
	traffic.set("event_closed_road",road)
