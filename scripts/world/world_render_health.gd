extends RefCounted
## Read-only archive-to-chunk contract. Never rebuilds or substitutes map data.

static func audit(data: Dictionary) -> Dictionary:
	var report := {"compatible":false,"status":"ARCHIVE DATA MISSING","errors":[],"expected":{}}
	var errors: Array = report.errors
	if data.get("format","")!="streetbound.streamed-world" or int(data.get("version",0))!=1:
		errors.append("Unsupported archive format/version")
	if data.get("units","")!="metres" or float(data.get("pixels_per_metre",0))!=20:
		errors.append("Expected metres and 20 pixels/metre")
	if float(data.get("chunk_size",0))<=0: errors.append("Invalid chunk size")
	for key in ["roads","segments","props","chunks","spawn","junctions","walls","terrain","surface_index"]:
		if not data.has(key): errors.append("Missing archive field: "+key)
	if not errors.is_empty():
		report.status="INCOMPATIBLE ARCHIVE"
		return report
	if data.roads.is_empty() or data.segments.is_empty() or data.props.is_empty():
		errors.append("Source road/scenery arrays are empty")
		return report
	var size := float(data.chunk_size)
	for key in data.chunks:
		var raw: PackedStringArray = str(key).split(",")
		if raw.size()!=2 or not raw[0].is_valid_int() or not raw[1].is_valid_int():
			errors.append("Invalid chunk key: "+str(key))
			continue
		for field in ["segments","props","junctions","walls","relief","rails"]:
			var source: String = {"relief":"relief_faces","rails":"mountain_rails"}.get(field,field)
			for index in data.chunks[key].get(field,[]):
				if int(index)<0 or int(index)>=data.get(source,[]).size():
					errors.append("Invalid %s index in chunk %s"%[field,key])
	# Check independent source coordinates, not just assignment totals. A
	# nonempty archive can still have all its content assigned to wrong keys.
	for field in ["segments","props"]:
		for index in data[field].size():
			var item: Dictionary = data[field][index]
			var p: Vector2
			if field=="props": p=Vector2(float(item.p[0]),float(item.p[1]))
			else: p=(Vector2(float(item.a[0]),float(item.a[1]))+Vector2(float(item.b[0]),float(item.b[1])))*.5
			var cell := Vector2i((p/size).floor())
			var key := "%d,%d"%[cell.x,cell.y]
			if not report.expected.has(key): report.expected[key]={"segments":0,"props":0}
			report.expected[key][field]+=1
			var assigned: Array = data.chunks.get(key,{}).get(field,[])
			if not assigned.has(float(index)) and not assigned.has(index):
				if errors.size()<20: errors.append("Missing %s assignment %d in %s"%[field,index,key])
	report.compatible=errors.is_empty()
	report.status="COMPATIBLE v1 / metres / 20 px/m" if errors.is_empty() else "CHUNK ASSIGNMENT ERROR"
	return report

static func snapshot(world: Node2D) -> Dictionary:
	var out := {"segments":0,"props":0,"batches":0,"road_nodes":0,"scenery_nodes":0,
		"visible_batches":0,"visible_props":0,"render_failures":0,
		"visible_road_nodes":0,"visible_scenery_nodes":0,"empty":0,"unexpected_empty":0,
		"failed":world.failed_chunks.size(),"status":"READY"}
	for chunk in world.chunks.values():
		if not chunk.stream_active: continue
		out.segments+=chunk.content.get("segments",[]).size()
		out.props+=chunk.content.get("props",[]).size()
		out.batches+=chunk.road_batches.size()
		if chunk.road_batches.is_empty() and chunk.prop_list.is_empty(): out.empty+=1
		if (not chunk.content.get("segments",[]).is_empty() and chunk.road_batches.is_empty()) or (not chunk.content.get("props",[]).is_empty() and chunk.prop_list.is_empty()):
			out.unexpected_empty+=1
		var rendered_batches := 0
		var rendered_props := 0
		for child in chunk.get_children():
			if child.get_script()==preload("res://scripts/world/coast_roads.gd"):
				out.road_nodes+=1
				if child.is_visible_in_tree():
					out.visible_road_nodes+=1
					if child.render_stage==1: rendered_batches+=child.road_batches.size()
			elif child.get_script()==preload("res://scripts/world/coast_scenery.gd"):
				out.scenery_nodes+=1
				if child.is_visible_in_tree():
					out.visible_scenery_nodes+=1
					rendered_props+=child.prop_list.size()
		out.visible_batches+=rendered_batches
		out.visible_props+=rendered_props
		if chunk.visible and (rendered_batches<chunk.road_batches.size() or rendered_props<chunk.prop_list.size()):
			out.render_failures+=1
	if not world.archive_audit.get("compatible",false): out.status=world.archive_audit.get("status","ARCHIVE DATA MISSING")
	elif not world.initialization_complete: out.status="WORLD INITIALIZATION FAILED"
	elif out.failed>0 or out.unexpected_empty>0: out.status="CHUNK CONSTRUCTION FAILED"
	elif (out.segments>0 and out.road_nodes==0) or (out.props>0 and out.scenery_nodes==0): out.status="RENDER NODES MISSING"
	elif out.road_nodes!=out.visible_road_nodes or out.scenery_nodes!=out.visible_scenery_nodes: out.status="RENDER LAYERS HIDDEN"
	elif out.render_failures>0: out.status="RENDER CONTENT MISSING"
	elif out.segments==0 and out.props==0: out.status="TERRAIN-ONLY AREA"
	return out
