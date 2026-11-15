extends RefCounted
## Source-safe, undoable authoring draft. This never mutates a live Morrow Coast
## Dictionary. Runtime streets, intersections and traffic remain authoritative
## until the checked-in production builder has completed an Apply operation.
const SOURCE := "res://map-editor/maps/morrow-coast.edits.world.json"
const MAX_HISTORY := 40
const RaceDefinition=preload("res://scripts/world/authored_race_definition.gd")
const RoadShapes=preload("res://scripts/dev/road_shape_geometry.gd")
const MAX_ROADS := 180
const MAX_PROPS := 4000
const MAX_DRAG_M := 350.0
const SIDEWALK_SNAP_M := 3.0
const SIDEWALK_POINT_MIN_M := 0.5
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
var draft_baseline_hash := ""
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
	draft_baseline_hash=baseline_hash
	history.clear()
	future.clear()
	dirty = false
	last_error = ""
	edit_revision += 1
	return true

func _fingerprint(value: Dictionary) -> String:
	# A stable normalization of JSON within the same native serializer.
	# JSON.parse_string normalizes integer tokens to floats in Godot. Hash the
	# same normalized representation before/after recovery or HTTP round trips.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value))).sha256_text()

func matches_remote(remote: Dictionary) -> bool:
	return _valid_source(remote) and _fingerprint(remote) == baseline_hash

func _valid_source(value: Dictionary) -> bool:
	if value.get("format") != "gdt.racing-world" or int(value.get("version",-1)) != 2 or \
			(value.get("name") != "Morrow Coast" and not value.get("customMap",false)):
		return false
	var world: Variant = value.get("world")
	if not world is Dictionary:
		return false
	var width: float = float(world.get("width",0))
	var height: float = float(world.get("height",0))
	if value.get("customMap",false):
		if str(value.get("name","")).strip_edges().is_empty() or world.get("base","grass") not in ["grass","forest","beach","desert","ocean","city","rock","mountain","lake","farmland"]:return false
		if not is_finite(width) or not is_finite(height) or width!=floorf(width) or height!=floorf(height):return false
	if (width < 600 or width > 24000 or height < 600 or height > 24000) if value.get("customMap",false) else (width < 6400 or width > 9600 or height < 4800 or height > 7200):
		return false
	for category in ["roads","regions","props","markers","assets"]:
		if not value.get(category) is Array:
			return false
	if value.roads.size() > MAX_ROADS or value.props.size() > MAX_PROPS or value.regions.size()>220 or value.markers.size()>400:
		return false
	var used := {}
	if not value.get("races",[]) is Array or value.get("races",[]).size()>64:return false
	for race in value.get("races",[]):
		if not race is Dictionary or not RaceDefinition.valid(race,width,height) or used.has(str(race.id)):return false
		used[str(race.id)]=true
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
		for i in range(1,road.points.size()):
			if Vector2(road.points[i].x,road.points[i].y).distance_to(Vector2(road.points[i-1].x,road.points[i-1].y))<1.0:return false
		if float(road.get("width",10))<6 or float(road.get("width",10))>160:return false
	for category in ["regions","markers"]:
		for item in value[category]:
			if not item is Dictionary or not item.has("id") or used.has(str(item.id)):return false
			used[str(item.id)]=true
			if category=="regions":
				if not item.get("points") is Array or item.points.size()<3 or item.points.size()>180:return false
				for point in item.points:
					if not _in_bounds(Vector2(float(point.get("x",-1)),float(point.get("y",-1))),value):return false
				if value.get("customMap",false):
					var polygon:=PackedVector2Array()
					for point in item.points:polygon.append(Vector2(point.x,point.y))
					if Geometry2D.triangulate_polygon(polygon).is_empty():return false
				if item.has("barrier") and not item.barrier is bool:return false
				if bool(item.get("barrier",false)) and (str(item.get("biome","")) not in ["mountain","rock"] or float(item.get("elevation",0))<5):return false
			elif not _in_bounds(Vector2(float(item.get("x",-1)),float(item.get("y",-1))),value):return false
	for prop in value.props:
		if not prop is Dictionary or used.has(str(prop.get("id",""))):
			return false
		if prop.has("roadFacing") and not prop.roadFacing is bool:return false
		if prop.has("roadFront") and prop.roadFront not in [0,90,180,270]:return false
		used[str(prop.id)] = true
		if not _in_bounds(Vector2(float(prop.get("x",-1)),
				float(prop.get("y",-1))),value):
			return false
		if str(prop.get("type",""))=="sidewalk":
			var vertices: Array[Vector2]=sidewalk_world_points(prop)
			var sizes: Array=prop.get("assetSize",[])
			if vertices.size()<2 or vertices.size()>100 or sizes.size()!=2 or (
					not is_finite(float(sizes[0])) or not is_finite(float(sizes[1])) or
					minf(float(sizes[0]),float(sizes[1]))<=0 or
					maxf(float(sizes[0]),float(sizes[1]))>12000 or
					float(prop.get("sidewalkWidth",0))<0.8 or float(prop.get("sidewalkWidth",0))>12.0):
				return false
			var local: Array=prop.get("sidewalkPoints",[])
			for i in vertices.size():
				if not _in_bounds(vertices[i],value):return false
				if i>0 and Vector2(float(local[i][0]),float(local[i][1])).distance_to(
						Vector2(float(local[i-1][0]),float(local[i-1][1])))<SIDEWALK_POINT_MIN_M:return false
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
	dirty = _fingerprint(doc) != draft_baseline_hash
	last_error = ""
	return true

func undo() -> bool:
	if history.is_empty():
		return false
	future.append(doc.duplicate(true))
	doc = history.pop_back()
	edit_revision += 1
	dirty = _fingerprint(doc) != draft_baseline_hash
	return true

func redo() -> bool:
	if future.is_empty():
		return false
	history.append(doc.duplicate(true))
	doc = future.pop_back()
	edit_revision += 1
	dirty = _fingerprint(doc) != draft_baseline_hash
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
	draft_baseline_hash=baseline_hash
	dirty = false
	history.clear()
	future.clear()
	return true

