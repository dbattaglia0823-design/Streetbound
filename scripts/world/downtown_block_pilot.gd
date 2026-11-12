extends RefCounted
## Controlled one-block city-art pilot in central Larkspur. Tags existing
## authored buildings ONLY; never creates/moves roads, props or colliders.
## All textures are original SVG art in assets/Buildings/DowntownPilot.
const HOTSPOT_M := Vector2(3150.0, 2820.0) # Market Street downtown district
const SEARCH_RADIUS_M := 620.0
const BLOCK_CELL_M := 144.0
const MAX_BUILDINGS := 8
const TYPES := ["building", "shop", "cafe", "showroom", "office", "hotel"]
const SPRITES := [
	preload("res://assets/Buildings/DowntownPilot/glass-office.svg"),
	preload("res://assets/Buildings/DowntownPilot/brick-hotel.svg"),
	preload("res://assets/Buildings/DowntownPilot/retail-studio.svg"),
	preload("res://assets/Buildings/DowntownPilot/art-deco-tower.svg")
]


static func _position(prop: Dictionary) -> Vector2:
	var raw: Array = prop.get("p", [0.0, 0.0])
	return Vector2(float(raw[0]), float(raw[1]))


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BLOCK_CELL_M), floori(p.y / BLOCK_CELL_M))


static func sprite(index: int) -> Texture2D:
	if index < 0 or index >= SPRITES.size():
		return null
	return SPRITES[index] as Texture2D


## Group by a stable 144m block cell so the city art cannot spread across
## multiple downtown neighborhoods. Prefer a dense cell near Market Street.
static func find_block(props: Array) -> Array[int]:
	var groups: Dictionary = {}
	var centroid_sum: Dictionary = {}
	for i in props.size():
		var prop: Dictionary = props[i]
		if str(prop.get("kind", "")) not in TYPES or prop.has("poi"):
			continue
		if not bool(prop.get("solid", false)):
			continue
		var p := _position(prop)
		if p.distance_to(HOTSPOT_M) > SEARCH_RADIUS_M:
			continue
		var key := _cell(p)
		if not groups.has(key):
			groups[key] = []
			centroid_sum[key] = Vector2.ZERO
		groups[key].append(i)
		centroid_sum[key] += p
	var winner := Vector2i(-1, -1)
	var best_score := -INF
	for key in groups:
		var group: Array = groups[key]
		var center: Vector2 = centroid_sum[key] / float(group.size())
		var score: float = float(mini(group.size(), MAX_BUILDINGS)) * 75.0 - \
			center.distance_to(HOTSPOT_M) * 0.3
		if score > best_score:
			best_score = score
			winner = key
	if not groups.has(winner):
		return []
	var chosen: Array[int] = []
	for index in groups[winner]:
		chosen.append(int(index))
	chosen.sort_custom(func(a: int, b: int) -> bool:
		var pa := _position(props[a])
		var pb := _position(props[b])
		return pa.distance_squared_to(HOTSPOT_M) < \
			pb.distance_squared_to(HOTSPOT_M))
	if chosen.size() > MAX_BUILDINGS:
		chosen.resize(MAX_BUILDINGS)
	return chosen


## Idempotent: re-tagging the same authored world doesn't accumulate buildings
## or depend on chunk streaming order.
static func apply(props: Array) -> Array[int]:
	var chosen := find_block(props)
	for index in chosen:
		var prop: Dictionary = props[index]
		prop["downtown_pilot_style"] = posmod(int(prop.get("seed", index)), SPRITES.size())
	return chosen
