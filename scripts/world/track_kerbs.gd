extends RefCounted
## Shared game/editor track paint. Stations are in pixels, so the red/white
## rhythm survives chunk boundaries and junction clipping.
const Lanes=preload("res://scripts/world/traffic_lane_geometry.gd")
const PPM:=20.0
const STRIPE_LENGTH:=3.0*PPM
const KERB_WIDTH:=1.0*PPM
const RED:=Color("#cf3438")
const WHITE:=Color("#f3f1e7")
const EDGE:=Color("#eeeade")

static func is_track(road: Dictionary) -> bool:
	return str(road.get("kind",road.get("roadClass",""))).to_lower()=="track" or str(road.get("surface","")).to_lower()=="track"

static func stripes(path: PackedVector2Array, station: float=0.0) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var cursor:=station
	for i in range(1,path.size()):
		var length:=path[i-1].distance_to(path[i])
		if length<0.001:continue
		var at:=0.0
		while at<length-0.001:
			var phase:=fposmod(cursor+at,STRIPE_LENGTH)
			var step:=minf(length-at,STRIPE_LENGTH-phase)
			if step<0.001:step=minf(length-at,0.001)
			result.append({"segment":i,"from":at/length,"to":(at+step)/length,
				"red":posmod(floori((cursor+at+0.0001)/STRIPE_LENGTH),2)==0})
			at+=step
		cursor+=length
	return result

static func paint(canvas: CanvasItem,path: PackedVector2Array,width: float,station: float=0.0) -> void:
	if path.size()<2:return
	var stripe_parts:=stripes(path,station)
	for side in [-1.0,1.0]:
		var outer:=Lanes.offset_path(path,float(side)*width*.5)
		var inner:=Lanes.offset_path(path,float(side)*(width*.5-KERB_WIDTH))
		for part in stripe_parts:
			var i:=int(part.segment)
			var a:=float(part.from);var b:=float(part.to)
			canvas.draw_colored_polygon(PackedVector2Array([
				outer[i-1].lerp(outer[i],a),outer[i-1].lerp(outer[i],b),
				inner[i-1].lerp(inner[i],b),inner[i-1].lerp(inner[i],a)
			]),RED if bool(part.red) else WHITE)
		canvas.draw_polyline(Lanes.offset_path(path,float(side)*(width*.5-KERB_WIDTH-3.0)),EDGE,3.0,true)
