extends SceneTree
## Sidewalk paths branch without adding traffic lanes, keep shared handles
## editable, and survive the existing World Forge v2 source contract.
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Scenery=preload("res://scripts/world/coast_scenery.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String,okay: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if okay else "FAIL",label,detail])
	if not okay:failures.append(label)

func near(a: Vector2,b: Vector2) -> bool:
	return a.distance_to(b)<0.05

func contains_anchor(prop: Dictionary,point: Vector2) -> bool:
	for at in Session.sidewalk_world_points(prop):
		if near(at,point):return true
	return false

func _run() -> void:
	var session=Session.new()
	check("sidewalk_source_loads",session.load_source())
	if session.doc.is_empty():quit(1);return
	var previous_roads:=JSON.stringify(session.doc.roads)
	var count_before: int=session.doc.props.size()
	var trunk: String=session.add_sidewalk([Vector2(2000,2000),
		Vector2(2040,2000),Vector2(2080,2000)],3.0)
	check("main_footpath_creates_a_sidewalk_prop_not_a_road",
		not trunk.is_empty() and session.doc.props.size()==count_before+1 and
		JSON.stringify(session.doc.roads)==previous_roads)
	var t_branch: String=session.add_sidewalk([Vector2(2040,2000.6),
		Vector2(2040,2040)],3.0)
	check("T_branch_snaps_to_existing_internal_anchor",
		not t_branch.is_empty() and contains_anchor(session.prop_at_id(t_branch),
			Vector2(2040,2000)))
	var interior: String=session.add_sidewalk([Vector2(2060,1960),
		Vector2(2060,2001.1)],2.8)
	check("T_branch_snaps_to_middle_of_an_existing_segment",
		not interior.is_empty() and
		contains_anchor(session.prop_at_id(trunk),Vector2(2060,2000)) and
		contains_anchor(session.prop_at_id(interior),Vector2(2060,2000)))
	var x_branch: String=session.add_sidewalk([Vector2(2030,1960),
		Vector2(2030,2040)],3.2)
	check("crossing_sidewalk_segments_create_connected_X_path",
		not x_branch.is_empty() and
		contains_anchor(session.prop_at_id(trunk),Vector2(2030,2000)) and
		contains_anchor(session.prop_at_id(x_branch),Vector2(2030,2000)))
	var count_trunk: int=session.prop_at_id(trunk).sidewalkPoints.size()
	var before_snapshot:=JSON.stringify(session.doc)
	check("moving_a_branch_joint_moves_the_parent_handle",
		session.move_sidewalk_point(interior,1,Vector2(2060,2005)) and
		contains_anchor(session.prop_at_id(interior),Vector2(2060,2005)) and
		contains_anchor(session.prop_at_id(trunk),Vector2(2060,2005)))
	check("shared_sidewalk_edit_undo_restores_both_paths",
		session.undo() and JSON.stringify(session.doc)==before_snapshot)
	check("shared_sidewalk_edit_redo_restores_both_paths",
		session.redo() and contains_anchor(session.prop_at_id(trunk),Vector2(2060,2005)))
	session.undo()
	check("Alt_style_detached_handle_moves_only_selected_branch",
		session.move_sidewalk_point(interior,1,Vector2(2060,2010),0.0,false) and
		contains_anchor(session.prop_at_id(trunk),Vector2(2060,2000)) and
		not contains_anchor(session.prop_at_id(trunk),Vector2(2060,2010)))
	check("explicit_sidewalk_reconnect_snaps_to_an_existing_segment",
		session.reconnect_sidewalk_endpoint(interior,1,12.0) and
		contains_anchor(session.prop_at_id(interior),Vector2(2060,2000)))
	var junction_idx: int=0
	for i in Session.sidewalk_world_points(session.prop_at_id(trunk)).size():
		if near(Session.sidewalk_world_points(session.prop_at_id(trunk))[i],Vector2(2030,2000)):
			junction_idx=i;break
	check("insert_sidewalk_handle_preserves_existing_branches",
		session.insert_sidewalk_point(trunk,junction_idx) and
		session.prop_at_id(trunk).sidewalkPoints.size()==count_trunk+1 and
		contains_anchor(session.prop_at_id(x_branch),Vector2(2030,2000)))
	check("remove_sidewalk_handle_is_undoable",
		session.remove_sidewalk_point(trunk,junction_idx+1) and
		session.undo() and session.prop_at_id(trunk).sidewalkPoints.size()==count_trunk+1)
	var moved_before:=Session.sidewalk_world_points(session.prop_at_id(t_branch))[0]
	var trunk_center:=Vector2(float(session.prop_at_id(trunk).x),float(session.prop_at_id(trunk).y))
	check("moving_whole_sidewalk_keeps_connected_branches_attached",
		session.move_prop(trunk,trunk_center+Vector2(10,10),0) and
		near(Session.sidewalk_world_points(session.prop_at_id(t_branch))[0],
			moved_before+Vector2(10,10)))
	check("path_attachments_survive_json_save_and_reload",
		session._valid_source(JSON.parse_string(JSON.stringify(session.doc))) and
		JSON.stringify(session.doc.roads)==previous_roads)
	check("sidewalk_points_outside_world_are_rejected",
		session.add_sidewalk([Vector2(-1,2000),Vector2(40,2000)]).is_empty())
	check("sidewalk_overlap_does_not_create_invalid_half_meter_segments",
		session.add_sidewalk([Vector2(2000,2200),Vector2(2000.2,2200)]).is_empty())
	var display: Array[Dictionary]=[
		{"kind":"sidewalk","seed":1,"editor_source_id":"a","p":[100.0,100.0],
		 "angle":0.0,"sidewalk_width":3.0,"sidewalk_scale":[1.0,1.0],
		 "sidewalk_points":[[-20.0,0.0],[0.0,0.0],[20.0,0.0]]},
		{"kind":"sidewalk","seed":2,"editor_source_id":"b","p":[100.0,100.0],
		 "angle":0.0,"sidewalk_width":3.0,"sidewalk_scale":[1.0,1.0],
		 "sidewalk_points":[[0.0,0.0],[0.0,20.0]]}
	]
	var joints: Array[Dictionary]=Scenery.sidewalk_junctions(display)
	check("game_renderer_merges_overlapping_sidewalk_caps_into_one_surface",
		joints.size()==1 and near(Vector2(joints[0].position),Vector2(2000,2000)))
	print("SIDEWALK BRANCH JUNCTIONS: ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
