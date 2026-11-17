extends Control
## Lightweight edge-of-screen awareness for traffic, racing opponents and
## local multiplayer. Positions are computed from the *actual* viewport's
## camera canvas transform, so zoom, follow rotation and split views work.
## This is an informational HUD only: it never modifies vehicle movement.
const PPM := 20.0
const MAX_RANGE_M := 260.0
const MIN_RANGE_M := 8.0
const MIN_CLOSING_MPS := 1.25
const FORWARD_DOT := 0.24
const MAX_MARKERS := 3
const REFRESH_SECONDS := 0.12
const VISIBLE_MARGIN_PX := 45.0
const EDGE_MARGIN := Vector2(94.0, 99.0)
const CHIP_WIDTH := 144.0
const CHIP_HEIGHT := 35.0
const INK := Color("#e8f0e9")
const ROAD := Color("#ffa85e")
const RIVAL := Color("#83cefd")

var player: VehicleController2D
var camera: Camera2D
var traffic: Node
var markers: Array[Dictionary] = []
var _clock := 0.0


func _ready() -> void:
	name = "OffscreenVehicleAwareness"
	add_to_group("streetbound_vehicle_awareness")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)


static func approach_info(player_position: Vector2, player_velocity: Vector2,
		forward: Vector2, other_position: Vector2,
		other_velocity: Vector2) -> Dictionary:
	var delta := other_position - player_position
	var distance_m := delta.length() / PPM
	if distance_m < MIN_RANGE_M or distance_m > MAX_RANGE_M:
		return {}
	var direction := delta.normalized()
	if direction.dot(forward.normalized()) < FORWARD_DOT:
		return {}
	var closing := (player_velocity - other_velocity).dot(direction)
	if closing < MIN_CLOSING_MPS:
		return {}
	return {"distance_m": distance_m, "closing_mps": closing}


static func is_on_screen(point: Vector2, view_size: Vector2,
		margin: float = VISIBLE_MARGIN_PX) -> bool:
	return Rect2(-Vector2.ONE * margin,
		view_size + Vector2.ONE * margin * 2.0).has_point(point)


static func edge_position(from_screen: Vector2, toward_screen: Vector2,
		view_size: Vector2, margin: Vector2 = EDGE_MARGIN) -> Vector2:
	# Ray/rectangle intersection gives a bearing-accurate edge marker. Clamp
	# the origin first because speed-follow cameras can lead far ahead.
	var low := Vector2(minf(margin.x,view_size.x*0.25),
		minf(margin.y,view_size.y*0.25))
	var high := view_size - low
	var origin := Vector2(clampf(from_screen.x,low.x,high.x),
		clampf(from_screen.y,low.y,high.y))
	var delta := toward_screen - from_screen
	if delta.length_squared() < 0.001:
		return origin
	var scale := INF
	if delta.x > 0.0001:
		scale = minf(scale,(high.x-origin.x)/delta.x)
	elif delta.x < -0.0001:
		scale = minf(scale,(low.x-origin.x)/delta.x)
	if delta.y > 0.0001:
		scale = minf(scale,(high.y-origin.y)/delta.y)
	elif delta.y < -0.0001:
		scale = minf(scale,(low.y-origin.y)/delta.y)
	return Vector2(
		clampf(origin.x+delta.x*maxf(0.0,scale),low.x,high.x),
		clampf(origin.y+delta.y*maxf(0.0,scale),low.y,high.y))


static func distance_caption(distance_m: float, rival: bool = false) -> String:
	var feet := roundi(maxf(0.0,distance_m)*3.28084 / 5.0)*5
	return "%s %d FT" % ["RIVAL" if rival else "CAR",feet]


func _process(dt: float) -> void:
	if get_tree().paused:
		if not markers.is_empty():
			markers.clear()
			queue_redraw()
		return
	_clock -= dt
	if _clock > 0.0:
		return
	_clock = REFRESH_SECONDS
	refresh_markers()


