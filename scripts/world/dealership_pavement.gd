extends Node2D
## Low-layer dealership pavement: road surfaces always render over the access
## throat. The building and sign are separate, above the road.
const PPM := 20.0
const ROAD_ASPHALT := Color("58656c")
const CURB := Color("c4c4b9")
var site: Dictionary = {}


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
	var d: float = float(site.get("setback_m", 36.0)) * PPM
	var half_width: float = 16.0 * PPM
	var front: float = -9.5 * PPM
	var back: float = -d + 5.0 * PPM
	var shoulder: float = 0.6 * PPM
	# Small road join is 12 m wide and reaches under the road centerline,
	# so it is never a blunt slab placed over the existing asphalt.
	var throat_half_width: float = 6.0 * PPM
	var join_start: float = -d - 3.0 * PPM
	var join_end: float = back + 4.0 * PPM
	var lot := Rect2(Vector2(-half_width, back),
		Vector2(half_width * 2.0, front - back))
	var throat := Rect2(Vector2(-throat_half_width, join_start),
		Vector2(throat_half_width * 2.0, join_end - join_start))
	# Existing asphalt shader adds continuous, world-aligned aggregate.
	draw_rect(lot.grow(shoulder), CURB)
	draw_rect(lot, ROAD_ASPHALT)
	# Draw the mouth after the curb to leave a true interruption in its
	# road-facing edge instead of a curb across the entrance.
	draw_rect(throat, ROAD_ASPHALT)
	# Recessed perimeter kerbs (only sides and the far/back edge).
	var left: float = -half_width + shoulder * 0.55
	var right: float = half_width - shoulder * 0.55
	draw_line(Vector2(left, back), Vector2(left, front), Color("dfded2"), 4.0, true)
	draw_line(Vector2(right, back), Vector2(right, front), Color("dfded2"), 4.0, true)
	draw_line(Vector2(left, front), Vector2(right, front), Color("dfded2"), 4.0, true)
	# Road-facing curb returns stop at the throat; traffic can enter freely.
	var curb_y: float = back - shoulder * 0.4
	for side in [-1.0, 1.0]:
		var sign: float = float(side)
		draw_line(Vector2(sign * throat_half_width, curb_y),
			Vector2(sign * (half_width + shoulder), curb_y),
			Color("d9d7ca"), 5.0, true)
	# Three showroom parking bays per side, leaving a wide two-way aisle.
	for side in [-1.0, 1.0]:
		var bay_side: float = float(side)
		for i in 4:
			var y: float = lerpf(back + PPM * 7.0, front - PPM * 2.0, float(i) / 3.0)
			var inner_x: float = bay_side * half_width * 0.42
			var outer_x: float = bay_side * half_width * 0.90
			draw_line(Vector2(inner_x, y), Vector2(outer_x, y),
				Color("d9d7c9"), 3.0, true)
		draw_line(Vector2(bay_side * half_width * .42, back + PPM * 7.0),
			Vector2(bay_side * half_width * .42, front - PPM * 2.0),
			Color("cbcbbd"), 3.0, true)
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
