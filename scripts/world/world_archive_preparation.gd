extends RefCounted
## Data-only world preparation. The detached JSON dictionary is exclusively
## owned by the loading worker until the main thread joins it. No SceneTree,
## texture creation, rendering/physics server or shared mutable cache access.
const RenderHealth=preload("res://scripts/world/world_render_health.gd")
const Widths=preload("res://scripts/world/road_width_adaptation.gd")
const Bridges=preload("res://scripts/world/automatic_road_bridges.gd")
const Mountains=preload("res://scripts/world/mountain_barrier_world.gd")

static func adapt(data: Dictionary) -> Dictionary:
	var legacy: Array=data.get("bridges",[]).duplicate(true)
	Widths.adapt(data)
	var bridges:=Bridges.apply(data,legacy)
	var mountains:=Mountains.apply(data)
	return {"bridges":bridges,"mountains":mountains}

static func prepare(data: Dictionary) -> Dictionary:
	var start:=Time.get_ticks_usec()
	var audit:=RenderHealth.audit(data)
	if not bool(audit.compatible):return {}
	var result:=adapt(data)
	result["audit"]=audit
	result["geometry_ms"]=float(Time.get_ticks_usec()-start)/1000.0
	return result