func road_at_id(road_id: String) -> Dictionary:
	for item in doc.get("roads",[]):
		if str(item.get("id","")) == road_id:
			return item
	return {}

func reconcile_runtime(data: Dictionary) -> bool:
	# The generator may introduce new default roads/POIs between editor saves.
	# Keep the on-disk hash for conflict detection, but edit the complete current
	# layout. Otherwise road-120 could mask a new highway instead of the user's road.
	var basis:=int(doc.get("morrowSourceRoadCount",120))
	var current:=int(data.get("editor_source_road_count",basis))
	var poi_basis:=int(doc.get("morrowSourcePoiCount",15))
	var poi_current:=int(data.get("editor_source_poi_count",poi_basis))
	var recovered:=false
	var authored: Dictionary={}
	for runtime in data.get("props",[]):
		if runtime.has("authoring_id"):authored[str(runtime.authoring_id)]=runtime
	for prop in doc.props:
		if not prop.has("replaces") or prop.has("sourceAppearance") or not authored.has(str(prop.id)):continue
		var runtime: Dictionary=authored[str(prop.id)]
		prop["sourceAppearance"]=runtime.duplicate(true)
		var scale_value: float=float(prop.get("scale",1))
		prop["assetSize"]=[float(runtime.size[0])/scale_value/float(prop.get("scaleX",1)),float(runtime.size[1])/scale_value/float(prop.get("scaleY",1))]
		recovered=true
	if recovered:
		initial=doc.duplicate(true);draft_baseline_hash=_fingerprint(doc);edit_revision+=1
	if current<=basis and poi_current<=poi_basis:return true
	var next:=doc.duplicate(true)
	if current>basis:
		for road in next.roads:
			var number:=int(str(road.id).trim_prefix("road-"))
			if number>=basis:road.id="road-%d"%(number+current-basis)
		for i in range(basis,current):
			if i>=data.roads.size():return false
			var raw: Dictionary=data.roads[i]
			var points: Array[Dictionary]=[]
			for p in raw.get("anchors",raw.points):points.append({"x":float(p[0]),"y":float(p[1])})
			next.roads.append({"id":"road-%d"%i,"name":str(raw.name),
				"roadClass":{"highway":"highway","rural":"country","mountain":"mountain","driveway":"service","track":"track"}.get(str(raw.kind),"city"),
				"surface":str(raw.surface).to_lower(),"width":float(raw.width)/float(data.get("road_width_scale",1))*float(doc.get("morrowRoadWidthScale",1)),
				"lanes":int(raw.lanes),"shoulder":2.0,"smooth":true,"markings":true,"points":points})
		next.roads.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(str(a.id).trim_prefix("road-"))<int(str(b.id).trim_prefix("road-")))
		next.morrowSourceRoadCount=current
	if poi_current>poi_basis:
		for marker in next.markers:
			var number:=int(str(marker.id).trim_prefix("marker-"))
			if number>poi_basis:marker.id="marker-%d"%(number+poi_current-poi_basis)
		for i in range(poi_basis,poi_current):
			if i>=data.pois.size():return false
			var poi: Dictionary=data.pois[i]
			next.markers.append({"id":"marker-%d"%(i+1),"name":str(poi.name),"type":"fuel" if "FUEL" in str(poi.category) else "custom",
				"x":float(poi.position[0]),"y":float(poi.position[1]),"rotation":0.0,"properties":{}})
		next.morrowSourcePoiCount=poi_current
	if not _valid_source(next):return false
	doc=next;initial=doc.duplicate(true);draft_baseline_hash=_fingerprint(doc)
	history.clear();future.clear();dirty=false;edit_revision+=1
	return true

func prop_at_id(prop_id: String) -> Dictionary:
	for item in doc.get("props",[]):
		if str(item.get("id","")) == prop_id:
			return item
	return {}

func race_at_id(identity: String) -> Dictionary:
	for race in doc.get("races",[]):
		if str(race.id)==identity:return race
	return {}

func save_race(points_m: Array[Vector2],settings: Dictionary,identity: String="") -> String:
	var race:=settings.duplicate(true)
	race.id=next_id("races","race") if identity.is_empty() else identity
	race.points=[]
	for p in points_m:race.points.append({"x":p.x,"y":p.y})
	if not RaceDefinition.valid(race,float(doc.world.width),float(doc.world.height)):
		last_error="Use a named sprint with 2+ points or a circuit with 3+ points. Keep checkpoints at least 5 m apart.";return ""
	var next:=doc.duplicate(true)
	if not next.has("races"):next["races"]=[]
	var replaced:=false
	for i in next.races.size():
		if str(next.races[i].id)==str(race.id):next.races[i]=race;replaced=true;break
	if not replaced:next.races.append(race)
	return str(race.id) if _commit(next) else ""

func move_race_point(identity: String,index: int,destination: Vector2) -> bool:
	var next:=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		if index<0 or index>=race.points.size():return false
		race.points[index]={"x":destination.x,"y":destination.y};return _commit(next)
	return false

