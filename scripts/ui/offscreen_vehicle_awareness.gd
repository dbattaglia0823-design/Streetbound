extends Control
## Lightweight edge-of-screen awareness for traffic, racing opponents and
## local multiplayer. Positions are computed from the *actual* viewport's
## camera canvas transform, so zoom, follow rotation and split views work.
## This is an informational HUD only: it never modifies vehicle movement.
const PPM := 20.0
const MAX_RANGE_M := 182.88  # 600 ft hard cap at 100 mph and faster
const MIN_SPEED_RANGE_M := 91.44  # 300 ft just above 40 mph
const FULL_RANGE_SPEED_MPH := 100.0
const MIN_RANGE_M := 8.0
const MIN_CLOSING_MPS := 1.25
const MPS_TO_MPH := 2.2369362920544
const MIN_PLAYER_SPEED_MPH := 40.0
## A 270-degree forward/side sweep: up to 135 degrees left or right.
## Exclude only the 90-degree sector directly behind the driver. The closing
## speed check still rejects traffic heading away, even in the widened area.
const FORWARD_DOT := -0.7071067811865476
const MAX_MARKERS := 3
const REFRESH_SECONDS := 0.10
# Once a tracked vehicle enters view, let its edge chip fade out smoothly.
# Faster player speeds need a shorter reminder because the car passes sooner.
const MAX_ONSCREEN_HOLD_S := 1.0
const MIN_ONSCREEN_HOLD_S := 0.25
const VISIBLE_MARGIN_PX := 45.0
const EDGE_MARGIN := Vector2(58.0, 76.0)
const CHIP_WIDTH := 92.0
const CHIP_HEIGHT := 27.0
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


static func player_is_fast_enough(velocity_mps: Vector2) -> bool:
	# The vehicle physics use meters/second, while the HUD shows mph.
	return velocity_mps.length() * MPS_TO_MPH > MIN_PLAYER_SPEED_MPH


static func detection_range_m(player_velocity_mps: Vector2) -> float:
	# At just above 40 mph warn within 300 ft; grow linearly to 600 ft at
	# 100 mph, and never exceed the 600 ft cap. The separate speed gate
	# prevents any warning at 40 mph or below.
	var speed_mph := player_velocity_mps.length() * MPS_TO_MPH
	var fraction := clampf((speed_mph - MIN_PLAYER_SPEED_MPH) /
		(FULL_RANGE_SPEED_MPH - MIN_PLAYER_SPEED_MPH), 0.0, 1.0)
	return lerpf(MIN_SPEED_RANGE_M, MAX_RANGE_M, fraction)


static func onscreen_hold_seconds(player_velocity_mps: Vector2) -> float:
	# Same 40–100 mph envelope as detection distance: 1 second at 40 mph,
	# 0.625 seconds at 70 mph, 0.25 seconds at 100 mph and beyond.
	var speed_mph := player_velocity_mps.length() * MPS_TO_MPH
	var fraction := clampf((speed_mph - MIN_PLAYER_SPEED_MPH) /
		(FULL_RANGE_SPEED_MPH - MIN_PLAYER_SPEED_MPH), 0.0, 1.0)
	return lerpf(MAX_ONSCREEN_HOLD_S, MIN_ONSCREEN_HOLD_S, fraction)


static func approach_info(player_position: Vector2, player_velocity: Vector2,
		forward: Vector2, other_position: Vector2,
		other_velocity: Vector2) -> Dictionary:
	if not player_is_fast_enough(player_velocity):
		return {}
	var delta := other_position - player_position
	var distance_m := delta.length() / PPM
	if distance_m < MIN_RANGE_M or distance_m > detection_range_m(player_velocity):
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


static func distance_caption(distance_m: float, _rival: bool = false) -> String:
	# Show only the distance, rounded to individual feet for live updates.
	return "%d FT" % roundi(maxf(0.0,distance_m)*3.28084)


