extends RefCounted
## Development-only audit. Runtime lane graph is authoritative; estimates never
## imply that a physical drive, collision test or police dispatch has passed.
const Elevation=preload("res://scripts/world/road_elevation.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")
const Network=preload("res://scripts/world/traffic_network.gd")
const Controls=preload("res://scripts/world/authored_gameplay_controls.gd")
const ACCESS_M:=25.0
const MAX_ISSUES:=2000

static func point(item: Dictionary) -> Vector2:
	return Vector2(float(item.get("x",0)),float(item.get("y",0)))

static func layer(item: Dictionary) -> int:
	return int(item.get("road_layer",item.get("properties",{}).get("road_layer",0)))

static func issue(report: Dictionary, severity: String, code: String, label: String, at: Vector2, fix: Dictionary={}) -> void:
	report.counts[severity]=int(report.counts.get(severity,0))+1
	if report.issues.size()<MAX_ISSUES:
		report.issues.append({"severity":severity,"code":code,"message":label,"position":[at.x,at.y],"fix":fix})
	else:
		report.truncated=true

static func report_base() -> Dictionary:
	return {"schema":1,"counts":{"error":0,"warning":0,"info":0},"issues":[],"truncated":false,"graph_current":false,"route_checks":0,"route_passes":0}

## Find only isolated, mutually unique endpoint pairs. Never move an already
## connected endpoint, a ramp/independent end or a locked/nonmatching layer.
static func source_audit(doc: Dictionary, report: Dictionary) -> void:
	var endpoints: Array[Dictionary]=[]
	for road in doc.get("roads",[]):
		var pts: Array=road.get("points",[])
		if pts.size()<2:
			issue(report,"error","road_geometry","Road has fewer than two points",Vector2.ZERO)
			continue
		var error:=Elevation.authoring_error(road)
		if not error.is_empty():issue(report,"error","elevation",str(road.id)+": "+error,point(pts[0]))
		for i in range(1,pts.size()):
			if point(pts[i-1]).distance_to(point(pts[i]))<.15:
				issue(report,"error","short_segment",str(road.id)+": coincident control points",point(pts[i]))
		for i in [0,pts.size()-1]:
			endpoints.append({"id":str(road.id),"index":i,"p":point(pts[i]),"layer":Elevation.endpoint_layer(road,i==0),"loose":str(road.get("surface","")) in ["dirt","gravel"],"unsafe":road.has("independentEnds") or road.has("elevation") or str(road.get("roadClass",""))=="onramp" or road.has("connectionModes") or road.has("connections") or road.has("startConnection") or road.has("endConnection")})
	var near: Dictionary={}
	for i in endpoints.size():
		var a: Dictionary=endpoints[i]
		var matches: Array[int]=[]
		for j in endpoints.size():
			if i==j:continue
			var b: Dictionary=endpoints[j]
			if a.layer!=b.layer or a.loose!=b.loose:continue
			if Vector2(a.p).distance_to(b.p)<=2.0:matches.append(j)
		near[i]=matches
	for i in endpoints.size():
		var matches: Array=near[i]
		if matches.size()!=1:continue
		var j:=int(matches[0])
		if j<=i or near[j].size()!=1 or int(near[j][0])!=i:continue
		var a: Dictionary=endpoints[i];var b: Dictionary=endpoints[j]
		var gap: float=Vector2(a.p).distance_to(b.p)
		if a.id==b.id or gap<.15:continue
		var fix: Dictionary={}
		if not a.unsafe and not b.unsafe and not _near_other_road(doc,a,b):
			fix={"id":a.id,"index":a.index,"from":[a.p.x,a.p.y],"to":[b.p.x,b.p.y],"target":b.id,"target_index":b.index}
		issue(report,"warning","endpoint_gap","Nearby endpoints %s / %s (%.2f m); inspect intended connection"%[a.id,b.id,gap],a.p,fix)
	# Coincident source props are suspicious, not proof of collision. Spatial
	# buckets avoid an all-pairs comparison over thousands of assets.
	var buckets: Dictionary={}
	for prop in doc.get("props",[]):
		if bool(prop.get("hidden",false)):continue
		var p:=point(prop)
		var key:=Vector2i(floori(p.x),floori(p.y))
		for dx in [-1,0,1]:
			for dy in [-1,0,1]:
				for other in buckets.get(key+Vector2i(dx,dy),[]):
					if p.distance_to(point(other))<.5:
						issue(report,"warning","prop_overlap","Nearly coincident props %s / %s"%[str(other.get("id","")),str(prop.get("id",""))],p)
		if not buckets.has(key):buckets[key]=[]
		buckets[key].append(prop)

## A nearby road interior can already own a junction. Do not snap an
## endpoint if that relationship is uncertain; leave it for manual review.
static func _near_other_road(doc: Dictionary,a: Dictionary,b: Dictionary) -> bool:
	for road in doc.get("roads",[]):
		if str(road.id) in [str(a.id),str(b.id)]:continue
		var pts: Array=road.get("points",[])
		for i in range(1,pts.size()):
			var first:=point(pts[i-1]);var last:=point(pts[i])
			if first.distance_squared_to(last)<.001:continue
			for candidate in [a,b]:
				if Vector2(candidate.p).distance_to(Geometry2D.get_closest_point_to_segment(candidate.p,first,last))<=3.0:return true
	return false