func _traffic_velocity(node: Node2D) -> Vector2:
	# TrafficFlow moves collidable CharacterBody2Ds using move_and_collide,
	# not CharacterBody2D.velocity. Use its actual agent speed (px/s).
	if is_instance_valid(traffic):
		var agents: Variant = traffic.get("agents")
		if agents is Array:
			for item in agents:
				if item is Dictionary and item.get("node") == node:
					if bool(node.get("recovering")):
						return Vector2.ZERO
					return Vector2.UP.rotated(node.global_rotation) * \
						float(item.get("speed",0.0)) / PPM
	if node is VehicleController2D:
		return (node as VehicleController2D).linear_velocity
	if node is CharacterBody2D:
		return (node as CharacterBody2D).velocity / PPM
	return Vector2.ZERO


func refresh_markers() -> void:
	markers.clear()
	if not is_instance_valid(player) or not is_instance_valid(camera) or \
			get_tree().paused or not player.is_inside_tree():
		queue_redraw()
		return
	var view: Viewport = camera.get_viewport()
	if view == null or view != get_viewport() or not camera.is_current():
		queue_redraw()
		return
	var size_px := view.get_visible_rect().size
	if size_px.x < 220.0 or size_px.y < 180.0:
		queue_redraw()
		return
	var canvas_transform := view.get_canvas_transform()
	var player_screen: Vector2 = canvas_transform * player.global_position
	var forward := Vector2.UP.rotated(player.global_rotation)
	if player.linear_velocity.length_squared() >= 9.0:
		forward = player.linear_velocity.normalized()
	var matches: Array[Dictionary] = []
	var seen := {}
	for group_name in ["traffic_vehicle","race_opponent","local_multiplayer_vehicle"]:
		for raw in get_tree().get_nodes_in_group(group_name):
			if not raw is Node2D:
				continue
			var target := raw as Node2D
			if target == player or not is_instance_valid(target) or \
					target.is_queued_for_deletion() or not target.is_visible_in_tree():
				continue
			var key := target.get_instance_id()
			if seen.has(key):
				continue
			seen[key] = true
			var info := approach_info(player.global_position,
				player.linear_velocity,forward,target.global_position,
				_traffic_velocity(target))
			if info.is_empty():
				continue
			var target_screen: Vector2 = canvas_transform * target.global_position
			if is_on_screen(target_screen,size_px):
				continue
			var rival: bool = str(group_name) != "traffic_vehicle"
			matches.append({
				"position":edge_position(player_screen,target_screen,size_px),
				"direction":(target_screen-player_screen).normalized(),
				"distance_m":float(info.distance_m),
				"closing_mps":float(info.closing_mps),
				"rival":rival,
				"target":target
			})
	matches.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return float(a.distance_m) < float(b.distance_m))
	for entry in matches:
		if markers.size() >= MAX_MARKERS:
			break
		var at: Vector2 = entry.position
		for placed in markers:
			if at.distance_to(placed.position) < 63.0:
				at.y = clampf(at.y + (63.0 if at.y < size_px.y*0.5 else -63.0),
					minf(EDGE_MARGIN.y,size_px.y*0.25),
					maxf(size_px.y*0.75,size_px.y-EDGE_MARGIN.y))
		entry.position = at
		markers.append(entry)
	queue_redraw()


func _draw() -> void:
	if markers.is_empty() or get_tree().paused:
		return
	var font: Font = ThemeDB.fallback_font
	for entry in markers:
		var position: Vector2 = entry.position
		var near := float(entry.distance_m) < 55.0
		var color: Color = RIVAL if bool(entry.rival) else ROAD
		if not near and not bool(entry.rival):
			color = Color("#e6c29a")
		var bounds := Rect2(position - Vector2(CHIP_WIDTH*0.5,CHIP_HEIGHT*0.5),
			Vector2(CHIP_WIDTH,CHIP_HEIGHT))
		draw_rect(bounds,Color(0.032,0.047,0.056,0.88),true)
		draw_rect(bounds,color.darkened(0.3),false,1.2)
		var tip := position + Vector2(-46.0,0.0)
		var angle: float = (entry.direction as Vector2).angle() + PI*0.5
		var triangle := PackedVector2Array([
			tip+Vector2(0.0,-10.0).rotated(angle),
			tip+Vector2(-7.0,8.0).rotated(angle),
			tip+Vector2(7.0,8.0).rotated(angle)])
		draw_colored_polygon(triangle,color)
		var caption := distance_caption(
			float(entry.distance_m),bool(entry.rival))
		draw_string(font,position + Vector2(-30.0,5.0),
			caption,HORIZONTAL_ALIGNMENT_LEFT,99.0,13,INK)
