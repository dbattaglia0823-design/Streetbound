extends RefCounted
## Solid, editable guardrail paths. Authored coordinates are metres; all
## physics shapes are created in the same 20 px/m frame as VehicleController2D.
const PPM := 20.0
const MAX_COLLISION_SPAN_M := 8.0
const MIN_WIDTH_M := 0.35
const MAX_WIDTH_M := 2.5


static func runtime_path_m(prop: Dictionary) -> PackedVector2Array:
	var path := PackedVector2Array()
	var center_raw: Array = prop.get("p",[0.0,0.0])
	if center_raw.size()!=2:
		return path
	var center := Vector2(float(center_raw[0]),float(center_raw[1]))
	var angle := float(prop.get("angle",0.0))
	var axes: Array=prop.get("guardrail_scale",[1.0,1.0])
	if axes.size()!=2:
		return path
	var scale_axes := Vector2(float(axes[0]),float(axes[1]))
	for point in prop.get("guardrail_points",[]):
		if not point is Array or point.size()!=2:
			return PackedVector2Array()
		path.append(center + (Vector2(float(point[0]),float(point[1])) *
			scale_axes).rotated(angle))
	return path


static func collision_shapes(body: StaticBody2D, world_points_m: PackedVector2Array,
		width_m: float, origin_m: Vector2 = Vector2.ZERO,
		chunk_bounds_m: Rect2 = Rect2(), editor_id: String = "") -> int:
	if world_points_m.size()<2 or width_m<0.05 or width_m>12.5:
		return 0
	var created := 0
	for segment in range(1,world_points_m.size()):
		var first: Vector2 = world_points_m[segment-1]
		var last: Vector2 = world_points_m[segment]
		var segment_m := last-first
		var length_m := segment_m.length()
		if length_m < 0.05:
			continue
		# Individual spans have a unique midpoint owner in streamed chunks;
		# no 200m-long static collider wakes up in a distant loaded cell.
		var sections := maxi(1,ceili(length_m/MAX_COLLISION_SPAN_M))
		for part in sections:
			var a := first.lerp(last,float(part)/float(sections))
			var b := first.lerp(last,float(part+1)/float(sections))
			var middle := (a+b)*0.5
			if chunk_bounds_m.has_area() and not chunk_bounds_m.has_point(middle):
				continue
			var shape := RectangleShape2D.new()
			# Tiny overlap makes adjacent spans behave as one solid rail.
			shape.size = Vector2(a.distance_to(b)+0.04,width_m)*PPM
			var collider := CollisionShape2D.new()
			collider.shape = shape
			collider.position = (middle-origin_m)*PPM
			collider.rotation = (b-a).angle()
			if not editor_id.is_empty():
				collider.set_meta("draft_prop_id",editor_id)
				collider.set_meta("editor_prop_key","authored:"+editor_id)
			body.add_child(collider)
			created += 1
	return created
