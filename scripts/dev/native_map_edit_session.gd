extends RefCounted
## Source-safe, undoable authoring draft. This never mutates a live Morrow Coast
## Dictionary. Runtime streets, intersections and traffic remain authoritative
## until the checked-in production builder has completed an Apply operation.
const SOURCE := "res://map-editor/maps/morrow-coast.edits.world.json"
const MAX_HISTORY := 40
const MAX_ROADS := 180
const MAX_PROPS := 4000
const MAX_DRAG_M := 350.0
const ART: Dictionary = {
	"house":{"type":"house","assetId":"game-house","size":Vector2(12,17)},
	"coastal_house":{"type":"house","assetId":"game-coastal_house","size":Vector2(12,17)},
	"shop":{"type":"building","assetId":"game-shop","size":Vector2(22,29)},
	"garage":{"type":"garage","assetId":"game-garage","size":Vector2(20,21)},
	"tree":{"type":"oak","assetId":"game-tree","size":Vector2(7,7)},
	"pine":{"type":"pine","assetId":"game-pine","size":Vector2(7,7)},
	"palm":{"type":"palm","assetId":"game-palm","size":Vector2(6.5,6.5)},
	"rock":{"type":"rock","assetId":"game-rock","size":Vector2(3,2.5)}
}
var doc: Dictionary = {}
var initial: Dictionary = {}
var baseline_hash := ""
var history: Array[Dictionary] = []
var future: Array[Dictionary] = []
var last_error := ""
var dirty := false
## Monotonic editor revision: avoids rescanning 20k runtime props every frame.
var edit_revision := 0

func load_source(path: String = SOURCE) -> bool:
	var content := FileAccess.get_file_as_string(path)
	if content.is_empty():
		last_error = "No Morrow Coast authoring source found."
		return false
	var parsed: Variant = JSON.parse_string(content)
	if not parsed is Dictionary or not _valid_source(parsed):
		last_error = "Morrow Coast source format, IDs or coordinates are invalid."
		return false
	doc = parsed.duplicate(true)
	initial = doc.duplicate(true)
	baseline_hash = _fingerprint(doc)
	history.clear()
	future.clear()
	dirty = false
	last_error = ""
	edit_revision += 1
	return true

func _fingerprint(value: Dictionary) -> String:
	# A stable normalization of JSON within the same native serializer.
	return JSON.stringify(value).sha256_text()

func matches_remote(remote: Dictionary) -> bool:
	return _valid_source(remote) and _fingerprint(remote) == baseline_hash

func _valid_source(value: Dictionary) -> bool:
	if value.get("format") != "gdt.racing-world" or int(value.get("version",-1)) != 2 or \
			value.get("name") != "Morrow Coast":
		return false
	var world: Variant = value.get("world")
	if not world is Dictionary:
		return false
	var width: float = float(world.get("width",0))
	var height: float = float(world.get("height",0))
	if width < 6400 or width > 9600 or height < 4800 or height > 7200:
		return false
	for category in ["roads","regions","props","markers","assets"]:
		if not value.get(category) is Array:
			return false
	if value.roads.size() > MAX_ROADS or value.props.size() > MAX_PROPS:
		return false
	var used := {}
	for road in value.roads:
		if not road is Dictionary or not str(road.get("id","")).begins_with("road-") or \
				not road.get("points") is Array or road.points.size() < 2 or \
				road.points.size() > 100:
			return false
		var identity := str(road.id)
		if used.has(identity):
			return false
		used[identity] = true
		for p in road.points:
			if not p is Dictionary or not _in_bounds(Vector2(
					float(p.get("x",-1)),float(p.get("y",-1))),value):
				return false
	for prop in value.props:
		if not prop is Dictionary or used.has(str(prop.get("id",""))):
			return false
		used[str(prop.id)] = true
		if not _in_bounds(Vector2(float(prop.get("x",-1)),
				float(prop.get("y",-1))),value):
			return false
	return true

func _in_bounds(p: Vector2, source: Dictionary = {}) -> bool:
	var record: Dictionary = source if not source.is_empty() else doc
	if record.is_empty():
		return false
	return is_finite(p.x) and is_finite(p.y) and \
		p.x >= 0 and p.y >= 0 and \
		p.x <= float(record.world.width) and p.y <= float(record.world.height)