## Recompute the proposal set against the current revision. The session
## commits the returned snapshot as one undoable transaction.
static func repaired(doc: Dictionary, requested: Array) -> Dictionary:
	var report:=report_base()
	source_audit(doc,report)
	var allowed: Array=[]
	for item in report.issues:
		if not item.fix.is_empty():allowed.append(item.fix)
	var next:=doc.duplicate(true)
	for fix in requested:
		if not fix in allowed:return {}
		for road in next.roads:
			if str(road.id)==str(fix.id):
				road.points[int(fix.index)]={"x":fix.to[0],"y":fix.to[1]}
	return next

static func edge_point(graph: RefCounted,id: int) -> Vector2:
	var edge: Dictionary=graph.edges[id]
	var pts: PackedVector2Array=edge.points
	return pts[pts.size()/2]/20.0

## Use weak components to identify separated road islands, not to assert
## directed reachability. Directed tests below use the production planner.
static func topology(graph: RefCounted, report: Dictionary) -> void:
	var n: int=graph.edges.size()
	report["lane_edges"]=n
	if n==0:
		issue(report,"error","empty_graph","No drivable lane edges",Vector2.ZERO)
		return
	var links: Array=[]
	for i in n:links.append([])
	for i in n:
		var edge: Dictionary=graph.edges[i]
		for raw in edge.next:
			var j:=int(raw)
			if j<0 or j>=n:
				issue(report,"error","invalid_link","Invalid directed edge successor",edge_point(graph,i))
				continue
			links[i].append(j);links[j].append(i)
		if edge.next.is_empty() and int(edge.get("end_j",-1))>=0:
			issue(report,"warning","junction_dead_end","Junction lane has no legal successor (may be intentional)",edge_point(graph,i))
	var seen: Dictionary={}
	var components: Array[Dictionary]=[]
	for i in n:
		if seen.has(i):continue
		var queue: Array[int]=[i];seen[i]=true
		var cursor:=0
		var lanes:=0
		var metres:=0.0
		while cursor<queue.size():
			var current:=queue[cursor];cursor+=1
			var edge: Dictionary=graph.edges[current]
			if not bool(edge.connector):
				lanes+=1;metres+=float(edge.length_px)/20.0
			for j in links[current]:
				if not seen.has(j):seen[j]=true;queue.append(j)
		if lanes>0:components.append({"edge":i,"lanes":lanes,"metres":metres})
	components.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.metres)>float(b.metres))
	report["components"]=components.size()
	for i in range(1,components.size()):
		var c: Dictionary=components[i]
		issue(report,"warning","road_island","Separate lane component: %d lanes / %.0f lane-metres"%[c.lanes,c.metres],edge_point(graph,int(c.edge)))

static func route(planner: RefCounted,a: Dictionary,b: Dictionary) -> Dictionary:
	var starts: Array[Dictionary]=planner._candidates(point(a)*20.0,Vector2.ZERO,"",layer(a))
	var goals: Array[Dictionary]=planner._candidates(point(b)*20.0,Vector2.ZERO,"",layer(b))
	starts=starts.filter(func(c: Dictionary)->bool:return float(c.distance)<=ACCESS_M*20.0)
	goals=goals.filter(func(c: Dictionary)->bool:return float(c.distance)<=ACCESS_M*20.0)
	if starts.is_empty() or goals.is_empty():return {}
	return planner._shortest(planner._local_candidates(starts),planner._local_candidates(goals))

## Bounded alternate search. Remove one interior edge from a private graph
## copy; the live runtime graph and its edge IDs remain untouched.
static func alternate(compiled: Dictionary,a: Dictionary,b: Dictionary,primary: Dictionary) -> Dictionary:
	var original: RefCounted=compiled.get("network")
	var sequence: Array=primary.get("edges",[])
	if original==null or sequence.size()<3:return {}
	var best: Dictionary={}
	var attempts:=mini(6,sequence.size()-2)
	for i in attempts:
		var index:=1+floori(float(i)*float(sequence.size()-2)/float(attempts))
		var blocked:=int(sequence[index])
		var graph:=Network.new()
		graph.edges=original.edges.duplicate(true)
		for edge in graph.edges:edge.next.erase(blocked)
		graph.edges[blocked].next.clear()
		var planner:=Planner.new()
		planner.setup(graph,compiled.data)
		var candidate:=route(planner,a,b)
		if candidate.is_empty() or blocked in candidate.edges or candidate.edges==sequence:continue
		if best.is_empty() or float(candidate.length_m)<float(best.length_m):best=candidate
	return best

static func check_leg(planner: RefCounted,a: Dictionary,b: Dictionary,label: String,report: Dictionary) -> void:
	report.route_checks+=1
	if route(planner,a,b).is_empty():
		issue(report,"error","unreachable_leg",label+": no directed route within 25 m access",point(b))
	else:report.route_passes+=1

