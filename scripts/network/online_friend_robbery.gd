extends Node2D
## Host-authoritative opt-in cooperative driving contract. One getaway driver
## (host) and 1-3 support drivers; existing shared police has one target.
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
const PPM := 20.0
const RALLY_RADIUS_M := 28.0
const READY_RADIUS_M := 24.0
var network: Node2D
var session: Node
var economy: VehicleOwnership
var marker_source: Node2D
var contact: Dictionary = {}
var offers: Dictionary = {}
var locations: Dictionary = {}
var participants: Dictionary = {}
var state := "idle"
var job_id := 0
var tier := ""
var risk := "standard"
var seconds_left := 0.0
var progress := 0.0
var message := ""
var consent_id := 0
var police_started := false
var escaped := false
var clock := 0.0
var panel: PanelContainer
var status: Label
var tier_picker: OptionButton
var risk_picker: OptionButton
var host_button: Button
var join_button: Button
var cancel_button: Button
var _reset_callbacks: Dictionary = {}

func _ready() -> void:
	network = get_parent() as Node2D
	session = get_node_or_null("/root/OnlineSession")
	economy = network.get_parent().get("vehicle_ownership") as VehicleOwnership
	marker_source = network.get_parent().get("authored_map_markers") as Node2D
	if session==null or not session.active or not is_instance_valid(economy) or not is_instance_valid(marker_source):
		return
	for marker in marker_source.get("markers"):
		locations[str(marker.id)] = marker
	contact = locations.get("marker-campaign-robbery-contact",{})
	if contact.is_empty():
		return
	for offer in contact.get("properties",{}).get("offers",[]):
		if not Rules.robbery_profile(offer).is_empty():
			offers[str(offer.robbery_tier)] = offer
	if offers.size()!=5:
		contact.clear()
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	panel = PanelContainer.new()
	panel.name = "CoopRobberyPanel"
	panel.position = Vector2(20,350)
	panel.custom_minimum_size.x = 440
	layer.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",4)
	panel.add_child(body)
	status = Label.new()
	status.custom_minimum_size = Vector2(420,72)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var row := HBoxContainer.new()
	body.add_child(row)
	tier_picker = OptionButton.new()
	for key in Rules.ROBBERY_ORDER:
		tier_picker.add_item(str(Rules.ROBBERY_TIERS[key]["title"]))
	row.add_child(tier_picker)
	risk_picker = OptionButton.new()
	for key in Rules.ROBBERY_RISKS:
		risk_picker.add_item(str(key).capitalize())
	risk_picker.select(1)
	row.add_child(risk_picker)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	host_button = _button(actions,"OFFER CO-OP",_host_action)
	join_button = _button(actions,"JOIN / READY",_join_action)
	cancel_button = _button(actions,"CANCEL",_cancel_action)
	session.peer_connection_suspended.connect(_peer_lost)
	session.session_closed.connect(_session_closed)
	if session.hosting and is_instance_valid(network.get("shared_police")):
		network.shared_police.escaped.connect(_police_escaped)
		network.shared_police.busted.connect(_police_busted)
	_refresh()

