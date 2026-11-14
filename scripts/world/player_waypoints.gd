extends Node
signal changed
const Network=preload("res://scripts/world/traffic_network.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")
const Navigation=preload("res://scripts/world/race_navigation.gd")
var world: Node2D
var player: VehicleController2D
var planner:=Planner.new()
var active:=false
var destination_m:=Vector2.ZERO
var destination_name:="Waypoint"
var navigation: RefCounted
var remaining_m:=0.0
var status:=""
var suspended:=false
var route_revision:=0
var _clock:=0.0
var _retry_clock:=0.0
var _last_station:=0.0

func _ready() -> void:
	name="PlayerWaypoints"
	var graph:=Network.new();graph.build(world.data,true)
	planner.setup(graph,world.data)

func set_destination(point_m: Vector2,title: String="Waypoint") -> bool:
	var extent:=Vector2(world.data.size[0],world.data.size[1])
	if not point_m.is_finite() or not Rect2(Vector2.ZERO,extent).has_point(point_m):return false
	destination_m=point_m;destination_name=title;active=true;_clock=0
	_reroute()
	return true

func clear_destination() -> void:
	active=false;navigation=null;remaining_m=0;status="";route_revision+=1;suspended=false;_last_station=0
	changed.emit()

func _reroute() -> void:
	var result:=planner.plan(player.global_position/20,destination_m,Vector2.UP.rotated(player.rotation))
	navigation=null;_last_station=0;route_revision+=1;_retry_clock=2.0
	if result.is_empty():
		remaining_m=player.global_position.distance_to(destination_m*20)/20
		status="No connected road route — move closer to a road"
	else:
		navigation=Navigation.new();navigation.setup(result.points_m,false)
		remaining_m=float(navigation.length_m)
		status="Follow the route" if float(result.access_distance_m)<20 else "Route to nearest road; destination is off-road"
	changed.emit()

func _process(dt: float) -> void:
	if not active or not is_instance_valid(player):return
	_clock-=dt;_retry_clock-=dt
	if _clock>0:return
	_clock=.35
	suspended=false
	for race in get_tree().get_nodes_in_group("streetbound_race"):
		if str(race.get("state")) in ["countdown","running"]:suspended=true;break
	if suspended:return
	var position_m:=player.global_position/20
	if position_m.distance_to(destination_m)<=16:
		active=false;navigation=null;remaining_m=0;status="Arrived · "+destination_name;route_revision+=1
		changed.emit();return
	if navigation==null:
		if _retry_clock<=0:_reroute()
		return
	var station:=float(navigation.station_at(position_m))
	remaining_m=maxf(0,float(navigation.length_m)-station)
	var deviation:=position_m.distance_to(navigation.point_at(station))
	if _retry_clock<=0 and (deviation>22 or station<_last_station-25):
		_reroute();return
	_last_station=maxf(_last_station,station)
	changed.emit()
