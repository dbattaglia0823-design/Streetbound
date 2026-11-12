extends Node2D
## Resolves ten curated showroom anchors to actual Morrow Coast road segments.
## Shops are placed only on collision-clear land with a road-facing driveway;
## no map rebake, detached island, road rewrite or fake teleport is required.
const Building = preload("res://scripts/world/dealership_building.gd")
const Pavement = preload("res://scripts/world/dealership_pavement.gd")
const PPM := 20.0
const LOCATION_PATH := "res://data/dealerships.json"
const STOP_SPEED_MPS := 1.7
const PARK_RADIUS_M := 7.0
const SIGN_DISTANCE_M := 68.0
var world: MorrowCoast
var player: VehicleController2D
var sites: Array[Dictionary] = []
var shop_nodes: Array[Node2D] = []
var pavement_nodes: Array[Node2D] = []


static func v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


func _ready() -> void:
	name = "MorrowDealerships"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCATION_PATH))
	if not parsed is Dictionary or not is_instance_valid(world):
		push_error("Dealership locations unavailable")
		return
	for definition in parsed.get("shops", []):
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
		if str(road.name) != road_name:
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
			for setback in [34.0,42.0,52.0]:
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
				var site := spec.duplicate(true)
				site["road_m"] = [road_point.x,road_point.y]
				site["road_id"] = int(sample.road_id)
				site["road_station_m"] = float(sample.station_m)
				site["road_side"] = float(side)
				site["center_m"] = [center.x,center.y]
				site["parking_m"] = [parking.x,parking.y]
				# In the local frame -Y is the side nearest the road.
				site["rotation"] = outward.angle() - PI * 0.5
				# Most source PNGs have the entrance on their bottom (+Y).
				# Rotate artwork independently from the physical parking frame.
				site["art_rotation"] = deg_to_rad(float(spec.get("art_rotation_degrees", 180.0)))
				site["pavement_seed"] = 7301 + str(spec.id).hash() % 20000
				site["setback_m"] = float(setback)
				site["site_search_attempts"] = attempts
				return site
	return {}


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
	return Pavement.contains_pavement(site, player.global_position) and \
		player.global_position.distance_to(v(site.parking_m)*PPM) <= \
		PARK_RADIUS_M*PPM and player.linear_velocity.length() <= STOP_SPEED_MPS


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
		return "PARK & STOP TO BROWSE  /  " + str(site.name)
	return "%s  /  %dm" % [str(site.name).to_upper(), roundi(distance)]


func is_paved_forecourt(point_px: Vector2) -> bool:
	# The artist's tapered throat and lot are also the physical asphalt.
	# Previously a larger rectangle granted paved traction outside the art
	# and omitted the flared entrance near some road edges.
	for site in sites:
		if Pavement.contains_pavement(site, point_px):
			return true
	return false
