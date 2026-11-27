extends RefCounted
## Shared authored district controls; coordinates and extents are metres.
static func zone(data: Dictionary,p: Vector2) -> Dictionary:
	var zones: Array=data.get("gameplay_zones",[])
	for i in range(zones.size()-1,-1,-1):
		var z: Dictionary=zones[i]
		if Rect2(float(z.x),float(z.y),float(z.w),float(z.h)).has_point(p):return z
	return {}

static func valid(doc: Dictionary) -> bool:
	var zones: Variant=doc.get("gameplayZones",[])
	var junctions: Variant=doc.get("junctionControls",[])
	if not zones is Array or not junctions is Array:return false
	if zones.size()>32 or junctions.size()>128:return false
	if not zones.is_empty() or not junctions.is_empty():
		if not doc.get("customMap",false):return false
	var width:=float(doc.world.get("width",0))
	var height:=float(doc.world.get("height",0))
	for z in zones:
		if not z is Dictionary or str(z.get("name","")).strip_edges().is_empty():return false
		for key in ["x","y","w","h","density","speed","patrol","response"]:
			if not z.get(key) is float and not z.get(key) is int:return false
			if not is_finite(float(z[key])):return false
		if z.x<0 or z.y<0 or z.w<1 or z.h<1 or z.x+z.w>width or z.y+z.h>height:return false
		if z.density<0 or z.density>200 or z.speed<0 or z.speed>160 or z.patrol<0 or z.patrol>30 or z.response<50 or z.response>150:return false
		if str(z.get("models","")) not in ["all","passenger","commercial"]:return false
	for j in junctions:
		if not j is Dictionary:return false
		for key in ["x","y","layer"]:
			if not j.get(key) is float and not j.get(key) is int:return false
			if not is_finite(float(j[key])):return false
		if j.x<0 or j.x>width or j.y<0 or j.y>height or absf(float(j.layer))>2 or float(j.layer)!=floorf(float(j.layer)):return false
		if str(j.get("control","")) not in ["stop","yield","signal","uncontrolled"]:return false
		if not j.get("turns") is Array or j.turns.is_empty():return false
		for turn in j.turns:
			if turn not in ["left","straight","right"]:return false
	return true

static func model_for(serial: int,count: int,models: String) -> int:
	var pool: Array[int]=[]
	if models=="passenger":pool=[0,1,2,3,4,5,7]
	if models=="commercial":pool=[6,8,9]
	return posmod(serial,count) if pool.is_empty() else posmod(pool[posmod(serial,pool.size())],count)

static func green(clock: float,slot: int,count: int) -> bool:
	return slot>=0 and count>0 and int(fposmod(clock,float(count)*10.0)/10.0)==slot and fposmod(clock,10.0)<8.0