func _commit(next: Dictionary) -> bool:
	if not _valid_source(next):
		last_error = "Edit was rejected: invalid world bounds or source geometry."
		return false
	if _fingerprint(doc) == _fingerprint(next):
		return true
	history.append(doc.duplicate(true))
	if history.size() > MAX_HISTORY:
		history.pop_front()
	doc = next
	edit_revision += 1
	future.clear()
	dirty = _fingerprint(doc) != baseline_hash
	last_error = ""
	return true

func undo() -> bool:
	if history.is_empty():
		return false
	future.append(doc.duplicate(true))
	doc = history.pop_back()
	edit_revision += 1
	dirty = _fingerprint(doc) != baseline_hash
	return true

func redo() -> bool:
	if future.is_empty():
		return false
	history.append(doc.duplicate(true))
	doc = future.pop_back()
	edit_revision += 1
	dirty = _fingerprint(doc) != baseline_hash
	return true

func discard_changes() -> void:
	doc = initial.duplicate(true)
	edit_revision += 1
	history.clear()
	future.clear()
	dirty = false

func accepted_remote(remote: Dictionary) -> bool:
	if not _valid_source(remote):
		return false
	doc = remote.duplicate(true)
	edit_revision += 1
	initial = doc.duplicate(true)
	baseline_hash = _fingerprint(doc)
	dirty = false
	history.clear()
	future.clear()
	return true

func road_at_id(road_id: String) -> Dictionary:
	for item in doc.get("roads",[]):
		if str(item.get("id","")) == road_id:
			return item
	return {}

func prop_at_id(prop_id: String) -> Dictionary:
	for item in doc.get("props",[]):
		if str(item.get("id","")) == prop_id:
			return item
	return {}

func _same_network(first: Dictionary, second: Dictionary) -> bool:
	var loose_a: bool = str(first.get("surface","")) in ["dirt","gravel"]
	var loose_b: bool = str(second.get("surface","")) in ["dirt","gravel"]
	return loose_a == loose_b

func move_road_point(road_id: String, point_index: int, destination_m: Vector2,
		grid_m: float = 1.0) -> bool:
	var target: Dictionary = road_at_id(road_id)
	if target.is_empty() or point_index < 0 or point_index >= target.points.size():
		last_error = "Select an editable source road control point."
		return false
	if grid_m > 0:
		destination_m = destination_m.snapped(Vector2(grid_m,grid_m))
	if not _in_bounds(destination_m):
		last_error = "Road anchors must remain inside the world."
		return false
	var from := Vector2(float(target.points[point_index].x),
		float(target.points[point_index].y))
	if from.distance_to(destination_m) > MAX_DRAG_M:
		last_error = "Road point moved more than 350m; choose a closer location."
		return false
	var draft: Dictionary = doc.duplicate(true)
	var touching_endpoint: bool = point_index == 0 or point_index == target.points.size()-1
	for road in draft.roads:
		var is_target: bool = str(road.id) == road_id
		if not is_target and not touching_endpoint:
			continue
		for i in road.points.size():
			if not is_target and i != 0 and i != road.points.size()-1:
				continue
			if not is_target and not _same_network(target,road):
				continue
			var location := Vector2(float(road.points[i].x),float(road.points[i].y))
			if (is_target and i==point_index) or \
					(touching_endpoint and location.distance_to(from)<0.05 and
					(i==0 or i==road.points.size()-1)):
				road.points[i] = {"x":destination_m.x,"y":destination_m.y}
	for road in draft.roads:
		for i in range(1,road.points.size()):
			var a := Vector2(float(road.points[i-1].x),float(road.points[i-1].y))
			var b := Vector2(float(road.points[i].x),float(road.points[i].y))
			if a.distance_to(b)<1.0:
				last_error = "Road point would create a zero-length segment."
				return false
	return _commit(draft)

func _new_prop_id() -> String:
	var used := {}
	for p in doc.props:
		used[str(p.id)] = true
	for i in range(1,MAX_PROPS+1):
		var key := "prop-native-%d" % i
		if not used.has(key):
			return key
	return ""

