extends Node2D
## Resolves ten curated showroom anchors to actual Morrow Coast road segments.
## Shops are placed only on collision-clear land with a road-facing driveway;
## no map rebake, detached island, road rewrite or fake teleport is required.
const Building = preload("res://scripts/world/dealership_building.gd")
const Pavement = preload("res://scripts/world/dealership_pavement.gd")
const PPM := 20.0
const DealerConfig = preload("res://scripts/world/dealership_config.gd")
const InteractionSpeed = preload("res://scripts/world/interaction_speed.gd")
const PARK_RADIUS_M := 7.0
const SIGN_DISTANCE_M := 68.0
var world: MorrowCoast
var editor_render_only := false
var player: VehicleController2D
var sites: Array[Dictionary] = []
var shop_nodes: Array[Node2D] = []
var pavement_nodes: Array[Node2D] = []


static func v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


func _ready() -> void:
	name = "MorrowDealerships"
	var authored := DealerConfig.document()
	# Exported builds may not include the editor JSON; the rebaker keeps the
	# same overrides in the shipped world.
	if not authored.has("dealerships") and world.data.has("editor_dealerships"):
		authored = {"dealerships":world.data.editor_dealerships}
	if not is_instance_valid(world):
		push_error("Dealership locations unavailable")
		return
	for definition in DealerConfig.combined(authored):
		var spec: Dictionary = definition
		var site := _find_clear_site(spec)
		if site.is_empty():
			push_error("Cannot place dealership by " + str(spec.road_name))
			continue
		sites.append(site)
		# This node is below the roadbed/markings, unlike the storefront.
		var pavement := Node2D.new()
		pavement.set_script(Pavement)
		pavement.site = site
		add_child(pavement)
		pavement_nodes.append(pavement)
		var node := Node2D.new()
		node.set_script(Building)
		node.site = site
		node.map_render_only = editor_render_only
		add_child(node)
		shop_nodes.append(node)
		# Map atlas and destination sidebar already support DEALERSHIP POIs.
		world.data.pois.append({
			"name": site.name,
			"category": "DEALERSHIP / " + str(site.tier),
			"position": site.parking_m,
			"road": int(site.road_id)
		})
	_refresh_existing_road_paint()


func _road_samples(road_name: String, near: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for road in world.data.roads:
		if not road_name.is_empty() and str(road.name) != road_name:
			continue
		var points: Array = road.points
		var station_m := 0.0
		for i in range(1, points.size()):
			var a := v(points[i-1])
			var b := v(points[i])
			var direction := (b-a).normalized()
			if direction.length_squared() < 0.1:
				continue
			var candidate := Geometry2D.get_closest_point_to_segment(near,a,b)
			var distance := candidate.distance_to(near)
			if distance < 190.0:
				result.append({"point":candidate,"direction":direction,
					"distance":distance,"road_id":int(road.get("id",-1)),
					"station_m": station_m + a.distance_to(candidate)})
			station_m += a.distance_to(b)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return float(a.distance) < float(b.distance))
	return result


func _find_clear_site(spec: Dictionary) -> Dictionary:
	if spec.has("x") and spec.has("y"):
		return _explicit_site(spec)
	var near := v(spec.near_m)
	var attempts := 0
	var checked: Array[Vector2] = []
	var samples := _road_samples(str(spec.road_name),near)
	for sample in samples:
		var road_point: Vector2 = sample.point
		var duplicate_sample := false
		for prior in checked:
			if prior.distance_to(road_point) < 12.0:
				duplicate_sample = true
				break
		if duplicate_sample:
			continue
		checked.append(road_point)
		if checked.size() > 32:
			break
		var tangent: Vector2 = sample.direction
		var normal := tangent.orthogonal()
		var toward_hint := (near-road_point).dot(normal)
		var preferred_side := 1.0 if toward_hint >= 0.0 else -1.0
		for side in [preferred_side, -preferred_side]:
			for setback in [34.0,42.0,52.0,66.0,86.0]:
				if float(spec.get("lot_depth_m",setback-14.5))>setback-14.5:continue
				attempts += 1
				var outward: Vector2 = normal * float(side)
				var center: Vector2 = road_point + outward * float(setback)
				var parking: Vector2 = center - outward * 17.0
				if not bool(world.can_place_at(center*PPM, 15.0, 1.0).clear):
					continue
				if not bool(world.can_place_at(parking*PPM, 4.0, 0.0).clear):
					continue
				var unoccupied := true
				for other in sites:
					if v(other.center_m).distance_to(center) < 95.0:
						unoccupied = false
						break
				if not unoccupied:
					continue
				return _site_from_geometry(spec,sample,center,float(side),float(setback),attempts)
	return {}


