extends SceneTree
## Real city archive + runtime lane network, streamed chunks, traffic and police.
const Traffic=preload("res://scripts/world/traffic_flow.gd")
const Police=preload("res://scripts/world/police_pursuit.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")
const Objectives=preload("res://scripts/world/objective_road_layer.gd")
const Vehicle=preload("res://scenes/vehicle.tscn")
var failures: Array[String]=[]

class CityWorld extends MorrowCoast:
	var fixture: Dictionary
	func _ready() -> void:
		_initialize_archive(fixture,true,false)

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL ",message)

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(1)
		return
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not raw is Dictionary:
		quit(1)
		return
	var started:=Time.get_ticks_usec()
	var world:=CityWorld.new()
	world.fixture=raw
	root.add_child(world)
	check(world.initialization_complete,"Large world initializes")
	if not world.initialization_complete:
		quit(1)
		return
	var car: VehicleController2D=Vehicle.instantiate()
	car.position=Vector2(300,850)*20
	car.external_input=true
	car.surface_provider=world
	root.add_child(car)
	world.vehicle=car
	var traffic:=Traffic.new()
	traffic.world=world;traffic.player=car;traffic.maximum_vehicles=24
	root.add_child(traffic)
	var police:=Police.new()
	police.world=world;police.player=car;police.traffic=traffic;police.shared_session=true
	root.add_child(police)
	var graph_ms:=float(Time.get_ticks_usec()-started)/1000.0
	var planner:=Planner.new()
	planner.setup(traffic.network,world.data)
	var route: Dictionary=planner.plan(Vector2(300,850),Vector2(2700,850),Vector2.UP,"","",1,-1)
	check(not route.is_empty(),"City planner connects deck to tunnel through legal ramps")
	var max_agents:=0
	var frame_started:=Time.get_ticks_usec()
	for tick in 360:
		await physics_frame
		max_agents=maxi(max_agents,traffic.agents.size())
	check(max_agents>0,"City ambient traffic spawns on actual lane graph")
	var deck: Dictionary=Objectives.contact(world,Vector2(300,850),1)
	check(not deck.is_empty(),"Elevated street has physical support")
	if not deck.is_empty():
		check(car.reconcile_road_contact(int(deck.road),float(deck.height_m)),"Player stages on city deck")
		check(police.start_pursuit(2),"Police dispatch accepts elevated target")
		check(police.last_seen_road_layer==1,"Police retain last confirmed deck level")
		for tick in 180:await physics_frame
	check(world.failed_chunks.is_empty(),"No streamed chunk build failures")
	check(world.chunks.size()<80,"Chunk streaming remains bounded")
	print(JSON.stringify({"roads":raw.roads.size(),"junctions":raw.junctions.size(),"lane_edges":traffic.network.edges.size(),
		"startup_and_graph_ms":graph_ms,"simulation_ms":float(Time.get_ticks_usec()-frame_started)/1000.0,
		"peak_traffic":max_agents,"police_units":police.units.size(),"loaded_chunks":world.chunks.size(),
		"max_chunk_build_ms":float(world.max_chunk_build_usec)/1000.0}))
	if failures.is_empty():print("ELEVATION CITY RUNTIME: PASS")
	quit(0 if failures.is_empty() else 1)
