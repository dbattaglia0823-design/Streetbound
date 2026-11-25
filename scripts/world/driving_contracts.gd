extends Node2D
## Vehicle-only world contracts. No player avatars or building interiors.
## Uses authoritative map markers, the existing police pursuit, shared car
## collection and real road-route planner, rather than custom teleport jobs.
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
const PPM := 20.0
var player: VehicleController2D
var world: Node2D
var economy: Object
var police: Node2D
var marker_source: Node2D
var map_hud: CanvasLayer
var active: Dictionary = {}
var destination: Dictionary = {}
var robbery_target: Dictionary = {}
var offer_settings: Dictionary = {}
var stage := "delivery"
var robbery_progress := 0.0
var remaining_seconds := 0.0
var started_car_id := ""
var run_token := ""
var _run_sequence := 0
var notice := "NO ACTIVE CONTRACT"
var notice_seconds := 0.0
var hud_layer: CanvasLayer
var readout: Label
var abandon_button: Button

func _ready() -> void:
	name = "DrivingContracts"
	if not is_instance_valid(player) or not is_instance_valid(economy):
		return
	player.vehicle_reset.connect(_on_vehicle_reset)
	if is_instance_valid(police):
		police.connect("busted",Callable(self,"_on_police_busted"))
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 4
	add_child(hud_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 286)
	panel.custom_minimum_size = Vector2(360, 44)
	hud_layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	readout = Label.new()
	readout.add_theme_font_size_override("font_size", 13)
	column.add_child(readout)
	abandon_button = Button.new()
	abandon_button.text = "ABANDON CONTRACT"
	abandon_button.pressed.connect(abandon)
	abandon_button.visible = false
	column.add_child(abandon_button)
	readout.text = "DRIVING CONTRACTS / Visit a contract marker"

func _find_dropoff(id: String) -> Dictionary:
	if not is_instance_valid(marker_source):
		return {}
	for marker in marker_source.get("markers"):
		if str(marker.get("id","")) == id and str(marker.get("type","")) == "contract_dropoff":
			if marker_source.has_method("_enabled") and not bool(marker_source.call("_enabled", marker)):
				return {}
			return marker
	return {}

func _find_robbery_target(id: String) -> Dictionary:
	if not is_instance_valid(marker_source):
		return {}
	for item in marker_source.get("markers"):
		if str(item.get("id","")) == id and str(item.get("type","")) == "robbery_target":
			if marker_source.has_method("_enabled") and not bool(marker_source.call("_enabled",item)):
				return {}
			return item
	return {}

func offer_lock_reason(contact: Dictionary, offer: Dictionary) -> String:
	if not is_instance_valid(economy):
		return "CONTRACTS UNAVAILABLE"
	if int(economy.call("player_level")) < int(offer.get("required_player_level",1)):
		return "REQUIRES DRIVER LEVEL %d" % int(offer.get("required_player_level",1))
	if int(economy.get("underground_reputation")) < int(offer.get("required_underground_rep",0)):
		return "REQUIRES UNDERGROUND REP %d" % int(offer.get("required_underground_rep",0))
	var key := str(marker_source.get("world_id"))+"::"+str(contact.get("id",""))+"_"+str(offer.get("id",""))
	if not bool(offer.get("repeatable",true)) and int(economy.get("completed_driving_contracts").get(key,0)) > 0:
		return "CONTRACT COMPLETED"
	return ""

func try_start_offer(contact: Dictionary, selected: Dictionary) -> Dictionary:
	if not is_instance_valid(marker_source) or str(contact.get("type","")) != "contract_contact":
		return {"result":"invalid"}
	if not bool(marker_source.call("_enabled",contact)):
		return {"result":"locked","message":"This contact is unavailable"}
	var offered: bool = false
	for option in contact.get("properties",{}).get("offers",[]):
		if option is Dictionary and option == selected:
			offered = true
			break
	if not offered:
		return {"result":"invalid","message":"This contact does not offer that job"}
	var map_entries: Dictionary = {}
	for marker in marker_source.get("markers"):
		map_entries[str(marker.get("id",""))] = marker
	if not Rules.valid_offer(selected,contact,map_entries):
		return {"result":"invalid","message":"The contract needs valid targets and configured rewards"}
	var lock := offer_lock_reason(contact,selected)
	if not lock.is_empty():
		return {"result":"locked","message":lock}
	var props := {
		"contract_kind":str(selected.get("kind","courier")),
		"destination_marker_id":str(selected.get("destination_marker_id","")),
		"radius_m":clampf(float(contact.get("properties",{}).get("radius_m",12.0)),4.0,50.0)
	}
	if str(selected.get("kind","")) == "robbery":
		props["robbery_marker_id"] = str(selected.get("robbery_marker_id",""))
	var source := {"id":str(contact.get("id",""))+"_"+str(selected.get("id","")),
		"name":str(selected.get("title","Driving job")),
		"type":"contract","x":float(contact.get("x",0)),
		"y":float(contact.get("y",0)),"properties":props}
	return try_start(source,selected)

