extends RefCounted
## Existing physical service aprons become usable where the shipped archive
## has no marker. Never invent a facility or replace a user-authored marker.
const PPM:=20.0
const Rules=preload("res://scripts/world/authored_marker_rules.gd")
const SERVICES={
	"Northshore Fuel Stop":"fuel","Southpoint Travel Stop":"fuel",
	"Juniper Roadside Fuel":"fuel","Harvest Rest":"fuel",
	"Willowmere Village":"garage","Saltair Motors":"garage"
}
static func markers(world: Node2D,existing: Array) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not is_instance_valid(world):return result
	for poi in world.data.get("pois",[]):
		var label:=str(poi.get("name",""))
		if not SERVICES.has(label) or poi.get("position",[]).size()!=2:continue
		var at:=Vector2(float(poi.position[0]),float(poi.position[1]))
		var kind: String=SERVICES[label]
		var covered:=false
		var identity: String="marker-regional-"+label.to_lower().replace(" ","-")
		for entry in existing:
			if not entry is Dictionary:continue
			var marker: Dictionary=entry.get("marker",entry)
			if str(marker.get("id",""))==identity or (str(marker.get("type",""))==kind and (str(marker.get("name",""))==label or at.distance_to(Vector2(float(marker.get("x",INF)),float(marker.get("y",INF))))<45.0)):
				covered=true;break
		if covered:continue
		var road: Dictionary=world.call("nearest_road_at",at*PPM,18.0)
		if road.is_empty() or float(road.get("distance_to_center_m",INF))>12.0:continue
		var marker: Dictionary={"id":identity,"name":label,"type":kind,"x":at.x,"y":at.y,"rotation":0.0,"properties":{"radius_m":16.0}}
		if Rules.valid(marker):result.append(marker)
	return result
