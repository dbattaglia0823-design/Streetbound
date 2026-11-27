extends Node2D
const ObjectiveLayer=preload("res://scripts/world/objective_road_layer.gd")
## Vehicle-only world contracts. No player avatars or building interiors.
## Uses authoritative map markers, the existing police pursuit, shared car
## collection and real road-route planner, rather than custom teleport jobs.
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
const PPM := 20.0
const HudStyle = preload("res://scripts/ui/driving_hud.gd")
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
var mission_crew: Array = []

func _crew_quote(offer: Dictionary) -> Dictionary:
	return economy.call("quote_crew",offer,mission_crew) if is_instance_valid(economy) and economy.has_method("quote_crew") else {}

func _robbery_hold(offer: Dictionary) -> float:
	return maxf(3.0,Rules.configured_robbery_hold(offer)*float(_crew_quote(offer).get("hold_factor",1.0)))

func _completed_lower(offer: Dictionary, progress: float) -> String:
	return Rules.completed_lower_risk(offer,progress,float(_crew_quote(offer).get("hold_factor",1.0)))

func _robbery_cash(offer: Dictionary) -> int:
	return int(_crew_quote(offer).get("cash",Rules.configured_reward("robbery",offer).cash))
var stage := "delivery"
var robbery_progress := 0.0
var early_finish_requested := false
var robbery_meter: ProgressBar
var robbery_status: Label
var early_finish_button: Button
var remaining_seconds := 0.0
var started_car_id := ""
var run_token := ""
var _run_sequence := 0
var notice := "NO ACTIVE CONTRACT"
var notice_seconds := 0.0
var hud_layer: CanvasLayer
var readout: Label
var status_host: VBoxContainer
var contract_panel: PanelContainer
var contract_title: Label
var deadline_bar: ProgressBar
var initial_seconds := 0.0
var abandon_button: Button

func _ready() -> void:
	name = "DrivingContracts"
	add_to_group("streetbound_contracts")
	if not is_instance_valid(player) or not is_instance_valid(economy):
		return
	player.vehicle_reset.connect(_on_vehicle_reset)
	if is_instance_valid(police):
		police.connect("busted",Callable(self,"_on_police_busted"))
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 4
	add_child(hud_layer)
	var parent: Node = status_host if is_instance_valid(status_host) else hud_layer
	contract_panel = HudStyle.status_card(parent,Color("#63d6da"))
	if not is_instance_valid(status_host):
		contract_panel.position = Vector2(16,140)
	var column := VBoxContainer.new()
	contract_panel.add_child(column)
	contract_title = HudStyle.status_text(column,"CONTRACT",11,Color("#63d6da"))
	readout = HudStyle.status_text(column,"",14,Color("#eaf2e8"))
	deadline_bar = HudStyle.status_bar(column,Color("#63d6da"))
	robbery_status = HudStyle.status_text(column,"",12,Color("#f2bd78"))
	robbery_status.hide()
	robbery_meter = HudStyle.status_bar(column,Color("#f2bd78"))
	robbery_meter.hide()
	early_finish_button = Button.new()
	early_finish_button.text = "FINISH LOWER REWARD"
	early_finish_button.visible = false
	early_finish_button.pressed.connect(_request_early_finish)
	column.add_child(early_finish_button)
	abandon_button = Button.new()
	abandon_button.text = "ABANDON CONTRACT"
	abandon_button.pressed.connect(abandon)
	abandon_button.visible = false
	column.add_child(abandon_button)
	readout.text = ""

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

func projected_payload_mass(offer: Dictionary) -> float:
	var payload := Rules.robbery_payload(offer)
	var factor := 1.0
	if is_instance_valid(player) and player.config != null:
		factor = player.config.mission_cargo_mass_factor
	return float(payload.x)*75.0 + float(payload.y)*clampf(factor,0.8,1.0)

func vehicle_requirement(offer: Dictionary) -> String:
	if Rules.robbery_payload(offer) == Vector2i.ZERO:
		return ""
	if not is_instance_valid(player) or player.config == null:
		return "VEHICLE UNAVAILABLE"
	return Rules.capacity_reason(offer,player.config.seating_capacity,player.config.cargo_capacity_kg)

