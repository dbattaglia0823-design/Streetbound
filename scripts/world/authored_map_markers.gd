extends Node2D
## In-world triggers for saved World Builder markers. Uses the actual car,
## garage selector, race coordinator, dealerships, and streamed road network.
## No duplicate economy, no fake race completion and no off-road fast travel.
const Rules=preload("res://scripts/world/authored_marker_rules.gd")
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
const Grid=preload("res://scripts/world/race_start_grid.gd")
const InteractionSpeed=preload("res://scripts/world/interaction_speed.gd")
const PPM:=20.0
var world: Node2D
var player: VehicleController2D
var economy: Object
var selector: CanvasLayer
var dealer_menu: CanvasLayer
var quick_upgrades: CanvasLayer
var resources: CanvasLayer
var traffic: Node2D
var map_hud: CanvasLayer
var races: Array[Node2D]=[]
var markers: Array[Dictionary]=[]
var prompt: Button
var panel: PanelContainer
var destinations: VBoxContainer
var message: Label
var dialog_title: Label
var _nearby: Dictionary={}
var _dialog_open:=false
var _clock:=0.0
var world_id: String="morrow-coast"

func _ready() -> void:
	name="AuthoredMapMarkers"
	# The location and fast-travel panels pause driving. Keep this
	# controller listening for Esc so the panels can be dismissed.
	process_mode=Node.PROCESS_MODE_ALWAYS
	world_id=str(world.data.get("editor_world_id","morrow-coast"))
	for entry in world.data.get("editor_markers",[]):
		if not entry is Dictionary:continue
		var raw: Dictionary=entry.get("marker",entry)
		if not raw.has("type") or not raw.has("x") or not raw.has("y"):continue
		if Rules.valid(raw):markers.append(raw)
	var canvas:=CanvasLayer.new();canvas.layer=8
	add_child(canvas)
	prompt=Button.new()
	prompt.name="MarkerInteraction"
	prompt.text=""
	prompt.position=Vector2(300,85)
	prompt.size=Vector2(370,40)
	prompt.visible=false
	prompt.pressed.connect(activate)
	canvas.add_child(prompt)
	panel=PanelContainer.new()
	panel.name="FastTravelMenu"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position=Vector2(-240,-210)
	panel.custom_minimum_size=Vector2(480,420)
	panel.visible=false
	panel.process_mode=Node.PROCESS_MODE_ALWAYS
	canvas.add_child(panel)
	var box:=VBoxContainer.new()
	panel.add_child(box)
	dialog_title=Label.new();dialog_title.text="FAST TRAVEL / SELECT DESTINATION"
	box.add_child(dialog_title)
	message=Label.new()
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=300
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	destinations=VBoxContainer.new()
	destinations.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(destinations)
	var close:=Button.new();close.text="Close"
	close.pressed.connect(_close_travel)
	box.add_child(close)

func _point(marker: Dictionary) -> Vector2:
	return Vector2(float(marker.x),float(marker.y))

func _enabled(marker: Dictionary) -> bool:
	return bool(marker.get("properties",{}).get("enabled",true)) and Rules.unlocked(marker,economy,world_id)

func _is_busy() -> bool:
	for race in races:
		if is_instance_valid(race) and str(race.get("state")) in ["countdown","running"]:return true
	return false

func nearest_marker() -> Dictionary:
	if not is_instance_valid(player):return {}
	var closest:=INF
	var found: Dictionary={}
	for marker in markers:
		if str(marker.type) in ["player_spawn","traffic_spawn"]:continue
		if not _enabled(marker):continue
		var radius:=float(marker.get("properties",{}).get("radius_m",12.0))
		var distance: float=player.global_position.distance_to(_point(marker)*PPM)/PPM
		if distance<=radius and distance<closest:
			closest=distance
			found=marker
	return found

func _process(dt: float) -> void:
	if not is_instance_valid(player):return
	_clock+=dt
	if _clock<0.16:return
	_clock=0.0
	_nearby=nearest_marker()
	if is_instance_valid(selector):
		selector.remote_garage_allowed=not _nearby.is_empty() and str(_nearby.type)=="garage" and not _is_busy() and InteractionSpeed.allowed(player.linear_velocity.length())
	if _dialog_open:
		prompt.visible=false
		return
	var kind: String=str(_nearby.get("type",""))
	var actionable:=kind in ["garage","dealership","mission","fast_travel","fuel",
		"race_start","checkpoint","finish","custom"]
	prompt.visible=actionable and not _is_busy() and not get_tree().paused
	if prompt.visible:
		var hint: String={"garage":"GARAGE","dealership":"DEALERSHIP","mission":"START MISSION",
			"fast_travel":"FAST TRAVEL","fuel":"SERVICE / FUEL", 
			"race_start":"RACE ROUTE","checkpoint":"CHECKPOINT",
			"finish":"FINISH","custom":"MAP WAYPOINT"}.get(kind,"INTERACT")
		prompt.text=str(_nearby.get("name",kind)).to_upper()+"  /  "+hint+"  [ F ]"
		prompt.disabled=not InteractionSpeed.allowed(player.linear_velocity.length())

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:return
	var key: InputEventKey=event
	if not key.pressed or key.echo:return
	if _dialog_open and key.keycode==KEY_ESCAPE:
		_close_travel()
		get_viewport().set_input_as_handled()
		return
	if key.keycode==KEY_F and not _dialog_open and not _nearby.is_empty() and \
			not get_tree().paused and not _is_busy() and InteractionSpeed.allowed(player.linear_velocity.length()):
		activate()
		get_viewport().set_input_as_handled()

func _linked_race(id: String) -> Node2D:
	if id.is_empty():return null
	for race in races:
		if is_instance_valid(race) and race.get("definition") is Dictionary and \
				str(race.definition.get("id",""))==id:return race
	return null