func change_race_points(identity: String,index: int,remove: bool) -> bool:
	var next:=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		index=clampi(index,0,race.points.size()-1)
		if remove:
			if race.points.size()<=(3 if race.mode=="circuit" else 2):last_error="Keep the race's start, finish and required checkpoints.";return false
			race.points.remove_at(index)
		else:
			var a: Dictionary=race.points[mini(index,race.points.size()-2)];var b: Dictionary=race.points[mini(index+1,race.points.size()-1)]
			race.points.insert(mini(index+1,race.points.size()-1),{"x":(a.x+b.x)*.5,"y":(a.y+b.y)*.5})
		return _commit(next)
	return false

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
	var touching_endpoint: bool = (point_index == 0 or point_index == target.points.size()-1) and not bool(target.get("independentEnds",false))
	for road in draft.roads:
		var is_target: bool = str(road.id) == road_id
		if not is_target and (not touching_endpoint or bool(road.get("independentEnds",false))):
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
		footprint: Vector2, sprite_id: String = "", sprite_region: Array = [],
		collision_mode: String = "solid", asset_name: String = "") -> String:
	if not (relative_path.begins_with("Buildings/") or relative_path.begins_with("Map Building Assets/")) or \
			"\\" in relative_path or ":" in relative_path or ".." in relative_path or \
			art_type not in ["house","building","warehouse","garage","gas_station",
				"industrial_prop","road_prop","ground_decal","oak","pine","palm","bush","rock","boulder"] or \
			collision_mode not in ["solid","none"] or \
			not _in_bounds(position_m) or doc.props.size() >= MAX_PROPS or \
			footprint.x <= 0.0 or footprint.y <= 0.0 or \
			footprint.x > 100.0 or footprint.y > 100.0:
		last_error = "Invalid project asset or placement."
		return ""
	var ext := relative_path.get_extension().to_lower()
	var found := FileAccess.file_exists("res://assets/"+relative_path)
	if not found and relative_path.begins_with("Buildings/"):
		found=FileAccess.file_exists("res://assets/Map Building Assets/"+relative_path)
	if ext not in ["png","webp","svg"] or not found:
		last_error = "Project artwork is missing or unsupported."
		return ""
	if sprite_region.size()!=0 and sprite_region.size()!=4:
		last_error = "Invalid sprite region."
		return ""
	var identity := _new_prop_id()
	if identity.is_empty():
		last_error = "No source prop IDs remain."
		return ""
	var final_id := sprite_id if sprite_id.begins_with("project-") else "project-"+relative_path.sha256_text().substr(0,24)
	var draft: Dictionary = doc.duplicate(true)
	var prop := {
		"id":identity,"name":asset_name if not asset_name.is_empty() else relative_path.get_file().get_basename().replace("_"," "),
		"type":art_type,"x":position_m.x,"y":position_m.y,
		"rotation":0.0,"scale":1.0,"assetId":final_id,
		"assetPath":relative_path,"assetSize":[footprint.x,footprint.y],
		"assetCollision":collision_mode
	}
	if sprite_region.size()==4:
		prop["assetRegion"]=sprite_region.duplicate()
	draft.props.append(prop)
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
		"type":str(style[0]),"assetId":"",
		"x":origin.x,"y":origin.y,
		"rotation":clampf(rad_to_deg(float(runtime.get("angle",0.0))),-360.0,360.0),
		"scale":1.0,"scaleX":1.0,"scaleY":1.0,
		"assetSize":native_size.duplicate(),"sourceAppearance":runtime.duplicate(true),
		"replaces":{"kind":original_kind,"seed":int(identity_seed),
			"p":[origin.x,origin.y]},"hidden":false
	})
	if not _commit(draft):
		return ""
	return id

## Sidewalks stay independent from the road traffic graph. Convert their
## authored local points into world coordinates before connecting branches.
static func sidewalk_world_points(prop: Dictionary) -> Array[Vector2]:
	var vertices: Array[Vector2]=[]
	if str(prop.get("type",""))!="sidewalk":return vertices
	var center:=Vector2(float(prop.get("x",0)),float(prop.get("y",0)))
	var angle:=deg_to_rad(float(prop.get("rotation",0)))
	var scale:=Vector2(float(prop.get("scale",1))*float(prop.get("scaleX",1)),
		float(prop.get("scale",1))*float(prop.get("scaleY",1)))
	for p in prop.get("sidewalkPoints",[]):
		if not p is Array or p.size()!=2 or not is_finite(float(p[0])) or not is_finite(float(p[1])):return []
		vertices.append(center+(Vector2(float(p[0]),float(p[1]))*scale).rotated(angle))
	return vertices


func _set_sidewalk_world_points(prop: Dictionary, vertices: Array[Vector2]) -> bool:
	if vertices.size()<2 or vertices.size()>100:return false
	var center:=Vector2(float(prop.x),float(prop.y))
	var angle:=deg_to_rad(float(prop.get("rotation",0)))
	var scale:=Vector2(float(prop.get("scale",1))*float(prop.get("scaleX",1)),
		float(prop.get("scale",1))*float(prop.get("scaleY",1)))
	if minf(scale.x,scale.y)<=0.0:return false
	var local: Array=[]
	var radius:=Vector2.ZERO
	var previous:=Vector2.INF
	for at in vertices:
		if not _in_bounds(at):return false
		var relative: Vector2=(at-center).rotated(-angle)/scale
		if not is_finite(relative.x) or not is_finite(relative.y) or (
				not local.is_empty() and relative.distance_to(previous)<SIDEWALK_POINT_MIN_M):
			return false
		local.append([relative.x,relative.y])
		radius=radius.max(relative.abs())
		previous=relative
	var size: Vector2=radius*2.0+Vector2.ONE*float(prop.get("sidewalkWidth",3))
	if maxf(size.x,size.y)>12000.0:return false
	prop["sidewalkPoints"]=local
	prop["assetSize"]=[size.x,size.y]
	return true


## Existing anchors and points in the middle of a path are both snap targets.
func _sidewalk_connection(at: Vector2,skip_id: String="",radius: float=SIDEWALK_SNAP_M,
		source: Dictionary={}) -> Dictionary:
	var record: Dictionary=source if not source.is_empty() else doc
	var best:=radius+0.00001
	var hit: Dictionary={}
	for prop in record.get("props",[]):
		if str(prop.get("type",""))!="sidewalk" or str(prop.id)==skip_id or bool(prop.get("hidden",false)):continue
		var vertices:=sidewalk_world_points(prop)
		for i in vertices.size():
			var distance:=at.distance_to(vertices[i])
			if distance<best-0.001:
				best=distance
				hit={"id":str(prop.id),"point":vertices[i],"index":i}
		for i in range(1,vertices.size()):
			var point:=Geometry2D.get_closest_point_to_segment(at,vertices[i-1],vertices[i])
			var distance:=at.distance_to(point)
			if distance>=best-0.001:continue
			if point.distance_to(vertices[i-1])<SIDEWALK_POINT_MIN_M or (
					point.distance_to(vertices[i])<SIDEWALK_POINT_MIN_M):
				continue
			best=distance
			hit={"id":str(prop.id),"point":point,"span":i}
	return hit


