extends SceneTree
## Confirm supplied traffic art, collision bodies, impact response, and lane
## return from actual displacement. No wall-clock or rendered screenshot needed.
const CarScript = preload("res://scripts/world/traffic_car.gd")
const Network = preload("res://scripts/world/traffic_network.gd")
const Flow = preload("res://scripts/world/traffic_flow.gd")
const PlayerScene = preload("res://scenes/vehicle.tscn")
const PPM := 20.0
var failures: Array[String] = []
var police_contacts := 0


func _initialize() -> void:
	call_deferred("run")


func check(label: String, valid: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL",label,detail])
	if not valid:
		failures.append(label)


func run() -> void:
	check("all_supplied_traffic_models_registered",CarScript.model_count() == 10,CarScript.model_count())
	var expected_paths := [
		"res://assets/Vehicles/Traffic Vehicles/Electric Traffic.png",
		"res://assets/Vehicles/Traffic Vehicles/Car1.png",
		"res://assets/Vehicles/Traffic Vehicles/Sedan.png",
		"res://assets/Vehicles/Traffic Vehicles/SportSUV.png",
		"res://assets/Vehicles/Traffic Vehicles/SUV.png",
		"res://assets/Vehicles/Traffic Vehicles/Minivan.png",
		"res://assets/Vehicles/Traffic Vehicles/Van.png",
		"res://assets/Vehicles/Traffic Vehicles/Taxi.png",
		"res://assets/Vehicles/Traffic Vehicles/Pickup Truck.png",
		"res://assets/Vehicles/Traffic Vehicles/Box Truck.png"
	]
	check("renamed_traffic_paths_preserve_slots",CarScript.MODEL_PATHS == expected_paths,
		CarScript.MODEL_PATHS)
	for path in expected_paths:
		check("current_texture_imported", ResourceLoader.exists(path, "Texture2D"), path)
	for i in CarScript.model_count():
		var car := CharacterBody2D.new()
		car.set_script(CarScript)
		car.set("model_index", i)
		car.position = Vector2(250 + i * 115, 950)
		root.add_child(car)
		await physics_frame
		var sprite: Sprite2D = car.get_node_or_null("VehicleArtwork")
		check("model_%02d_png_loaded" % i,sprite != null,
			CarScript.MODEL_PATHS[i])
		if sprite != null:
			check("model_%02d_uses_current_texture" % i,
				sprite.texture.resource_path == expected_paths[i], sprite.texture.resource_path)
			var image: Image = sprite.texture.get_image()
			var corner: Color = image.get_pixel(0,0)
			var middle: Color = image.get_pixel(image.get_width()/2,image.get_height()/2)
			print("TRAFFIC MODEL %d alpha corner=%.3f center=%.3f" % [
				i,corner.a,middle.a])
			check("model_%02d_visible_bounds" % i,
				sprite.region_rect.size.x > 4 and sprite.region_rect.size.y > 4,
				sprite.region_rect)
		var collider: CollisionShape2D = car.get_node_or_null("VehicleCollider")
		check("model_%02d_has_live_collision" % i,
			car.collision_layer == 1 and car.collision_mask == 3 and
			collider != null and not collider.disabled and
			car.is_in_group("traffic_vehicle") and not collider.visible)
		car.queue_free()
		await physics_frame

	# Patrols are a moving-traffic role, not a pursuit or a parked-car slot.
	var patrols: Array[Dictionary] = CarScript.patrol_models()
	var expected_patrols := ["police-crown-vic", "police-explorer", "police-f150",
		"police-charger", "police-challenger"]
	var patrol_ids: Array = []
	for model in patrols:
		patrol_ids.append(model["id"])
		var patrol := CharacterBody2D.new()
		patrol.set_script(CarScript)
		patrol.set("patrol_model", model)
		patrol.position = Vector2(8000, 18000)
		root.add_child(patrol)
		await physics_frame
		var sprite := patrol.get_node_or_null("VehicleArtwork") as Sprite2D
		var collider := patrol.get_node_or_null("VehicleCollider") as CollisionShape2D
		check("patrol_art_%s" % model["id"], sprite != null and
			sprite.texture.resource_path == str(model["texture"]) and
			is_equal_approx(sprite.rotation_degrees, float(model["sprite_rotation_degrees"])))
		check("patrol_role_%s" % model["id"], patrol.is_in_group("traffic_vehicle") and
			patrol.is_in_group("police_patrol") and not patrol.is_in_group("police_vehicle") and
			collider != null and not collider.disabled and
			is_equal_approx(float(patrol.get("length_px")), float(model["length_m"]) * PPM))
		var origin := patrol.position
		patrol.call("move_traffic", Vector2.UP * 12.0, 0.1)
		check("patrol_physical_movement_%s" % model["id"], patrol.position.distance_to(origin) > 1.0)
		patrol.queue_free()
		await physics_frame
	check("only_five_patrol_models", patrol_ids == expected_patrols, patrol_ids)
	var spawn_ids: Array = []
	for serial in range(Flow.PATROL_INTERVAL * 5):
		var selection: Dictionary = Flow.patrol_for_spawn(serial, 0)
		if not selection.is_empty():
			spawn_ids.append(selection["id"])
		check("patrol_cap_%d" % serial, Flow.patrol_for_spawn(serial, Flow.MAX_AMBIENT_PATROLS).is_empty())
	check("patrol_rotation_and_frequency", spawn_ids == expected_patrols, spawn_ids)
	check("civilian_slots_unchanged", CarScript.model_count() == 10)
	# This car is deliberately pushed away from a legal lane.
	var flow: Node2D = Node2D.new()
	flow.set_script(preload("res://scripts/world/traffic_flow.gd"))
	flow.name = "TrafficFlowTest"
	var graph=Network.new()
	var source = {
		"roads":[{
			"name":"Long Town Road","start":"a","end":"b",
			"kind":"local","surface":"ASPHALT","width":10.0,"lanes":2,
			"points":[[50.0,200.0],[650.0,200.0]]
		}],
		"junctions":[]
	}
	graph.build(source)
	check("test_route_generated",graph.edges.size() >= 2,graph.edges.size())
	var lane: Dictionary = graph.edges[0]
	var initial: Dictionary = graph.point_on_edge(0,300.0*20.0)
	var actor := CharacterBody2D.new()
	actor.set_script(CarScript)
	if not patrols.is_empty():
		actor.set("patrol_model", patrols[0])
	actor.position=initial.position
	actor.rotation=float(initial.angle)
	root.add_child(actor)
	await physics_frame
	var player := PlayerScene.instantiate()
	player.position=actor.position+Vector2(0,1000)
	root.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	flow.network=graph
	flow.player=player
	flow.active_junctions={}
	# Bypass _ready: it requires a full streamed Morrow Coast world.
	var agent: Dictionary = {
		"uid":1,"node":actor,"edge":0,"progress":6000.0,
		"speed":70.0,"cruise":160.0,"next":-2,
		"stop_wait":0.0,"stop_done":false,
		"recovery_time":0.0,"recovery_refresh":0.0,"recovery_goal":{}
	}
	actor.receive_impact(Vector2(0,400))
	check("impact_starts_recovery",actor.recovering and actor.impact_count==1)
	var before: Vector2 = actor.position
	for frame in 60:
		await physics_frame
		flow._recover_agent(agent,1.0/60.0)
	check("knockback_has_real_displacement",actor.position.distance_to(before)>3.0,
		actor.position.distance_to(before))
	var recovered := false
	for frame in 900:
		await physics_frame
		flow._recover_agent(agent,1.0/60.0)
		if not actor.recovering:
			recovered=true
			break
	check("crashed_car_finds_drivable_lane",recovered,
		[actor.position,agent.progress])
	check("recovered_car_on_directional_edge",int(agent.edge)>=0 and
		int(agent.edge)<graph.edges.size(),agent.edge)
	var target: Dictionary = graph.recovery_target(actor.position,Vector2.UP.rotated(actor.rotation),0)
	check("recovery_search_uses_real_road",not target.is_empty(),target.get("distance_px",INF))
	# Actual post-crash body coordinates take priority over stale route progress.
	# A player ahead must make both normal AI driving and recovery yield.
	actor.rotation = 0.0
	player.position = actor.position + Vector2.UP * PPM * 5.0
	check("player_ahead_stops_post_crash_traffic",
		flow._player_awareness(agent, PPM * 6.0) <= 0.01)
	player.position = actor.position + Vector2.DOWN * PPM * 5.0
	check("player_behind_does_not_stop_traffic",
		is_equal_approx(flow._player_awareness(agent, PPM * 6.0), PPM * 6.0))
	player.position = actor.position + Vector2.RIGHT * PPM * 5.0
	check("neighboring_lane_does_not_stop_traffic",
		is_equal_approx(flow._player_awareness(agent, PPM * 6.0), PPM * 6.0))
	var other=CharacterBody2D.new()
	other.set_script(CarScript)
	other.position=Vector2(9000,9000)
	root.add_child(other)
	await physics_frame
	var player2:=PlayerScene.instantiate()
	player2.position=Vector2(9000,9400)
	root.add_child(player2)
	player2.set_physics_process(false)
	player2.police_collision.connect(func(_speed: float): police_contacts += 1)
	await physics_frame
	# Test the exact same collision callback used by the player controller:
	# impact physically displaces the traffic car without disabling collision.
	player2.linear_velocity = Vector2.UP*18.0
	for frame in 100:
		await physics_frame
		player2.step_vehicle(1.0/60.0,Vector4.ZERO)
		if int(other.impact_count)>0:
			break
	check("player_car_collision_pushes_traffic",other.impact_count>0,other.impact_count)
	check("player_keeps_momentum_against_traffic",
		player2.linear_velocity.length() > 4.5,player2.linear_velocity)
	check("collision_keeps_player_velocity_synced",player2.velocity.distance_to(
		player2.linear_velocity*20.0)<0.02,player2.velocity)
	check("civilian_crash_does_not_report_police_contact", police_contacts == 0)
	# Repeat the real physics collision with a police patrol, not a synthetic signal.
	var police_car := CharacterBody2D.new()
	police_car.set_script(CarScript)
	if not patrols.is_empty():
		police_car.set("patrol_model", patrols[0])
	police_car.position = Vector2(15000,15000)
	root.add_child(police_car)
	player2.position = Vector2(15000,15400)
	player2.rotation = 0.0
	player2.linear_velocity = Vector2.UP*18.0
	await physics_frame
	for frame in 100:
		await physics_frame
		player2.step_vehicle(1.0/60.0,Vector4.ZERO)
		if police_contacts > 0:
			break
	check("real_police_patrol_crash_reports_contact", police_contacts > 0, police_contacts)
	print("TRAFFIC ART / COLLISION / RECOVERY: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
