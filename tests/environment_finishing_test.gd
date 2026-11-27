extends SceneTree
const Rules=preload("res://scripts/world/environment_finishing_rules.gd")
const Planner=preload("res://scripts/dev/environment_detail_planner.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
var failures:=0

func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL ",label)

func _initialize() -> void:
	check(Rules.darkness(Color.WHITE)==0.0 and Rules.darkness(Color(.48,.54,.72))>.9,"day-night response")
	check(Rules.classify("Foundry industrial")=="industrial" and Rules.classify("Coastal beach")=="coastal","district classification")
	check(Rules.style_at({"gameplay_zones":[{"x":0,"y":0,"w":100,"h":100,"name":"Downtown"}]},Vector2(50,50))=="downtown","authored district precedence")
	check(Rules.owns(Vector2.ZERO,Vector2(100,100)) and not Rules.owns(Vector2(100,50),Vector2(100,100)),"exclusive chunk ownership")
	var complete:=Rules.stations(0,100,20)
	var parts:=Rules.stations(0,40,20)+Rules.stations(40,60,20)
	check(complete==parts,"station continuity")
	var session:=Session.new()
	session.doc=Library.create("Finishing test",1200,1200,"grass")
	session.add_road(Vector2(100,600),Vector2(1100,600))
	var before: Dictionary=session.doc.duplicate(true)
	var settings: Dictionary={"style":"coastal","radius":200,"spacing":30,"density":1.0,"seed":42}
	var plan:=Planner.plan(session.doc,Vector2(600,600),settings,8000)
	check(not plan.has("error") and plan.props.size()>0 and plan==Planner.plan(session.doc,Vector2(600,600),settings,8000),"deterministic scenery")
	check(session.doc==before,"preview does not modify source")
	check(Planner.plan(session.doc,Vector2(600,600),settings,session.doc.props.size()).props.is_empty(),"capacity")
	var prior:=session.history.size()
	check(not session.apply_construction(plan).is_empty() and session.history.size()==prior+1,"single transaction")
	check(session.undo() and session.doc==before,"undo")
	if failures==0:print("ENVIRONMENT FINISHING: PASS")
	quit(0 if failures==0 else 1)