func sidewalk_snap_point(at: Vector2,radius: float=SIDEWALK_SNAP_M) -> Vector2:
	var hit:=_sidewalk_connection(at,"",radius)
	return Vector2(hit.point) if not hit.is_empty() else at


func _connect_sidewalk_in_doc(next: Dictionary,identity: String,index: int,
		radius: float=SIDEWALK_SNAP_M) -> bool:
	var source: Dictionary={}
	for prop in next.props:
		if str(prop.id)==identity:source=prop;break
	if source.is_empty():return false
	var points:=sidewalk_world_points(source)
	if index not in [0,points.size()-1]:return false
	var hit:=_sidewalk_connection(points[index],identity,radius,next)
	if hit.is_empty():return false
	var destination: Vector2=hit.point
	var target: Dictionary={}
	for prop in next.props:
		if str(prop.id)==str(hit.id):target=prop;break
	if target.is_empty():return false
	var neighbors:=sidewalk_world_points(target)
	if hit.has("span"):neighbors.insert(int(hit.span),destination)
	points[index]=destination
	if not _set_sidewalk_world_points(source,points) or (
			not _set_sidewalk_world_points(target,neighbors)):
		return false
	return true


## Insert a real control point where two sidewalks cross, so an X junction
## behaves like two T junctions rather than two independent overlays.
func _insert_sidewalk_junction(prop: Dictionary,intersection: Vector2) -> bool:
	var points:=sidewalk_world_points(prop)
	for p in points:
		if p.distance_to(intersection)<0.05:return true
	if points.size()>=100:return false
	for i in range(1,points.size()):
		var projected:=Geometry2D.get_closest_point_to_segment(intersection,points[i-1],points[i])
		if projected.distance_to(intersection)>0.05:continue
		if points[i-1].distance_to(intersection)<SIDEWALK_POINT_MIN_M or (
				points[i].distance_to(intersection)<SIDEWALK_POINT_MIN_M):
			return false
		points.insert(i,intersection)
		return _set_sidewalk_world_points(prop,points)
	return false


func _link_sidewalk_crossings(next: Dictionary,identity: String) -> void:
	var source: Dictionary={}
	for prop in next.props:
		if str(prop.id)==identity:source=prop;break
	if source.is_empty():return
	for target in next.props:
		if str(target.get("type",""))!="sidewalk" or str(target.id)==identity:continue
		var crossed: Array[Vector2]=[]
		var a:=sidewalk_world_points(source)
		var b:=sidewalk_world_points(target)
		for i in range(1,a.size()):
			for j in range(1,b.size()):
				var intersection: Variant=Geometry2D.segment_intersects_segment(a[i-1],a[i],b[j-1],b[j])
				if intersection is Vector2:
					var unique:=true
					for old in crossed:
						if old.distance_to(intersection)<0.05:unique=false;break
					if unique:crossed.append(intersection)
		for intersection in crossed:
			# Stage both insertions so an invalid 0.5m segment never alters
			# either path when only one half of the junction is possible.
			var src_copy: Dictionary=source.duplicate(true)
			var dst_copy: Dictionary=target.duplicate(true)
			if _insert_sidewalk_junction(src_copy,intersection) and (
					_insert_sidewalk_junction(dst_copy,intersection)):
				source.merge(src_copy,true)
				target.merge(dst_copy,true)


func reconnect_sidewalk_endpoint(identity: String,index: int,radius: float=SIDEWALK_SNAP_M) -> bool:
	var source:=prop_at_id(identity)
	if str(source.get("type",""))!="sidewalk" or index not in [0,source.sidewalkPoints.size()-1]:
		last_error="Select the first or last sidewalk point to connect.";return false
	var next:=doc.duplicate(true)
	if not _connect_sidewalk_in_doc(next,identity,index,radius):
		last_error="Move the endpoint within %.1fm of an existing sidewalk."%radius;return false
	return _commit(next)


func move_sidewalk_point(identity: String,index: int,destination: Vector2,
		grid_m: float=0.0,move_joined: bool=true) -> bool:
	var item:=prop_at_id(identity)
	if str(item.get("type",""))!="sidewalk":return false
	var current:=sidewalk_world_points(item)
	if index<0 or index>=current.size():return false
	if grid_m>0:destination=destination.snapped(Vector2.ONE*grid_m)
	var old: Vector2=current[index]
	if old.distance_to(destination)>MAX_DRAG_M or not _in_bounds(destination):
		last_error="Keep sidewalk handles inside the map and move under 350m.";return false
	var next:=doc.duplicate(true)
	for prop in next.props:
		if str(prop.get("type",""))!="sidewalk":continue
		if str(prop.id)!=identity and not move_joined:continue
		var points:=sidewalk_world_points(prop)
		var changed:=false
		for i in points.size():
			if (str(prop.id)==identity and i==index) or (
					move_joined and points[i].distance_to(old)<0.05):
				points[i]=destination;changed=true
		if changed and not _set_sidewalk_world_points(prop,points):
			last_error="This would overlap path handles or move a joined path outside the map.";return false
	return _commit(next)


func insert_sidewalk_point(identity: String,index: int) -> bool:
	var next:=doc.duplicate(true)
	for prop in next.props:
		if str(prop.id)!=identity or str(prop.get("type",""))!="sidewalk":continue
		var points:=sidewalk_world_points(prop)
		if points.size()>=100:return false
		var segment:=clampi(index,0,points.size()-2)
		points.insert(segment+1,(points[segment]+points[segment+1])*.5)
		if not _set_sidewalk_world_points(prop,points):return false
		return _commit(next)
	return false