func robbery_availability(offer: Dictionary) -> Dictionary:
	if not is_instance_valid(economy) or not is_instance_valid(marker_source):
		return {}
	return economy.call("robbery_availability",str(marker_source.get("world_id")),offer)

func offer_lock_reason(contact: Dictionary, offer: Dictionary) -> String:
	if not is_instance_valid(economy):
		return "CONTRACTS UNAVAILABLE"
	if int(economy.call("player_level")) < int(offer.get("required_player_level",1)):
		return "REQUIRES DRIVER LEVEL %d" % int(offer.get("required_player_level",1))
	if int(economy.get("underground_reputation")) < Rules.required_rep(offer):
		return "REQUIRES REP %d / %d MORE" % [Rules.required_rep(offer),Rules.required_rep(offer)-int(economy.get("underground_reputation"))]
	var prerequisite:=str(offer.get("required_race_id",""))
	if not prerequisite.is_empty():
		var event_key:=str(marker_source.get("world_id"))+"::"+prerequisite
		if int(economy.call("completed_event_count",event_key))<=0:
			var race_title:=prerequisite
			for race in marker_source.get("races"):
				if is_instance_valid(race) and race.get("definition") is Dictionary and str(race.get("definition").get("id",""))==prerequisite:
					race_title=str(race.get("race_title"));break
			return "WIN "+race_title.to_upper()+" FIRST"
	var key := str(marker_source.get("world_id"))+"::"+str(contact.get("id",""))+"_"+str(offer.get("id",""))
	if not bool(offer.get("repeatable",true)) and int(economy.get("completed_driving_contracts").get(key,0)) > 0:
		return "CONTRACT COMPLETED"
	return Rules.availability_text(robbery_availability(offer)) if not Rules.robbery_profile(offer).is_empty() else ""

func try_start_offer(contact: Dictionary, selected: Dictionary, risk: String = "standard", use_hired_crew: bool = false) -> Dictionary:
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
		"radius_m":clampf(float(contact.get("properties",{}).get("radius_m",12.0)),4.0,50.0),
		"road_layer":ObjectiveLayer.marker_layer(contact)
	}
	if str(selected.get("kind","")) == "robbery":
		props["robbery_marker_id"] = str(selected.get("robbery_marker_id",""))
	var source := {"id":str(contact.get("id",""))+"_"+str(selected.get("id","")),
		"name":str(selected.get("title","Driving job")),
		"type":"contract","x":float(contact.get("x",0)),
		"y":float(contact.get("y",0)),"properties":props}
	var chosen := selected.duplicate(true)
	if not Rules.robbery_profile(selected).is_empty():
		chosen = Rules.with_robbery_risk(selected,risk)
		if chosen.is_empty():
			return {"result":"invalid","message":"Invalid robbery risk selection"}
	elif risk != "standard":
		return {"result":"invalid","message":"This contract does not support risk selection"}
	var capacity_lock := vehicle_requirement(chosen)
	if not capacity_lock.is_empty():
		return {"result":"vehicle_capacity","message":capacity_lock}
	var ids: Array = economy.call("crew_for_offer",chosen) if use_hired_crew and not Rules.robbery_profile(chosen).is_empty() else []
	return try_start(source,chosen,ids)

## Career navigation uses the real active contact, not a fabricated waypoint.
func career_contact() -> Dictionary:
	if not is_instance_valid(marker_source):
		return {}
	for item in marker_source.get("markers"):
		if str(item.get("id","")) == "marker-campaign-robbery-contact" and str(item.get("type","")) == "contract_contact" and bool(marker_source.call("_enabled",item)):
			return item.duplicate(true)
	return {}

func _waypoints() -> Node:
	if not is_instance_valid(map_hud):
		return null
	var candidate: Node = map_hud.get("waypoints")
	return candidate if is_instance_valid(candidate) else null

