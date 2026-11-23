extends RefCounted
## Shared aerodynamic drafting rules. Only longitudinal aero drag is reduced;
## engine torque, tire traction, braking and steering are never amplified.
const PPM := 20.0
const START_SPEED_MPS := 12.0
const FULL_SPEED_MPS := 27.0
const MAX_GAP_M := 38.0
const MAX_DRAG_REDUCTION := 0.18
const SAMPLE_SECONDS := 0.10

## The trailing car must be travelling *forward* behind a moving car in
## nearly the same lane and direction. No wall/side-by-side/reverse drafting.
static func strength_for(follower_at: Vector2, follower_heading: float,
		follower_velocity: Vector2, leader_at: Vector2, leader_heading: float,
		leader_velocity: Vector2) -> float:
	var heading := Vector2.UP.rotated(follower_heading)
	var leader_forward := Vector2.UP.rotated(leader_heading)
	var alignment := heading.dot(leader_forward)
	if alignment < .88:
		return 0.0
	var speed := follower_velocity.dot(heading)
	var lead_speed := leader_velocity.dot(leader_forward)
	if speed < START_SPEED_MPS or lead_speed < START_SPEED_MPS:
		return 0.0
	var relative := (leader_at - follower_at) / PPM
	var ahead := relative.dot(heading)
	if ahead < 2.0 or ahead > MAX_GAP_M:
		return 0.0
	var lateral := absf(relative.dot(Vector2.RIGHT.rotated(follower_heading)))
	if lateral > 3.6:
		return 0.0
	var speed_factor := smoothstep(START_SPEED_MPS,FULL_SPEED_MPS,
		minf(speed,lead_speed))
	var angle_factor := smoothstep(.88,.985,alignment)
	var near_factor := smoothstep(2.0,7.0,ahead)
	var far_factor := 1.0 - smoothstep(16.0,MAX_GAP_M,ahead)
	var lane_factor := 1.0 - smoothstep(1.2,3.6,lateral)
	return clampf(speed_factor*angle_factor*near_factor*far_factor*lane_factor,
		0.0,1.0)


static func aero_drag_multiplier(strength: float) -> float:
	return 1.0 - clampf(strength,0.0,1.0)*MAX_DRAG_REDUCTION


## Queries only nearby live physical racing cars and traffic within the same
## world. Called at 10 Hz rather than once per vehicle per physics tick.
static func best_strength(car: Node2D) -> float:
	if not car.is_inside_tree():
		return 0.0
	var world: Node = car.get("surface_provider") as Node
	if not is_instance_valid(world):
		return 0.0
	var follower_velocity: Vector2 = car.get("linear_velocity")
	var forward: Vector2 = Vector2.UP.rotated(car.rotation)
	if bool(car.get("reversing")) or follower_velocity.dot(forward) < START_SPEED_MPS:
		return 0.0
	var best := 0.0
	for node in car.get_tree().get_nodes_in_group("drafting_vehicle"):
		if node == car or not node is Node2D:
			continue
		var leader := node as Node2D
		if leader.get("surface_provider") != world or \
				car.global_position.distance_squared_to(leader.global_position) > \
				pow(MAX_GAP_M * PPM + 50.0, 2.0):
			continue
		var leader_velocity: Vector2=leader.get("linear_velocity")
		best = maxf(best,strength_for(car.global_position,car.rotation,
			follower_velocity,leader.global_position,leader.rotation,
			leader_velocity))
	for node in car.get_tree().get_nodes_in_group("traffic_vehicle"):
		if not node is Node2D or node.get_parent() == null or \
				node.get_parent().get_parent() != world:
			continue
		var leader := node as Node2D
		if car.global_position.distance_squared_to(leader.global_position) > \
				pow(MAX_GAP_M * PPM + 50.0,2.0):
			continue
		var speed: float=float(leader.get("motion_speed_mps"))
		var lead_velocity := Vector2.UP.rotated(leader.rotation)*speed
		best=maxf(best,strength_for(car.global_position,car.rotation,
			follower_velocity,leader.global_position,leader.rotation,
			lead_velocity))
	return best


## A leading vehicle can show a subtle wake when a racer is actually
## tucked into it. This is visual-only and also works for AI traffic.
static func wake_strength(leader: Node2D, world: Node, velocity: Vector2) -> float:
	if not leader.is_inside_tree() or not is_instance_valid(world):
		return 0.0
	var best := 0.0
	for node in leader.get_tree().get_nodes_in_group("drafting_vehicle"):
		if not node is Node2D or node == leader:
			continue
		var follower := node as Node2D
		if follower.get("surface_provider") != world or \
				follower.global_position.distance_squared_to(leader.global_position) > \
				pow(MAX_GAP_M * PPM + 50.0,2.0):
			continue
		var follower_velocity: Vector2=follower.get("linear_velocity")
		best=maxf(best,strength_for(follower.global_position,follower.rotation,
			follower_velocity,leader.global_position,leader.rotation,
			velocity))
	return best