func remove_sidewalk_point(identity: String,index: int) -> bool:
	var next:=doc.duplicate(true)
	for prop in next.props:
		if str(prop.id)!=identity or str(prop.get("type",""))!="sidewalk":continue
		var points:=sidewalk_world_points(prop)
		if points.size()<=2 or index<0 or index>=points.size():
			last_error="Keep at least two sidewalk points.";return false
		points.remove_at(index)
		if not _set_sidewalk_world_points(prop,points):return false
		return _commit(next)
	return false


func add_sidewalk(points_m: Array[Vector2],width_m: float=3.0) -> String:
	if points_m.size()<2 or points_m.size()>100 or width_m<.8 or width_m>12:
		last_error="Sidewalks need 2–100 points and width 0.8–12 m.";return ""
	var bounds:=Rect2(points_m[0],Vector2.ZERO)
	for i in points_m.size():
		if not _in_bounds(points_m[i]) or (i>0 and points_m[i].distance_to(points_m[i-1])<.5):
			last_error="Keep sidewalk points in the map and at least half a metre apart.";return ""
		bounds=bounds.expand(points_m[i])
	var center:=bounds.get_center()
	var id:=_new_prop_id();var next:=doc.duplicate(true)
	var prop: Dictionary={"id":id,"name":"Sidewalk","type":"sidewalk","assetId":"",
		"x":center.x,"y":center.y,"rotation":0,"scale":1,
		"assetSize":[bounds.size.x+width_m,bounds.size.y+width_m],
		"sidewalkWidth":width_m,"sidewalkPoints":[]}
	if not _set_sidewalk_world_points(prop,points_m):
		last_error="Invalid sidewalk path or footprint.";return ""
	next.props.append(prop)
	# Branch from the end or middle of any existing path in one undo step.
	for endpoint in [0,points_m.size()-1]:
		var trial: Dictionary=next.duplicate(true)
		if _connect_sidewalk_in_doc(trial,id,endpoint):next=trial
	_link_sidewalk_crossings(next,id)
	return id if _commit(next) else ""


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
	var moved_sidewalk:=str(item.get("type",""))=="sidewalk"
	var previous: Array[Vector2]=sidewalk_world_points(item) if moved_sidewalk else []
	var delta:=destination_m-original
	for prop in draft.props:
		if str(prop.id)==prop_id:
			prop.x=destination_m.x;prop.y=destination_m.y
		elif moved_sidewalk and str(prop.get("type",""))=="sidewalk":
			var points:=sidewalk_world_points(prop)
			var changed:=false
			for i in points.size():
				for old in previous:
					if points[i].distance_to(old)<0.05:
						points[i]+=delta;changed=true;break
			if changed and not _set_sidewalk_world_points(prop,points):
				last_error="Moving this sidewalk would pull a joined path outside the map.";return false
	return _commit(draft)

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
	return add_road_path([first,last])

func next_id(category: String, prefix: String) -> String:
	var number := 0
	for item in doc.get(category,[]):
		var text:=str(item.get("id",""))
		if text.begins_with(prefix+"-") and text.trim_prefix(prefix+"-").is_valid_int():
			number=maxi(number,int(text.trim_prefix(prefix+"-"))+1)
	return prefix+"-"+str(number)

func add_road_path(points_m: Array[Vector2], settings: Dictionary={}) -> String:
	if points_m.size()<2 or points_m.size()>100 or doc.roads.size()>=MAX_ROADS:
		last_error="Roads need 2–100 control points; at most 180 roads are supported."
		return ""
	var vertices: Array[Dictionary]=[]
	for point in points_m:
		if not _in_bounds(point):
			last_error="Road points must be inside the map."
			return ""
		if not vertices.is_empty() and point.distance_to(Vector2(vertices[-1].x,vertices[-1].y))<1.0:
			last_error="Road points must be at least one metre apart."
			return ""
		vertices.append({"x":point.x,"y":point.y})
	var id:=next_id("roads","road")
	var road: Dictionary={"id":id,"name":"Editor road","roadClass":"city",
		"surface":"asphalt","width":10.0,"lanes":2,"shoulder":2.0,"smooth":true,"markings":true,"points":vertices}
	for key in ["roadClass","surface","width","lanes"]:
		if settings.has(key):road[key]=settings[key]
	var next:=doc.duplicate(true)
	next.roads.append(road)
	var temporary=get_script().new();temporary.doc=next
	for endpoint in [0,vertices.size()-1]:temporary.reconnect_endpoint(id,endpoint,.05)
	return id if _commit(temporary.doc) else ""

func move_shape(category: String, identity: String, delta: Vector2, grid_m: float=0.0) -> bool:
	if grid_m>0:delta=delta.snapped(Vector2.ONE*grid_m)
	var next:=doc.duplicate(true)
	var target: Dictionary={}
	for item in next.get(category,[]):
		if str(item.id)==identity:target=item;break
	if target.is_empty():
		last_error="Select a road, region or marker first."
		return false
	if category=="markers":
		target.x=float(target.x)+delta.x;target.y=float(target.y)+delta.y
	else:
		var ends: Array[Vector2]=[]
		if category=="roads" and not bool(target.get("independentEnds",false)):
			ends=[Vector2(target.points[0].x,target.points[0].y),Vector2(target.points[-1].x,target.points[-1].y)]
			if not RoadShapes.circle(target.points).is_empty():
				ends.clear()
				for p in target.points:ends.append(RoadShapes.point(p))
		for point in target.points:
			point.x=float(point.x)+delta.x;point.y=float(point.y)+delta.y
		if category=="roads":
			for road in next.roads:
				if str(road.id)==identity or not _same_network(target,road) or bool(road.get("independentEnds",false)):continue
				for index in [0,road.points.size()-1]:
					var point: Dictionary=road.points[index]
					for old in ends:
						if Vector2(point.x,point.y).distance_to(old)<.05:
							point.x=float(point.x)+delta.x;point.y=float(point.y)+delta.y;break
	return _commit(next)

