extends Node2D
## Static, deterministic roadside furnishing at metre-based stations. Drawn in
## one cached canvas per streamed chunk; zero per-prop scene or physics nodes.
## All object positions follow the same sampled road paths as sidewalks.
const PPM := 20.0
const Walkways = preload("res://scripts/world/urban_walkways.gd")
var road_batches: Array[Dictionary] = []
var junction_list: Array[Dictionary] = []
var origin_m := Vector2.ZERO
var chunk_size_px := 3840.0

func _in_chunk(p: Vector2) -> bool:
	return p.x >= 8.0 and p.y >= 8.0 and p.x < chunk_size_px - 8.0 and p.y < chunk_size_px - 8.0

func _near_junction(p: Vector2, radius: float) -> bool:
	for junction in junction_list:
		var jp := (Vector2(float(junction.p[0]), float(junction.p[1])) - origin_m) * PPM
		if jp.distance_squared_to(p) < radius * radius:
			return true
	return false

func _lamp(p: Vector2, heading: Vector2) -> void:
	# Warm street lantern with northwest sun shadow; a tiny deterministic
	# illustrated element instead of an expensive real-time light source.
	draw_line(p + Vector2(10, 11), p + Vector2(28, 30), Color(.09,.16,.15,.24), 8.0, true)
	draw_circle(p + Vector2(4, 5), 12, Color(.36,.42,.40,.28))
	draw_circle(p, 9.0, Color("788d85"))
	draw_circle(p, 6.0, Color("e8d9ae"))
	draw_circle(p - Vector2(2,2), 3.0, Color("fff2c5"))
	var outward := heading.orthogonal()
	draw_line(p, p - outward * 16.0, Color("8a9890"), 4.0, true)

func _bench(p: Vector2, direction: Vector2) -> void:
	var tangent := direction.normalized()
	var lateral := tangent.orthogonal()
	var center := p + Vector2(4, 8)
	draw_line(center - tangent * 24.0, center + tangent * 24.0,
		Color(.12,.17,.17,.24), 16.0, true)
	for side in [-1.0, 1.0]:
		var a := p + tangent * side * 19.0
		draw_line(a - lateral * 11.0, a + lateral * 11.0,
			Color("7b8172"), 5.0, true)
	for offset in [-7.0, 0.0, 7.0]:
		draw_line(p + lateral * offset - tangent * 24.0,
			p + lateral * offset + tangent * 24.0,
			Color("b9a17e") if offset != 0.0 else Color("d2bc96"), 4.5, true)

func _post(p: Vector2, size: float) -> void:
	draw_line(p + Vector2(3, 5), p + Vector2(13, 14),
		Color(.12,.17,.15,.22), size * .80, true)
	draw_circle(p, size, Color("d0ccac"))
	draw_circle(p - Vector2(1.0,1.0), size * .45, Color("f1e6cc"))

func _sign(p: Vector2, direction: Vector2) -> void:
	var heading := direction.normalized()
	draw_line(p + Vector2(6, 8), p + Vector2(14, 17), Color(.11,.17,.17,.25), 7.0, true)
	draw_circle(p, 3.8, Color("667773"))
	var right := heading.orthogonal()
	var a := p - right * 14.0
	var b := p + right * 14.0
	draw_line(a,b,Color("eee7d1"),10.0,true)
	draw_line(a + heading * 2.0, b + heading * 2.0,Color("527c73"),5.0,true)

func _place_at_stations(batch: Dictionary, spacing: float, callback: Callable) -> void:
	var path: PackedVector2Array = batch.path
	var covered := 0.0
	var base := float(batch.phase)
	for i in range(1,path.size()):
		var a := path[i - 1]
		var b := path[i]
		var segment := b - a
		var length := segment.length()
		if length <= .01:
			continue
		var forward := segment / length
		var start := base + covered
		var finish := start + length
		var station := ceilf((start + .05) / spacing) * spacing
		while station < finish - .05:
			var center := a + forward * (station - start)
			if _in_chunk(center):
				callback.call(center,forward,int(round(station / spacing)))
			station += spacing
		covered += length

func _urban_detail(batch: Dictionary) -> void:
	var width := float(batch.road.width) * PPM
	_place_at_stations(batch, 800.0, func(center: Vector2, forward: Vector2, index: int):
		if _near_junction(center, width * .65 + 125.0):
			return
		var normal := forward.orthogonal()
		for side in [-1.0, 1.0]:
			var p := center + normal * side * (width * .5 + Walkways.SIDEWALK_WIDTH_PX * .83)
			if _in_chunk(p):
				if index % 3 == 0 and side > 0.0:
					_bench(p, forward)
				else:
					_lamp(p, forward * side)
	)
	# Hydrants, waste baskets and junction approach signs. Small enough not
	# to clutter the road, each centered on a true sampled curb tangent.
	_place_at_stations(batch, 1900.0, func(center: Vector2, forward: Vector2, index: int):
		var side := 1.0 if index % 2 == 0 else -1.0
		var p := center + forward.orthogonal() * side * (width * .5 + 35.0)
		if _in_chunk(p) and not _near_junction(center, width * .7 + 60.0):
			_sign(p, forward)
	)

func _rural_detail(batch: Dictionary) -> void:
	var road_kind: String = str(batch.road.kind)
	var width := float(batch.road.width) * PPM
	_place_at_stations(batch, 650.0 if road_kind == "rural" else 1300.0,
		func(center: Vector2, forward: Vector2, index: int):
			if _near_junction(center, width * .60 + 100.0):
				return
			for side in [-1.0,1.0]:
				var p := center + forward.orthogonal() * side * (width * .5 + 76.0)
				if _in_chunk(p):
					_post(p, 4.8 if road_kind == "rural" else 3.4)
	)

func _draw() -> void:
	for batch in road_batches:
		var kind: String = str(batch.road.kind)
		if kind in ["local","arterial"]:
			_urban_detail(batch)
		elif kind in ["rural","mountain","highway"]:
			_rural_detail(batch)