func _process(dt: float) -> void:
	# Stop warnings immediately when slowing to 40 mph or below instead of
	# leaving a stale chip visible until the next traffic discovery scan.
	if get_tree().paused or not is_instance_valid(player) or \
			not player_is_fast_enough(player.linear_velocity):
		# Recheck traffic immediately upon returning above 40 mph or unpausing.
		_clock = 0.0
		if not markers.is_empty():
			markers.clear()
			queue_redraw()
		return
	# Update active targets and countdowns every frame; a discovery scan must
	# not reset the hold timer of an already-visible vehicle.
	_update_live_markers(dt)
	_clock -= dt
	if _clock <= 0.0:
		# Discover new traffic at 100 ms intervals, but retain live markers.
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
	if not is_instance_valid(player) or not is_instance_valid(camera) or \
			get_tree().paused or not player.is_inside_tree() or \
			not player_is_fast_enough(player.linear_velocity):
		markers.clear()
		queue_redraw()
		return
	var view: Viewport = camera.get_viewport()
	if view == null or view != get_viewport() or not camera.is_current():
		markers.clear()
		queue_redraw()
		return
	var size_px := view.get_visible_rect().size
	if size_px.x < 220.0 or size_px.y < 180.0:
		markers.clear()
		queue_redraw()
		return
	# Preserve previously detected targets through refreshes, including ones
	# now inside the view whose short fade-out has not yet expired.
	_update_live_markers(0.0)
	var canvas_transform := view.get_canvas_transform()
	var player_screen: Vector2 = canvas_transform * player.global_position
	var forward := Vector2.UP.rotated(player.global_rotation)
	if player.linear_velocity.length_squared() >= 9.0:
		forward = player.linear_velocity.normalized()
	var matches: Array[Dictionary] = markers.duplicate()
	var seen := {}
	for previous in matches:
		var tracked: Node2D = previous.get("target") as Node2D
		if is_instance_valid(tracked):
			seen[tracked.get_instance_id()] = true
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
	# Active offscreen hazards take priority over on-screen fading reminders
	# when all three available marker slots are occupied.
	matches.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var a_holding := bool(a.get("onscreen_hold", false))
		var b_holding := bool(b.get("onscreen_hold", false))
		if a_holding != b_holding:
			return not a_holding
		return float(a.distance_m) < float(b.distance_m))
	markers.clear()
	for entry in matches:
		if markers.size() >= MAX_MARKERS:
			break
		var at: Vector2 = entry.position
		for placed in markers:
			if at.distance_to(placed.position) < 48.0:
				at.y = clampf(at.y + (48.0 if at.y < size_px.y*0.5 else -48.0),
					minf(EDGE_MARGIN.y,size_px.y*0.25),
					maxf(size_px.y*0.75,size_px.y-EDGE_MARGIN.y))
		entry.position = at
		markers.append(entry)
	queue_redraw()