static func road_path(road: Dictionary) -> PackedVector2Array:
	var anchors: Array=road.get("points",[])
	var circle:=RoadShapes.circle(anchors)
	if not circle.is_empty():return RoadShapes.circle_path(anchors,circle)
	var result:=PackedVector2Array()
	for i in range(anchors.size()-1):
		var a:=Vector2(anchors[i].x,anchors[i].y)
		var b:=Vector2(anchors[i+1].x,anchors[i+1].y)
		var prior: Dictionary=anchors[maxi(0,i-1)]
		var following: Dictionary=anchors[mini(anchors.size()-1,i+2)]
		var ta: Vector2=((b-Vector2(prior.x,prior.y))*.33).limit_length(a.distance_to(b)*.7)
		var tb: Vector2=((Vector2(following.x,following.y)-a)*.33).limit_length(a.distance_to(b)*.7)
		var steps:=clampi(ceili(a.distance_to(b)/6.0),2,160)
		for j in steps:
			var t:=float(j)/steps
			result.append(a.lerp(b,t) if not bool(road.get("smooth",true)) else
				a*(2*t*t*t-3*t*t+1)+b*(-2*t*t*t+3*t*t)+ta*(t*t*t-2*t*t+t)+tb*(t*t*t-t*t))
	if not anchors.is_empty():result.append(Vector2(anchors[-1].x,anchors[-1].y))
	return result

func add_circle_road(center: Vector2,radius: float,settings: Dictionary={}) -> String:
	if not is_finite(radius) or radius<8:
		last_error="Circular roads need a radius of at least 8 metres.";return ""
	if radius<=float(settings.get("width",10))*.5+2:
		last_error="Increase the radius so the roundabout has an open center.";return ""
	return add_road_path(RoadShapes.circle_points(center,radius),settings)

func _replace_road_points(identity: String,vertices: Array,old_points: Array,moved_points: Array) -> bool:
	var target:=road_at_id(identity)
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)==identity:road.points=vertices
		elif not target.get("independentEnds",false) and not road.get("independentEnds",false) and _same_network(target,road):
			# Keep attached branch endpoints on their authored junction anchors.
			for index in [0,road.points.size()-1]:
				for i in old_points.size():
					if RoadShapes.point(road.points[index]).distance_to(RoadShapes.point(old_points[i]))<.05:
						road.points[index]=moved_points[i].duplicate();break
	if not _valid_source(next):
		last_error="The shape would leave the map or put road points less than 1 metre apart. Use a smaller change.";return false
	return _commit(next)

func resize_circle_road(identity: String,radius: float) -> bool:
	var road:=road_at_id(identity)
	var shape:=RoadShapes.circle(road.get("points",[]))
	if shape.is_empty():last_error="Select a circular road to change its radius.";return false
	if not is_finite(radius) or radius<8 or radius<=float(road.width)*.5+2:
		last_error="Increase the radius so the roundabout has an open center.";return false
	var vertices: Array=[]
	for raw in road.points:
		var p: Vector2=Vector2(shape.center)+(RoadShapes.point(raw)-Vector2(shape.center)).normalized()*radius
		vertices.append({"x":p.x,"y":p.y})
	return _replace_road_points(identity,vertices,road.points,vertices)

func bend_road(identity: String,bend_m: float) -> bool:
	var road:=road_at_id(identity)
	if road.is_empty():last_error="Select a road to curve.";return false
	var anchors: Array=road.points
	var a:=RoadShapes.point(anchors[0]);var b:=RoadShapes.point(anchors[-1])
	var chord:=a.distance_to(b)
	if chord<2 or not is_finite(bend_m):last_error="Closed roads use the radius tool. Select an open road to curve.";return false
	var left:=Vector2((b-a).y,-(b-a).x).normalized()
	var stations: Array[float]=[0.0]
	for i in range(1,anchors.size()):stations.append(stations[-1]+RoadShapes.point(anchors[i-1]).distance_to(RoadShapes.point(anchors[i])))
	var knots: Array[float]=[]
	for station in stations:knots.append(station/stations[-1])
	if anchors.size()<17:
		for i in range(1,16):
			var t:=i/16.0;var too_close:=false
			for old in knots:
				if absf(t-old)*chord<1.1:too_close=true;break
			if not too_close:knots.append(t)
	knots.sort()
	var vertices: Array=[];var moved: Array=[]
	for t in knots:
		var p:=a.lerp(b,t)+left*(4*bend_m*t*(1-t))
		vertices.append({"x":p.x,"y":p.y})
	for t in stations:
		var fraction:=t/stations[-1]
		var p:=a.lerp(b,fraction)+left*(4*bend_m*fraction*(1-fraction))
		moved.append({"x":p.x,"y":p.y})
	return _replace_road_points(identity,vertices,anchors,moved)

func road_preview_source(drag: Dictionary) -> Dictionary:
	if drag.get("kind","") not in ["road","road_move","region","race_point","sidewalk_point","sidewalk_move"]:return doc
	# Use the same endpoint propagation as the committed edit, without adding
	# history or changing the real source while the mouse is held down.
	var temporary=get_script().new()
	temporary.doc=doc
	if drag.kind=="road":temporary.move_road_point(str(drag.id),int(drag.index),Vector2(drag.to)/20.0,0.0)
	elif drag.kind=="region":temporary.move_shape("regions",str(drag.id),(Vector2(drag.to)-Vector2(drag.from))/20.0)
	elif drag.kind=="race_point":temporary.move_race_point(str(drag.id),int(drag.index),Vector2(drag.to)/20.0)
	elif drag.kind=="sidewalk_point":
		temporary.move_sidewalk_point(str(drag.id),int(drag.index),Vector2(drag.to)/20.0,0.0,
			not bool(drag.get("detach",false)))
	elif drag.kind=="sidewalk_move":
		temporary.move_prop(str(drag.id),Vector2(drag.to)/20.0,0.0)
	else:temporary.move_shape("roads",str(drag.id),(Vector2(drag.to)-Vector2(drag.from))/20.0)
	return temporary.doc

