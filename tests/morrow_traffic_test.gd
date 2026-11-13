extends SceneTree
## Geometry routing is checked independently of rendering and the real game.
const Network = preload("res://scripts/world/traffic_network.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, good: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL",label,detail])
	if not good:failures.append(label)

func synthetic() -> Dictionary:
	var roads := [
		{"name":"East-West","start":"a","end":"b","kind":"local",
		 "surface":"ASPHALT","width":9.0,"lanes":2,
		 "points":[[100.0,300.0],[500.0,300.0]]},
		{"name":"North-South","start":"c","end":"d","kind":"arterial",
		 "surface":"ASPHALT","width":12.0,"lanes":2,
		 "points":[[300.0,100.0],[300.0,500.0]]},
		{"name":"No paved gravel crossing","start":"e","end":"f",
		 "kind":"gravel","surface":"GRAVEL","width":6.0,"lanes":1,
		 "points":[[100.0,350.0],[500.0,350.0]]}
	]
	var arms := []
	for road_id in 2:
		for side in [-1,1]:
			arms.append({"road":road_id,"side":side,
				"station":180.0 if side==-1 else 220.0,
				"control":"stop","direction":[1,0],
				"p":[300.0,300.0]})
	var junctions := [{
		"p":[300.0,300.0],"approaches":arms,"control":"all_way_stop",
		"roads":[0,1],"kind":"crossroads"
	}]
	return {"roads":roads,"junctions":junctions}


func run() -> void:
	var network=Network.new()
	network.build(synthetic())
	check("source_roads_indexed",network.source_road_count==3,network.source_road_count)
	check("paved_lane_edges_generated",network.edges.size()>=8,network.edges.size())
	check("turning_connectors_exist",network.connector_count>=5,network.connector_count)
	var has_left := false
	var has_right := false
	var has_straight := false
	var stop_control := false
	var no_gravel := true
	var directions := {}
	for edge in network.edges:
		if int(edge.road)==2:no_gravel=false
		if not bool(edge.connector):
			if int(edge.road)==0:
				directions[int(edge.direction)]=edge
		else:
			if str(edge.turn)=="left":has_left=true
			if str(edge.turn)=="right":has_right=true
			if str(edge.turn)=="straight":has_straight=true
			if str(edge.control)=="stop":stop_control=true
	check("right_hand_two_way_lanes",directions.has(1) and directions.has(-1))
	if directions.has(1) and directions.has(-1):
		var forward: PackedVector2Array=directions[1].points
		var backward: PackedVector2Array=directions[-1].points
		check("forward_lane_right_of_centerline",forward[0].y>300.0*20.0,forward[0].y)
		check("reverse_lane_uses_other_side",backward[0].y<300.0*20.0,backward[0].y)
	check("junction_turn_options_exist",has_left and has_right and has_straight,
		[has_left,has_right,has_straight])
	check("all_way_stop_causes_stop_turns",stop_control)
	check("gravel_has_no_paved_traffic_connections",no_gravel)
	var sample: Dictionary=network.point_on_edge(0,100.0)
	check("sample_in_world_pixels",sample.position.length()>1000.0,sample.position)
	check("road_spatial_candidates_usable",not network.nearby_edges(Vector2(300.0,300.0)*20.0).is_empty())
	var main: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.vehicle.set_physics_process(false)
	var traffic: Node2D=main.ground.get_node_or_null("AmbientTraffic")
	check("ambient_traffic_attached_to_morrow_scene",traffic!=null)
	if traffic!=null:
		traffic.enabled=false
		check("live_morrow_has_routes",traffic.network.edges.size()>40,
			traffic.network.edges.size())
		check("live_morrow_intersections_linked",traffic.network.connector_count>10,
			traffic.network.connector_count)
		check_live_lane_sides(traffic)
		check("traffic_bounded",traffic.maximum_vehicles<=20 and traffic.agents.size()<=20)
		check("cosmetic_traffic_not_mixed_into_player_physics",
			not traffic.get_node_or_null("TrafficBody"))
	print("MORROW COAST TRAFFIC: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func check_live_lane_sides(traffic: Node2D) -> void:
	var wrong_side: Array[int] = []
	var checked := 0
	for edge in traffic.network.edges:
		if bool(edge.connector):continue
		checked+=1
		var sample: Dictionary = traffic.network.point_on_edge(int(edge.id),float(edge.length_px)*0.5)
		var position_px: Vector2 = sample.position
		var raw: Array = traffic.world.data.roads[int(edge.road)].points
		var nearest_distance := INF
		var signed_side := 0.0
		for i in range(1,raw.size()):
			var a := Vector2(float(raw[i-1][0]),float(raw[i-1][1]))*20.0
			var b := Vector2(float(raw[i][0]),float(raw[i][1]))*20.0
			if a.distance_squared_to(b)<0.01:continue
			var closest := Geometry2D.get_closest_point_to_segment(position_px,a,b)
			var distance_px := closest.distance_squared_to(position_px)
			if distance_px<nearest_distance:
				nearest_distance=distance_px
				# Positive cross product means screen-right, in both travel directions.
				signed_side=((b-a).normalized()*int(edge.direction)).cross(position_px-closest)
		if signed_side<=0.1:wrong_side.append(int(edge.id))
	check("every_live_road_lane_keeps_right_including_curves",checked>0 and wrong_side.is_empty(),
		{"checked":checked,"wrong_side":wrong_side})
