extends RefCounted
## Source-safe, undoable authoring draft. This never mutates a live Morrow Coast
## Dictionary. Runtime streets, intersections and traffic remain authoritative
## until the checked-in production builder has completed an Apply operation.
const RoadJump=preload("res://scripts/world/road_jump.gd")
const HeightField=preload("res://scripts/world/authored_height_field.gd")
const Workspace=preload("res://scripts/dev/native_editor_workspace.gd")
const Elevation=preload("res://scripts/world/road_elevation.gd")
const GameplayControls=preload("res://scripts/world/authored_gameplay_controls.gd")
const SOURCE := "res://map-editor/maps/morrow-coast.edits.world.json"
const MAX_HISTORY := 100
const HISTORY_BUDGET_BYTES := 32*1024*1024
const RaceDefinition=preload("res://scripts/world/authored_race_definition.gd")
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
const MarkerRules=preload("res://scripts/world/authored_marker_rules.gd")
const RaceGrid=preload("res://scripts/world/race_start_grid.gd")
const RoadShapes=preload("res://scripts/dev/road_shape_geometry.gd")
const Sidewalks=preload("res://scripts/dev/sidewalk_topology.gd")
const AutoRails=preload("res://scripts/dev/road_auto_guardrails.gd")
const DealershipConfig=preload("res://scripts/world/dealership_config.gd")
const MAX_ROADS := 180
const MAX_PROPS := 4000
const CUSTOM_MAX_ROADS := 360
const CUSTOM_MAX_PROPS := 8000
const MAX_DRAG_M := 350.0
const ART: Dictionary = {
	"stunt_ramp":{"type":"stunt_ramp","assetId":"","size":Vector2(5,8)},
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
# Editor-only guard; never persisted in map files.
var unlocked_road_layer:=99

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
	if not GameplayControls.valid(value):return false
	if value.has("editorLayers") and (not value.get("customMap",false) or not Workspace.valid_layers(value.editorLayers)):return false
	if value.has("terrainHeight") and not HeightField.valid(value.terrainHeight):return false
	var rain: Variant = value.get("rain_intensity",0.0)
	if not (rain is int or rain is float) or not is_finite(float(rain)) or \
			float(rain)<0.0 or float(rain)>1.0:
		return false
	var width: float = float(world.get("width",0))
	var height: float = float(world.get("height",0))
	if value.get("customMap",false):
		if str(value.get("name","")).strip_edges().is_empty() or world.get("base","grass") not in ["grass","forest","beach","desert","ocean","city","rock","mountain","lake","farmland","dirt","asphalt"]:return false
		if not is_finite(width) or not is_finite(height) or width!=floorf(width) or height!=floorf(height):return false
	if (width < 600 or width > 24000 or height < 600 or height > 24000) if value.get("customMap",false) else (width < 6400 or width > 9600 or height < 4800 or height > 7200):
		return false
	for category in ["roads","regions","props","markers","assets"]:
		if not value.get(category) is Array:
			return false
	if value.roads.size() > road_limit(value) or value.props.size() > prop_limit(value) or value.regions.size()>220 or value.markers.size()>400:
		return false
	var used := {}
	if not value.get("races",[]) is Array or value.get("races",[]).size()>64 or not EventRules.valid_graph(value.get("races",[])):return false
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
		for key in ["junctionStart","junctionEnd"]:
			if str(road.get(key,"auto")) not in ["auto","intersection","merge"]:return false
		for i in range(1,road.points.size()):
			if Vector2(road.points[i].x,road.points[i].y).distance_to(Vector2(road.points[i-1].x,road.points[i-1].y))<1.0:return false
		if not Elevation.authoring_error(road).is_empty() or not AutoRails.valid(road):return false
		if str(road.get("roadClass",""))=="onramp" and (int(road.get("lanes",1)) not in [1,2] or str(road.get("surface","")) not in ["asphalt","concrete"]):return false
		if road.has("jump") and RoadJump.authoring_preview(road).is_empty():return false
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
	var dealers: Variant = value.get("dealerships", [])
	if not dealers is Array or dealers.size() > DealershipConfig.MAX_SHOPS:
		return false
	for dealer in dealers:
		if not dealer is Dictionary:
			return false
		var id := str(dealer.get("id", ""))
		if id.is_empty() or used.has("dealer:" + id) or id.length() > 80:
			return false
		used["dealer:" + id] = true
		if dealer.has("x") != dealer.has("y"):
			return false
		if dealer.has("x") and not _in_bounds(Vector2(float(dealer.x),float(dealer.y)),value):
			return false
		if dealer.has("lot_width_m") and (float(dealer.lot_width_m)<18.0 or float(dealer.lot_width_m)>70.0):
			return false
		if dealer.has("lot_depth_m") and (float(dealer.lot_depth_m)<14.0 or float(dealer.lot_depth_m)>60.0):
			return false
		if dealer.has("inventory_mode") and str(dealer.inventory_mode) not in ["automatic","manual"]:
			return false
		if dealer.has("inventory"):
			if not dealer.inventory is Array or dealer.inventory.size()>1000:
				return false
			var inventory_seen: Dictionary = {}
			for vehicle_id in dealer.inventory:
				if not vehicle_id is String or vehicle_id.is_empty() or vehicle_id.length()>100 or inventory_seen.has(vehicle_id):
					return false
				inventory_seen[vehicle_id]=true
		if id.begins_with("custom-dealer-"):
			if str(dealer.get("name","")).strip_edges().is_empty() or \
					str(dealer.get("texture","")).find("res://assets/Map Building Assets/Buildings/Dealerships/")!=0:
				return false
	if not MarkerRules.valid_links(value.markers,value.get("races",[]),value.get("dealerships",[])):return false
	for prop in value.props:
		if not prop is Dictionary or used.has(str(prop.get("id",""))):
			return false
		if prop.has("roadFacing") and not prop.roadFacing is bool:return false
		if prop.has("roadFront") and prop.roadFront not in [0,90,180,270]:return false
		used[str(prop.id)] = true
		if not _in_bounds(Vector2(float(prop.get("x",-1)),
				float(prop.get("y",-1))),value):
			return false
		var path_kind:=str(prop.get("type",""))
		if path_kind in ["sidewalk","guardrail"]:
			var path: Array[Vector2]=Sidewalks.world_points(prop)
			var path_width:=float(prop.get("guardrailWidth",0)) if path_kind=="guardrail" else float(prop.get("sidewalkWidth",0))
			if path_kind=="sidewalk":
				if not Sidewalks.valid_points(path,path_width,
						Rect2(Vector2.ZERO,Vector2(width,height))):return false
			else:
				if path.size()<2 or path.size()>100 or path_width<.35 or path_width>2.5:return false
				for i in path.size():
					if not _in_bounds(path[i],value) or (i>0 and path[i].distance_to(path[i-1])<.5):
						return false
	return true


## Curated shops are virtual until edited. Keeping default locations out of
## the source means a stock change cannot accidentally move a legacy shop.
func dealership_list() -> Array[Dictionary]:
	if doc.get("customMap",false):
		var shops: Array[Dictionary]=[]
		for dealer in doc.get("dealerships",[]):shops.append(dealer.duplicate(true))
		return shops
	return DealershipConfig.combined(doc)

func dealership_at_id(identity: String) -> Dictionary:
	for dealer in dealership_list():
		if str(dealer.get("id", "")) == identity:
			return dealer
	return {}

func update_dealership(identity: String, fields: Dictionary) -> bool:
	if dealership_at_id(identity).is_empty():
		last_error = "Unknown dealership."
		return false
	var next: Dictionary = doc.duplicate(true)
	if not next.has("dealerships"):
		next["dealerships"] = []
	var target: Dictionary = {}
	for dealer in next.dealerships:
		if str(dealer.id)==identity:
			target=dealer
			break
	if target.is_empty():
		target={"id":identity}
		next.dealerships.append(target)
	for field in fields:
		if field not in ["name","tier","region","texture","x","y","lot_width_m","lot_depth_m","inventory_mode","inventory"]:
			last_error = "Unsupported dealership property."
			return false
		target[field]=fields[field]
	return _commit(next)

func add_dealership(position_m: Vector2) -> String:
	if not _in_bounds(position_m):
		last_error = "Dealership placement is outside the map."
		return ""
	var next: Dictionary = doc.duplicate(true)
	if not next.has("dealerships"):
		next["dealerships"]=[]
	if dealership_list().size()>=DealershipConfig.MAX_SHOPS:
		last_error = "The map has reached its dealership limit."
		return ""
	var number:=1
	while not dealership_at_id("custom-dealer-%d"%number).is_empty():
		number+=1
	var id: String="custom-dealer-%d"%number
	var template: Dictionary=DealershipConfig.defaults()[3]
	next.dealerships.append({"id":id,"name":"New dealership %d"%number,
		"tier":"CUSTOM SHOWROOM","region":"Custom location",
		"texture":str(template.texture),"x":position_m.x,"y":position_m.y,
		"lot_width_m":32.0,"lot_depth_m":20.0,
		"inventory_mode":"manual","inventory":[]})
	return id if _commit(next) else ""

func delete_dealership(identity: String) -> bool:
	var next: Dictionary=doc.duplicate(true)
	for index in next.get("dealerships",[]).size():
		if str(next.dealerships[index].id)!=identity:
			continue
		next.dealerships.remove_at(index)
		return _commit(next)
	last_error="No saved overrides to remove."
	return false

func road_limit(source: Dictionary = {}) -> int:
	var target: Dictionary=doc if source.is_empty() else source
	return CUSTOM_MAX_ROADS if target.get("customMap",false) else MAX_ROADS

func prop_limit(source: Dictionary = {}) -> int:
	var target: Dictionary=doc if source.is_empty() else source
	return CUSTOM_MAX_PROPS if target.get("customMap",false) else MAX_PROPS

func _in_bounds(p: Vector2, source: Dictionary = {}) -> bool:
	var record: Dictionary = source if not source.is_empty() else doc
	if record.is_empty():
		return false
	return is_finite(p.x) and is_finite(p.y) and \
		p.x >= 0 and p.y >= 0 and \
		p.x <= float(record.world.width) and p.y <= float(record.world.height)

static func road_touches_layer(road: Dictionary,layer: int) -> bool:
	if layer==99:return true
	var profile: Dictionary=road.get("elevation",{})
	return layer in profile.get("point_layers",[int(profile.get("start_layer",0)),int(profile.get("end_layer",0))])

func _locked_roads_unchanged(next: Dictionary) -> bool:
	if not Workspace.locks_unchanged(doc,next):
		last_error="Edit would modify an object in a locked named layer.";return false
	if unlocked_road_layer==99:return true
	var after: Dictionary={}
	for road in next.get("roads",[]):after[str(road.id)]=road
	for road in doc.get("roads",[]):
		if not road_touches_layer(road,unlocked_road_layer) and after.get(str(road.id),{})!=road:
			last_error="Edit would change a locked road. Select all levels or unlock other roads first."
			return false
	return true

func _commit(next: Dictionary) -> bool:
	if not _locked_roads_unchanged(next):return false
	if not _valid_source(next):
		last_error = "Edit was rejected: invalid world bounds or source geometry."
		return false
	if next.has("editorLayers"):
		var live:=Workspace.records(next)
		for layer in next.editorLayers:
			layer.ids=layer.ids.filter(func(id: String)->bool:return live.has(id))
	if _fingerprint(doc) == _fingerprint(next):
		return true
	history.append(doc.duplicate(true))
	# Snapshots are deep copies. Estimate their cost from source size and
	# bound the retained history on dense maps rather than growing without limit.
	var estimated_bytes := maxi(1024,JSON.stringify(doc).to_utf8_buffer().size()*4)
	var limit := clampi(HISTORY_BUDGET_BYTES/estimated_bytes,2,MAX_HISTORY)
	while history.size()>limit:history.pop_front()
	doc = next
	edit_revision += 1
	future.clear()
	dirty = _fingerprint(doc) != draft_baseline_hash
	last_error = ""
	return true

func undo() -> bool:
	if history.is_empty() or not _locked_roads_unchanged(history[-1]):
		return false
	future.append(doc.duplicate(true))
	doc = history.pop_back()
	edit_revision += 1
	dirty = _fingerprint(doc) != draft_baseline_hash
	return true

func redo() -> bool:
	if future.is_empty() or not _locked_roads_unchanged(future[-1]):
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
				"roadClass":{"highway":"highway","rural":"country","mountain":"mountain","driveway":"service","track":"track","alley":"alley","onramp":"onramp"}.get(str(raw.kind),"city"),
				"surface":str(raw.surface).to_lower(),"width":float(raw.width)/float(data.get("road_width_scale",1))*float(doc.get("morrowRoadWidthScale",1)),
				"lanes":int(raw.lanes),"shoulder":0.0 if str(raw.kind)=="alley" else 2.0,"smooth":true,"markings":str(raw.kind)!="alley","points":points})
			if raw.has("elevation"):next.roads[-1].elevation=raw.elevation.duplicate()
			if raw.has("jump"):next.roads[-1].jump=raw.jump.duplicate()
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