func insert_road_point(identity: String, position_m: Vector2) -> bool:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		if road.points.size()>=100:return false
		var nearest:=INF
		var at:=1
		for i in range(1,road.points.size()):
			var a:=Vector2(road.points[i-1].x,road.points[i-1].y)
			var b:=Vector2(road.points[i].x,road.points[i].y)
			var distance:=Geometry2D.get_closest_point_to_segment(position_m,a,b).distance_to(position_m)
			if distance<nearest:nearest=distance;at=i
		road.points.insert(at,{"x":position_m.x,"y":position_m.y})
		return _commit(next)
	return false

func set_road_settings(identity: String, settings: Dictionary) -> bool:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		for key in ["roadClass","surface","width","lanes"]:
			if settings.has(key):road[key]=settings[key]
		return _commit(next)
	return false

func delete_entity(identity: String) -> bool:
	if not prop_at_id(identity).is_empty():return delete_prop(identity)
	for category in ["roads","regions","markers","races"]:
		for item in ([] if doc.get("customMap",false) or category=="races" else initial.get(category,[])):
			if str(item.id)==identity:
				last_error="Original roads, terrain and gameplay markers are protected. Move or reshape them instead."
				return false
		for index in doc.get(category,[]).size():
			if str(doc[category][index].id)!=identity:continue
			var next:=doc.duplicate(true)
			next[category].remove_at(index)
			# Roads are numbered consecutively for the production importer.
			if category=="roads":
				for i in next.roads.size():next.roads[i].id="road-%d"%i
			return _commit(next)
	return false

func add_region(points_m: Array[Vector2], biome: String = "grass",barrier: bool=false,elevation_m: float=0) -> String:
	var clean: Array[Vector2]=[]
	for p in points_m:
		if clean.is_empty() or clean[-1].distance_to(p)>.05:clean.append(p)
	if clean.size()>2 and clean[0].distance_to(clean[-1])<.05:clean.pop_back()
	points_m=clean
	if points_m.size()<3 or biome not in ["grass","forest","city","beach",
			"rock","mountain","lake","desert","farmland","ocean"]:
		last_error = "Terrain needs three points and a supported biome."
		return ""
	for p in points_m:
		if not _in_bounds(p):
			last_error = "Terrain point outside the map."
			return ""
	if points_m.size()>180:
		last_error="Terrain supports at most 180 vertices."
		return ""
	var packed:=PackedVector2Array(points_m)
	if Geometry2D.triangulate_polygon(packed).is_empty():
		last_error="Terrain needs a simple, non-crossing polygon with real area."
		return ""
	var id := next_id("regions","region")
	var vertices: Array[Dictionary] = []
	for p in points_m:
		vertices.append({"x":p.x,"y":p.y})
	var draft: Dictionary = doc.duplicate(true)
	draft.regions.append({"id":id,"name":"Editor terrain",
		"biome":biome,"points":vertices,"elevation":elevation_m})
	if barrier:
		draft.regions[-1]["barrier"]=true;draft.regions[-1].name="Mountain barrier"
	return id if _commit(draft) else ""


func add_marker(position_m: Vector2, marker_kind: String = "checkpoint") -> String:
	if not _in_bounds(position_m) or marker_kind not in [
			"traffic_spawn","race_start","checkpoint","finish"]:
		last_error = "Unsupported game marker or position."
		return ""
	var id := next_id("markers","marker")
	var draft: Dictionary = doc.duplicate(true)
	draft.markers.append({"id":id,"name":marker_kind.capitalize(),
		"type":marker_kind,"x":position_m.x,"y":position_m.y,
		"rotation":0.0,"properties":{}})
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

func edit_entity(identity: String, values: Dictionary, destination: Vector2, point_index: int=-1) -> bool:
	# Compose the inspector's fields and connected-end movement into one undo step.
	var temporary=get_script().new();temporary.doc=doc
	var category: String=""
	var item: Dictionary={}
	for collection in ["roads","regions","props","markers","races"]:
		for candidate in doc.get(collection,[]):
			if str(candidate.id)==identity:category=collection;item=candidate;break
		if not item.is_empty():break
	if item.is_empty():return false
	var center:=Vector2.ZERO
	if item.has("points"):
		for p in item.points:center+=Vector2(p.x,p.y)
		center/=item.points.size()
		if category=="roads":
			var circle:=RoadShapes.circle(item.points)
			if not circle.is_empty():center=circle.center
	else:center=Vector2(item.x,item.y)
	var ok:=false
	if category=="props":
		if str(item.get("type",""))=="sidewalk" and point_index>=0:
			ok=temporary.move_sidewalk_point(identity,point_index,destination)
		else:ok=temporary.move_prop(identity,destination,0)
	elif category=="roads" and point_index>=0:ok=temporary.move_road_point(identity,point_index,destination,0)
	elif category=="races" and point_index>=0:ok=temporary.move_race_point(identity,point_index,destination)
	else:ok=temporary.move_shape(category,identity,destination-center,0)
	if not ok:last_error=temporary.last_error;return false
	var next: Dictionary=temporary.doc.duplicate(true)
	for target in next[category]:
		if str(target.id)!=identity:continue
		if values.has("name"):target.name=str(values.name).strip_edges().left(120)
		if category=="props":
			if values.has("rotation"):target.rotation=float(values.rotation)
			if values.has("roadFacing"):target["roadFacing"]=bool(values.roadFacing)
			if values.has("roadFront"):target["roadFront"]=int(values.roadFront)
			if values.has("scale"):target.scale=clampf(float(values.scale),.2,5.0)
			for axis in ["scaleX","scaleY"]:
				if values.has(axis):target[axis]=clampf(float(values[axis]),.2,5.0)
		if category=="regions" and values.has("biome"):target.biome=str(values.biome)
		if category=="regions":
			if values.has("elevation"):target.elevation=clampf(float(values.elevation),0,2000)
			if values.has("barrier"):
				if bool(values.barrier) and str(target.biome) in ["mountain","rock"]:target["barrier"]=true
				else:target.erase("barrier")
		break
	return _commit(next)