func add_prop(art_kind: String, position_m: Vector2) -> String:
	if not ART.has(art_kind) or not _in_bounds(position_m) or doc.props.size() >= MAX_PROPS:
		last_error = "Choose a supported game asset inside Morrow Coast."
		return ""
	var entry: Dictionary = ART[art_kind]
	var identity := _new_prop_id()
	if identity.is_empty():
		return ""
	var draft: Dictionary = doc.duplicate(true)
	draft.props.append({
		"id":identity,"name":art_kind.capitalize(),
		"type":str(entry.type),
		"x":position_m.x,"y":position_m.y,"rotation":0.0,
		"scale":1.0,"assetId":str(entry.assetId)
	})
	return identity if _commit(draft) else ""


## Match the browser editor's validated project asset contract exactly.
## These paths are relative to res://assets, never arbitrary external files.
func add_project_prop(relative_path: String, art_type: String, position_m: Vector2,
		footprint: Vector2) -> String:
	if not relative_path.begins_with("Buildings/") or "\\" in relative_path or \
			":" in relative_path or ".." in relative_path or \
			art_type not in ["house","building","warehouse","garage"] or \
			not _in_bounds(position_m) or doc.props.size() >= MAX_PROPS or \
			footprint.x <= 0.0 or footprint.y <= 0.0 or \
			footprint.x > 100.0 or footprint.y > 100.0:
		last_error = "Invalid project asset or placement."
		return ""
	var ext := relative_path.get_extension().to_lower()
	if ext not in ["png","webp","svg"] or not FileAccess.file_exists(
			"res://assets/"+relative_path):
		last_error = "Project artwork is missing or unsupported."
		return ""
	var identity := _new_prop_id()
	if identity.is_empty():
		last_error = "No source prop IDs remain."
		return ""
	var draft: Dictionary = doc.duplicate(true)
	draft.props.append({
		"id":identity,"name":relative_path.get_file().get_basename().replace("_"," "),
		"type":art_type,"x":position_m.x,"y":position_m.y,
		"rotation":0.0,"scale":1.0,
		"assetId":"project-"+relative_path.sha256_text().substr(0,24),
		"assetPath":relative_path,
		"assetSize":[footprint.x,footprint.y]
	})
	return identity if _commit(draft) else ""