static func shift_race_grid(race: Dictionary,delta: Vector2) -> void:
	if race.has("player_start") and race.player_start is Dictionary:
		race.player_start.x=float(race.player_start.x)+delta.x
		race.player_start.y=float(race.player_start.y)+delta.y
	for slot in race.get("enemy_starts",[]):
		slot.x=float(slot.x)+delta.x
		slot.y=float(slot.y)+delta.y

func save_race(points_m: Array[Vector2],settings: Dictionary,identity: String="") -> String:
	# Preserve unrelated editor configuration (enemy pool and rewards) when
	# someone adjusts the route, name, laps or grid in the compact sidebar.
	var prior: Dictionary=race_at_id(identity) if not identity.is_empty() else {}
	var race: Dictionary=prior.duplicate(true)
	race.merge(settings,true)
	var generated_layer: int=int(settings.get("objective_layer",0))
	race.erase("objective_layer")
	var generated_layers: Array=settings.get("objective_layers",[])
	race.erase("objective_layers")
	if not generated_layers.is_empty() and generated_layers.size()!=points_m.size():return ""
	race.id=next_id("races","race") if identity.is_empty() else identity
	race.points=[]
	for p in points_m:
		var point := {"x":p.x,"y":p.y}
		# Settings edits and unchanged gates preserve authored levels;
		# a fully redrawn route defaults newly placed gates to ground.
		for previous in prior.get("points",[]):
			if Vector2(previous.x,previous.y).distance_to(p)<.01 and int(previous.get("road_layer",0))!=0:
				point["road_layer"]=int(previous.road_layer)
				break
		if settings.has("objective_layer"):
			if generated_layer==0:point.erase("road_layer")
			else:point["road_layer"]=generated_layer
		if not generated_layers.is_empty():
			var layer:=int(generated_layers[race.points.size()])
			if absi(layer)>2:return ""
			if layer==0:point.erase("road_layer")
			else:point["road_layer"]=layer
		race.points.append(point)
	var default_count: int=prior.get("enemy_starts",[]).size()
	var count: int=int(race.get("opponent_count",default_count))
	var formation: String=str(race.get("formation",prior.get("formation","single_file")))
	race.erase("opponent_count")
	if settings.has("opponent_count") or prior.has("player_start"):
		if race.points.size()>=2 and count>=0 and count<=RaceGrid.MAX_RIVALS and formation in RaceGrid.FORMATIONS:
			race.merge(RaceGrid.layout(race.points,count,formation,prior),true)
	if not RaceDefinition.valid(race,float(doc.world.width),float(doc.world.height)):
		last_error="Check race checkpoints, grid spacing, starts inside the map and up to six AI rivals.";return ""
	var next:=doc.duplicate(true)
	if not next.has("races"):next["races"]=[]
	var replaced:=false
	for i in next.races.size():
		if str(next.races[i].id)==str(race.id):next.races[i]=race;replaced=true;break
	if not replaced:next.races.append(race)
	return str(race.id) if _commit(next) else ""