func _update_live_markers(dt: float = 0.0) -> void:
	if markers.is_empty():
		return
	if not is_instance_valid(player) or not is_instance_valid(camera) or \
			not player.is_inside_tree() or \
			not player_is_fast_enough(player.linear_velocity):
		markers.clear()
		queue_redraw()
		return
	var view: Viewport = camera.get_viewport()
	if view == null or view != get_viewport() or not camera.is_current():
		markers.clear()
		queue_redraw()
		return
	var size_px := view.get_visible_rect().size
	var canvas_transform := view.get_canvas_transform()
	var player_screen: Vector2 = canvas_transform * player.global_position
	var forward := Vector2.UP.rotated(player.global_rotation)
	if player.linear_velocity.length_squared() >= 9.0:
		forward = player.linear_velocity.normalized()
	var updated: Array[Dictionary] = []
	for entry in markers:
		var target: Node2D = entry.get("target") as Node2D
		if not is_instance_valid(target) or target.is_queued_for_deletion() or \
				not target.is_visible_in_tree():
			continue
		var delta := target.global_position - player.global_position
		var distance_m := delta.length() / PPM
		# A car outside the speed-adaptive warning range is no longer nearby,
		# even if it had started an on-screen transition.
		if distance_m > detection_range_m(player.linear_velocity):
			continue
		var target_screen: Vector2 = canvas_transform * target.global_position
		var onscreen := is_on_screen(target_screen,size_px)
		var live_entry: Dictionary = entry.duplicate()
		live_entry.distance_m = distance_m
		live_entry.direction = (target_screen-player_screen).normalized()
		if onscreen:
			# Only a previously tracked offscreen vehicle may start a hold.
			# Keep the chip at the edge instead of covering the now-visible car.
			if not bool(entry.get("onscreen_hold",false)):
				var hold_seconds := onscreen_hold_seconds(player.linear_velocity)
				live_entry.onscreen_hold = true
				live_entry.hold_elapsed_s = 0.0
				live_entry.hold_remaining_s = hold_seconds
				live_entry.hold_total_s = hold_seconds
			else:
				# Measure time since entry, not since the last 100 ms scan.
				# Acceleration shortens the allowed *total* duration; braking
				# cannot increase an already-started hold.
				var elapsed := float(entry.get("hold_elapsed_s",0.0)) + dt
				var total := minf(float(entry.get("hold_total_s",1.0)),
					onscreen_hold_seconds(player.linear_velocity))
				live_entry.hold_elapsed_s = elapsed
				live_entry.hold_total_s = total
				live_entry.hold_remaining_s = total - elapsed
			if float(live_entry.hold_remaining_s) <= 0.0:
				continue
		else:
			# Once outside view again, restore ordinary closing-traffic rules.
			var info := approach_info(player.global_position,
				player.linear_velocity,forward,target.global_position,
				_traffic_velocity(target))
			if info.is_empty():
				continue
			live_entry.onscreen_hold = false
			live_entry.hold_elapsed_s = 0.0
			live_entry.hold_remaining_s = 0.0
			live_entry.closing_mps = float(info.closing_mps)
			var at := edge_position(player_screen,target_screen,size_px)
			for placed in updated:
				if at.distance_to(placed.position) < 48.0:
					at.y = clampf(at.y + (48.0 if at.y < size_px.y*0.5 else -48.0),
						minf(EDGE_MARGIN.y,size_px.y*0.25),
						maxf(size_px.y*0.75,size_px.y-EDGE_MARGIN.y))
			live_entry.position = at
		updated.append(live_entry)
	markers = updated
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
		var opacity := 1.0
		if bool(entry.get("onscreen_hold",false)):
			opacity = clampf(float(entry.get("hold_remaining_s",0.0)) /
				maxf(float(entry.get("hold_total_s",1.0)),0.001),0.0,1.0)
		color.a *= opacity
		var bounds := Rect2(position - Vector2(CHIP_WIDTH*0.5,CHIP_HEIGHT*0.5),
			Vector2(CHIP_WIDTH,CHIP_HEIGHT))
		var background := Color(0.032,0.047,0.056,0.88 * opacity)
		var outline := color.darkened(0.3)
		draw_rect(bounds,background,true)
		draw_rect(bounds,outline,false,1.2)
		var tip := position + Vector2(-32.0,0.0)
		var angle: float = (entry.direction as Vector2).angle() + PI*0.5
		var triangle := PackedVector2Array([
			tip+Vector2(0.0,-7.0).rotated(angle),
			tip+Vector2(-5.0,6.0).rotated(angle),
			tip+Vector2(5.0,6.0).rotated(angle)])
		draw_colored_polygon(triangle,color)
		var caption := distance_caption(
			float(entry.distance_m),bool(entry.rival))
		var ink := INK
		ink.a *= opacity
		draw_string(font,position + Vector2(-17.0,4.0),
			caption,HORIZONTAL_ALIGNMENT_LEFT,58.0,11,ink)
