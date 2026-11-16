extends SceneTree
## Native Map Builder marquee and bulk-edit regression against a blank custom map.
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Groups=preload("res://scripts/dev/native_map_group_edit.gd")
const Gizmos=preload("res://scripts/dev/native_world_editor_gizmos.gd")
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("_run")

func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)

func _run() -> void:
	var doc: Dictionary=Library.create("Marquee test",1200,900,"grass")
	var session: Variant=Session.new()
	session.doc=doc.duplicate(true);session.initial=doc.duplicate(true)
	session.draft_baseline_hash=session._fingerprint(doc)
	var a: String=session.add_prop("house",Vector2(100,100))
	var b: String=session.add_prop("house",Vector2(145,100))
	var c: String=session.add_prop("house",Vector2(400,400))
	var marker: String=session.add_marker(Vector2(130,110),"checkpoint")
	check("three_props_and_marker_are_editable",not a.is_empty() and not b.is_empty() and not c.is_empty() and not marker.is_empty())
	var size:=func(_prop: Dictionary)->Vector2:return Vector2(20,20)
	var path:=func(road: Dictionary)->PackedVector2Array:return Session.road_path(road)
	var area:=Rect2(Vector2(92,92),Vector2(76,36))
	var hit: Array[String]=Groups.collect(session.doc,area,
		{"scenery":true,"markers":true,"roads":true,"terrain":true},size,path)
	check("marquee_selects_both_props_and_marker",hit.has(a) and hit.has(b) and hit.has(marker),hit)
	check("marquee_does_not_select_distant_prop",not hit.has(c),hit)
	var hidden_layers: Array[String]=Groups.collect(session.doc,area,
		{"scenery":false,"markers":true,"roads":false,"terrain":false},size,path)
	check("layer_filters_exclude_hidden_scenery",not hidden_layers.has(a) and hidden_layers.has(marker))
	var no_collision: Array[String]=Groups.collect(session.doc,
		Rect2(Vector2(800,800),Vector2(50,50)),
		{"scenery":true,"markers":true,"roads":true,"terrain":true},size,path)
	check("empty_area_has_no_false_selection",no_collision.is_empty())
	var g: Variant=Gizmos.new()
	root.add_child(g)
	g.selected_source_id=""
	g.selected_ids=[a,b]
	check("multi_selected_props_both_have_outlines",
		g._show_prop_outline(session.prop_at_id(a)) and
		g._show_prop_outline(session.prop_at_id(b)) and
		not g._show_prop_outline(session.prop_at_id(c)))
	g.selected_ids=[]
	check("deselect_hides_all_group_outlines",
		not g._show_prop_outline(session.prop_at_id(a)))
	var before_history: int=session.history.size()
	var moved: bool=Groups.move(session,[a,b],Vector2(20,10))
	check("group_move_translates_every_member_once",moved and
		Vector2(session.prop_at_id(a).x,session.prop_at_id(a).y).distance_to(Vector2(120,110))<.01 and
		Vector2(session.prop_at_id(b).x,session.prop_at_id(b).y).distance_to(Vector2(165,110))<.01)
	check("group_move_does_not_touch_other_entities",
		Vector2(session.prop_at_id(c).x,session.prop_at_id(c).y)==Vector2(400,400) and
		session.history.size()==before_history+1)
	check("one_undo_restores_all_moved_objects",
		session.undo() and Vector2(session.prop_at_id(a).x,session.prop_at_id(a).y)==Vector2(100,100) and
		Vector2(session.prop_at_id(b).x,session.prop_at_id(b).y)==Vector2(145,100))
	check("redo_restores_group_move",session.redo() and float(session.prop_at_id(a).x)==120)
	before_history=session.history.size()
	var clones: Array[String]=Groups.duplicate(session,[a,b])
	check("group_duplicate_creates_two_unique_copies",clones.size()==2 and
		clones[0]!=a and clones[1]!=b and clones[0]!=clones[1] and
		not session.prop_at_id(clones[0]).is_empty() and not session.prop_at_id(clones[1]).is_empty())
	check("duplicates_keep_relative_spacing_and_offset",
		clones.size()==2 and
		Vector2(session.prop_at_id(clones[0]).x,session.prop_at_id(clones[0]).y)==Vector2(132,122) and
		Vector2(session.prop_at_id(clones[1]).x,session.prop_at_id(clones[1]).y)==Vector2(177,122))
	check("group_duplicate_is_one_undo",session.history.size()==before_history+1 and session.undo() and
		session.prop_at_id(clones[0]).is_empty() and session.prop_at_id(clones[1]).is_empty())
	check("duplicate_redo_restores_both",session.redo() and not session.prop_at_id(clones[0]).is_empty())
	before_history=session.history.size()
	check("group_delete_removes_all_clones_atomically",
		Groups.delete(session,clones) and session.prop_at_id(clones[0]).is_empty() and
		session.prop_at_id(clones[1]).is_empty() and session.history.size()==before_history+1)
	check("undo_restores_deleted_selection",
		session.undo() and not session.prop_at_id(clones[0]).is_empty() and not session.prop_at_id(clones[1]).is_empty())
	check("align_left_is_one_group_edit",Groups.arrange_props(session,[a,b],"left") and
		is_equal_approx(float(session.prop_at_id(a).x),float(session.prop_at_id(b).x)))
	check("align_top_keeps_objects_on_same_row",
		Groups.arrange_props(session,[a,c],"top") and is_equal_approx(float(session.prop_at_id(a).y),float(session.prop_at_id(c).y)))
	check("three_way_distribution_spreads_centers",
		Groups.arrange_props(session,[a,b,c],"horizontal"))
	# All-or-nothing bounds validation. A member near the edge prevents
	# the whole move without silently moving only the other member.
	var edge: String=session.add_prop("house",Vector2(1180,230))
	var original_a: Vector2=Vector2(session.prop_at_id(a).x,session.prop_at_id(a).y)
	before_history=session.history.size()
	check("out_of_bounds_group_move_is_rejected_without_partial_mutation",
		not Groups.move(session,[a,edge],Vector2(50,0)) and
		Vector2(session.prop_at_id(a).x,session.prop_at_id(a).y)==original_a and
		session.history.size()==before_history)
	# Mixing source roads, regions, markers, and scenery remains atomic.
	var road: String=session.add_road(Vector2(600,600),Vector2(700,600))
	var region: String=session.add_region([Vector2(750,600),Vector2(800,600),Vector2(800,650)],"forest")
	before_history=session.history.size()
	check("mixed_source_group_moves_in_one_history_entry",
		not road.is_empty() and not region.is_empty() and
		Groups.move(session,[road,region,marker],Vector2(5,0)) and
		session.history.size()==before_history+1)
	check("selected_road_and_region_hit_by_box",Groups.collect(session.doc,
		Rect2(Vector2(595,590),Vector2(210,75)),
		{"scenery":false,"markers":false,"roads":true,"terrain":true},size,path).has(road))
	g.queue_free()
	await process_frame
	print("MAP BUILDER MULTI-SELECT: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