## Update the designated player's or rival's race-specific starting slot.
## Index -1 is the player; indices 0..5 are AI starting places.
func set_race_grid_slot(identity: String,index: int,position_m: Vector2,rotation_degrees: float=NAN) -> bool:
	var next: Dictionary=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		var previous: Dictionary=race.get("player_start",{})
		if previous.is_empty():
			previous=RaceGrid.default_player(race.points)
			race["player_start"]=previous
			if not race.has("enemy_starts"):race["enemy_starts"]=[]
		var target: Dictionary={}
		if index==-1:target=race.player_start
		elif index>=0 and index<race.get("enemy_starts",[]).size():target=race.enemy_starts[index]
		else:
			last_error="Choose a valid player or AI grid slot."
			return false
		target.x=position_m.x;target.y=position_m.y
		if is_finite(rotation_degrees):target.rotation=rotation_degrees
		if not RaceDefinition.valid(race,float(next.world.width),float(next.world.height)):
			last_error="Grid positions must fit the map and leave room between vehicles."
			return false
		return _commit(next)
	last_error="Race is no longer available."
	return false

func reset_race_grid(identity: String,formation: String) -> bool:
	var next: Dictionary=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		var count: int=race.get("enemy_starts",[]).size()
		var replacement: Dictionary=RaceGrid.layout(race.points,count,formation)
		race.merge(replacement,true)
		if not RaceDefinition.valid(race,float(next.world.width),float(next.world.height)):
			last_error="Grid would fall outside the map or overlap; choose another layout."
			return false
		return _commit(next)
	last_error="Select a race first."
	return false

func set_race_objective_layer(identity: String,index: int,layer: int) -> bool:
	if absi(layer)>2:return false
	var next:=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		if index<0 or index>=race.points.size():return false
		if layer==0:race.points[index].erase("road_layer")
		else:race.points[index]["road_layer"]=layer
		return _commit(next)
	return false

func move_race_point(identity: String,index: int,destination: Vector2) -> bool:
	var next:=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		if index<0 or index>=race.points.size():return false
		race.points[index].x=destination.x;race.points[index].y=destination.y;return _commit(next)
	return false

func change_race_points(identity: String,index: int,remove: bool) -> bool:
	var next:=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		index=clampi(index,0,race.points.size()-1)
		if remove:
			if index==0 or (race.mode=="sprint" and index==race.points.size()-1):
				last_error="Start and finish are fixed gates. Select an intermediate checkpoint to remove."
				return false
			if race.points.size()<=(3 if race.mode=="circuit" else 2):last_error="Keep the race's start, finish and required checkpoints.";return false
			race.points.remove_at(index)
		else:
			var a: Dictionary=race.points[mini(index,race.points.size()-2)];var b: Dictionary=race.points[mini(index+1,race.points.size()-1)]
			race.points.insert(mini(index+1,race.points.size()-1),{"x":(a.x+b.x)*.5,"y":(a.y+b.y)*.5})
		return _commit(next)
	return false

## Insert a gate at the exact map location. Preserve sprint finish as the last
## point; circuits can insert after the last checkpoint before looping home.
## Returns the new point index, or -1 on validation failure.
func insert_race_checkpoint(identity: String,point_m: Vector2,after_index: int=-1) -> int:
	if not point_m.is_finite():
		last_error="Choose a finite checkpoint location on the road."
		return -1
	var next: Dictionary=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		if race.points.size()>=100:
			last_error="A race can have at most 100 route points."
			return -1
		var last_slot: int=race.points.size()-1 if race.mode=="sprint" else race.points.size()
		var insert_at: int=clampi(after_index+1,1,last_slot) if after_index>=0 else last_slot
		race.points.insert(insert_at,{"x":point_m.x,"y":point_m.y})
		if not _commit(next):
			last_error="Checkpoint must be on the map and at least 5 m from adjacent gates."
			return -1
		return insert_at
	last_error="Select a saved race first."
	return -1

