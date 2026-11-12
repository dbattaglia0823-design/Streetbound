extends Node2D
## Low-layer dealership pavement: road surfaces always render over the access
## throat. The building and sign are separate, above the road.
const PPM := 20.0
const ROAD_ASPHALT := Color("58656c")
const CURB := Color("c4c4b9")
var site: Dictionary = {}


## Shared geometry for visual paint AND driving-surface queries. Coordinates
## are metres in the site's local (road-facing -Y) reference frame.
static func lot_rect(site_data: Dictionary) -> Rect2:
	var setback: float = float(site_data.get("setback_m", 36.0))
	return Rect2(Vector2(-16.0, -setback + 5.0),
		Vector2(32.0, setback - 14.5))


static func entrance_polygon(site_data: Dictionary) -> PackedVector2Array:
	var setback: float = float(site_data.get("setback_m", 36.0))
	return PackedVector2Array([
		Vector2(-6.0, -setback - 3.0),
		Vector2(6.0, -setback - 3.0),
		Vector2(7.5, -setback + 9.0),
		Vector2(-7.5, -setback + 9.0)
	])


static func contains_pavement(site_data: Dictionary, position_px: Vector2) -> bool:
	var center_raw: Array = site_data.get("center_m", [])
	if center_raw.size() != 2:
		return false
	var center := Vector2(float(center_raw[0]), float(center_raw[1]))
	var local: Vector2 = (position_px / PPM - center).rotated(
		-float(site_data.get("rotation", 0.0)))
	return lot_rect(site_data).has_point(local) or \
		Geometry2D.is_point_in_polygon(local, entrance_polygon(site_data))


func _ready() -> void:
	name = "DealershipPavement_" + str(site.id)
	position = Vector2(float(site.center_m[0]), float(site.center_m[1])) * PPM
	rotation = float(site.rotation)
	# Road shoulder/sidewalk stage is 1; actual pavement and markings are 2-4.
	# This lets the main road paint naturally over the end of the driveway.
	z_index = 1
	material = preload("res://scripts/world/scenery_cutout.tres")
	queue_redraw()


func _draw() -> void:
	if site.is_empty():
		return
	var lot_m: Rect2 = lot_rect(site)
	var lot := Rect2(lot_m.position * PPM, lot_m.size * PPM)
	var half_width: float = lot.size.x * 0.5
	var front: float = lot.end.y
	var back: float = lot.position.y
	var shoulder: float = 0.6 * PPM
	# Same tapered throat points drive both rendered asphalt and the
	# physically drivable surface query; no visual/traction disagreement.
	var entrance_m: PackedVector2Array = entrance_polygon(site)
	var throat_poly := PackedVector2Array()
	for pt in entrance_m:
		throat_poly.append(pt * PPM)
	var throat_half_width: float = absf(throat_poly[0].x)
	var throat_inner_half: float = absf(throat_poly[2].x)
	var join_start: float = throat_poly[0].y
	var join_end: float = throat_poly[2].y
	# Existing asphalt shader adds continuous, world-aligned aggregate.
	draw_rect(lot.grow(shoulder), CURB)
	draw_rect(lot, ROAD_ASPHALT)
	# Open a genuine curb break. The tapered opening widens as it reaches
	# the parking aisle; no flat road-spanning rectangle can mask lane paint.
	draw_colored_polygon(throat_poly, ROAD_ASPHALT)
	# Recessed perimeter kerbs (only sides and the far/back edge).
	var left: float = -half_width + shoulder * 0.55
	var right: float = half_width - shoulder * 0.55
	draw_line(Vector2(left, back), Vector2(left, front), Color("dfded2"), 4.0, true)
	draw_line(Vector2(right, back), Vector2(right, front), Color("dfded2"), 4.0, true)
	draw_line(Vector2(left, front), Vector2(right, front), Color("dfded2"), 4.0, true)
	# Road-facing curb returns stop at the flared opening, not across it.
	var curb_y: float = back - shoulder * 0.4
	var curb_mouth: float = lerpf(throat_half_width, throat_inner_half,
		clampf((curb_y - join_start) / (join_end - join_start), 0.0, 1.0))
	for side in [-1.0, 1.0]:
		var sign: float = float(side)
		draw_line(Vector2(sign * curb_mouth, curb_y),
			Vector2(sign * (half_width + shoulder), curb_y),
			Color("d9d7ca"), 5.0, true)
	# Parking marks scale with actual lot setback (34/42/52m): keep
	# individual stalls ~4.5-5.0m long rather than stretching three huge
	# spaces across larger forecourts. A clear 13m two-way aisle remains.
	var bay_start: float = back + PPM * 6.0
	var bay_end: float = front - PPM * 2.0
	var stall_count: int = clampi(roundi((bay_end - bay_start) /
		(PPM * 4.8)), 2, 8)
	for side in [-1.0, 1.0]:
		var bay_side: float = float(side)
		var inner_x: float = bay_side * half_width * 0.42
		var outer_x: float = bay_side * half_width * 0.90
		for i in stall_count + 1:
			var y: float = lerpf(bay_start, bay_end,
				float(i) / float(stall_count))
			draw_line(Vector2(inner_x, y), Vector2(outer_x, y),
				Color("d9d7c9"), 3.0, true)
		draw_line(Vector2(inner_x, bay_start),
			Vector2(inner_x, bay_end), Color("cbcbbd"), 3.0, true)
	# Faded tire paths and longitudinal drainage lanes reuse the road palette.
	for side in [-1.0, 1.0]:
		var track_x: float = float(side) * PPM * 2.4
		draw_line(Vector2(track_x, back + PPM * 2.0),
			Vector2(track_x, front - PPM * 3.0), Color(.10,.14,.16,.12), PPM * .30, true)
	# Dedicated interaction/browse spot stays visible but unobstructed.
	var browse_y: float = -17.0 * PPM
	draw_rect(Rect2(Vector2(-PPM * 5.5, browse_y - PPM * 5.0),
		Vector2(PPM * 11.0, PPM * 10.0)), Color("c2b894"), false, 3.0, true)
	# Deterministic, fine-grained weathering that won't shimmer in streamed world.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site.get("pavement_seed", 7092))
	for i in 28:
		var wear_x: float = rng.randf_range(-half_width + PPM, half_width - PPM)
		var wear_y: float = rng.randf_range(back + PPM, front - PPM)
		var center := Vector2(wear_x, wear_y)
		draw_line(center, center + Vector2(rng.randf_range(6.0, 32.0),
			rng.randf_range(-5.0, 5.0)), Color(.09,.14,.16,.11), 1.6, true)
