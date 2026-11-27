extends Node2D
## Surface-only cut-and-cover artwork. All coordinates originate in the
## baked ramp and use the same width and depth as its excavation colliders.
const Elevation = preload("res://scripts/world/road_elevation.gd")
const Walkways = preload("res://scripts/world/urban_walkways.gd")
const PPM := 20.0
const CUT_MARGIN := 1.2
const BANK_MARGIN := 5.0
const PALETTES := {
	"grass": ["68794b","8b7958"], "meadow": ["68794b","8b7958"],
	"forest": ["405336","77664b"], "highland": ["69794b","827c65"],
	"mountain": ["77796e","69675f"], "rock": ["77796e","69675f"],
	"beach": ["c7b487","a18a64"], "sand": ["c7b487","a18a64"],
	"desert": ["bd9868","987652"], "dirt": ["896745","715338"],
	"gravel": ["888171","726e63"], "farmland": ["757947","806442"],
	"field": ["757947","806442"], "city": ["89897e","716e65"],
	"asphalt": ["777974","666864"], "town": ["74805b","8c8067"]
}
var world: Node2D
var origin_m := Vector2.ZERO
var plans: Array[Dictionary] = []
var extent_m := Vector2.ZERO


static func terrain_regions(regions: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region in regions:
		var shape := PackedVector2Array()
		for p in region.get("points",[]):shape.append(Vector2(float(p[0]),float(p[1])))
		if shape.size()<3:continue
		result.append({"kind":str(region.get("kind","grass")),"shape":shape,"bounds":Elevation.polygon_bounds(shape)})
	return result


static func terrain_kind(at: Vector2, regions: Array[Dictionary]) -> String:
	var kind := "grass"
	for region in regions:
		if region.bounds.has_point(at) and Geometry2D.is_point_in_polygon(at,region.shape):
			kind=str(region.kind)
	return kind


static func palette(kind: String) -> Array:
	var pair: Array = PALETTES.get(kind,PALETTES.grass)
	return [Color(pair[0]),Color(pair[1])]


## Resample the complete ramp in surface-to-covered order. Keeping stations
## in metres makes the two directions and streamed chunks agree.
static func build(road: Dictionary, regions: Array[Dictionary], connected: bool) -> Dictionary:
	if not Elevation.is_open_cut(road):return {}
	var source := PackedVector2Array()
	for p in road.points:
		var v := Vector2(float(p[0]),float(p[1]))
		if source.is_empty() or v.distance_to(source[-1])>.01:source.append(v)
	if source.size()<2:return {}
	var reversed := Elevation.endpoint_layer(road,true)<0
	if reversed:source.reverse()
	var path := PackedVector2Array([source[0]])
	var stations := PackedFloat32Array([0.0])
	var total := 0.0
	for i in range(1,source.size()):
		var length := source[i-1].distance_to(source[i])
		var steps := maxi(1,ceili(length/3.0))
		for k in range(1,steps+1):
			var t := float(k)/steps
			path.append(source[i-1].lerp(source[i],t))
			stations.append(total+length*t)
		total+=length
	if total<.01:return {}
	var half := float(road.width)*.5
	var strips: Array[Dictionary] = []
	for side in [-1.0,1.0]:
		var inner := Walkways.offset(path,side*(half+.10))
		var rim := Walkways.offset(path,side*(half+CUT_MARGIN))
		var outer := Walkways.offset(path,side*(half+BANK_MARGIN))
		for i in range(1,path.size()):
			var t0 := float(stations[i-1])/total
			var t1 := float(stations[i])/total
			var depth0 := absf(Elevation.height_at(road,1.0-t0 if reversed else t0))/Elevation.HEIGHT_M
			var depth1 := absf(Elevation.height_at(road,1.0-t1 if reversed else t1))/Elevation.HEIGHT_M
			var bank0 := rim[i-1].lerp(outer[i-1],depth0)
			var bank1 := rim[i].lerp(outer[i],depth1)
			var sample := bank0.lerp(bank1,.5)
			var kind := terrain_kind(sample,regions)
			var ink := palette(kind)
			var facing := (rim[i]-inner[i]).normalized().dot(Vector2(-.65,-.76))
			var earth: Color = ink[1]
			var top: Color = ink[0]
			var wall := earth.lerp(Color("343635"),.46).lightened(maxf(0.0,facing)*.13)
			if kind in ["city","town","asphalt"]:wall=Color("777a75").darkened(.32-maxf(0.0,facing)*.12)
			strips.append({"kind":kind,"face":PackedVector2Array([inner[i-1],inner[i],rim[i],rim[i-1]]),
				"face_colors":PackedColorArray([Color(wall,.22+.78*depth0),Color(wall,.22+.78*depth1),Color(top,.6+.4*depth1),Color(top,.6+.4*depth0)]),
				"bank":PackedVector2Array([rim[i-1],rim[i],bank1,bank0]),
				"bank_colors":PackedColorArray([Color(earth,depth0*.86),Color(earth,depth1*.86),Color(top,0.0),Color(top,0.0)]),
				"rim":PackedVector2Array([rim[i-1],rim[i]]),"depth":depth1})
	var mouth := path[-1]
	var toward_surface := (path[-2]-mouth).normalized()
	var across := toward_surface.orthogonal()
	var roof_kind := terrain_kind(mouth-toward_surface*2.5,regions)
	return {"strips":strips,"mouth":mouth,"outside":toward_surface,"across":across,
		"half":half,"connected":connected,"kind":roof_kind,
		"bounds":Elevation.polygon_bounds(path).grow(half+BANK_MARGIN+6.0)}


func _ready() -> void:
	var ink := ShaderMaterial.new()
	ink.shader=preload("res://scripts/world/tunnel_earth.gdshader")
	material=ink


func _local(at: Vector2) -> Vector2:
	return (at-origin_m)*PPM


func _polygon(shape: PackedVector2Array, colors: PackedColorArray) -> void:
	var local := PackedVector2Array()
	for p in shape:local.append(_local(p))
	if local.size()<3 or Geometry2D.triangulate_polygon(local).is_empty():return
	draw_polygon(local,colors)


func _line(a: Vector2,b: Vector2,color: Color,width_m: float) -> void:
	draw_line(_local(a),_local(b),color,width_m*PPM,true)


func _surface_clear(at: Vector2) -> bool:
	# Never cover an independent surface street or parking access. The
	# actual excavated ramp is not classified as ordinary surface asphalt.
	return str(world.surface_at(at*PPM).get("name","GRASS"))!="ASPHALT"


func _draw() -> void:
	var bounds := Rect2(origin_m,extent_m).grow(1.0)
	for plan in plans:
		if not bounds.intersects(plan.bounds):continue
		for strip in plan.strips:
			var face: PackedVector2Array = strip.face
			var bank: PackedVector2Array = strip.bank
			if not bounds.intersects(Elevation.polygon_bounds(bank).merge(Elevation.polygon_bounds(face))):continue
			if _surface_clear(bank[2]) and _surface_clear(bank[3]):
				_polygon(bank,strip.bank_colors)
			_polygon(face,strip.face_colors)
			var rim: PackedVector2Array=strip.rim
			var depth:=float(strip.depth)
			_line(rim[0],rim[1],Color(.22,.21,.18,.35+depth*.45),.10)
			_line(rim[0],rim[1],Color(.79,.75,.65,.18+depth*.22),.045)
		if bool(plan.connected):_portal(plan)


func _portal(plan: Dictionary) -> void:
	var m: Vector2 = plan.mouth
	var d: Vector2 = plan.outside
	var n: Vector2 = plan.across
	var half := float(plan.half)
	var rim := half+CUT_MARGIN
	var roof: Color=palette(str(plan.kind))[0]
	# A graded earth/rock brow on the covered side, feathered into the
	# existing terrain rather than a rectangular painted patch.
	var a := m-d*.25-n*(rim+.9)
	var b := m-d*.25+n*(rim+.9)
	var c := m-d*4.8+n*(rim+2.0)
	var e := m-d*4.8-n*(rim+2.0)
	if _surface_clear(c) and _surface_clear(e) and _surface_clear((c+e)*.5):
		_polygon(PackedVector2Array([a,b,c,e]),PackedColorArray([roof.darkened(.22),roof.darkened(.22),Color(roof,0),Color(roof,0)]))
	# Depth cue across the descending pavement. The surface-only artwork
	# stays under the driver and disappears behind the underground blackout.
	_polygon(PackedVector2Array([m-n*half,m+n*half,m+d*5.0+n*half,m+d*5.0-n*half]),
		PackedColorArray([Color(.035,.04,.045,.88),Color(.035,.04,.045,.88),Color(.035,.04,.045,0),Color(.035,.04,.045,0)]))
	# Concrete brow, recessed opening and cap with directional lighting.
	_line(m-n*rim,m+n*rim,Color("292c2d"),1.35)
	_line(m-d*.62-n*rim,m-d*.62+n*rim,Color("666961"),.95)
	_line(m-d*1.08-n*rim,m-d*1.08+n*rim,Color("b1b1a3"),.20)
	for side in [-1.0,1.0]:
		var p := m+n*rim*side
		_line(p-d*.9,p+d*2.8,Color("444744"),.85)
		_line(p-d*.9,p+d*2.8,Color("a09d8d"),.26)
		_line(p-n*side*.33+d*.5,p-n*side*.33+d*1.25,Color("e8b65d"),.15)
