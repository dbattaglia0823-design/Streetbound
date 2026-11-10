extends Node2D
## Bounded near-player traffic with real car artwork, physical collision,
## directed lane routing and local post-collision path recovery.
const Network = preload("res://scripts/world/traffic_network.gd")
const Car = preload("res://scripts/world/traffic_car.gd")
const PPM := 20.0
const PALETTE := [
	Color("7b8b9b"),Color("b5b6aa"),Color("a08f7a"),Color("617a77"),
	Color("a77c6b"),Color("8b94a4"),Color("c9c1ad"),Color("515d67")
]

@export_range(0,30,1) var maximum_vehicles := 16
@export var enabled := true
var world: Node2D
var player: VehicleController2D
var network
var agents: Array[Dictionary] = []
var random := RandomNumberGenerator.new()
var active_junctions: Dictionary = {}
var _id_serial := 0
var _spawn_clock := 0.0
var _simulation_clock := 0.0
var show_routes := false


func _ready() -> void:
	name = "AmbientTraffic"
	random.seed = 260822
	network = Network.new()
	if world != null:
		network.build(world.data)
	z_index = 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _unhandled_input(event: InputEvent) -> void:
	# F6 previews actual routed paths rather than unrelated guessed lines.
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode==KEY_F5:
			enabled=not enabled
			if not enabled:
				clear_traffic()
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode==KEY_F6:
			show_routes=not show_routes
			queue_redraw()
			get_viewport().set_input_as_handled()


func clear_traffic() -> void:
	for agent in agents:
		var node: Node2D=agent.node
		if is_instance_valid(node):node.queue_free()
	agents.clear()
	active_junctions.clear()


func _spawn_one() -> bool:
	if not is_instance_valid(player) or network.edges.is_empty():
		return false
	var ids: Array[int] = network.nearby_edges(player.global_position,400.0)
	if ids.is_empty():
		return false
	for attempt in 32:
		var id: int = ids[random.randi_range(0,ids.size()-1)]
		var edge: Dictionary = network.edges[id]
		if bool(edge.connector) or float(edge.length_px)<PPM*35.0:
			continue
		var progress := random.randf_range(PPM*7.0,maxf(PPM*8.0,float(edge.length_px)-PPM*8.0))
		var sample: Dictionary=network.point_on_edge(id,progress)
		var p: Vector2=sample.position
		var away := p.distance_to(player.global_position)
		if away<PPM*75.0 or away>PPM*390.0:
			continue
		if str(world.surface_at(p).name) != "ASPHALT":
			continue
		var free := true
		for other in agents:
			if p.distance_to(other.node.global_position)<PPM*35.0:
				free=false
				break
		if not free:
			continue
		var car := CharacterBody2D.new()
		car.set_script(Car)
		car.name = "TrafficCar%02d" % _id_serial
		car.set("model_index", _id_serial % Car.MODEL_PATHS.size())
		car.car_color = PALETTE[_id_serial%PALETTE.size()]
		car.accent_color=Color("d2c4a7")
		car.global_position=p
		car.rotation=float(sample.angle)
		add_child(car)
		var speed := float(edge.speed_px)*random.randf_range(0.72,0.93)
		agents.append({
			"uid":_id_serial,"node":car,"edge":id,
			"progress":progress,"speed":speed*0.65,"cruise":speed,
			"next":-2,"stop_wait":0.0,"stop_done":false,
			"recovery_time":0.0,"recovery_refresh":0.0,"recovery_goal":{}
		})
		_id_serial+=1
		return true
	return false


func _choose_next(edge: Dictionary) -> int:
	var choices: Array=edge.next
	if choices.is_empty():
		return -1
	var best := -1
	if random.randf()<0.72:
		for option in choices:
			var e: Dictionary=network.edges[int(option)]
			if str(e.get("turn","straight"))=="straight":
				best=int(option)
				break
	if best>=0:
		return best
	return int(choices[random.randi_range(0,choices.size()-1)])


func _car_following(index: int,desired_px: float) -> float:
	var agent: Dictionary=agents[index]
	var distance_to_front := INF
	for i in agents.size():
		if i==index:
			continue
		var other: Dictionary=agents[i]
		if int(other.edge)!=int(agent.edge) or bool(other.node.get("recovering")):
			continue
		var gap := float(other.progress)-float(agent.progress)
		if gap>0.0:
			distance_to_front=minf(distance_to_front,gap)
	if distance_to_front < PPM*24.0:
		return minf(desired_px,maxf(0.0,(distance_to_front-PPM*6.0)*0.7))
	return desired_px


