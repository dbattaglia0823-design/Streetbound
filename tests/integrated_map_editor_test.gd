extends SceneTree
## Cross-phase source -> production archive -> release flow. No live physics
## or FPS assertions; those remain separate real-world test suites.
const City=preload("res://scripts/dev/advanced_world_construction.gd")
const Audit=preload("res://scripts/dev/world_validation.gd")
const Finish=preload("res://scripts/dev/environment_detail_planner.gd")
const Compare=preload("res://scripts/dev/map_release_comparison.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Day=preload("res://scripts/world/living_world_rules.gd")
const Light=preload("res://scripts/world/environment_finishing_rules.gd")
var failures:=0

func check(ok: bool,label: String) -> void:
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func run_release(args: Array[String]) -> Dictionary:
	var arguments:=PackedStringArray([ProjectSettings.globalize_path("res://tools/world_release.py"),"--project",ProjectSettings.globalize_path("res://")])
	arguments.append_array(PackedStringArray(args))
	var executable: String="py" if OS.get_name()=="Windows" else "python3"
	if OS.get_name()=="Windows":arguments.insert(0,"-3")
	var output: Array=[]
	var code:=OS.execute(executable,arguments,output,true)
	if code!=0:
		check(false,"production release: "+str(output).left(500))
		return {}
	var raw: Variant=JSON.parse_string(str(output[0]).strip_edges()) if not output.is_empty() else null
	return raw if raw is Dictionary else {}

func _initialize() -> void:
	var folder: String="user://integrated-map-test-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	var session:=Session.new()
	session.doc=Library.create("Integration district",2400,2400,"grass")
	var plan:=City.plan_neighborhood(session.doc,Vector2(1200,1200),{"columns":3,"rows":3,"block":180,"width":12,"density":.7,"seed":42,"parks":true,"parking":true},360,8000)
	check(not plan.has("error"),"neighborhood proposal")
	if plan.has("error"):quit(1);return
	check(not session.apply_construction(plan).is_empty(),"apply neighborhood")
	var report:=Audit.audit(session.doc,{},{}, "integration")
	check(report.performance.status=="unmeasured","no false performance result")
	# Add a real spawn on the first generated road. Home marker is outside
	# the travel lane and must survive the production compiler.
	var road: Dictionary=session.doc.roads[0]
	var a:=Vector2(float(road.points[0].x),float(road.points[0].y))
	var b:=Vector2(float(road.points[-1].x),float(road.points[-1].y))
	var spawn:=a.lerp(b,.25)
	check(not session.add_marker(spawn,"player_spawn").is_empty(),"player spawn")
	check(not session.add_marker(spawn+Vector2(-25,0),"home").is_empty(),"safehouse marker")
	var file:=Library.save(session.doc,"integrated.world.json")
	check(not file.is_empty(),"initial map save")
	if file.is_empty():quit(1);return
	var before: Dictionary=session.doc.duplicate(true)
	var detail:=Finish.plan(session.doc,a.lerp(b,.5)+Vector2(-35,0),{"style":"coastal","radius":160,"spacing":32,"density":1.0,"seed":19},8000)
	check(not detail.has("error") and not detail.get("props",[]).is_empty(),"finishing proposal")
	if not detail.get("props",[]).is_empty():
		check(not session.apply_construction(detail).is_empty(),"apply finishing")
	check(Library.save(session.doc,file)==file,"save finished source")
	var backups:=Library.backups(file)
	check(backups.size()==1,"automatic backup across finishing")
	if not backups.is_empty():
		var prior:=Library.load_backup(file,backups[0])
		var delta:=Compare.compare(prior,session.doc)
		check(Compare.equal_value(prior,before) and delta.entities.props.added.size()>0,"version comparison")
	check(Light.darkness(Day.tint(0))>0.9 and Light.darkness(Day.tint(43200))==0.0,"clock drives light response")
	var source:=ProjectSettings.globalize_path(Library.folder().path_join(file))
	var destination:=ProjectSettings.globalize_path(Library.folder().path_join("integrated.zip"))
	var active_before:=FileAccess.get_sha256("res://worlds/active-world.json")
	var preflight:=run_release(["--preflight",source])
	check(preflight.get("result","")=="ready" and int(preflight.get("audit",{}).get("error_count",-1))==0,"release compiler and structural audit")
	var exported:=run_release(["--export",source,"--output",destination])
	var verified:=run_release(["--verify",destination])
	check(exported.get("result","")=="exported" and verified.get("result","")=="verified" and exported.get("archive_sha256","")!="" and exported.get("archive_sha256","")==verified.get("archive_sha256",""),"exact package identity")
	check(FileAccess.get_sha256("res://worlds/active-world.json")==active_before,"no activation during preflight/export")
	if failures==0:print("INTEGRATED MAP EDITOR: PASS")
	quit(0 if failures==0 else 1)
