extends Node
## Isolated physical validation run. Uses the actual player car, ambient
## traffic, collision signals, physics and police dispatch in Test Drive.
const Audit=preload("res://scripts/dev/world_validation.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")
const Navigation=preload("res://scripts/world/race_navigation.gd")
const Driver=preload("res://scripts/world/race_ai_driver.gd")
const Metrics=preload("res://scripts/world/ai_benchmark_metrics.gd")
const Elevation=preload("res://scripts/world/road_elevation.gd")
var host: Node
var car: VehicleController2D
var flow: Node
var police: Node
var spec: Dictionary={}
var guide: RefCounted
var driver: Node
var metrics:=Metrics.new()
var result: Dictionary={}
var elapsed:=0.0
var next_sample:=0.0
var progress:=0.0
var active:=false

func _ready() -> void:
	set_physics_process(false)
	result={"source_hash":str(get_tree().get_meta("streetbound_test_drive_source_hash","")),"scenario":str(spec.get("scenario","Normal")),"status":"not_run","first_dispatch_s":-1.0,"first_nearby_police_s":-1.0,"peak_units":0,"peak_traffic":0,"peak_stopped_traffic":0,"traffic_samples":0,"max_cross_track_m":0.0}
	if not is_instance_valid(car) or not is_instance_valid(flow):
		_finish("missing_vehicle_or_traffic");return
	var planner:=Planner.new()
	planner.setup(flow.get("network"),host.ground.data)
	var route:=Audit.route(planner,spec.get("start",{}),spec.get("finish",{}))
	if route.is_empty() or float(route.length_m)<20.0 or float(route.length_m)>5000.0:
		_finish("invalid_route");return
	# A first physical runner supports flat routes only. Mixed-grade paths
	# remain available in the directed navigation preview.
	for id in route.edges:
		var edge: Dictionary=flow.get("network").edges[int(id)]
		if absf(float(edge.get("start_height_m",0)))>.1 or absf(float(edge.get("end_height_m",0)))>.1:
			_finish("elevated_route_not_supported");return
	var pts: PackedVector2Array=route.points_m
	if car.global_position.distance_to(pts[0]*20.0)>100.0:
		_finish("spawn_mismatch");return
	result["route_m"]=float(route.length_m)
	guide=Navigation.new()
	guide.setup(pts)
	car.external_input=true
	car.crash_contact.connect(_collision)
	driver=Driver.new()
	driver.reaction_seconds=0.0
	driver.throttle_limit=.65
	driver.cruise_speed_mps=18.0
	add_child(driver)
	driver.setup_navigation(car,guide)
	var scenario:=str(spec.get("scenario","Normal"))
	flow.set("maximum_vehicles",{"Normal":16,"Rush hour":24,"Heavy":30,"Police":16}.get(scenario,16))
	driver.enable_race_traffic(host.ground,flow)
	active=true
	driver.launch()
	set_physics_process(true)

func _collision(_speed: float,_point: Vector2,_normal: Vector2,_before: Vector2) -> void:
	if active:metrics.collision()

func _physics_process(dt: float) -> void:
	if not active:return
	elapsed+=dt
	metrics.sample(dt,car.global_position,car.linear_velocity.length(),car.command,str(car.surface))
	if elapsed<next_sample:return
	next_sample=elapsed+.25
	var station: float=guide.station_at(car.global_position/20.0)
	# Clamp credited progress to what the physical car could traverse.
	var advance:=maxf(0.0,station-progress)
	if advance<=maxf(5.0,car.linear_velocity.length()*.5+3.0):progress=maxf(progress,station)
	var cross: float=guide.point_at(station).distance_to(car.global_position/20.0)
	result.max_cross_track_m=maxf(float(result.max_cross_track_m),cross)
	var agents: Array=flow.get("agents")
	var stopped:=0
	for agent in agents:
		if float(agent.get("speed",0))<20.0:stopped+=1
	result.peak_traffic=maxi(int(result.peak_traffic),agents.size())
	result.peak_stopped_traffic=maxi(int(result.peak_stopped_traffic),stopped)
	result.traffic_samples+=1
	if result.scenario=="Police" and is_instance_valid(police):
		if elapsed>=3.0 and not result.has("dispatch_started"):
			result["dispatch_started"]=bool(police.call("start_pursuit",1))
			result["dispatch_at_s"]=elapsed
		var units: Array=police.get("units")
		result.peak_units=maxi(int(result.peak_units),units.size())
		if bool(result.get("dispatch_started",false)):
			if not units.is_empty() and float(result.first_dispatch_s)<0:result.first_dispatch_s=elapsed-float(result.dispatch_at_s)
			for unit in units:
				var officer: Node2D=unit.get("car")
				if is_instance_valid(officer) and officer.global_position.distance_to(car.global_position)<=1000.0 and officer.get("road_layer")==car.road_layer and float(result.first_nearby_police_s)<0:
					result.first_nearby_police_s=elapsed-float(result.dispatch_at_s)
	if cross>100.0:_finish("off_route")
	elif progress>=float(guide.length_m)-12.0 and car.global_position.distance_to(guide.points_m[-1]*20.0)<=300.0:
		_finish("completed")
	elif elapsed>=clampf(float(guide.length_m)/6.0+30.0,45.0,180.0):
		_finish("timeout")

func _finish(status: String,return_to_editor: bool=true) -> void:
	active=false
	set_physics_process(false)
	if is_instance_valid(driver):driver.stop()
	if is_instance_valid(car):
		car.command=Vector4.ZERO
		car.external_input=false
	result["status"]=status
	result["progress_m"]=progress
	result["metrics"]=metrics.summary()
	get_tree().set_meta("streetbound_validation_drive_report",result.duplicate(true))
	if return_to_editor:host.call_deferred("_return_from_test_drive")

func cancel() -> void:
	if active:_finish("cancelled",false)