## Reorder gates without changing a sprint's start or finish. Circuits keep
## index zero as their start/finish line.
func reorder_race_checkpoint(identity: String,index: int,direction: int) -> bool:
	var next: Dictionary=doc.duplicate(true)
	for race in next.get("races",[]):
		if str(race.id)!=identity:continue
		var last_movable: int=race.points.size()-2 if race.mode=="sprint" else race.points.size()-1
		var target: int=index+direction
		if index<1 or index>last_movable or target<1 or target>last_movable or absi(direction)!=1:
			last_error="Only intermediate checkpoints can change order."
			return false
		var point: Dictionary=race.points[index]
		race.points[index]=race.points[target]
		race.points[target]=point
		return _commit(next)
	last_error="Select a saved race first."
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
			if not is_target and (not _same_network(target,road) or
					Elevation.endpoint_layer(target,point_index==0)!=Elevation.endpoint_layer(road,i==0)):
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
	for i in range(1,prop_limit()+1):
		var key := "prop-native-%d" % i
		if not used.has(key):
			return key
	return ""

func add_prop(art_kind: String, position_m: Vector2) -> String:
	if not ART.has(art_kind) or not _in_bounds(position_m) or doc.props.size() >= prop_limit():
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
			not _in_bounds(position_m) or doc.props.size() >= prop_limit() or \
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
			bool(runtime.get("protected",false)) or doc.props.size()>=prop_limit():
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

## Guardrails are independent, solid road-style polylines. They have no
## traffic network connection, junction merging or sidewalk auto-snap.
func add_guardrail(points_m: Array[Vector2],width_m: float=.65) -> String:
	if points_m.size()<2 or points_m.size()>100 or width_m<.35 or width_m>2.5:
		last_error="Guardrails need 2–100 points and width 0.35–2.5 m.";return ""
	var bounds:=Rect2(points_m[0],Vector2.ZERO)
	for i in points_m.size():
		if not _in_bounds(points_m[i]) or not points_m[i].is_finite() or \
				(i>0 and points_m[i].distance_to(points_m[i-1])<.5):
			last_error="Keep guardrail points inside the map, at least 0.5 m apart.";return ""
		bounds=bounds.expand(points_m[i])
	var center:=bounds.get_center()
	var points: Array=[]
	for p in points_m:points.append([p.x-center.x,p.y-center.y])
	var id:=_new_prop_id()
	var next:=doc.duplicate(true)
	next.props.append({"id":id,"name":"Guardrail","type":"guardrail","assetId":"",
		"x":center.x,"y":center.y,"rotation":0,"scale":1,
		"assetSize":[bounds.size.x+width_m,bounds.size.y+width_m],
		"guardrailWidth":width_m,"guardrailPoints":points})
	return id if _commit(next) else ""


func add_sidewalk(points_m: Array[Vector2],width_m: float=3.0) -> String:
	if points_m.size()<2 or points_m.size()>100 or width_m<.8 or width_m>12:
		last_error="Sidewalks need 2–100 points and width 0.8–12 m.";return ""
	var bounds:=Rect2(points_m[0],Vector2.ZERO)
	for i in points_m.size():
		if not _in_bounds(points_m[i]) or (i>0 and points_m[i].distance_to(points_m[i-1])<.5):
			last_error="Keep sidewalk points in the map and at least half a metre apart.";return ""
		bounds=bounds.expand(points_m[i])
	var center:=bounds.get_center();var points: Array=[]
	for p in points_m:points.append([p.x-center.x,p.y-center.y])
	var id:=_new_prop_id();var next:=doc.duplicate(true)
	next.props.append({"id":id,"name":"Sidewalk","type":"sidewalk","assetId":"",
		"x":center.x,"y":center.y,"rotation":0,"scale":1,
		"assetSize":[bounds.size.x+width_m,bounds.size.y+width_m],
		"sidewalkWidth":width_m,"sidewalkPoints":points})
	# One atomic edit: both path ends join existing trunks, and genuine
	# crossings receive shared anchors without deleting any branches.
	Sidewalks.connect_tips(next.props,id)
	Sidewalks.connect_crossings(next.props,id)
	return id if _commit(next) else ""


func move_sidewalk_point(identity: String, index: int, target_m: Vector2,
		snap_radius_m: float = Sidewalks.SNAP_RADIUS_M,
		preserve_joint: bool = true) -> bool:
	var current: Dictionary=prop_at_id(identity)
	var path_kind:=str(current.get("type",""))
	if path_kind not in ["sidewalk","guardrail"]:
		last_error="Select a path control point.";return false
	if path_kind=="guardrail":
		preserve_joint=false
	var before: Array[Vector2]=Sidewalks.world_points(current)
	if index<0 or index>=before.size() or not _in_bounds(target_m):
		last_error="Sidewalk points must remain inside the map.";return false
	var next:=doc.duplicate(true)
	var proposed:=target_m
	if preserve_joint and path_kind=="sidewalk" and index in [0,before.size()-1]:
		var snap_to: Dictionary=Sidewalks.snap(next.props,target_m,snap_radius_m,identity)
		if not snap_to.is_empty():
			proposed=snap_to.point
			# Create an explicit vertex on the receiving trunk, like road
			# T junctions; do not merge away either independently editable path.
			if int(snap_to.vertex)<0:
				for other in next.props:
					if str(other.get("id",""))==str(snap_to.id):
						if not Sidewalks._insert_on_segment(other,proposed,int(snap_to.segment)):
							last_error="Sidewalk has reached its 100-point limit.";return false
						break
	if not Sidewalks.move_anchor(next.props,identity,index,proposed,preserve_joint):
		last_error="Sidewalk junction would become too short or invalid.";return false
	if not _commit(next):
		last_error="Unable to move sidewalk anchor inside the map.";return false
	return true


func move_prop(prop_id: String, destination_m: Vector2, grid_m: float = 1.0,
		preserve_joint: bool = true) -> bool:
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
			if str(prop.get("type","")) in ["sidewalk","guardrail"]:
				var previous: Array[Vector2]=Sidewalks.world_points(prop)
				var shift:=destination_m-original
				var moved: Array[Vector2]=[]
				for p in previous:moved.append(p+shift)
				Sidewalks.write_world_points(prop,moved)
				if preserve_joint and str(prop.get("type",""))=="sidewalk":
					for other in draft.props:
						if str(other.id)==prop_id or str(other.get("type",""))!="sidewalk" or bool(other.get("hidden",false)):
							continue
						var neighbor: Array[Vector2]=Sidewalks.world_points(other)
						var attached:=false
						for i in neighbor.size():
							for old_point in previous:
								if neighbor[i].distance_to(old_point)<.05:
									neighbor[i]+=shift
									attached=true
									break
						if attached:Sidewalks.write_world_points(other,neighbor)
			else:
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
	return add_road_path([first,last])