func _waypoints() -> Node:
	if not is_instance_valid(map_hud):
		return null
	var candidate: Node = map_hud.get("waypoints")
	return candidate if is_instance_valid(candidate) else null

func _road_accessible(position_m: Vector2) -> bool:
	if not is_instance_valid(world) or not world.has_method("nearest_road_at"):
		return false
	var road: Dictionary = world.call("nearest_road_at",position_m * PPM, 28.0)
	return not road.is_empty() and float(road.get("distance_to_center_m", INF)) <= 22.0

func try_start(source: Dictionary, authored_offer: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(player) or not is_instance_valid(economy) or not is_instance_valid(police):
		return {"result":"unavailable"}
	if not active.is_empty():
		return {"result":"busy","message":"Finish or abandon your active driving contract"}
	if int(police.get("wanted_level")) > 0:
		return {"result":"wanted","message":"Lose police before accepting another job"}
	if player.linear_velocity.length() > Rules.MAX_ARRIVAL_SPEED_MPS:
		return {"result":"moving","message":"Stop your car before accepting the contract"}
	if not is_instance_valid(marker_source) or not bool(marker_source.call("_enabled", source)):
		return {"result":"locked","message":"This contract is currently unavailable"}
	var props: Dictionary = source.get("properties",{})
	var target: Dictionary = _find_dropoff(str(props.get("destination_marker_id","")))
	if not Rules.valid_link(source, target):
		return {"result":"unlinked","message":"Place and link a dropoff marker at least 100 metres away"}
	var source_pos := Vector2(float(source.x), float(source.y))
	var kind := str(props.get("contract_kind","courier"))
	var robbery: Dictionary = {}
	if kind == "robbery":
		robbery = _find_robbery_target(str(props.get("robbery_marker_id","")))
		if robbery.is_empty():
			return {"result":"unlinked","message":"Robbery location is missing or disabled"}
	var next_stop: Dictionary = robbery if kind == "robbery" else target
	var target_pos := Vector2(float(next_stop.x),float(next_stop.y))
	if player.global_position.distance_to(source_pos * PPM) > clampf(
			float(props.get("radius_m",12.0)),4.0,50.0) * PPM:
		return {"result":"out_of_range"}
	if not _road_accessible(source_pos) or not _road_accessible(target_pos) or \
			(kind=="robbery" and not _road_accessible(Vector2(float(target.x),float(target.y)))):
		return {"result":"offroad","message":"The pickup and dropoff must be close to drivable roads"}
	var guide := _waypoints()
	if not is_instance_valid(guide):
		return {"result":"navigation_unavailable"}
	# A disconnected destination cannot be accepted as a completable job.
	var planner: RefCounted = guide.get("planner")
	if planner == null:
		return {"result":"navigation_unavailable"}
	var route: Dictionary = planner.call("plan",player.global_position / PPM,
		target_pos, Vector2.UP.rotated(player.rotation))
	if route.is_empty():
		return {"result":"unreachable","message":"No connected road route to that dropoff"}
	if not Rules.valid_kind(kind):
		return {"result":"invalid"}
	if kind=="robbery":
		var escape_route: Dictionary=planner.call("plan",target_pos,
			Vector2(float(target.x),float(target.y)),Vector2.UP)
		if escape_route.is_empty():
			return {"result":"unreachable","message":"Robbery drop-off is disconnected from the target"}
	var heat: int = Rules.configured_wanted(kind,authored_offer)
	if not bool(guide.call("set_destination",target_pos, str(next_stop.get("name","Contract destination")))):
		return {"result":"navigation_unavailable"}
	if heat > 0 and kind != "robbery" and not bool(police.call("start_pursuit",heat)):
		guide.call("clear_destination")
		return {"result":"police_unavailable","message":"Unable to begin getaway pursuit on this road"}
	_run_sequence += 1
	run_token = "job-%d-%d-%d" % [
		int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), _run_sequence]
	active = source.duplicate(true)
	destination = target.duplicate(true)
	robbery_target = robbery.duplicate(true)
	offer_settings = authored_offer.duplicate(true)
	stage = "robbery" if kind == "robbery" else "delivery"
	robbery_progress = 0.0
	started_car_id = str(economy.active_id)
	remaining_seconds = Rules.configured_time(kind,authored_offer)
	notice = "DRIVE TO " + str(next_stop.get("name","DESTINATION")).to_upper()
	notice_seconds = 4.0
	return {"result":"started","kind":kind,"destination":str(target.get("name","Destination"))}

func _clear_route() -> void:
	var guide := _waypoints()
	if not is_instance_valid(guide) or destination.is_empty():
		return
	if bool(guide.get("active")) and str(guide.get("destination_name")) in [
			str(destination.get("name","Contract destination")),
			str(robbery_target.get("name","Robbery target"))]:
		guide.call("clear_destination")

func _end(message: String) -> void:
	_clear_route()
	active.clear()
	destination.clear()
	robbery_target.clear()
	offer_settings.clear()
	stage = "delivery"
	robbery_progress = 0.0
	remaining_seconds = 0.0
	started_car_id = ""
	run_token = ""
	notice = message
	notice_seconds = 5.0