## Adopt a specifically selected, replaceable original scene prop using the same
## (kind, seed, original-position) identity expected by the Python importer.
## Never edit an anonymous procedural instance in-place or change landmarks.
func adopt_runtime_prop(runtime: Dictionary) -> String:
	var mapping := {
		"tree":["oak","game-tree"],"pine":["pine","game-pine"],
		"palm":["palm","game-palm"],"rock":["rock","game-rock"],
		"house":["house","game-house"],"lodge":["house",""],
		"coastal_house":["house","game-coastal_house"],
		"shop":["building","game-shop"],"building":["building","game-shop"],
		"warehouse":["warehouse","game-shop"],"showroom":["building","game-garage"],
		"garage":["garage","game-garage"],"workshop":["garage","game-garage"],
		"fuel":["gas_station","game-shop"],
		"cafe":["building",""],"office":["building",""],
		"hotel":["building",""],"island":["island",""],
		"bush":["bush",""],"lamp":["streetlight",""],
		"sign":["sign",""],"barrier":["barrier",""],
		"dock":["dock",""],"lot":["parking",""],
		"forecourt":["forecourt",""],
		"parked_car":["parked_car",""],"planter":["planter",""],
		"garden":["garden",""],"field":["field",""],
		"drag_prep":["drag_prep",""],"drag_tree":["drag_tree",""],
		"drag_lane_mark":["drag_lane_mark",""],
		"drag_scoreboard":["drag_scoreboard",""],
		"grandstand":["grandstand",""],
		"start_line":["start_line",""],"finish_line":["finish_line",""]
	}
	var original_kind := str(runtime.get("kind",""))
	var identity_seed: Variant = runtime.get("seed")
	var place: Variant = runtime.get("p")
	# Godot JSON.parse_string can materialize an integer-valued JSON seed
	# as TYPE_FLOAT. Accept it only when finite and mathematically integral,
	# then write a real JSON integer back for Python's identity validator.
	var numeric_seed: bool = typeof(identity_seed) in [TYPE_INT,TYPE_FLOAT]
	var integral_seed: bool = numeric_seed and is_finite(float(identity_seed)) and \
		absf(float(identity_seed)-roundf(float(identity_seed)))<0.0001
	if not mapping.has(original_kind) or not integral_seed or \
			int(identity_seed)<0 or int(identity_seed)>2147483647 or \
			not place is Array or place.size()!=2 or \
			runtime.has("authoring_id") or \
			bool(runtime.get("protected",false)) or doc.props.size()>=MAX_PROPS:
		last_error = "This generated item has no safe replaceable source identity."
		return ""
	var origin := Vector2(float(place[0]),float(place[1]))
	if not _in_bounds(origin):
		last_error = "Original scenery is outside the editable world."
		return ""
	for item in doc.props:
		if not item.has("replaces"):
			continue
		var replacement: Dictionary = item.replaces
		if str(replacement.get("kind",""))==original_kind and \
				int(replacement.get("seed",-1))==int(identity_seed) and \
				Vector2(float(replacement.p[0]),float(replacement.p[1])).distance_to(origin)<0.05:
			last_error = "This original game item has already been adopted."
			return ""
	var id := _new_prop_id()
	if id.is_empty():
		return ""
	var style: Array = mapping[original_kind]
	var native_size: Variant = runtime.get("size",[12.0,17.0])
	var base_size := Vector2(12,17)
	match str(style[0]):
		"building":base_size=Vector2(22,29)
		"warehouse":base_size=Vector2(28,37)
		"garage":base_size=Vector2(20,21)
		"gas_station":base_size=Vector2(18,17)
		"oak","pine":base_size=Vector2(7,7)
		"palm":base_size=Vector2(6.5,6.5)
		"rock":base_size=Vector2(3,2.5)
		"bush":base_size=Vector2(2.5,2.5)
		"streetlight":base_size=Vector2(1.3,1.3)
		"sign":base_size=Vector2(1.6,1.4)
		"barrier":base_size=Vector2(3,1)
		"parking":base_size=Vector2(38,28)
		"dock":base_size=Vector2(3,11)
		"parked_car":base_size=Vector2(1.9,4.6)
		"planter":base_size=Vector2(2.8,2.8)
		"garden":base_size=Vector2(8,2.4)
		"field":base_size=Vector2(90,70)
		"island":base_size=Vector2(23,23)
		"forecourt":base_size=Vector2(23,16)
		"drag_prep":base_size=Vector2(8.5,22)
		"drag_tree":base_size=Vector2(3,10)
		"drag_lane_mark":base_size=Vector2(.35,12)
		"drag_scoreboard":base_size=Vector2(4,10)
		"grandstand":base_size=Vector2(36,17)
		"start_line","finish_line":base_size=Vector2(14,1.2)
	var size_ratio := 1.0
	if native_size is Array and native_size.size()==2:
		size_ratio = clampf((float(native_size[0])/base_size.x+
			float(native_size[1])/base_size.y)*0.5,0.25,5.0)
	var draft: Dictionary = doc.duplicate(true)
	draft.props.append({
		"id":id,"name":original_kind.capitalize(),
		"type":str(style[0]),"assetId":str(style[1]),
		"x":origin.x,"y":origin.y,
		"rotation":clampf(rad_to_deg(float(runtime.get("angle",0.0))),-360.0,360.0),
		"scale":size_ratio,
		"replaces":{"kind":original_kind,"seed":int(identity_seed),
			"p":[origin.x,origin.y]},"hidden":false
	})
	if not _commit(draft):
		return ""
	return id


func move_prop(prop_id: String, destination_m: Vector2, grid_m: float = 1.0) -> bool:
	var item := prop_at_id(prop_id)
	if item.is_empty() or not _in_bounds(destination_m):
		last_error = "Only source-authored assets may be moved inside the world."
		return false
	if grid_m > 0:
		destination_m = destination_m.snapped(Vector2(grid_m,grid_m))
	if not _in_bounds(destination_m):
		return false
	var original := Vector2(float(item.x),float(item.y))
	if original.distance_to(destination_m)>MAX_DRAG_M:
		last_error = "Asset moved more than 350m; use smaller steps."
		return false
	var draft: Dictionary = doc.duplicate(true)
	for prop in draft.props:
		if str(prop.id)==prop_id:
			prop.x = destination_m.x
			prop.y = destination_m.y
			return _commit(draft)
	return false

