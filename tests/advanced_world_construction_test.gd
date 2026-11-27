extends SceneTree
const Advanced=preload("res://scripts/dev/advanced_world_construction.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
var failures:=0

func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL ",label)

func _initialize() -> void:
	var session:=Session.new()
	session.doc=Library.create("Advanced construction",2400,2400,"grass")
	var before: Dictionary=session.doc.duplicate(true)
	var settings: Dictionary={"columns":3,"rows":3,"block":180,"width":12,"density":1.0,"seed":42,"parks":true,"parking":true,"sidewalks":true}
	var center:=Vector2(1200,1200)
	var plan:=Advanced.plan_neighborhood(session.doc,center,settings,360,8000)
	check(not plan.has("error"),"neighborhood generated")
	if plan.has("error"):quit(1);return
	check(plan==Advanced.plan_neighborhood(session.doc,center,settings,360,8000),"determinism")
	check(session.doc==before,"preview nonmutating")
	check(plan.stats.buildings>0 and plan.stats.parks==1 and plan.stats.parking>0 and plan.stats.parking==plan.stats.driveways,"mixed buildings park and parking access")
	check(plan.regions.size()==9 and plan.roads.size()>8,"editable blocks and service roads")
	check(Advanced.plan_neighborhood(session.doc,Vector2(5,5),settings,360,8000).has("error"),"bounds rejection")
	check(Advanced.plan_neighborhood(session.doc,center,settings,3,8000).has("error"),"road limit")
	var protected_doc: Dictionary=before.duplicate(true)
	protected_doc.markers.append({"x":1200,"y":1200,"type":"fuel"})
	check(Advanced.plan_neighborhood(protected_doc,center,settings,360,8000).has("error"),"protect existing service markers")
	check(not session.apply_construction(plan).is_empty() and session.history.size()==1,"transaction")
	check(Advanced.plan_neighborhood(session.doc,center,settings,360,8000).has("error"),"occupied district rejection")
	check(session.undo() and session.doc==before,"undo")
	var diamond:=Advanced.plan_diamond(session.doc,center,{"interchange_span":240},360)
	check(not diamond.has("error") and diamond.roads.size()==6,"diamond six roads")
	if not diamond.has("error"):
		check(absf(float(diamond.roads[2].points[0].x)-float(diamond.roads[5].points[-1].x))>=90.0,"separate entry/exit junctions")
		check(diamond.roads[0].elevation.start_layer==1 and diamond.roads[2].junctionEnd=="intersection" and diamond.roads[3].junctionEnd=="merge","grade and one-way semantics")
		check(not session.apply_construction(diamond).is_empty() and session.undo(),"diamond transaction")
	# This test runs the actual Python compiler for both plans, rather than
	# assuming source validation proves junction topology.
	var neighborhood_bake:=Advanced.preflight(before,plan)
	check(bool(neighborhood_bake.ok),"production neighborhood bake: "+str(neighborhood_bake.message))
	var diamond_bake:=Advanced.preflight(before,diamond)
	check(bool(diamond_bake.ok) and int(diamond_bake.get("merges",0))==2,"production diamond bake: "+str(diamond_bake.message))
	if failures==0:print("ADVANCED WORLD CONSTRUCTION: PASS")
	quit(0 if failures==0 else 1)
