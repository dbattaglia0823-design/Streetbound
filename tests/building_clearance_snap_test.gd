extends SceneTree
## Building authoring accepts intentional overlap, and nearby facades or corners
## snap to exact fractional metre positions instead of the editor grid.
const Snap=preload("res://scripts/dev/building_snap.gd")
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("_run")
func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s %s"%["PASS" if ok else "FAIL",label,str(detail)])
	if not ok:failures.append(label)
func at(prop: Dictionary) -> Vector2:
	return Vector2(float(prop.x),float(prop.y))
func place(e: Variant,pos: Vector2) -> String:
	e._choose_tool("place:house")
	e._source_click(pos*20.0)
	return str(e.source_id)

func _run() -> void:
	var neighbor: Dictionary={"p":Vector2.ZERO,"size":Vector2(12,17),"angle":0.0}
	var neighbors: Array=[neighbor]
	var wall: Dictionary=Snap.match(Vector2(12.35,0.4),Vector2(12,17),0,neighbors)
	check("wall_join_aligns_centres_without_gap",not wall.is_empty() and
		Vector2(wall.position).distance_to(Vector2(12,0))<.001,wall)
	var corner: Dictionary=Snap.match(Vector2(12.4,17.35),Vector2(12,17),0,neighbors)
	check("corner_to_corner_snapping_hits_exact_anchor",not corner.is_empty() and
		Vector2(corner.position).distance_to(Vector2(12,17))<.001,corner)
	check("deep_overlap_does_not_force_separation",
		Snap.match(Vector2(1,2),Vector2(12,17),0,neighbors).is_empty())
	var turn: float=PI/5.0
	var oriented: Dictionary={"p":Vector2(20,20),"size":Vector2(12,17),"angle":turn}
	var exact: Vector2=Vector2(20,20)+Vector2(12,0).rotated(turn)
	var rotated: Dictionary=Snap.match(exact+Vector2(.2,.35),Vector2(12,17),turn,[oriented])
	check("rotated_roofs_join_at_exact_angles",not rotated.is_empty() and
		Vector2(rotated.position).distance_to(exact)<.001,rotated)
	var folder: String="res://.runtime/building-overlap-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH",folder+"/draft.json")
	var scene: Node=load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(scene)
	for i in 8:await process_frame
	var e: Variant=scene.native_world_editor
	e.map_switcher.map_name.text="Building overlap validation"
	e.map_switcher.width.value=1200
	e.map_switcher.height.value=1000
	e.map_switcher.create_map(e)
	var first: String=place(e,Vector2(300,200))
	check("first_building_is_created",not first.is_empty())
	# Existing assets may be placed with fractional coordinates through the
	# inspector. A matching wall must retain those exact values despite grid on.
	e.authoring.edit_entity(first,{},Vector2(300.25,200.35))
	e._refresh_authoring()
	var second: String=place(e,Vector2(312.65,200.75))
	var first_prop: Dictionary=e.authoring.prop_at_id(first)
	var second_prop: Dictionary=e.authoring.prop_at_id(second)
	check("neighbor_snaps_exactly_despite_enabled_grid",not second_prop.is_empty() and
		at(second_prop).distance_to(Vector2(312.25,200.35))<.001,
		[at(first_prop),at(second_prop),e.snap_m])
	var size: Vector2=e.gizmos._prop_size(first_prop)/20.0
	check("new_buildings_touch_wall_without_forced_clearance",
		is_equal_approx(at(second_prop).distance_to(at(first_prop)),size.x),
		[at(first_prop),at(second_prop)])
	# Nearby but non-exact placement should pull to both corner coordinates.
	var candidate: Dictionary=e._snap_building_transform(first_prop,Vector2(324.7,217.65))
	check("corner_snap_bypasses_grid_rounding",bool(candidate.valid) and
		Vector2(candidate.position).distance_to(Vector2(324.25,217.35))<.01,candidate)
	# Explicitly overlapping buildings can be created, resized and rotated.
	var overlap_id: String=place(e,Vector2(300.25,200.35))
	var overlapped: Dictionary=e.authoring.prop_at_id(overlap_id)
	check("deep_overlap_placement_is_allowed",not overlapped.is_empty() and
		at(overlapped).distance_to(at(first_prop))<2.0)
	e._choose_tool("move_prop");e.source_id=first;e._refresh_authoring()
	var previous_history: int=e.authoring.history.size()
	e._resize_selected(1.2)
	check("resizing_through_another_building_is_allowed",
		is_equal_approx(float(e.authoring.prop_at_id(first).scale),1.2) and
		e.authoring.history.size()==previous_history+1)
	e._rotate_selected(45)
	check("rotation_through_other_buildings_is_allowed",
		is_equal_approx(float(e.authoring.prop_at_id(first).rotation),45.0))
	# Inspector sizing and rotation also use the same overlap-permissive path.
	e.inspector_scale_x.value=1.4
	check("inspector_scale_does_not_reject_overlap",
		is_equal_approx(float(e.authoring.prop_at_id(first).get("scaleX",1.0)),1.4))
	e._reset_asset_size()
	check("resetting_size_does_not_reject_overlap",
		is_equal_approx(float(e.authoring.prop_at_id(first).scale),1.0))
	# Dragging and grouped operations may move a second footprint onto another.
	e._choose_tool("move_prop");e.source_id=second;e._refresh_authoring()
	var old_pos: Vector2=at(e.authoring.prop_at_id(second))
	var origin: Vector2=old_pos*20.0
	e.pending_drag={"kind":"prop","id":second,"from":origin,"to":origin,"grab":origin}
	e._refresh_authoring()
	e._update_drag_preview(at(first_prop)*20.0)
	check("overlapping_drag_preview_is_not_invalid",not bool(e.pending_drag.get("invalid",true)))
	e._finish_source_drag(at(first_prop)*20.0)
	check("dragging_building_over_another_is_allowed",
		at(e.authoring.prop_at_id(second)).distance_to(at(first_prop))<2.0)
	e._set_multi([second])
	check("group_move_can_overlap_buildings",e._group_action("move",Vector2(1,0)))
	e._set_multi([])
	e.source_id=second;e._refresh_authoring()
	var previous_count: int=e.authoring.doc.props.size()
	e._duplicate_selected()
	check("overlapping_duplicate_is_allowed",
		e.authoring.doc.props.size()==previous_count+1 and
		not e.authoring.prop_at_id(e.source_id).is_empty())
	e._undo()
	check("overlap_duplicate_is_undoable",e.authoring.doc.props.size()==previous_count)
	e._discard_draft()
	scene.queue_free()
	await process_frame
	print("BUILDING CLEARANCE SNAPPING: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