func _road_accessible(position_m: Vector2, layer: int=0) -> bool:
	if layer!=0:return ObjectiveLayer.supported(world,position_m,layer)
	if not is_instance_valid(world) or not world.has_method("nearest_road_at"):
		return false
	var road: Dictionary = world.call("nearest_road_at",position_m * PPM, 28.0)
	return not road.is_empty() and float(road.get("distance_to_center_m", INF)) <= 22.0

func try_start(source: Dictionary, authored_offer: Dictionary = {}, crew_ids: Array = []) -> Dictionary:
	if not is_instance_valid(player) or not is_instance_valid(economy) or not is_instance_valid(police):
		return {"result":"unavailable"}
	if not active.is_empty():
		return {"result":"busy","message":"Finish or abandon your active driving contract"}
	for race in get_tree().get_nodes_in_group("streetbound_race"):
		if str(race.get("state")) in ["countdown","running"]:
			return {"result":"busy","message":"Finish the active race first"}
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
	if not Rules.valid_robbery_profile(kind,authored_offer):
		return {"result":"invalid","message":"Invalid robbery profile or risk"}
	if not Rules.robbery_profile(authored_offer).is_empty() and int(economy.get("underground_reputation")) < Rules.required_rep(authored_offer):
		return {"result":"locked","message":"Insufficient underground reputation"}
	if not crew_ids.is_empty() and (kind!="robbery" or (economy.call("quote_crew",authored_offer,crew_ids) as Dictionary).is_empty()):
		return {"result":"invalid_crew","message":"Selected crew is unavailable"}
	var capacity_lock := vehicle_requirement(authored_offer)
	if not capacity_lock.is_empty():
		return {"result":"vehicle_capacity","message":capacity_lock}
	var robbery: Dictionary = {}
	if kind == "robbery":
		robbery = _find_robbery_target(str(props.get("robbery_marker_id","")))
		if robbery.is_empty():
			return {"result":"unlinked","message":"Robbery location is missing or disabled"}
		if not Rules.robbery_profile(authored_offer).is_empty():
			if str(robbery.get("id","")) != str(authored_offer.get("robbery_marker_id","")):
				return {"result":"invalid","message":"Robbery target mismatch"}
			var availability := robbery_availability(authored_offer)
			if not bool(availability.get("available",false)):
				return {"result":"unavailable","message":Rules.availability_text(availability)}
	var next_stop: Dictionary = robbery if kind == "robbery" else target
	var target_pos := Vector2(float(next_stop.x),float(next_stop.y))
	if not ObjectiveLayer.matches(player,ObjectiveLayer.marker_layer(source)) or player.global_position.distance_to(source_pos * PPM) > clampf(
			float(props.get("radius_m",12.0)),4.0,50.0) * PPM:
		return {"result":"out_of_range"}
	if not _road_accessible(source_pos,ObjectiveLayer.marker_layer(source)) or not _road_accessible(target_pos,ObjectiveLayer.marker_layer(next_stop)) or \
			(kind=="robbery" and not _road_accessible(Vector2(float(target.x),float(target.y)),ObjectiveLayer.marker_layer(target))):
		return {"result":"offroad","message":"The pickup and dropoff must be close to drivable roads"}
	var guide := _waypoints()
	if not is_instance_valid(guide):
		return {"result":"navigation_unavailable"}
	# A disconnected destination cannot be accepted as a completable job.
	var planner: RefCounted = guide.get("planner")
	if planner == null:
		return {"result":"navigation_unavailable"}
	var route: Dictionary = planner.call("plan",player.global_position / PPM,
		target_pos, Vector2.UP.rotated(player.rotation),"","",player.road_layer,ObjectiveLayer.marker_layer(next_stop))
	if route.is_empty():
		return {"result":"unreachable","message":"No connected road route to that dropoff"}
	if not Rules.valid_kind(kind):
		return {"result":"invalid"}
	if kind=="robbery":
		var escape_route: Dictionary=planner.call("plan",target_pos,
			Vector2(float(target.x),float(target.y)),Vector2.UP,"","",ObjectiveLayer.marker_layer(robbery),ObjectiveLayer.marker_layer(target))
		if escape_route.is_empty():
			return {"result":"unreachable","message":"Robbery drop-off is disconnected from the target"}
	var heat: int = Rules.configured_wanted(kind,authored_offer)
	if not bool(guide.call("set_destination",target_pos, str(next_stop.get("name","Contract destination")),ObjectiveLayer.marker_layer(next_stop))):
		return {"result":"navigation_unavailable"}
	if heat > 0 and kind != "robbery" and not bool(police.call("start_pursuit",heat)):
		guide.call("clear_destination")
		return {"result":"police_unavailable","message":"Unable to begin getaway pursuit on this road"}
	if not Rules.robbery_profile(authored_offer).is_empty():
		var reservation: String = economy.call("reserve_robbery_location",str(marker_source.get("world_id")),authored_offer)
		if reservation != "ready":
			guide.call("clear_destination")
			return {"result":reservation,"message":"LOCATION UNAVAILABLE / "+reservation.to_upper().replace("_"," ")}
	_run_sequence += 1
	run_token = "job-%d-%d-%d" % [
		int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), _run_sequence]
	active = source.duplicate(true)
	destination = target.duplicate(true)
	robbery_target = robbery.duplicate(true)
	offer_settings = authored_offer.duplicate(true)
	mission_crew = crew_ids.duplicate()
	stage = "robbery" if kind == "robbery" else "delivery"
	robbery_progress = 0.0
	early_finish_requested = false
	started_car_id = str(economy.active_id)
	remaining_seconds = Rules.configured_time(kind,authored_offer)*float(_crew_quote(authored_offer).get("time_factor",1.0))
	initial_seconds = remaining_seconds
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
	if is_instance_valid(player):
		player.clear_mission_payload()
	_clear_route()
	active.clear()
	destination.clear()
	robbery_target.clear()
	offer_settings.clear()
	mission_crew.clear()
	stage = "delivery"
	robbery_progress = 0.0
	early_finish_requested = false
	remaining_seconds = 0.0
	initial_seconds = 0.0
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