func _player_awareness(agent: Dictionary, desired_px: float,
		travel_direction: Vector2 = Vector2.ZERO) -> float:
	# Use the NPC's actual body, not the saved lane station. After an impact
	# the car may be several metres away from its old route sample.
	if not is_instance_valid(player) or desired_px <= 0.0:
		return desired_px
	var node: CharacterBody2D = agent.node
	var heading := travel_direction.normalized() if travel_direction.length_squared() > 0.001 \
		else Vector2.UP.rotated(node.rotation)
	var relative := player.global_position - node.global_position
	var ahead := relative.dot(heading)
	var sideways := absf(heading.cross(relative))
	# Both body half-lengths plus a buffer; include the real lateral width.
	# Do not yield to a player behind or on a neighboring lane.
	if ahead < -PPM * 0.5 or sideways > PPM * 3.1:
		return desired_px
	var clearance := ahead - PPM * 4.9
	var stopping_distance := desired_px * desired_px / (2.0 * PPM * 9.0)
	if clearance > stopping_distance + PPM * 5.5:
		return desired_px
	return minf(desired_px, maxf(0.0, clearance - PPM * 2.5) * 1.5)


func _next_target(agent: Dictionary,edge: Dictionary) -> int:
	if int(agent.next)==-2:
		agent.next=_choose_next(edge)
	return int(agent.next)


func _tick_agent(index: int,dt: float) -> bool:
	var agent: Dictionary=agents[index]
	var edge: Dictionary=network.edges[int(agent.edge)]
	var node: CharacterBody2D=agent.node
	if not is_instance_valid(node):
		return false
	if node.global_position.distance_to(player.global_position)>PPM*530.0:
		return false
	if bool(node.get("recovering")):
		return _recover_agent(agent,dt)
	var previous_progress := float(agent.progress)
	var remaining := float(edge.length_px)-float(agent.progress)
	var desired := minf(float(edge.speed_px),float(agent.cruise))
	desired=_car_following(index,desired)
	desired=_player_awareness(agent,desired)
	var next_id := -2
	if remaining < maxf(PPM*32.0,float(agent.speed)*1.2):
		next_id=_next_target(agent,edge)
	if next_id>=0:
		var next: Dictionary=network.edges[next_id]
		if bool(next.connector):
			desired=minf(desired,maxf(float(next.speed_px),remaining*0.8))
			var junction := int(next.start_j)
			var owner := int(active_junctions.get(junction,-1))
			var control := str(next.control)
			var should_yield := junction>=0 and owner>=0 and owner!=int(agent.uid)
			if control=="stop" and not bool(agent.stop_done) and remaining<PPM*8.0:
				desired=minf(desired,maxf(0.0,(remaining-PPM*1.3)*0.5))
				if float(agent.speed)<PPM*0.9 and remaining<PPM*2.5:
					agent.stop_wait=float(agent.stop_wait)+dt
					if float(agent.stop_wait)>=0.85:
						agent.stop_done=true
			if control=="yield" and remaining<PPM*13.0:
				desired=minf(desired,PPM*4.0)
			if should_yield and remaining<PPM*7.0:
				desired=0.0
			if control=="stop" and not bool(agent.stop_done) and remaining<PPM*2.4:
				desired=0.0

	var previous := float(agent.speed)
	# Brake decisively when the player is immediately ahead, including
	# when we have only just switched from a crash back to lane following.
	var rate := PPM*5.5 if desired>previous else (PPM*24.0 if desired<PPM*0.2 else PPM*9.0)
	agent.speed=move_toward(previous,desired,rate*dt)
	agent.progress=float(agent.progress)+float(agent.speed)*dt
	if float(agent.progress)>=float(edge.length_px):
		var chosen := _next_target(agent,edge)
		if chosen<0:
			return false
		if bool(edge.connector):
			var old_j := int(edge.end_j)
			if int(active_junctions.get(old_j,-1))==int(agent.uid):
				active_junctions.erase(old_j)
		var next_edge: Dictionary=network.edges[chosen]
		if bool(next_edge.connector) and int(next_edge.start_j)>=0:
			active_junctions[int(next_edge.start_j)]=int(agent.uid)
		var excess := float(agent.progress)-float(edge.length_px)
		agent.edge=chosen
		agent.progress=minf(excess,float(next_edge.length_px)*0.7)
		agent.next=-2
		agent.stop_wait=0.0
		agent.stop_done=false
	var sample: Dictionary=network.point_on_edge(int(agent.edge),float(agent.progress))
	# Move through the physics server, not by teleporting a sprite. A
	# collision marks the agent for local lane rejoining next tick.
	var motion: Vector2 = sample.position - node.global_position
	var collision: Variant = node.call("move_traffic", motion, dt)
	node.rotation=lerp_angle(node.rotation,float(sample.angle),minf(1.0,dt*11.0))
	if collision != null or bool(node.get("recovering")):
		agent.progress=previous_progress
		agent.speed=minf(float(agent.speed),PPM*3.0)
		agent.recovery_time=0.0
		agent.recovery_refresh=0.0
		agent.recovery_goal={}
	return true