func _on_vehicle_reset() -> void:
	if not active.is_empty():
		_end("CONTRACT FAILED / VEHICLE RESET")

func _on_police_busted(_reason: String) -> void:
	if not active.is_empty():
		_end("CONTRACT FAILED / BUSTED")

func abandon() -> void:
	if not active.is_empty():
		_end("CONTRACT ABANDONED")

func _complete() -> void:
	if active.is_empty() or destination.is_empty():
		return
	var kind := str(active.get("properties",{}).get("contract_kind","courier"))
	var event_key := str(marker_source.get("world_id")) + "::" + str(active.get("id",""))
	var payout: Dictionary = economy.call("record_driving_contract",run_token, event_key, kind, offer_settings)
	if str(payout.get("result","")) == "completed":
		_end("JOB COMPLETE / +%s / +%d DRIVER XP / +%d STREET REP" % [
			economy.dollars(int(payout.get("cash",0))), int(payout.get("player_xp",0)),
			int(payout.get("underground_rep",0))])
	else:
		_end("JOB NOT PAID / " + str(payout.get("result","save_failed")))

func _physics_process(dt: float) -> void:
	if active.is_empty() or not is_instance_valid(player):
		return
	if dt <= 0.0:
		return
	if str(economy.active_id) != started_car_id:
		_end("CONTRACT FAILED / VEHICLE CHANGED")
		return
	if player.damage_drive_fraction <= 0.0 or player.fuel_drive_fraction <= 0.0:
		_end("CONTRACT FAILED / VEHICLE DISABLED")
		return
	if is_instance_valid(marker_source):
		for race in marker_source.get("races"):
			if is_instance_valid(race) and str(race.get("state")) in ["countdown","running"]:
				_end("CONTRACT FAILED / RACE STARTED")
				return
	remaining_seconds -= dt
	if remaining_seconds <= 0.0:
		_end("CONTRACT FAILED / TIME EXPIRED")
		return
	if is_instance_valid(police) and float(police.get("bust_timer")) > 0.0:
		_end("CONTRACT FAILED / BUSTED")
		return
	if stage == "robbery":
		var robbery_pos := Vector2(float(robbery_target.x),float(robbery_target.y)) * PPM
		var robbery_distance := player.global_position.distance_to(robbery_pos) / PPM
		if Rules.arrived(robbery_distance,player.linear_velocity.length()):
			robbery_progress += dt
		else:
			robbery_progress = 0.0
		if robbery_progress >= Rules.ROBBERY_HOLD_SECONDS:
			# Crew action happens inside the building; the player remains
			# inside the getaway vehicle throughout the timed handoff.
			var next_heat := Rules.configured_wanted("robbery",offer_settings)
			if next_heat > 0 and not bool(police.call("start_pursuit",next_heat)):
				_end("ROBBERY FAILED / NO POLICE ROUTE")
				return
			stage = "delivery"
			var guide := _waypoints()
			if is_instance_valid(guide):
				guide.call("set_destination",Vector2(float(destination.x),float(destination.y)),
					str(destination.get("name","Getaway dropoff")))
			notice = "CREW ON BOARD / EVADE POLICE"
			notice_seconds = 4.0
		return
	var dist_m := player.global_position.distance_to(
		Vector2(float(destination.x),float(destination.y)) * PPM) / PPM
	if not Rules.arrived(dist_m, player.linear_velocity.length()):
		return
	var kind := str(active.get("properties",{}).get("contract_kind","courier"))
	if int(police.get("wanted_level")) > 0:
		notice = "EVADE POLICE BEFORE DROP-OFF"
		notice_seconds = 1.5
		return
	_complete()

func _process(dt: float) -> void:
	if not is_instance_valid(readout):
		return
	notice_seconds = maxf(0.0, notice_seconds - dt)
	abandon_button.visible = not active.is_empty()
	if active.is_empty():
		readout.text = "DRIVING CONTRACTS / REP %d / " % int(economy.get("underground_reputation")) + \
			(notice if notice_seconds > 0.0 else "Find a job marker")
		return
	var kind := str(active.get("properties",{}).get("contract_kind","courier"))
	var dist_m := player.global_position.distance_to(
		Vector2(float(destination.x),float(destination.y)) * PPM) / PPM
	var objective := "WAIT FOR CREW %ds" % maxi(0,ceili(Rules.ROBBERY_HOLD_SECONDS-robbery_progress)) if stage=="robbery" else \
		("EVADE POLICE & DELIVER" if Rules.configured_wanted(kind,offer_settings) > 0 else "DELIVER")
	if stage=="robbery":
		dist_m = player.global_position.distance_to(
			Vector2(float(robbery_target.x),float(robbery_target.y)) * PPM) / PPM
	readout.text = "%s / %s / %dm / %ds" % [
		kind.to_upper(), objective, roundi(dist_m), ceili(remaining_seconds)]
	if notice_seconds > 0.0:
		readout.text += " / " + notice