func next_id(category: String, prefix: String) -> String:
	var number := 0
	for item in doc.get(category,[]):
		var text:=str(item.get("id",""))
		if text.begins_with(prefix+"-") and text.trim_prefix(prefix+"-").is_valid_int():
			number=maxi(number,int(text.trim_prefix(prefix+"-"))+1)
	return prefix+"-"+str(number)

func add_road_path(points_m: Array[Vector2], settings: Dictionary={}) -> String:
	if points_m.size()<2 or points_m.size()>100 or doc.roads.size()>=road_limit():
		last_error="Roads need 2–100 control points; this map supports %d roads."%road_limit()
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
	if road.roadClass=="onramp":
		road.name="On-ramp / off-ramp"
		road.lanes=clampi(int(settings.get("lanes",1)),1,2)
		road.surface="asphalt"
		road.markings=true
	if road.roadClass=="alley":
		road.name="Alleyway"
		road.shoulder=0.0
		road.markings=false
		if not settings.has("width"):road.width=6.0
		if not settings.has("lanes"):road.lanes=1
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
		var end_layers: Array[int]=[]
		if category=="roads" and not bool(target.get("independentEnds",false)):
			ends=[Vector2(target.points[0].x,target.points[0].y),Vector2(target.points[-1].x,target.points[-1].y)]
			end_layers=[Elevation.endpoint_layer(target,true),Elevation.endpoint_layer(target,false)]
			if not RoadShapes.circle(target.points).is_empty():
				ends.clear()
				end_layers.clear()
				for p in target.points:
					ends.append(RoadShapes.point(p))
					end_layers.append(Elevation.endpoint_layer(target,true))
		for point in target.points:
			point.x=float(point.x)+delta.x;point.y=float(point.y)+delta.y
		if category=="races":shift_race_grid(target,delta)
		if category=="roads":
			for road in next.roads:
				if str(road.id)==identity or not _same_network(target,road) or bool(road.get("independentEnds",false)):continue
				for index in [0,road.points.size()-1]:
					var point: Dictionary=road.points[index]
					for i in ends.size():
						var layer := Elevation.endpoint_layer(road,index==0)
						if layer==end_layers[i] and Vector2(point.x,point.y).distance_to(ends[i])<.05:
							point.x=float(point.x)+delta.x;point.y=float(point.y)+delta.y;break
	return _commit(next)

## Resize a terrain region's stored vertices around its current footprint center.
## Width and height can be changed independently; source geometry stays editable.
func resize_region(identity: String, scale_x: float, scale_y: float) -> bool:
	if not is_finite(scale_x) or not is_finite(scale_y) or scale_x<=0.0 or scale_y<=0.0:
		last_error="Terrain resize factors must be positive, finite numbers."
		return false
	var next: Dictionary=doc.duplicate(true)
	for region in next.get("regions",[]):
		if str(region.get("id",""))!=identity:continue
		var points: Array=region.get("points",[])
		if points.size()<3:
			last_error="Terrain needs at least three vertices."
			return false
		var low:=Vector2(INF,INF)
		var high:=Vector2(-INF,-INF)
		for point in points:
			var position:=Vector2(float(point.x),float(point.y))
			low=low.min(position);high=high.max(position)
		var size: Vector2=(high-low)*Vector2(scale_x,scale_y)
		if size.x<2.0 or size.y<2.0:
			last_error="Terrain must remain at least 2 metres wide and tall."
			return false
		var center: Vector2=(low+high)*0.5
		var outline:=PackedVector2Array()
		for point in points:
			var before:=Vector2(float(point.x),float(point.y))
			var resized: Vector2=center+(before-center)*Vector2(scale_x,scale_y)
			if not _in_bounds(resized):
				last_error="Resized terrain would extend outside the map."
				return false
			point.x=resized.x;point.y=resized.y
			outline.append(resized)
		var twice_area:=0.0
		for i in outline.size():
			twice_area+=outline[i].cross(outline[(i+1)%outline.size()])
		if absf(twice_area)<50.0 or Geometry2D.triangulate_polygon(outline).is_empty():
			last_error="Terrain must retain a non-crossing area of at least 25 square metres."
			return false
		return _commit(next)
	last_error="Select an editable terrain region first."
	return false

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
					var layer := Elevation.endpoint_layer(target,i==0)
					var ramp := Elevation.endpoint_layer(target,true)!=Elevation.endpoint_layer(target,false)
					if (ramp and i not in [0,old_points.size()-1]) or layer!=Elevation.endpoint_layer(road,index==0):
						continue
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
	if drag.get("kind","") not in ["road","road_move","region","race_point"]:return doc
	# Use the same endpoint propagation as the committed edit, without adding
	# history or changing the real source while the mouse is held down.
	var temporary=get_script().new()
	temporary.doc=doc
	if drag.kind=="road":temporary.move_road_point(str(drag.id),int(drag.index),Vector2(drag.to)/20.0,0.0)
	elif drag.kind=="region":temporary.move_shape("regions",str(drag.id),(Vector2(drag.to)-Vector2(drag.from))/20.0)
	elif drag.kind=="race_point":temporary.move_race_point(str(drag.id),int(drag.index),Vector2(drag.to)/20.0)
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
		if road.get("elevation",{}).has("point_layers"):
			var values: Array=road.elevation.point_layers
			for layer in [values[at-1],values[at]]:
				var trial:=values.duplicate()
				trial.insert(at,layer)
				road.elevation={"start_layer":trial[0],"end_layer":trial[-1],"point_layers":trial}
				if Elevation.authoring_error(road).is_empty():return _commit(next)
			last_error="Inserted point would create a steep grade."
			return false
		return _commit(next)
	return false

## Keep the entire authored road in one undo transaction.
func apply_point_elevations(identity: String, layers: Array) -> bool:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		if layers.size()!=road.points.size() or layers.size()<2:return false
		if road.has("jump"):
			last_error="Remove the stunt jump before setting point heights."
			return false
		road.elevation={"start_layer":layers[0],"end_layer":layers[-1],"point_layers":layers.duplicate()}
		last_error=Elevation.authoring_error(road)
		if not last_error.is_empty():return false
		if layers.all(func(v: Variant)->bool:return int(v)==0):road.erase("elevation")
		return _commit(next)
	return false


func set_auto_guardrails(identity: String, settings: Dictionary) -> bool:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		if settings.is_empty():road.erase("autoGuardrails")
		else:road["autoGuardrails"]=settings.duplicate(true)
		if not AutoRails.valid(road):
			last_error="Choose a ground-level road and a start percentage smaller than the end.";return false
		return _commit(next)
	return false