func _button(parent: Control, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func busy() -> bool:
	return state in ["lobby","pickup","delivery"]

func _car(id: int) -> VehicleController2D:
	return network.get("local_vehicle") as VehicleController2D if id==int(session.own_id()) else network.get("peer_cars").get(id) as VehicleController2D

func _connected(id: int) -> bool:
	return session.players.has(id) and (id==1 or (session.world_ready_peers.has(id) and not session.disconnected_since.has(id))) and is_instance_valid(_car(id))

func _near(car: VehicleController2D, marker: Dictionary, radius: float) -> bool:
	return is_instance_valid(car) and not marker.is_empty() and Rules.arrived(car.global_position.distance_to(Vector2(float(marker.x),float(marker.y))*PPM)/PPM,car.linear_velocity.length(),radius)

func _offer() -> Dictionary:
	return Rules.with_robbery_risk(offers.get(tier,{}),risk)

func _marker(id: String) -> Dictionary:
	return locations.get(id,{})

func _race_busy() -> bool:
	var race: Node = network.get("friend_race")
	return is_instance_valid(race) and str(race.get("state")) in ["lobby","countdown","running"]

func _police_clear() -> bool:
	var police: Node = network.get("shared_police")
	return is_instance_valid(police) and int(police.get("wanted_level"))==0 and float(police.get("bust_timer"))<=0.0

func _car_id(id: int) -> String:
	return str(session.players.get(id,{}).get("car_id",""))

func _eligible(offer: Dictionary) -> bool:
	return not offer.is_empty() and economy.underground_reputation>=Rules.required_rep(offer) and economy.owns(economy.active_id)

func _host_action() -> void:
	if not session.hosting:
		return
	if state=="lobby":
		_start()
		return
	if busy() or _race_busy() or not _police_clear() or not _near(_car(1),contact,READY_RADIUS_M):
		return
	tier = Rules.ROBBERY_ORDER[tier_picker.selected]
	risk = Rules.ROBBERY_RISKS[risk_picker.selected]
	var offer := _offer()
	if not _eligible(offer):
		message = "REPUTATION REQUIREMENT NOT MET"
		return
	var availability := economy.robbery_availability("morrow-coast",offer)
	if not bool(availability.available):
		message = Rules.availability_text(availability)
		return
	var payload := Rules.robbery_payload(offer)
	if not _car(1).can_carry_mission(payload.x,float(payload.y)):
		message = "HOST VEHICLE CAPACITY INSUFFICIENT"
		return
	job_id += 1
	consent_id = job_id
	participants = {1:{"car_id":economy.active_id}}
	state = "lobby"
	message = "Friends must park nearby and explicitly join."
	_publish()

func _join_action() -> void:
	if session.hosting or state!="lobby" or session.reconnecting:
		return
	var me := int(session.own_id())
	var joining := not participants.has(me)
	if joining and (not _eligible(_offer()) or not _near(_car(me),contact,READY_RADIUS_M)):
		message = "PARK AT FIXER / REPUTATION REQUIRED"
		return
	consent_id = job_id if joining else 0
	_request_join.rpc_id(1,job_id,joining,economy.underground_reputation)

@rpc("any_peer","reliable")
func _request_join(requested: int, joining: bool, reported_rep: int) -> void:
	if not session.hosting:
		return
	_host_join(multiplayer.get_remote_sender_id(),requested,joining,reported_rep)

func _host_join(id: int, requested: int, joining: bool, reported_rep: int) -> void:
	if id<=1 or state!="lobby" or requested!=job_id or not _connected(id):
		return
	if joining:
		if participants.size()>=4 or reported_rep<Rules.required_rep(_offer()) or reported_rep>100000 or not _near(_car(id),contact,READY_RADIUS_M) or _car_id(id).is_empty():
			return
		participants[id] = {"car_id":_car_id(id)}
	else:
		participants.erase(id)
	_publish()

func _all_near(marker: Dictionary, radius: float) -> bool:
	for id in participants:
		if not _connected(int(id)) or not _near(_car(int(id)),marker,radius):
			return false
	return participants.size()>=2

func _start() -> void:
	if not session.hosting or state!="lobby" or participants.size()<2 or _race_busy() or not _police_clear() or not _all_near(contact,READY_RADIUS_M):
		message = "ALL PARTICIPANTS MUST BE PARKED AT FIXER"
		return
	var offer := _offer()
	var payload := Rules.robbery_payload(offer)
	if not _eligible(offer) or not _car(1).can_carry_mission(payload.x,float(payload.y)):
		message = "HOST REPUTATION OR CAPACITY REQUIREMENT"
		return
	for id in participants:
		if str(participants[id].car_id)!=_car_id(int(id)):
			message = "VEHICLE CHANGED / REJOIN LOBBY"
			return
	var target := _marker(str(offer.robbery_marker_id))
	var dropoff := _marker(str(offer.destination_marker_id))
	var hud: Node = marker_source.get("map_hud")
	var guide: Node = hud.get("waypoints") if is_instance_valid(hud) else null
	var planner: RefCounted = guide.get("planner") if is_instance_valid(guide) else null
	if target.is_empty() or dropoff.is_empty() or planner==null:
		message = "ROUTE UNAVAILABLE"
		return
	var a := Vector2(float(target.x),float(target.y))
	var b := Vector2(float(dropoff.x),float(dropoff.y))
	if (planner.call("plan",_car(1).global_position/PPM,a,Vector2.UP) as Dictionary).is_empty() or (planner.call("plan",a,b,Vector2.UP) as Dictionary).is_empty():
		message = "ROUTE UNAVAILABLE"
		return
	if economy.reserve_robbery_location("morrow-coast",offer)!="ready":
		message = "LOCATION UNAVAILABLE"
		return
	seconds_left = Rules.configured_time("robbery",offer)
	progress = 0.0
	police_started = false
	escaped = false
	state = "pickup"
	message = "All participants: reach pickup and stop."
	for id in participants:
		var car := _car(int(id))
		var callback := _reset_detected.bind(int(id))
		car.vehicle_reset.connect(callback)
		_reset_callbacks[id] = callback
	_publish()

func _reset_detected(_id: int) -> void:
	if state in ["pickup","delivery"]:
		_finish(false,"PARTICIPANT RESET")

func _clear_callbacks() -> void:
	for id in _reset_callbacks:
		var car := _car(int(id))
		if is_instance_valid(car) and car.vehicle_reset.is_connected(_reset_callbacks[id]):
			car.vehicle_reset.disconnect(_reset_callbacks[id])
	_reset_callbacks.clear()

func _police_escaped() -> void:
	if state=="delivery" and police_started:
		escaped = true

func _police_busted(_reason: String) -> void:
	if state=="delivery" and police_started:
		_finish(false,"GETAWAY DRIVER BUSTED")

func _peer_lost(id: int) -> void:
	if session.hosting and busy() and participants.has(id):
		_finish(false,"PARTICIPANT DISCONNECTED")

func _session_closed(_reason: String) -> void:
	if is_instance_valid(network.get("local_vehicle")):
		network.local_vehicle.clear_mission_payload()
	state = "idle"
	consent_id = 0
	if is_instance_valid(panel):
		panel.hide()

func _cancel_action() -> void:
	if session.hosting and busy():
		_finish(false,"CANCELLED")
	elif busy() and participants.has(int(session.own_id())):
		_request_leave.rpc_id(1,job_id)

@rpc("any_peer","reliable")
func _request_leave(requested: int) -> void:
	if session.hosting and requested==job_id and busy() and participants.has(multiplayer.get_remote_sender_id()):
		_finish(false,"PARTICIPANT LEFT")

func _physics_process(dt: float) -> void:
	if not is_instance_valid(panel) or not session.active or not session.hosting or state not in ["pickup","delivery"]:
		return
	for id in participants:
		if not _connected(int(id)) or str(participants[id].car_id)!=_car_id(int(id)) or _car(int(id)).damage_drive_fraction<=0.0:
			_finish(false,"PARTICIPANT UNAVAILABLE")
			return
	seconds_left -= dt
	if seconds_left<=0.0:
		_finish(false,"TIME EXPIRED")
		return
	var offer := _offer()
	if state=="pickup":
		if not _police_clear():
			_finish(false,"POLICE BUSY")
			return
		if _all_near(_marker(str(offer.robbery_marker_id)),RALLY_RADIUS_M):
			progress += dt
		else:
			progress = 0.0
		if progress>=Rules.configured_robbery_hold(offer):
			var payload := Rules.robbery_payload(offer)
			if not _car(1).load_mission_payload(payload.x,float(payload.y)) or not network.call("_start_verified_police_pursuit",1,Rules.configured_wanted("robbery",offer)):
				_finish(false,"HANDOFF FAILED")
				return
			police_started = true
			state = "delivery"
			message = "Host carries crew/cargo. All drivers reach drop-off after escape."
			_publish()
	elif escaped and _police_clear() and _all_near(_marker(str(offer.destination_marker_id)),RALLY_RADIUS_M):
		_finish(true,"TEAM DELIVERY COMPLETE")

func _finish(success: bool, reason: String) -> void:
	if not busy():
		return
	state = "results" if success else "aborted"
	message = reason
	_clear_callbacks()
	if is_instance_valid(_car(1)):
		_car(1).clear_mission_payload()
	# Do not cancel unrelated pursuits or interrupt the bust recovery.
	if not success and police_started and int(network.get("police_target_peer"))==1:
		var police: Node = network.get("shared_police")
		if is_instance_valid(police) and float(police.get("bust_timer"))<=0.0:
			police.call("_escape")
	police_started = false
	_publish()

func _publish() -> void:
	if not session.hosting:
		return
	var payload := {"id":job_id,"state":state,"tier":tier,"risk":risk,"participants":participants.duplicate(true),"seconds":maxf(0.0,seconds_left),"progress":progress,"message":message}
	if multiplayer.has_multiplayer_peer():
		_receive.rpc(payload)
	_apply(payload)

@rpc("authority","reliable")
func _receive(payload: Dictionary) -> void:
	if not session.hosting:
		_apply(payload)

func _apply(payload: Dictionary) -> void:
	var next_id := int(payload.get("id",0))
	var next_state := str(payload.get("state",""))
	var next_tier := str(payload.get("tier",""))
	var next_risk := str(payload.get("risk",""))
	var roster: Variant = payload.get("participants",{})
	if next_id<job_id or next_id<1 or next_state not in ["lobby","pickup","delivery","results","aborted"] or next_tier not in offers or next_risk not in Rules.ROBBERY_RISKS or not roster is Dictionary or roster.size()>4:
		return
	var changed_stage := next_id!=job_id or next_state!=state
	job_id = next_id
	state = next_state
	tier = next_tier
	risk = next_risk
	participants = roster.duplicate(true)
	seconds_left = float(payload.get("seconds",0))
	progress = float(payload.get("progress",0))
	message = str(payload.get("message","")).left(200)
	var me := int(session.own_id())
	if consent_id==job_id and participants.has(me):
		if state in ["pickup","delivery"] and (changed_stage or session.hosting):
			_route_local()
		if state=="results" and participants.size()>=2 and participants[me] is Dictionary:
			var receipt := economy.record_coop_robbery(str(session.reward_session_id),job_id,tier,risk,participants.size(),str(participants[me].get("car_id","")))
			if str(receipt.result)=="completed":
				message += " / +"+VehicleOwnership.dollars(int(receipt.cash))+" / +%d REP" % int(receipt.underground_rep)
				consent_id = 0
			elif str(receipt.result)!="save_failed":
				message += " / "+str(receipt.result).to_upper()
				consent_id = 0
	elif state=="aborted":
		consent_id = 0
	_refresh()

func _route_local() -> void:
	var offer := _offer()
	var marker := _marker(str(offer.robbery_marker_id) if state=="pickup" else str(offer.destination_marker_id))
	var hud: Node = marker_source.get("map_hud")
	var guide: Node = hud.get("waypoints") if is_instance_valid(hud) else null
	if is_instance_valid(guide) and not marker.is_empty():
		guide.call("set_destination",Vector2(float(marker.x),float(marker.y)),str(marker.name))

func _process(dt: float) -> void:
	if not is_instance_valid(panel) or not session.active:
		return
	clock += dt
	if clock<0.5:
		return
	clock = 0.0
	if session.hosting and state in ["pickup","delivery"]:
		_publish()
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(panel):
		return
	var me := int(session.own_id())
	var nearby := _near(_car(me),contact,READY_RADIUS_M)
	panel.visible = nearby or busy() or (state in ["results","aborted"] and participants.has(me))
	tier_picker.visible = session.hosting and not busy()
	risk_picker.visible = tier_picker.visible
	host_button.visible = session.hosting and state not in ["pickup","delivery"]
	host_button.text = "START TEAM ROBBERY" if state=="lobby" else "OFFER CO-OP"
	host_button.disabled = not nearby or _race_busy() or (state=="lobby" and participants.size()<2)
	join_button.visible = not session.hosting and state=="lobby"
	join_button.text = "LEAVE TEAM" if participants.has(me) else "JOIN / READY"
	join_button.disabled = not participants.has(me) and (not nearby or not _eligible(_offer()))
	cancel_button.visible = busy() and (session.hosting or participants.has(me))
	var offer := _offer()
	var title := "CO-OP ROBBERY / 2-4 DRIVERS"
	if not offer.is_empty():
		title += " / "+str(offer.title)
	var detail := "Park at the underground fixer. Host chooses a contract."
	if busy():
		detail = "%s / %d DRIVERS / %ds LEFT" % [state.to_upper(),participants.size(),ceili(seconds_left)]
		if state=="pickup":
			detail += " / %.1f of %.0fs" % [progress,Rules.configured_robbery_hold(offer)]
		if participants.size()>=2:
			detail += " / "+VehicleOwnership.dollars(floori(float(Rules.configured_reward("robbery",offer).cash)/float(participants.size())))+" EACH"
	status.text = title+"\n"+detail+"\n"+message

func _exit_tree() -> void:
	_clear_callbacks()
