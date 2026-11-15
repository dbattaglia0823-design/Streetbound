extends SceneTree
## Editing T/Y/X sidewalk branches must keep source props, junction anchors,
## undo/redo safety, and downstream v2 map serialization intact.
const Session = preload("res://scripts/dev/native_map_edit_session.gd")
const Paths = preload("res://scripts/dev/sidewalk_topology.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL",label])
	if not okay:
		failures.append(label)

func _at(item: Dictionary, index: int) -> Vector2:
	var points: Array[Vector2]=Paths.world_points(item)
	return points[index]

func _run() -> void:
	var session=Session.new()
	check("source_is_valid_before_edit",session.load_source())
	if session.doc.is_empty():
		quit(1)
		return
	var previous_count: int=session.doc.props.size()
	var trunk_id: String=session.add_sidewalk([
		Vector2(3100,3050),Vector2(3200,3050)],3.0)
	check("sidewalk_trunk_created",not trunk_id.is_empty() and
		session.doc.props.size()==previous_count+1)
	var branch_id: String=session.add_sidewalk([
		Vector2(3153,3052),Vector2(3153,3120)],2.5)
	var trunk: Dictionary=session.prop_at_id(trunk_id)
	var branch: Dictionary=session.prop_at_id(branch_id)
	var corner: Vector2=_at(branch,0)
	check("new_branch_snaps_to_middle_of_trunk",
		Paths.world_points(trunk).any(func(p: Vector2)->bool:
			return p.distance_to(corner)<.01) and
		absf(corner.y-3050)<.01 and
		corner.x >= 3150 and corner.x <= 3156)
	check("T_junction_preserves_independent_editable_paths",
		session.doc.props.size()==previous_count+2 and
		trunk.sidewalkPoints.size()==3 and branch.sidewalkPoints.size()==2)
	var third_id: String=session.add_sidewalk([
		Vector2(3148,3053),Vector2(3075,3120)],2.0)
	var third: Dictionary=session.prop_at_id(third_id)
	check("Y_branch_joins_shared_trunk_without_erasing_other_branch",
		session.doc.props.size()==previous_count+3 and
		Paths.junctions(session.doc.props).size()>=1 and
		not third.is_empty())
	var before_undo: Dictionary=session.doc.duplicate(true)
	check("undo_removes_only_last_branch",
		session.undo() and session.prop_at_id(third_id).is_empty() and
		not session.prop_at_id(branch_id).is_empty())
	check("redo_recovers_sidewalk_branches_identically",
		session.redo() and session.doc==before_undo)
	# Moving the parent anchor must move its attached branch end as well.
	trunk=session.prop_at_id(trunk_id)
	var anchor_index: int=-1
	for i in trunk.sidewalkPoints.size():
		if _at(trunk,i).distance_to(corner)<.01:anchor_index=i
	check("explicit_T_junction_anchor_created",anchor_index>=0)
	var shifted:=corner+Vector2(0,6)
	check("dragging_shared_anchor_keeps_T_junction_connected",
		session.move_sidewalk_point(trunk_id,anchor_index,shifted,0.0) and
		_at(session.prop_at_id(branch_id),0).distance_to(shifted)<.01 and
		_at(session.prop_at_id(trunk_id),anchor_index).distance_to(shifted)<.01)
	check("undo_rejoins_original_junction",
		session.undo() and _at(session.prop_at_id(branch_id),0).distance_to(corner)<.01)
	check("Alt_detach_moves_only_selected_branch",
		session.move_sidewalk_point(branch_id,0,corner+Vector2(8,0),0.0,false) and
		_at(session.prop_at_id(trunk_id),anchor_index).distance_to(corner)<.01 and
		_at(session.prop_at_id(branch_id),0).distance_to(corner)>5.0)
	# A walk crossing another with neither tip touching should form an X.
	var crossing_parent: String=session.add_sidewalk([
		Vector2(3500,3250),Vector2(3600,3250)],3.0)
	var crossing_child: String=session.add_sidewalk([
		Vector2(3550,3200),Vector2(3550,3300)],2.5)
	var parent_path: Array[Vector2]=Paths.world_points(session.prop_at_id(crossing_parent))
	var child_path: Array[Vector2]=Paths.world_points(session.prop_at_id(crossing_child))
	check("X_crossing_has_explicit_shared_vertex",
		parent_path.size()==3 and child_path.size()==3 and
		parent_path[1].distance_to(Vector2(3550,3250))<.01 and
		child_path[1].distance_to(Vector2(3550,3250))<.01)
	check("crossings_are_not_traffic_roads",
		session.doc.roads.size()==session.initial.roads.size())
	check("sidewalk_edited_world_remains_valid",session._valid_source(session.doc))
	var encoded:=JSON.stringify(session.doc)
	var decoded=JSON.parse_string(encoded)
	check("junctions_survive_world_v2_serialization",
		decoded is Dictionary and session._valid_source(decoded) and
		Paths.junctions(decoded.props).size()>=2)
	check("all_added_footpaths_are_undoable",
		session.dirty and session.undo())
	print("BRANCHING SIDEWALK PATHS: ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
