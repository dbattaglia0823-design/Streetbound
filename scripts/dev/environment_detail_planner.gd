extends RefCounted
## Source-only scenery proposals. Existing City clearance/index and Session
## transaction remain authoritative. All proposals use supported prop kinds.
const City=preload("res://scripts/dev/native_city_construction.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Rules=preload("res://scripts/world/environment_finishing_rules.gd")
const MAX_PROPS:=300
const PALETTES={
	"residential":["tree","bush","garden","streetlight"],
	"downtown":["planter","streetlight","sign","bush"],
	"industrial":["sign","streetlight","bush","planter"],
	"coastal":["palm","bush","streetlight","garden"],
	"rural":["pine","tree","bush","sign"]
}

static func _protected(doc: Dictionary,p: Vector2) -> bool:
	for marker in doc.get("markers",[]):
		if p.distance_to(Vector2(float(marker.x),float(marker.y)))<maxf(16.0,float(marker.get("properties",{}).get("radius_m",12.0))+5.0):return true
	for race in doc.get("races",[]):
		for point in race.get("points",[]):
			if p.distance_to(Vector2(float(point.x),float(point.y)))<18.0:return true
	for dealer in doc.get("dealerships",[]):
		if dealer.has("x") and dealer.has("y") and p.distance_to(Vector2(float(dealer.x),float(dealer.y)))<70.0:return true
	return false

static func _kind_radius(kind: String) -> float:
	return float({"planter":2.0,"garden":4.3,"streetlight":1.0,"sign":1.1,"tree":5.0,"pine":5.0,"palm":4.7,"bush":1.8}.get(kind,5.0))

static func plan(doc: Dictionary,center: Vector2,settings: Dictionary,limit: int) -> Dictionary:
	var style:=str(settings.get("style","residential"))
	if not PALETTES.has(style):return City._error("Unknown environmental style.")
	var radius:=clampf(float(settings.get("radius",180)),50.0,500.0)
	var spacing:=clampf(float(settings.get("spacing",32)),18.0,100.0)
	var density:=clampf(float(settings.get("density",.8)),0.0,1.0)
	var area:=Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)
	var index:=City._index(doc)
	var props: Array=[]
	var palette: Array=PALETTES[style]
	var stats: Dictionary={}
	var rng:=RandomNumberGenerator.new();rng.seed=int(settings.get("seed",1847))
	var available:=mini(MAX_PROPS,maxi(0,limit-doc.props.size()))
	# Stable source order and station-based sampling. Road clearance is
	# checked again against every authored road and existing prop.
	for road in doc.roads:
		if props.size()>=available:break
		if road.has("elevation") or road.has("jump") or str(road.get("roadClass","")) in ["track","onramp","highway","service"]:continue
		var path:=Session.road_path(road)
		if path.size()<2 or not City._bounds(path).grow(30.0).intersects(area):continue
		var passed:=0.0
		for i in range(1,path.size()):
			var a:=path[i-1];var b:=path[i]
			var length:=a.distance_to(b)
			if length<.001:continue
			var direction: Vector2=(b-a)/length
			for at in Rules.stations(passed,length,spacing):
				if props.size()>=available:break
				var base:=a+direction*(at-passed)
				if not area.has_point(base):continue
				for side in [-1.0,1.0]:
					if props.size()>=available or rng.randf()>density:continue
					var kind: String=palette[rng.randi_range(0,palette.size()-1)]
					var scale:=rng.randf_range(.8,1.05)
					var clearance:=_kind_radius(kind)*scale+3.0
					var offset:=float(road.width)*.5+float(road.get("shoulder",2))+8.0+clearance
					var p:=base+direction.orthogonal()*float(side)*offset
					if not area.has_point(p) or _protected(doc,p):continue
					if not City._place(doc,index,props,kind,p,rad_to_deg(direction.angle()),scale,doc.props.size()+available):continue
					props[-1].name="Finish / "+style+" / "+kind
					stats[kind]=int(stats.get(kind,0))+1
			passed+=length
	return {"roads":[],"regions":[],"props":props,"area":area,"label":"Environmental finishing / "+style,"stats":stats}