func _recover_agent(agent: Dictionary, dt: float) -> bool:
	# The vehicle stays where the collision left it, including on grass or a
	# shoulder. Reproject onto a FORWARD legal lane only, and drive toward a
	# point ahead of the projection. Never reset to the original waypoint.
	var node: CharacterBody2D = agent.node
	var age: float = float(agent.get("recovery_time",0.0)) + dt
	agent.recovery_time=age
	# Release previous junction claims when a crash blocks the intersection.
	if age <= dt + 0.0001:
		for key in active_junctions.keys():
			if int(active_junctions[key]) == int(agent.uid):
				active_junctions.erase(key)
	agent.recovery_refresh=float(agent.get("recovery_refresh",0.0))-dt
	if float(agent.recovery_refresh) <= 0.0:
		var forward := Vector2.UP.rotated(node.rotation)
		var goal: Dictionary = network.recovery_target(node.global_position,
			forward,int(agent.edge))
		agent.recovery_goal=goal
		agent.recovery_refresh=0.24
	var target: Dictionary = agent.recovery_goal
	if target.is_empty():
		agent.speed=0.0
		node.call("move_traffic", Vector2.ZERO, dt)
		# If a car gets trapped outside all routes, don't pop it out of
		# existence while the player watches. Recycle after they drive away.
		return age < 18.0 or node.global_position.distance_to(player.global_position) < PPM*130.0
	var intended: Vector2 = target.lookahead
	var delta: Vector2 = intended - node.global_position
	var desired_angle := delta.angle() + PI * 0.5
	# Gentle low-speed steering makes a recovery visible rather than an
	# impossible sideways slide. Knockback fades in move_traffic().
	node.rotation=lerp_angle(node.rotation,desired_angle,minf(1.0,dt*2.65))
	var direction := Vector2.UP.rotated(node.rotation)
	var goal_speed := clampf(delta.length() * 0.75,PPM*1.0,PPM*6.0)
	# Recovery must also yield. It previously drove blindly toward its lane
	# and repeatedly pushed a player who was already in front of the car.
	goal_speed = _player_awareness(agent, goal_speed, direction)
	var blocked_by_player := goal_speed <= 0.01
	var speed := 0.0 if blocked_by_player else move_toward(
		float(agent.speed), goal_speed, PPM*5.5*dt)
	if blocked_by_player:
		# Remove residual crash momentum aimed at the player while waiting.
		var toward_player := (player.global_position - node.global_position).normalized()
		var recoil: Vector2 = node.recovery_velocity
		if recoil.dot(toward_player) > 0.0:
			node.recovery_velocity = recoil.slide(toward_player)
	agent.speed=speed
	var hit: Variant = node.call("move_traffic", direction*speed*dt,dt)
	if hit != null:
		agent.speed=0.0
	# Once aligned with a real sampled lane, switch back to the existing
	# lane-following and intersection decision logic. The nearest station is
	# computed afresh so the NPC never warps back to its pre-crash progress.
	if node.global_position.distance_to(target.nearest) < PPM*1.25 and \
		direction.dot(Vector2(target.heading)) > 0.77 and \
		(node.get("recovery_velocity") as Vector2).length() < PPM*1.2:
		var found: Dictionary = network.recovery_target(node.global_position,
			direction,int(target.edge),PPM*6.0)
		if not found.is_empty() and float(found.distance_px) < PPM*1.4:
			agent.edge=int(found.edge)
			agent.progress=float(found.progress)
			agent.next=-2
			agent.stop_wait=0.0
			agent.stop_done=false
			agent.recovery_time=0.0
			agent.recovery_refresh=0.0
			agent.recovery_goal={}
			node.set("recovering",false)
	return true

func _physics_process(dt: float) -> void:
	if not enabled or not is_instance_valid(player) or network==null:
		return
	var step := minf(dt,0.05)
	_simulation_clock+=step
	for i in range(agents.size()-1,-1,-1):
		if not _tick_agent(i,step):
			var node: Node2D=agents[i].node
			if is_instance_valid(node):node.queue_free()
			var agent_id := int(agents[i].uid)
			for j in active_junctions.keys():
				if int(active_junctions[j])==agent_id:active_junctions.erase(j)
			agents.remove_at(i)
	_spawn_clock+=step
	if _spawn_clock>0.6 and agents.size()<maximum_vehicles:
		_spawn_clock=0.0
		_spawn_one()
	if show_routes and int(_simulation_clock*3.0)!=int((_simulation_clock-step)*3.0):
		queue_redraw()


func _draw() -> void:
	if not show_routes or not is_instance_valid(player) or network==null:
		return
	var mid := player.global_position
	var painted := 0
	for edge in network.edges:
		if painted>140:
			break
		var path: PackedVector2Array=edge.points
		if path.is_empty() or path[0].distance_to(mid)>PPM*350.0:
			continue
		draw_polyline(path,Color(0.96,0.67,0.30,0.52) if bool(edge.connector)
			else Color(0.17,0.94,0.91,0.40),2.0,true)
		painted+=1