func _exit_tree() -> void:
	if is_instance_valid(player) and not active.is_empty():
		player.clear_mission_payload()

func _request_early_finish() -> void:
	if not active.is_empty() and stage == "robbery":
		early_finish_requested = true

func _complete() -> void:
	if active.is_empty() or destination.is_empty() or stage != "delivery":
		return
	var kind := str(active.get("properties",{}).get("contract_kind","courier"))
	var event_key := str(marker_source.get("world_id")) + "::" + str(active.get("id",""))
	var payout: Dictionary = economy.call("record_driving_contract",run_token, event_key, kind, offer_settings,mission_crew)
	if str(payout.get("result","")) == "completed":
		var result_text := "JOB COMPLETE / +%s / +%d DRIVER XP / +%d STREET REP" % [
			economy.dollars(int(payout.get("cash",0))), int(payout.get("player_xp",0)),
			int(payout.get("underground_rep",0))]
		if int(payout.get("crew_count",0))>0:
			result_text += "\nCREW CUT %s / +%d XP EACH" % [economy.dollars(int(payout.crew_cut)),int(payout.crew_xp)]
		var promotion := str(payout.get("rank_up",""))
		if not promotion.is_empty():
			result_text += "\n"+promotion
		_end(result_text)
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
		if ObjectiveLayer.matches(player,ObjectiveLayer.marker_layer(robbery_target)) and Rules.arrived(robbery_distance,player.linear_velocity.length(),
				Rules.configured_arrival_radius(offer_settings)):
			robbery_progress += dt
		else:
			robbery_progress = 0.0
		if early_finish_requested:
			early_finish_requested = false
			var lower := _completed_lower(offer_settings,robbery_progress)
			if not lower.is_empty():
				offer_settings = Rules.with_robbery_risk(offer_settings,lower)
		if robbery_progress >= _robbery_hold(offer_settings):
			# Crew action happens inside the building; the player remains
			# inside the getaway vehicle throughout the timed handoff.
			var payload := Rules.robbery_payload(offer_settings)
			if payload != Vector2i.ZERO and not player.load_mission_payload(payload.x,float(payload.y)):
				_end("ROBBERY FAILED / VEHICLE CAPACITY")
				return
			var next_heat := Rules.configured_wanted("robbery",offer_settings)
			if next_heat > 0 and not bool(police.call("start_pursuit",next_heat)):
				_end("ROBBERY FAILED / NO POLICE ROUTE")
				return
			stage = "delivery"
			var guide := _waypoints()
			if is_instance_valid(guide):
				guide.call("set_destination",Vector2(float(destination.x),float(destination.y)),
					str(destination.get("name","Getaway dropoff")),ObjectiveLayer.marker_layer(destination))
			notice = "CREW ON BOARD / EVADE POLICE"
			notice_seconds = 4.0
		return
	var dist_m := player.global_position.distance_to(
		Vector2(float(destination.x),float(destination.y)) * PPM) / PPM
	if not ObjectiveLayer.matches(player,ObjectiveLayer.marker_layer(destination)) or not Rules.arrived(dist_m, player.linear_velocity.length(),
			Rules.configured_arrival_radius(offer_settings)):
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
	var show_robbery := not active.is_empty() and stage == "robbery"
	robbery_meter.visible = show_robbery
	robbery_status.visible = show_robbery
	early_finish_button.visible = false
	if show_robbery:
		var required := _robbery_hold(offer_settings)
		robbery_meter.value = clampf(robbery_progress / required * 100.0,0.0,100.0)
		robbery_status.text = "CREW PROGRESS / %.1fs of %.0fs" % [robbery_progress,required]
		if not Rules.robbery_profile(offer_settings).is_empty():
			robbery_status.text = "%s / %s / HEAT %d / %.1fs of %.0fs" % [
				Rules.robbery_risk(offer_settings).to_upper(),economy.dollars(_robbery_cash(offer_settings)),
				Rules.configured_wanted("robbery",offer_settings),robbery_progress,required]
			var lower := _completed_lower(offer_settings,robbery_progress)
			if not lower.is_empty():
				var lower_offer := Rules.with_robbery_risk(offer_settings,lower)
				early_finish_button.text = "FINISH %s / %s / HEAT %d" % [
					lower.to_upper(),economy.dollars(_robbery_cash(lower_offer)),
					Rules.configured_wanted("robbery",lower_offer)]
				early_finish_button.visible = true
	contract_panel.visible = not active.is_empty() or notice_seconds>0.0
	deadline_bar.visible = not active.is_empty()
	if active.is_empty():
		contract_title.text = "CONTRACT RESULT"
		readout.text = notice if notice_seconds>0.0 else ""
		return
	contract_title.text = str(active.get("name","DRIVING CONTRACT")).to_upper()
	deadline_bar.value = clampf(remaining_seconds/maxf(1.0,initial_seconds)*100.0,0.0,100.0)
	var kind := str(active.get("properties",{}).get("contract_kind","courier"))
	var dist_m := player.global_position.distance_to(
		Vector2(float(destination.x),float(destination.y)) * PPM) / PPM
	var objective := "WAIT FOR CREW %ds" % maxi(0,ceili(_robbery_hold(offer_settings)-robbery_progress)) if stage=="robbery" else \
		("EVADE POLICE & DELIVER" if Rules.configured_wanted(kind,offer_settings) > 0 else "DELIVER")
	if stage=="robbery":
		dist_m = player.global_position.distance_to(
			Vector2(float(robbery_target.x),float(robbery_target.y)) * PPM) / PPM
	var distance := "%.1f MI" % (dist_m/1609.344) if dist_m>=160.9344 else "%d FT" % roundi(dist_m*3.28084)
	readout.text = "%s\n%s  /  %s LEFT" % [objective,distance,Rules.timer_text(ceili(remaining_seconds))]
	if stage == "delivery" and player.mission_payload_mass_kg() > 0.0:
		readout.text += "\nCREW %d / CARGO %.0f KG / +%.0f KG LOAD" % [player.mission_passengers,player.mission_cargo_kg,player.mission_payload_mass_kg()]
	if notice_seconds > 0.0:
		readout.text += " / " + notice
