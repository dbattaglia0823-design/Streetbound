extends SceneTree
const Audit=preload("res://scripts/dev/world_validation.gd")
const Network=preload("res://scripts/world/traffic_network.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")

func _initialize() -> void:
	var doc: Dictionary={"roads":[{"id":"a","points":[{"x":0,"y":0},{"x":10,"y":0}]},{"id":"b","points":[{"x":11,"y":0},{"x":30,"y":0}]}],"props":[{"id":"p","x":5,"y":5},{"id":"q","x":5.1,"y":5}],"markers":[],"races":[]}
	var report:=Audit.audit(doc,{},{},"revision")
	var fixes: Array=[]
	for row in report.issues:
		if not row.fix.is_empty():fixes.append(row.fix)
	if fixes.size()!=1 or int(report.counts.warning)!=2 or report.graph_current or report.performance.status!="unmeasured":
		printerr("FAIL source diagnostics ",report);quit(1);return
	var repaired:=Audit.repaired(doc,fixes)
	if repaired.is_empty() or repaired.roads[0].points[-1].x!=11 or doc.roads[0].points[-1].x!=10:
		printerr("FAIL repair must preserve original");quit(1);return
	var stale: Dictionary=doc.duplicate(true)
	stale.roads[1].points[0].x=15
	if not Audit.repaired(stale,fixes).is_empty():
		printerr("FAIL stale proposal accepted");quit(1);return
	var profile: Dictionary={"source_hash":"revision","cells":{Vector2i.ZERO:{"frames":10,"frame_peak_ms":22,"build_usec":1500,"draw_peak":10}}}
	Audit.performance(report,profile,"revision")
	if report.performance.frames!=10 or report.performance.peak_chunk_build_ms!=1.5:
		printerr("FAIL profile aggregation");quit(1);return
	Audit.performance(report,profile,"changed")
	if report.performance.status!="unmeasured":
		printerr("FAIL stale profile accepted");quit(1);return
	var graph:=Network.new()
	for i in 3:
		var x:=float(i)*2000.0 if i<2 else 20000.0
		graph._add_edge({"points":PackedVector2Array([Vector2(x,0),Vector2(x+2000,0)]),"speed_px":200.0,"road":i,"connector":false,"end_j":-1})
	graph.edges[0].next.append(1)
	var topology:=Audit.report_base()
	Audit.topology(graph,topology)
	if topology.components!=2 or topology.lane_edges!=3:
		printerr("FAIL separated component count");quit(1);return
	var planner:=Planner.new()
	planner.setup(graph,{})
	var start: Dictionary={"x":10,"y":0}
	var finish: Dictionary={"x":190,"y":0}
	var route:=Audit.route(planner,start,finish)
	if route.is_empty() or absf(float(route.length_m)-180.0)>.1:
		printerr("FAIL legal directed route");quit(1);return
	if not Audit.route(planner,finish,start).is_empty() or not Audit.route(planner,start,{"x":1050,"y":0}).is_empty():
		printerr("FAIL illegal reverse or disconnected route");quit(1);return
	if not Audit.alternate({"network":graph,"data":{}},start,finish,route).is_empty():
		printerr("FAIL invented alternate");quit(1);return
	print("WORLD VALIDATION: PASS")
	quit(0)