func set_road_settings(identity: String, settings: Dictionary) -> bool:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		for key in ["roadClass","surface","width","lanes","junctionStart","junctionEnd"]:
			if settings.has(key):
				if key in ["junctionStart","junctionEnd"] and settings[key]=="auto":road.erase(key)
				else:road[key]=settings[key]
		if road.roadClass=="onramp":
			road.lanes=clampi(int(road.get("lanes",1)),1,2)
			road.surface="asphalt"
			road.markings=true
		if settings.has("elevation"):
			road.elevation=settings.elevation
			last_error=Elevation.authoring_error(road)
			if not last_error.is_empty():return false
			if Elevation.endpoint_layer(road,true)==0 and Elevation.endpoint_layer(road,false)==0:
				road.erase("elevation")
		if settings.has("jump"):
			if settings.jump == null:
				road.erase("jump")
			else:
				road.jump = settings.jump
		if road.has("jump") and RoadJump.authoring_preview(road).is_empty():
			last_error="Jump needs a straight ground road with room for the approach and landing at all allowed speeds."
			return false
		if road.roadClass=="alley":
			road.shoulder=0.0
			road.markings=false
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
			"rock","mountain","lake","desert","farmland","ocean","dirt","asphalt"]:
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
	if not _in_bounds(position_m) or marker_kind not in MarkerRules.TYPES:
		last_error = "Unsupported game marker or position."
		return ""
	var id := next_id("markers","marker")
	var draft: Dictionary = doc.duplicate(true)
	draft.markers.append({"id":id,"name":marker_kind.capitalize(),
		"type":marker_kind,"x":position_m.x,"y":position_m.y,
		"rotation":0.0,"properties":{}})
	return id if _commit(draft) else ""


func marker_at_id(identity: String) -> Dictionary:
	for marker in doc.get("markers",[]):
		if str(marker.get("id",""))==identity:return marker
	return {}

## A linked marker edits the physical shop's stock. An unlinked marker can
## run its own storefront, using the same catalog and purchase rules.
func set_marker_dealer_stock(identity: String,ids: Array) -> bool:
	var point:=marker_at_id(identity)
	if point.is_empty() or str(point.get("type",""))!="dealership" or not MarkerRules.valid_inventory(ids):
		last_error="Select a dealership point and valid vehicle IDs.";return false
	for id in ids:
		if DealershipConfig.CATALOG.find_by_id(str(id)).is_empty():
			last_error="Unknown playable vehicle: "+str(id);return false
	var properties: Dictionary=point.get("properties",{}).duplicate(true)
	var dealer_id:=str(properties.get("dealer_id",""))
	if not dealer_id.is_empty():
		return update_dealership(dealer_id,{"inventory_mode":"manual","inventory":ids.duplicate()})
	properties["dealer_inventory"]=ids.duplicate()
	return update_marker(identity,{"properties":properties})

func update_marker(identity: String,details: Dictionary) -> bool:
	var draft: Dictionary=doc.duplicate(true)
	for marker in draft.get("markers",[]):
		if str(marker.id)!=identity:continue
		for field in ["name","type","rotation","properties"]:
			if details.has(field):marker[field]=details[field]
		if _commit(draft):return true
		last_error="Invalid marker type, linked race/dealer, or duplicate player spawn."
		return false
	last_error="Select a placed game marker."
	return false

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
	if category=="props":ok=temporary.move_prop(identity,destination,0)
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

## Bulk edits are atomic and restricted to explicit fields. Mixed selections
## edit only the chosen category; incompatible values reject the whole edit.
func bulk_properties(ids: Array[String],category: String,patch: Dictionary) -> bool:
	if ids.is_empty() or patch.is_empty() or category not in ["roads","props","regions"]:return false
	var allowed: Array={"roads":["roadClass","surface","width","lanes","elevation","markings"],"props":["rotation","scale","scaleX","scaleY","roadFacing"],"regions":["biome","elevation","barrier"]}[category]
	for key in patch:
		if key not in allowed:
			last_error="Unsupported bulk property."
			return false
	var next:=doc.duplicate(true)
	var count:=0
	for entry in next[category]:
		if str(entry.id) not in ids or bool(entry.get("hidden",false)):continue
		count+=1
		for key in patch:entry[key]=patch[key]
		if category=="roads":
			if str(entry.roadClass) not in ["city","highway","country","mountain","service","track","alley","onramp"] or str(entry.surface) not in ["asphalt","concrete","gravel","dirt","track"] or float(entry.width)<6 or float(entry.width)>160 or int(entry.lanes)<1 or int(entry.lanes)>6:
				last_error="Invalid road type, surface, width or lanes."
				return false
			if entry.roadClass=="onramp":
				entry.lanes=clampi(int(entry.get("lanes",1)),1,2);entry.surface="asphalt";entry.markings=true
			if entry.roadClass=="alley":
				entry.shoulder=0.0;entry.markings=false
			if patch.has("elevation"):
				last_error=Elevation.authoring_error(entry)
				if not last_error.is_empty():return false
				if int(entry.elevation.start_layer)==0 and int(entry.elevation.end_layer)==0 and not entry.elevation.has("point_layers"):entry.erase("elevation")
		elif category=="props":
			if str(entry.get("type","")) in ["sidewalk","guardrail"] and (patch.has("scale") or patch.has("scaleX") or patch.has("scaleY") or patch.has("rotation")):
				last_error="Path scenery requires its dedicated geometry tools."
				return false
			for key in ["scale","scaleX","scaleY"]:
				if patch.has(key) and (not is_finite(float(patch[key])) or float(patch[key])<.2 or float(patch[key])>5.0):
					last_error="Asset scale must be between 0.2 and 5."
					return false
		elif category=="regions" and str(entry.get("biome","")) not in ["mountain","rock"]:
			entry.erase("barrier")
	if count==0:
		last_error="No selected objects match this category."
		return false
	return _commit(next)


func set_named_layers(layers: Array) -> bool:
	if not doc.get("customMap",false) or not Workspace.valid_layers(layers):return false
	var next:=doc.duplicate(true)
	next.editorLayers=layers.duplicate(true)
	return _commit(next)

func resize_custom_world(width: int,height: int) -> bool:
	var next:=Workspace.resize(doc,width,height)
	if next.is_empty():last_error="Invalid custom map size.";return false
	# Do not silently delete or clip roads, races, or linked gameplay entities.
	if not _valid_source(next):
		last_error="Resize would exclude existing geometry or gameplay markers. Move or delete them first.";return false
	return _commit(next)

func restore_snapshot(snapshot: Dictionary) -> bool:
	if bool(snapshot.get("customMap",false))!=bool(doc.get("customMap",false)):return false
	if not doc.get("customMap",false):
		if snapshot.get("name")!="Morrow Coast":return false
		var extent: Dictionary=snapshot.get("world",{})
		if int(extent.get("width",0))<int(initial.world.width) or int(extent.get("height",0))<int(initial.world.height):return false
		if snapshot.get("morrowSourceRoadCount",-1)!=doc.get("morrowSourceRoadCount",-2):return false
	return _commit(snapshot.duplicate(true))