func duplicate_entity(identity: String) -> String:
	for category in ["roads","regions","props","markers","races"]:
		for item in doc.get(category,[]):
			if str(item.id)!=identity or bool(item.get("hidden",false)):continue
			if category=="markers" and str(item.get("type","")) not in ["checkpoint","race_start","finish","traffic_spawn"]:
				last_error="This gameplay marker cannot be duplicated.";return ""
			var copy: Dictionary=item.duplicate(true)
			var prefix: String={"roads":"road","regions":"region","props":"prop","markers":"marker","races":"race"}[category]
			var id:=next_id(category,prefix)
			copy.id=id;copy.name=str(item.get("name",prefix))+" copy"
			copy.erase("replaces");copy.erase("hidden")
			if copy.has("points"):
				for p in copy.points:p.x=float(p.x)+12;p.y=float(p.y)+12
			else:copy.x=float(copy.x)+12;copy.y=float(copy.y)+12
			var next:=doc.duplicate(true);next[category].append(copy)
			return id if _commit(next) else ""
	return ""

func remove_road_point(identity: String,index: int) -> bool:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		if index<0 or index>=road.points.size() or road.points.size()<=2:
			last_error="A road needs two points. Add a point before removing one.";return false
		road.points.remove_at(index);return _commit(next)
	return false

func split_road(identity: String,index: int) -> String:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		if index==0 or index==road.points.size()-1:
			road["independentEnds"]=true
			return identity if _commit(next) else ""
		if road.points.size()==2:
			var a: Dictionary=road.points[0];var b: Dictionary=road.points[1]
			road.points.insert(1,{"x":(float(a.x)+float(b.x))*.5,"y":(float(a.y)+float(b.y))*.5});index=1
		if index<=0 or index>=road.points.size()-1:index=road.points.size()/2
		var second: Dictionary=road.duplicate(true)
		var id:=next_id("roads","road")
		second.id=id;second.name=str(road.name)+" (2)"
		second["independentEnds"]=true;road["independentEnds"]=true
		second.points=road.points.slice(index)
		road.points=road.points.slice(0,index+1)
		next.roads.append(second)
		return id if _commit(next) else ""
	return ""

func reconnect_endpoint(identity: String,index: int,radius: float=12.0) -> bool:
	var target:=road_at_id(identity)
	if target.is_empty() or index not in [0,target.points.size()-1]:
		last_error="Select the first or last road point to reconnect.";return false
	var at:=Vector2(target.points[index].x,target.points[index].y)
	var best:=radius+.001
	var candidates: Array[Dictionary]=[]
	for road in doc.roads:
		if str(road.id)==identity or not _same_network(target,road):continue
		for end in [0,road.points.size()-1]:
			var p:=Vector2(road.points[end].x,road.points[end].y)
			var distance:=at.distance_to(p)
			if distance>radius:continue
			if distance<best-.05:best=distance;candidates.clear()
			if absf(distance-best)<=.05:candidates.append({"id":str(road.id),"p":p})
	if candidates.is_empty():
		return connect_road_interior(identity,index,at,radius)
	var destination: Vector2=candidates[0].p
	for candidate in candidates:
		if destination.distance_to(candidate.p)>.05:
			last_error="Two different endpoints are equally close. Move nearer the intended one.";return false
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)==identity:
			road.points[index]={"x":destination.x,"y":destination.y};road.erase("independentEnds")
		for candidate in candidates:
			if str(road.id)==candidate.id:road.erase("independentEnds")
	return _commit(next)

func connect_road_interior(identity: String,index: int,at: Vector2,radius: float=12.0) -> bool:
	var target:=road_at_id(identity)
	var best:=radius;var hit: Dictionary={}
	for road in doc.roads:
		if str(road.id)==identity or not _same_network(target,road):continue
		var path:=road_path(road)
		var circle:=RoadShapes.circle(road.points)
		if not circle.is_empty():
			var p:=RoadShapes.closest_on_circle(circle,at)
			if at.distance_to(p)<best:
				var angle: float=(p-Vector2(circle.center)).angle()
				var phase: float=(RoadShapes.point(road.points[0])-Vector2(circle.center)).angle()
				var station:=fposmod(float(circle.direction)*(angle-phase),TAU)
				var insert_at: int=road.points.size()-1
				for i in range(1,road.points.size()-1):
					var next_angle: float=(RoadShapes.point(road.points[i])-Vector2(circle.center)).angle()
					if fposmod(float(circle.direction)*(next_angle-phase),TAU)>station:insert_at=i;break
				best=at.distance_to(p);hit={"id":str(road.id),"p":p,"span":insert_at}
			continue
		var span:=1
		var boundary:=clampi(ceili(Vector2(road.points[0].x,road.points[0].y).distance_to(Vector2(road.points[1].x,road.points[1].y))/6.0),2,160)
		for i in range(1,path.size()):
			while i>boundary and span<road.points.size()-1:
				span+=1
				boundary+=clampi(ceili(Vector2(road.points[span-1].x,road.points[span-1].y).distance_to(Vector2(road.points[span].x,road.points[span].y))/6.0),2,160)
			var p:=Geometry2D.get_closest_point_to_segment(at,path[i-1],path[i])
			var distance:=at.distance_to(p)
			if distance<best:best=distance;hit={"id":str(road.id),"p":p,"span":span}
	if hit.is_empty():last_error="No compatible road within reach. Move the endpoint closer to a road.";return false
	var destination: Vector2=hit.p
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)==str(hit.id):
			var anchor:=-1
			for i in road.points.size():
				var p:=Vector2(road.points[i].x,road.points[i].y)
				if p.distance_to(destination)<.5:anchor=i;destination=p;break
			if anchor<0:
				if road.points.size()>=100:last_error="Target road has reached its control-point limit.";return false
				road.points.insert(int(hit.span),{"x":destination.x,"y":destination.y})
			road.erase("independentEnds")
	for road in next.roads:
		if str(road.id)==identity:road.points[index]={"x":destination.x,"y":destination.y};road.erase("independentEnds")
	return _commit(next)