static func access(planner: RefCounted,marker: Dictionary) -> bool:
	var choices: Array=planner._candidates(point(marker)*20.0,Vector2.ZERO,"",layer(marker))
	return not choices.is_empty() and float(choices[0].distance)<=ACCESS_M*20.0

static func gameplay(doc: Dictionary,planner: RefCounted,report: Dictionary) -> void:
	var markers: Dictionary={}
	for m in doc.get("markers",[]):markers[str(m.id)]=m
	for m in markers.values():
		var props: Dictionary=m.get("properties",{})
		if not bool(props.get("enabled",true)):continue
		var kind:=str(m.get("type",""))
		if kind not in ["garage","fuel","contract","contract_contact","contract_dropoff","robbery_target","dealership"]:continue
		if not access(planner,m):
			issue(report,"error","marker_access",str(m.get("name",m.id))+": no nearby lane on its level",point(m))
		var offers: Array=props.get("offers",[]) if kind=="contract_contact" else []
		if kind=="contract":
			offers=[{"destination_marker_id":props.get("destination_marker_id",""),"kind":props.get("contract_kind","courier")}]
		for offer in offers:
			var title:=str(m.id)+"/"+str(offer.get("title","contract"))
			var destination: Dictionary=markers.get(str(offer.get("destination_marker_id","")),{})
			var target: Dictionary=m
			if str(offer.get("kind",""))=="robbery":
				target=markers.get(str(offer.get("robbery_marker_id","")),{})
				if target.is_empty():
					issue(report,"error","missing_target",title+": missing robbery target",point(m));continue
				check_leg(planner,m,target,title+" pickup → target",report)
			if destination.is_empty() or not bool(destination.get("properties",{}).get("enabled",true)):
				issue(report,"error","missing_destination",title+": missing/disabled destination",point(m));continue
			check_leg(planner,target,destination,title+" → dropoff",report)
	for race in doc.get("races",[]):
		var pts: Array=race.get("points",[])
		var name:=str(race.get("name",race.get("id","race")))
		for i in range(1,pts.size()):
			check_leg(planner,pts[i-1],pts[i],name+" checkpoint %d"%i,report)
		if pts.size()>2 and str(race.get("mode",""))=="circuit":
			check_leg(planner,pts[-1],pts[0],name+" closing lap",report)

## Deterministic lane-load screening, not a traffic or police physics sim.
## Reports district patrol settings and relative lane storage at three loads.
static func scenarios(graph: RefCounted,data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for name in ["Normal","Rush hour","Heavy"]:
		var multiplier: float={"Normal":1.0,"Rush hour":1.5,"Heavy":2.0}[name]
		var high:=0;var count:=0;var patrol_off:=0
		for edge in graph.edges:
			if bool(edge.connector):continue
			var at:=edge_point(graph,int(edge.id))
			var z:=Controls.zone(data,at)
			var density:=float(z.get("density",100))/100.0*multiplier
			if density>=2.0:high+=1
			if float(z.get("patrol",7))==0.0:patrol_off+=1
			count+=1
		rows.append({"scenario":name,"multiplier":multiplier,"high_demand_lanes":high,"lanes":count,"patrol_disabled_lanes":patrol_off})
	return rows

static func performance(report: Dictionary,profile: Dictionary,hash: String) -> void:
	if profile.is_empty() or str(profile.get("source_hash",""))!=hash:
		report["performance"]={"status":"unmeasured"};return
	var frames:=0;var peak:=0.0;var build:=0.0;var draw:=0
	for row in profile.get("cells",{}).values():
		frames+=int(row.get("frames",0))
		peak=maxf(peak,float(row.get("frame_peak_ms",0)))
		build=maxf(build,float(row.get("build_usec",0))/1000.0)
		draw=maxi(draw,int(row.get("draw_peak",0)))
	report["performance"]={"status":"sampled" if frames>0 else "unmeasured","frames":frames,"peak_frame_ms":peak,"peak_chunk_build_ms":build,"peak_draw_calls":draw,"cells":profile.get("cells",{}).size()}

static func audit(doc: Dictionary,compiled: Dictionary,profile: Dictionary,hash: String) -> Dictionary:
	var report:=report_base()
	report["source_hash"]=hash
	source_audit(doc,report)
	performance(report,profile,hash)
	if compiled.is_empty() or compiled.get("network")==null:
		issue(report,"info","graph_unavailable","Current production graph unavailable; route checks not run",Vector2.ZERO)
	else:
		report.graph_current=true
		var graph: RefCounted=compiled.network
		topology(graph,report)
		var planner:=Planner.new()
		planner.setup(graph,compiled.data)
		gameplay(doc,planner,report)
		report["scenarios"]=scenarios(graph,compiled.data)
	report["status"]="BLOCKED" if int(report.counts.error)>0 else ("REVIEW" if not report.graph_current or int(report.counts.warning)>0 else "STATIC CHECKS CLEAR")
	return report
