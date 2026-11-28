extends Node2D
## Shared top-down running, brake and reverse lights for player, rival,
## multiplayer and traffic cars. Sprite-space glow avoids a Light2D per car.
## Lamps use the visible body silhouette and optional per-model UV anchors.
const DEFAULT_BOUNDS := Rect2(Vector2(-19.0,-38.0),Vector2(38.0,76.0))
var vehicle: Node2D
var rear_points: Array[Vector2] = []
var front_points: Array[Vector2] = []
var braking := false
var reversing := false
var _ready_to_draw := false

static func rear_points_from_bounds(bounds: Rect2, left_uv: Vector2 = Vector2(.20,.925),
		right_uv: Vector2 = Vector2(.80,.925)) -> Array[Vector2]:
	return [bounds.position+bounds.size*left_uv,
		bounds.position+bounds.size*right_uv]

static func brake_lights_active(brake_input: float, handbrake_input: float,
		in_reverse: bool) -> bool:
	return not in_reverse and maxf(brake_input,handbrake_input*.65) > .12

static func points_for(body: Node2D, front: bool = false) -> Array[Vector2]:
	var bounds: Rect2 = DEFAULT_BOUNDS
	var left_uv := Vector2(.20,.925)
	var right_uv := Vector2(.80,.925)
	var rig: Node = body.get_node_or_null("Art/Wheels")
	if is_instance_valid(rig):
		var fitted: Rect2 = rig.get("visible_bounds")
		if fitted.has_area():
			bounds=fitted
		var appearance: Resource = rig.get("appearance") as Resource
		if appearance != null:
			left_uv=appearance.get("rear_light_left_uv")
			right_uv=appearance.get("rear_light_right_uv")
	elif body.is_in_group("traffic_vehicle"):
		var raw_width: Variant=body.get("width_px")
		var raw_length: Variant=body.get("length_px")
		# Incomplete traffic proxies may not expose dimensions.
		if (raw_width is float or raw_width is int) and (raw_length is float or raw_length is int):
			var width: float=float(raw_width)
			var length: float=float(raw_length)
			if is_finite(width) and is_finite(length) and width>0 and length>0:
				bounds=Rect2(Vector2(-width*.5,-length*.5),Vector2(width,length))
	if front:
		return [bounds.position+bounds.size*Vector2(.20,.075), bounds.position+bounds.size*Vector2(.80,.075)]
	return rear_points_from_bounds(bounds,left_uv,right_uv)

func _ready() -> void:
	if not is_instance_valid(vehicle):
		vehicle=get_parent() as Node2D
	z_index=3
	# Run after Art's frame animation, including its airborne lift and scale.
	process_priority=10
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(vehicle):
		return
	# Lamp anchors and glow radii are authored in the body's rest coordinates.
	# Copy its complete local transform, not just the scale, to keep them fitted.
	var art:=vehicle.get_node_or_null("Art") as Node2D
	if is_instance_valid(art):transform=art.transform
	var next_brake := false
	var next_reverse := false
	if vehicle is VehicleController2D:
		var car := vehicle as VehicleController2D
		next_brake=brake_lights_active(car.brake,car.handbrake,car.reversing)
		next_reverse=car.reversing
	else:
		next_brake=bool(vehicle.get("brake_lights_on"))
		next_reverse=bool(vehicle.get("reverse_lights_on"))
	var next_points:=points_for(vehicle)
	var next_front:=points_for(vehicle,true)
	if _ready_to_draw and next_brake==braking and next_reverse==reversing and next_points==rear_points and next_front==front_points:
		return
	braking=next_brake
	reversing=next_reverse
	rear_points=next_points
	front_points=next_front
	_ready_to_draw=true
	queue_redraw()

func _draw() -> void:
	for point in front_points:
		draw_circle(point,5.5,Color(.82,.91,1.0,.13))
		draw_circle(point,2.4,Color(.95,.97,1.0,.86))
	if rear_points.size()!=2:
		return
	for point in rear_points:
		# Dim running lamps stay on; braking intensifies without affecting
		# the underlying car artwork or physics collision.
		var glow := Color(1.0,.08,.045,.22) if braking else Color(.85,.065,.052,.075)
		draw_circle(point,11.0 if braking else 7.0,glow)
		draw_circle(point,5.1 if braking else 3.6,
			Color(1.0,.12,.09,.42) if braking else Color(.70,.07,.06,.44))
		draw_circle(point,2.9 if braking else 2.3,
			Color(1.0,.31,.19,.98) if braking else Color(.91,.13,.08,.76))
	if reversing:
		# White reverse lamps sit just inside the red lamp pair.
		var middle: Vector2=(rear_points[0]+rear_points[1])*.5
		for point in rear_points:
			var inside: Vector2=point.lerp(middle,.42)
			draw_circle(inside,7.0,Color(.8,.92,1.0,.15))
			draw_circle(inside,2.8,Color(.95,.97,1.0,.94))