func rotate_prop(prop_id: String, step_degrees: float) -> bool:
	if not is_finite(step_degrees) or absf(step_degrees)>180.0:
		return false
	var draft: Dictionary = doc.duplicate(true)
	for prop in draft.props:
		if str(prop.id)==prop_id:
			prop.rotation = wrapf(float(prop.rotation)+step_degrees,-180.0,180.0)
			return _commit(draft)
	return false

func resize_prop(prop_id: String, factor: float) -> bool:
	if not is_finite(factor) or factor<0.75 or factor>1.25:
		return false
	var draft: Dictionary = doc.duplicate(true)
	for prop in draft.props:
		if str(prop.id)==prop_id:
			prop.scale = clampf(float(prop.scale)*factor,0.25,5.0)
			return _commit(draft)
	return false

func delete_prop(prop_id: String) -> bool:
	var item := prop_at_id(prop_id)
	if item.is_empty():
		last_error = "No editable asset selected."
		return false
	if item.has("replaces"):
		var hidden_draft: Dictionary = doc.duplicate(true)
		for prop in hidden_draft.props:
			if str(prop.id)==prop_id:
				prop.hidden = true
				return _commit(hidden_draft)
		return false
	var draft: Dictionary = doc.duplicate(true)
	var props: Array = []
	for prop in draft.props:
		if str(prop.id)!=prop_id:
			props.append(prop)
	draft.props = props
	return _commit(draft)

## Direct tools share the browser editor's source schema and undo log.
func add_road(first: Vector2, last: Vector2) -> String:
	if not _in_bounds(first) or not _in_bounds(last) or \
			first.distance_to(last) < 3.0 or doc.roads.size() >= MAX_ROADS:
		last_error = "Road must have two distinct in-bounds endpoints."
		return ""
	var id := "road-%d" % doc.roads.size()
	var draft: Dictionary = doc.duplicate(true)
	draft.roads.append({"id":id,"name":"Editor road","roadClass":"city",
		"surface":"asphalt","width":10,"lanes":2,"shoulder":2,
		"smooth":true,"markings":true,
		"points":[{"x":first.x,"y":first.y},{"x":last.x,"y":last.y}]})
	return id if _commit(draft) else ""


func add_region(points_m: Array[Vector2], biome: String = "grass") -> String:
	if points_m.size()<3 or biome not in ["grass","forest","city","beach",
			"rock","mountain","lake","desert","farmland","ocean"]:
		last_error = "Terrain needs three points and a supported biome."
		return ""
	for p in points_m:
		if not _in_bounds(p):
			last_error = "Terrain point outside the map."
			return ""
	var id := "region-%d" % doc.regions.size()
	var vertices: Array[Dictionary] = []
	for p in points_m:
		vertices.append({"x":p.x,"y":p.y})
	var draft: Dictionary = doc.duplicate(true)
	draft.regions.append({"id":id,"name":"Editor terrain",
		"biome":biome,"points":vertices})
	return id if _commit(draft) else ""


func add_marker(position_m: Vector2, marker_kind: String = "checkpoint") -> String:
	if not _in_bounds(position_m) or marker_kind not in [
			"traffic_spawn","race_start","checkpoint","finish"]:
		last_error = "Unsupported game marker or position."
		return ""
	var id := "marker-%d" % doc.markers.size()
	var draft: Dictionary = doc.duplicate(true)
	draft.markers.append({"id":id,"name":marker_kind.capitalize(),
		"type":marker_kind,"x":position_m.x,"y":position_m.y,
		"rotation":0.0})
	return id if _commit(draft) else ""


func source_road_id_for_runtime(index: int) -> String:
	# The importer shifts only legacy IDs at the source_count boundary;
	# IDs before the recorded basis are identical to runtime road indices.
	if index < 0 or index >= doc.roads.size():
		return ""
	var id := "road-%d" % index
	return id if not road_at_id(id).is_empty() else ""

func index_of_runtime_prop(runtime: Dictionary) -> String:
	# A generated item has NO stable editable identity. Refuse to move it,
	# even when its appearance resembles a sourced object.
	var authoring_id := str(runtime.get("authoring_id",""))
	return authoring_id if not prop_at_id(authoring_id).is_empty() else ""
