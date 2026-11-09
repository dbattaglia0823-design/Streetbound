extends Node2D
## Cached cut-rock facets, strata, ambient contact shade and outside guardrails.
var world: Node2D
var origin_m := Vector2.ZERO
var content: Dictionary
var render_stage := 0
var mesh: ArrayMesh
var vertices := PackedVector2Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()

func _ready() -> void:
	if render_stage==0:
		material=preload("res://scripts/world/cliff_rock.tres")
		_faces()
	else: _rails()
	if vertices.is_empty(): return
	mesh=ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	vertices=PackedVector2Array()
	colors=PackedColorArray()
	uvs=PackedVector2Array()

func point(raw: Array) -> Vector2:
	return (Vector2(float(raw[0]),float(raw[1]))-origin_m)*20.0

func _draw() -> void:
	if mesh!=null: draw_mesh(mesh,null)

func _quad(points: PackedVector2Array, tints: PackedColorArray, coordinates := PackedVector2Array()) -> void:
	for index in [0,1,2,0,2,3]:
		vertices.append(points[index])
		colors.append(tints[index%tints.size()])
		uvs.append(coordinates[index] if coordinates.size()==4 else Vector2.ZERO)

func _stroke(a: Vector2,b: Vector2,color: Color,width: float,_aa := true) -> void:
	var direction := (b-a).normalized()
	var normal := Vector2(-direction.y,direction.x)*width*.5
	_quad(PackedVector2Array([a-normal,b-normal,b+normal,a+normal]),PackedColorArray([color]))

func _post(p: Vector2,radius: float,color: Color) -> void:
	_quad(PackedVector2Array([p+Vector2(-radius,-radius),p+Vector2(radius,-radius),p+Vector2(radius,radius),p+Vector2(-radius,radius)]),PackedColorArray([color]))

func _faces() -> void:
	for index in content.get("relief",[]):
		var face: Dictionary = world.data.relief_faces[int(index)]
		var a := point(face.toe[0])
		var b := point(face.toe[1])
		var c := point(face.lip[1])
		var d := point(face.lip[0])
		var light := float(face.light)
		# Soft directional cast shade plus a tighter contact strip at the foot.
		for spread in [1.0,.65,.3]:
			var cast: Vector2 = Vector2(70,90)*float(spread)
			_quad(PackedVector2Array([a,b,b+cast,a+cast]),PackedColorArray([Color(.12,.18,.20,.07)]))
		_stroke(a,b,Color(.14,.20,.20,.26),18,true)
		var stone := Color("646d64").lerp(Color("aaa18b"),light)
		if face.get("kind","")=="earth": stone=Color("728366")
		var station := float(face.station)*.25
		var end := station+float(face.length)*.25
		var uv := PackedVector2Array([Vector2(station,0),Vector2(end,0),Vector2(end,1),Vector2(station,1)])
		var face_colors := PackedColorArray([stone.darkened(.15),stone.darkened(.15),stone.lightened(.10),stone.lightened(.10)])
		_quad(PackedVector2Array([a,b,c,d]),face_colors,uv)
		_stroke(d,c,Color(.69,.68,.53,.46),3,true)

func _rails() -> void:
	for index in content.get("rails",[]):
		var rail: Dictionary = world.data.mountain_rails[int(index)]
		var a := point(rail.points[0])
		var b := point(rail.points[1])
		_stroke(a+Vector2(10,14),b+Vector2(10,14),Color(.10,.16,.18,.25),10,true)
		_stroke(a,b,Color("566563"),9,true)
		_stroke(a-Vector2(0,2),b-Vector2(0,2),Color("bbc5b8"),4,true)
		if rail.post:
			_post(a,5,Color("535e5b"))
			_post(a-Vector2(1,2),3,Color("d6d1b5"))