## An authored dealer has a real, deliberate map location. Reject impossible
## placements rather than silently moving a store to an unrelated road.
func _explicit_site(spec: Dictionary) -> Dictionary:
	var center:=Vector2(float(spec.x),float(spec.y))
	# Moving an existing shop can also choose a different road.
	var samples:=_road_samples("",center)
	for sample in samples:
		var direction: Vector2=sample.direction
		var normal:=direction.orthogonal()
		var perpendicular: float=(center-Vector2(sample.point)).dot(normal)
		var setback:=absf(perpendicular)
		if setback<28.0 or setback>105.0 or center.distance_to(Vector2(sample.point))>110.0:
			continue
		if float(spec.get("lot_depth_m",setback-14.5))>setback-14.5:
			continue
		if not bool(world.can_place_at(center*PPM,15.0,1.0).clear):
			continue
		var outward: Vector2=normal*(1.0 if perpendicular>=0.0 else -1.0)
		var parking: Vector2=center-outward*17.0
		if not bool(world.can_place_at(parking*PPM,4.0,0.0).clear):
			continue
		var occupied:=false
		for other in sites:
			if v(other.center_m).distance_to(center)<95.0:
				occupied=true
				break
		if occupied:
			continue
		return _site_from_geometry(spec,sample,center,1.0 if perpendicular>=0 else -1.0,setback,1)
	return {}


func _site_from_geometry(spec: Dictionary,sample: Dictionary,center: Vector2,
		side: float,setback: float,attempts: int) -> Dictionary:
	var outward: Vector2=Vector2(sample.direction).orthogonal()*side
	var road_point: Vector2=sample.point
	var paint_station: float=float(sample.station_m)
	var nearest: Dictionary=world.nearest_road_at(road_point*PPM,8.0)
	if not nearest.is_empty() and int(nearest.road_id)==int(sample.road_id):
		var segment_index: int=int(nearest.segment_index)
		var segment: Dictionary=world.data.segments[segment_index]
		paint_station=float(world.segment_stations[segment_index])+ \
			v(segment.a).distance_to(nearest.closest_point_px/PPM)
	var site:=spec.duplicate(true)
	site["road_m"]=[road_point.x,road_point.y]
	site["road_id"]=int(sample.road_id)
	site["road_station_m"]=paint_station
	site["road_side"]=side
	site["road_name"]=str(world.data.roads[int(sample.road_id)].name)
	site["center_m"]=[center.x,center.y]
	var parking: Vector2=center-outward*17.0
	site["parking_m"]=[parking.x,parking.y]
	site["rotation"]=outward.angle()-PI*.5
	site["art_rotation"]=deg_to_rad(float(spec.get("art_rotation_degrees",180.0)))
	site["pavement_seed"]=7301+str(spec.id).hash()%20000
	site["setback_m"]=setback
	site["site_search_attempts"]=attempts
	return site


## Called once after all ten sites have been placed. The world spawns the
## first chunk before its dealer manager, so those already-created road
## renderers need one repaint when curb openings become known.
func _refresh_existing_road_paint() -> void:
	var road_script: Script = preload("res://scripts/world/coast_roads.gd")
	for chunk in world.chunks.values():
		for drawn in chunk.get_children():
			if drawn.get_script() == road_script:
				drawn.queue_redraw()


func get_site(id: String) -> Dictionary:
	for site in sites:
		if str(site.id) == id:
			return site
	return {}


func closest_site() -> Dictionary:
	if not is_instance_valid(player):
		return {}
	var closest := SIGN_DISTANCE_M
	var result := {}
	for site in sites:
		var d := player.global_position.distance_to(v(site.parking_m)*PPM)/PPM
		if d < closest:
			closest = d
			result = site
	return result


func can_browse(site: Dictionary) -> bool:
	if site.is_empty() or not is_instance_valid(player):
		return false
	# The browsing trigger belongs inside the outlined forecourt bay,
	# not on the roadside shoulder or an invisible radius on nearby grass.
	return Pavement.contains_lot(site, player.global_position) and \
		InteractionSpeed.allowed(player.linear_velocity.length())


func nearby_shop() -> Dictionary:
	return closest_site()


func parking_prompt() -> String:
	var site := closest_site()
	if site.is_empty():
		return ""
	var p := v(site.parking_m) * PPM
	var distance := player.global_position.distance_to(p)/PPM
	if can_browse(site):
		return "BROWSE DEALERSHIP  [ F ]"
	if distance <= PARK_RADIUS_M + 5.0:
		return "SLOW TO 15 MPH TO BROWSE  /  " + str(site.name)
	return "%s  /  %dm" % [str(site.name).to_upper(), roundi(distance)]


func is_paved_forecourt(point_px: Vector2) -> bool:
	# The artist's tapered throat and lot are also the physical asphalt.
	# Previously a larger rectangle granted paved traction outside the art
	# and omitted the flared entrance near some road edges.
	for site in sites:
		if Pavement.contains_pavement(site, point_px):
			return true
	return false