func replace_assets(ids: Array[String],entry: Dictionary) -> bool:
	if ids.is_empty():return false
	var next:=doc.duplicate(true)
	var count:=0
	var kind:=str(entry.get("kind",""))
	for prop in next.props:
		if str(prop.id) not in ids:continue
		if prop.has("replaces") or str(prop.get("type","")) in ["sidewalk","guardrail"]:
			last_error="Select ordinary authored scenery, not adopted or path assets.";return false
		count+=1
		for key in ["assetPath","assetSize","assetRegion","assetCollision","roadFront","roadFacing"]:prop.erase(key)
		if bool(entry.get("project",false)):
			var path:=str(entry.get("path",""))
			if not (path.begins_with("Buildings/") or path.begins_with("Map Building Assets/")) or ".." in path or not FileAccess.file_exists("res://assets/"+path):
				last_error="Project asset not available.";return false
			var size: Array=entry.get("world_size",[])
			if size.size()!=2:size=[22.0,29.0] if kind in ["building","warehouse"] else [12.0,17.0]
			prop.type=kind;prop.assetId=str(entry.get("project_id","project-"+path.sha256_text().substr(0,24)))
			prop.assetPath=path;prop.assetSize=size.duplicate();prop.assetCollision=str(entry.get("collision","solid"))
			if entry.get("region",[]).size()==4:prop.assetRegion=entry.region.duplicate()
		else:
			if not ART.has(kind):last_error="Select a supported asset.";return false
			prop.type=ART[kind].type;prop.assetId=ART[kind].assetId
		prop.name=str(entry.get("name",kind))
	if count!=ids.size():last_error="Select only scenery objects for asset replacement.";return false
	return _commit(next)

## Height-field edits remain a single normal undo step.
func set_terrain_height(field: Dictionary) -> bool:
	if not HeightField.valid(field):
		last_error="Invalid custom terrain height field.";return false
	var next:=doc.duplicate(true)
	next.terrainHeight=field.duplicate(true)
	return _commit(next)

## Commit an externally generated, validated source plan in one history step.
func apply_construction(plan: Dictionary) -> Array[String]:
	var ids: Array[String]=[]
	if plan.has("error"):last_error=str(plan.error);return ids
	var roads: Array=plan.get("roads",[])
	var props: Array=plan.get("props",[])
	var regions: Array=plan.get("regions",[])
	var markers: Array=plan.get("markers",[])
	var dealers: Array=plan.get("dealerships",[])
	var field: Dictionary=plan.get("terrainHeight",{})
	if roads.is_empty() and props.is_empty() and regions.is_empty() and markers.is_empty() and field.is_empty():last_error="Nothing fits in the selected area.";return ids
	if doc.roads.size()+roads.size()>road_limit() or doc.props.size()+props.size()>prop_limit() or doc.regions.size()+regions.size()>220 or doc.markers.size()+markers.size()>400:
		last_error="Construction exceeds map capacity.";return ids
	if not roads.is_empty() and unlocked_road_layer not in [0,99]:
		last_error="Unlock ground roads before generating streets.";return ids
	var next:=doc.duplicate(true)
	for road in roads:
		next.roads.append(road.duplicate(true));ids.append(str(road.id))
	var number:=int(next_id("props","prop").trim_prefix("prop-"))
	for prop in props:
		var item: Dictionary=prop.duplicate(true)
		item.id="prop-%d"%number;number+=1
		next.props.append(item);ids.append(str(item.id))
	var region_number:=int(next_id("regions","region").trim_prefix("region-"))
	for region in regions:
		var item: Dictionary=region.duplicate(true)
		item.id="region-%d"%region_number;region_number+=1
		next.regions.append(item);ids.append(str(item.id))
	for marker in markers:
		next.markers.append(marker.duplicate(true));ids.append(str(marker.id))
	if not field.is_empty():next.terrainHeight=field.duplicate(true)
	if not dealers.is_empty():
		if not next.has("dealerships"):next.dealerships=[]
		for dealer in dealers:next.dealerships.append(dealer.duplicate(true))
	if not _commit(next):return []
	return ids

## Align or distribute ordinary scenery centres. Road and path geometry is
## not moved implicitly, protecting shared junctions and continuous rails.
func arrange_props(ids: Array[String],mode: String,axis: int) -> bool:
	if axis not in [0,1] or mode not in ["align","distribute"]:return false
	var next:=doc.duplicate(true)
	var selected: Array[Dictionary]=[]
	var key: String="x" if axis==0 else "y"
	for prop in next.props:
		if str(prop.id) not in ids or bool(prop.get("hidden",false)):continue
		if str(prop.get("type","")) in ["sidewalk","guardrail"]:
			last_error="Select ordinary scenery rather than path objects."
			return false
		selected.append(prop)
	if selected.size()!=ids.size() or selected.size()<(3 if mode=="distribute" else 2):
		last_error="Select at least %d ordinary scenery objects."%(3 if mode=="distribute" else 2)
		return false
	selected.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a[key])<float(b[key]))
	var first:=float(selected[0][key])
	var last:=float(selected[-1][key])
	var mean:=0.0
	for item in selected:mean+=float(item[key])
	mean/=selected.size()
	for i in selected.size():
		selected[i][key]=mean if mode=="align" else lerpf(first,last,float(i)/float(selected.size()-1))
	return _commit(next)

## Internal reusable clipboard, independent of the source map. Do not copy
## gameplay IDs or adopted-world replacement links across maps.
func copy_group(ids: Array[String]) -> Dictionary:
	var entries: Array[Dictionary]=[]
	var assets: Array=[]
	var total:=Vector2.ZERO
	var n:=0
	for category in ["roads","regions","props"]:
		for item in doc[category]:
			if str(item.id) not in ids or bool(item.get("hidden",false)):continue
			var copy: Dictionary=item.duplicate(true)
			copy.erase("replaces");copy.erase("hidden")
			entries.append({"category":category,"item":copy})
			if copy.has("points"):
				for p in copy.points:total+=Vector2(p.x,p.y);n+=1
			else:
				total+=Vector2(copy.x,copy.y);n+=1
			var asset_id:=str(copy.get("assetId",""))
			for asset in doc.get("assets",[]):
				if str(asset.get("id",""))==asset_id and not assets.has(asset):assets.append(asset.duplicate(true))
	if entries.is_empty() or entries.size()!=ids.size():
		last_error="Copy only editable roads, terrain regions and scenery; gameplay IDs must be authored separately."
		return {}
	return {"entries":entries,"assets":assets,"origin":total/maxi(1,n)}