func activate() -> void:
	if get_tree().paused or _nearby.is_empty() or _is_busy() or \
			not InteractionSpeed.allowed(player.linear_velocity.length()):return
	var kind: String=str(_nearby.type)
	var properties: Dictionary=_nearby.get("properties",{})
	match kind:
		"garage":
			if is_instance_valid(selector):selector.open_menu()
		"dealership":
			# Never let a marker tied to one dealer open a different shop.
			# The real forecourt/collision and parking speed rules remain
			# authoritative; a marker cannot bypass purchase access.
			if is_instance_valid(dealer_menu) and is_instance_valid(dealer_menu.manager):
				var required: String=str(properties.get("dealer_id",""))
				var closest: Dictionary=dealer_menu.manager.nearby_shop()
				if required.is_empty() or str(closest.get("id",""))==required:
					dealer_menu.open_menu()
				else:
					_show_info(_nearby,"Drive into the linked dealership's real parking forecourt to browse its inventory.")
		"mission":
			var race:=_linked_race(str(properties.get("race_id","")))
			if race==null or not bool(race.get("available")):
				_show_info(_nearby,"No linked race is ready. Configure the mission's Race ID in the map builder.")
				return
			if race.has_method("_lock_reason") and not str(race.call("_lock_reason")).is_empty():return
			world.stream_at(Grid.point(Grid.player_slot(race.definition))*PPM)
			Grid.teleport(player,Grid.player_slot(race.definition))
			race.call("start_race")
		"fast_travel":_open_travel()
		"fuel":
			# Station F uses the actual paid fuel service; nitrous retains
			# its original instantaneous kit refill behavior.
			if is_instance_valid(resources):
				resources.try_refuel()
			# The base game already recharges nitrous automatically. This
			# service marker provides an immediate refill for an installed kit.
			player.nitrous_fuel_seconds=maxf(0.0,float(player.config.nitrous_capacity_seconds))
			if float(player.config.nitrous_capacity_seconds)<=0.0 and is_instance_valid(quick_upgrades):
				quick_upgrades.open_menu()
		"race_start","checkpoint","finish","custom":
			var race:=_linked_race(str(properties.get("race_id","")))
			if race!=null and is_instance_valid(map_hud) and is_instance_valid(map_hud.waypoints):
				map_hud.waypoints.set_destination(race.start_m,str(race.race_title))
			else:
				_show_info(_nearby,"This marker is available as a map landmark. Link a race to navigate to its start.")

func _safe_destination(marker: Dictionary) -> bool:
	var target: Vector2=_point(marker)*PPM
	var road: Dictionary=world.nearest_road_at(target,10.0)
	if road.is_empty() or str(world.surface_at(target).get("name",""))!="ASPHALT":return false
	if float(road.get("distance_to_center_m",INF))>maxf(0,float(road.get("road_width_m",0))*.5-2.0):return false
	var centre: Vector2=_point(marker)
	for prop in world.data.get("props",[]):
		if not bool(prop.get("solid",false)):continue
		var p: Vector2=Vector2(float(prop.p[0]),float(prop.p[1]))
		var extents: Vector2=Vector2(float(prop.size[0]),float(prop.size[1]))
		var radius: float=maxf(float(prop.get("radius",0)),extents.length()*.5)
		if centre.distance_to(p)<radius+3.0:return false
	return true

func _show_info(marker: Dictionary,fallback: String) -> void:
	if _dialog_open:return
	for child in destinations.get_children():
		destinations.remove_child(child);child.queue_free()
	dialog_title.text=str(marker.get("name","MAP MARKER")).to_upper()
	message.text=str(marker.get("properties",{}).get("description",fallback))
	panel.visible=true
	_dialog_open=true
	get_tree().paused=true

func _open_travel() -> void:
	if _dialog_open or _is_busy() or player.linear_velocity.length()>1.0:return
	dialog_title.text="FAST TRAVEL / SELECT DESTINATION"
	for child in destinations.get_children():
		destinations.remove_child(child);child.queue_free()
	var total:=0
	for marker in markers:
		if str(marker.type)!="fast_travel" or not _enabled(marker) or \
				str(marker.id)==str(_nearby.id):continue
		# Use actual production asphalt and collision clearance: never
		# teleport into ocean, scenery, barriers, or the edge of a map.
		if not _safe_destination(marker):continue
		var button:=Button.new()
		button.text=str(marker.get("name","Travel Point"))
		button.pressed.connect(_travel_to.bind(marker))
		destinations.add_child(button)
		total+=1
	message.text="Select an unlocked travel station." if total>0 else "No other unlocked, drivable stations are available."
	panel.visible=true
	_dialog_open=true
	get_tree().paused=true

func _travel_to(marker: Dictionary) -> void:
	if not _dialog_open or not _enabled(marker):return
	if player.linear_velocity.length()>1.0 or _is_busy():return
	if not _safe_destination(marker):return
	var target:=_point(marker)*PPM
	# Real streaming and camera follow are retained, including traffic.
	# VehicleController2D uses its own metre/second dynamics rather
	# than RigidBody2D.angular_velocity. Reset every velocity component
	# so the car cannot carry pre-teleport drift into its new street.
	player.global_position=target
	player.rotation=deg_to_rad(float(marker.get("rotation",0)))
	player.linear_velocity=Vector2.ZERO
	player.velocity=Vector2.ZERO
	player.yaw_rate=0.0
	player.longitudinal_speed=0.0
	player.lateral_speed=0.0
	player.slip_angle=0.0
	player.reset_physics_interpolation()
	world.stream_at(target)
	_close_travel()

func _close_travel() -> void:
	if not _dialog_open:return
	panel.visible=false
	_dialog_open=false
	get_tree().paused=false
