extends RefCounted
## Objective layers are absolute six-metre road levels, not rounded bands.
const Elevation=preload("res://scripts/world/road_elevation.gd")
const MARKER_TYPES=["contract","contract_contact","contract_dropoff","robbery_target","race_start","checkpoint","finish","mission","custom"]

static func valid_layer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and absf(float(value))<=2 and float(value)==floorf(float(value))

static func marker_layer(marker: Dictionary) -> int:
	return int(marker.get("properties",{}).get("road_layer",0))

static func point_layer(point: Dictionary) -> int:
	return int(point.get("road_layer",0))

static func matches(car: VehicleController2D, layer: int) -> bool:
	return is_instance_valid(car) and car.can_reach_road_layer(layer)

## Only actual pavement on the selected level can support a staged car.
static func contact(world: Node2D, at_m: Vector2, layer: int) -> Dictionary:
	if layer==0 or not is_instance_valid(world) or not world.has_method("elevation_at"):
		return {}
	var data: Dictionary=world.get("data")
	var cell:=float(data.surface_cell)
	var key: String="%d,%d"%[floori(at_m.x/cell),floori(at_m.y/cell)]
	for index in data.surface_index.get(key,[]):
		var road_id:=int(data.segments[int(index)].road)
		var grade: Dictionary=world.elevation_at(at_m*20.0,road_id,layer*6.0)
		if not grade.is_empty() and absf(float(grade.get("height_m",0))-layer*6.0)<.65:
			return grade
	return {}

static func supported(world: Node2D, at_m: Vector2, layer: int) -> bool:
	return layer==0 or not contact(world,at_m,layer).is_empty()