func paste_group(group: Dictionary,at: Vector2) -> Array[String]:
	var ids: Array[String]=[]
	if group.is_empty() or not at.is_finite():return ids
	var next:=doc.duplicate(true)
	var delta: Vector2=at-Vector2(group.origin)
	for asset in group.get("assets",[]):
		var found:=false
		for existing in next.assets:
			if str(existing.id)!=str(asset.id):continue
			if existing!=asset:
				last_error="Clipboard asset ID conflicts with this map."
				return []
			found=true
		if not found:next.assets.append(asset.duplicate(true))
	var counters: Dictionary={}
	for category in ["roads","regions","props"]:
		var prefix: String={"roads":"road","regions":"region","props":"prop"}[category]
		counters[category]=int(next_id(category,prefix).trim_prefix(prefix+"-"))
	for record in group.entries:
		var category: String=record.category
		var target: Dictionary=record.item.duplicate(true)
		var prefix: String={"roads":"road","regions":"region","props":"prop"}[category]
		target.id=prefix+"-"+str(counters[category])
		counters[category]+=1
		target.name=(str(target.get("name",prefix))+" copy").left(120)
		if category=="props" and str(target.get("type","")) in ["sidewalk","guardrail"]:
			var moved: Array[Vector2]=[]
			for point in Sidewalks.world_points(target):moved.append(point+delta)
			Sidewalks.write_world_points(target,moved)
		elif target.has("points"):
			for p in target.points:p.x=float(p.x)+delta.x;p.y=float(p.y)+delta.y
		else:
			target.x=float(target.x)+delta.x;target.y=float(target.y)+delta.y
		next[category].append(target);ids.append(str(target.id))
	if not _commit(next):return []
	return ids


## Apply group edits as one validated source mutation and one undo step.
func batch_entities(ids: Array[String], delta: Vector2, operation: String) -> Array[String]:
	var result: Array[String]=[]
	if ids.is_empty() or not delta.is_finite() or operation not in ["move","duplicate","delete"]:
		last_error="Invalid group selection or operation."
		return result
	if operation=="move" and delta.length()>MAX_DRAG_M:
		last_error="Group movement is limited to 350 metres per edit."
		return result
	var chosen: Dictionary={}
	for id in ids:chosen[id]=true
	var next: Dictionary=doc.duplicate(true)
	var found: Dictionary={}
	for category in ["props","markers","regions","roads"]:
		for entity in next.get(category,[]):
			var id:=str(entity.get("id",""))
			if not chosen.has(id):continue
			if bool(entity.get("hidden",false)):
				last_error="Hidden objects cannot be edited."
				return []
			if operation=="duplicate" and category=="markers" and str(entity.get("type","")) not in ["checkpoint","race_start","finish","traffic_spawn"]:
				last_error="This gameplay marker cannot be duplicated."
				return []
			found[id]=true
	if found.size()!=chosen.size():
		last_error="Some selected objects no longer exist."
		return []
	for category in ["props","markers","regions","roads"]:
		var entries: Array=next[category]
		var additions: Array=[]
		var prefix: String={"props":"prop","markers":"marker","regions":"region","roads":"road"}[category]
		var counter:=0
		for entry in entries:
			var name:=str(entry.get("id",""))
			if name.begins_with(prefix+"-") and name.trim_prefix(prefix+"-").is_valid_int():
				counter=maxi(counter,int(name.trim_prefix(prefix+"-"))+1)
		for entry in entries:
			var id:=str(entry.get("id",""))
			if not chosen.has(id):continue
			if operation=="delete":
				if entry.has("replaces"):entry.hidden=true
				continue
			var target: Dictionary=entry
			if operation=="duplicate":
				target=entry.duplicate(true)
				target.id=prefix+"-"+str(counter)
				counter+=1
				target.name=str(entry.get("name",prefix))+" copy"
				target.erase("replaces")
				target.erase("hidden")
				additions.append(target)
				result.append(str(target.id))
			else:
				result.append(id)
			if category=="props" and str(target.get("type","")) in ["sidewalk","guardrail"]:
				var points: Array[Vector2]=Sidewalks.world_points(target)
				var translated: Array[Vector2]=[]
				for point in points:translated.append(point+delta)
				Sidewalks.write_world_points(target,translated)
			elif target.has("points"):
				for point in target.points:
					point.x=float(point.x)+delta.x
					point.y=float(point.y)+delta.y
			else:
				target.x=float(target.x)+delta.x
				target.y=float(target.y)+delta.y
		if operation=="delete":
			var kept: Array=[]
			for entry in entries:
				if chosen.has(str(entry.get("id",""))) and not entry.has("replaces"):continue
				kept.append(entry)
			next[category]=kept
		elif operation=="duplicate":
			for item in additions:next[category].append(item)
	if not _commit(next):
		return []
	return result


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
				if category=="races":shift_race_grid(copy,Vector2(12,12))
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
		road.points.remove_at(index)
		if road.get("elevation",{}).has("point_layers"):
			var values: Array=road.elevation.point_layers
			values.remove_at(index)
			road.elevation.start_layer=values[0];road.elevation.end_layer=values[-1]
		return _commit(next)
	return false

func split_road(identity: String,index: int) -> String:
	var next:=doc.duplicate(true)
	for road in next.roads:
		if str(road.id)!=identity:continue
		if road.has("autoGuardrails") and index!=0 and index!=road.points.size()-1:
			last_error="Remove road-linked guardrails before splitting, then set ranges on the new roads.";return ""
		if road.has("jump") and index!=0 and index!=road.points.size()-1:
			last_error="Remove the jump before splitting its road."
			return ""
		if index==0 or index==road.points.size()-1:
			road["independentEnds"]=true
			return identity if _commit(next) else ""
		if road.has("junctionStart") or road.has("junctionEnd") or str(road.get("roadClass",""))=="onramp":
			last_error="Reset connection modes to Automatic and use a regular road type before splitting."
			return ""
		if road.get("elevation",{}).has("point_layers") or Elevation.endpoint_layer(road,true)!=Elevation.endpoint_layer(road,false):
			last_error="Clear individual point elevations or set a flat layer before splitting it."
			return ""
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
	var layer := Elevation.endpoint_layer(target,index==0)
	for road in doc.roads:
		if str(road.id)==identity or not _same_network(target,road):continue
		for end in [0,road.points.size()-1]:
			if Elevation.endpoint_layer(road,end==0)!=layer:continue
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
		var layer := Elevation.endpoint_layer(target,index==0)
		if Elevation.endpoint_layer(road,true)!=layer or Elevation.endpoint_layer(road,false)!=layer:continue
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

func set_gameplay_controls(category: String,records: Array) -> bool:
	if category not in ["gameplayZones","junctionControls"]:return false
	var next: Dictionary=doc.duplicate(true)
	next[category]=records.duplicate(true)
	return _commit(next)
