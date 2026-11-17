extends SceneTree
## Prevent 1 m quantization from making authored building footprints overlap.
const Snap=preload("res://scripts/dev/building_snap.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

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
	var other: Dictionary={"p":Vector2.ZERO,"size":Vector2(12,17),"angle":0.0}
	var neighbors: Array=[other]
	check("touching_footprints_require_clearance",
		not Snap.has_clearance(Vector2(12,0),Vector2(12,17),0,neighbors))
	var fixed: Dictionary=Snap.resolve(Vector2(12,0),Vector2(12,17),0,neighbors)
	check("grid_overlap_is_pushed_to_safe_edge",
		bool(fixed.valid) and Snap.has_clearance(Vector2(fixed.position),Vector2(12,17),0,neighbors),
		fixed)
	check("correction_does_not_jump_far_from_cursor",
		Vector2(fixed.position).distance_to(Vector2(12,0))<.3)
	check("deep_overlap_rejected_instead_of_teleport",
		not bool(Snap.resolve(Vector2.ZERO,Vector2(12,17),0,neighbors).valid))
	var turn:=PI/4.0
	var rotated: Dictionary={"p":Vector2.ZERO,"size":Vector2(12,17),"angle":turn}
	var angle_pos:=Vector2.RIGHT.rotated(turn)*12.0
	var diagonal: Dictionary=Snap.resolve(angle_pos,Vector2(12,17),turn,[rotated])
	check("rotated_footprints_test_actual_sat_edges",
		bool(diagonal.valid) and Snap.has_clearance(Vector2(diagonal.position),Vector2(12,17),turn,[rotated]))
	check("already_clear_buildings_do_not_move",
		Snap.resolve(Vector2(30,0),Vector2(12,17),0,neighbors).position==Vector2(30,0))
	var folder: String="res://.runtime/building-clearance-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH",folder+"/draft.json")
	var scene: Node=load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(scene)
	for i in 8:await process_frame
	var e: Variant=scene.native_world_editor
	e.map_switcher.map_name.text="Building clearance validation"
	e.map_switcher.width.value=1200
	e.map_switcher.height.value=1000
	e.map_switcher.create_map(e)
	var first: String=place(e,Vector2(300,200))
	var second: String=place(e,Vector2(312.3,200))
	var first_prop: Dictionary=e.authoring.prop_at_id(first)
	var second_prop: Dictionary=e.authoring.prop_at_id(second)
	var size: Vector2=e.gizmos._prop_size(first_prop)/20.0
	check("new_building_is_created",not first_prop.is_empty() and not second_prop.is_empty())
	var first_neighbor: Array=[{"p":at(first_prop),"size":size,"angle":0.0}]
	check("placement_avoids_one_m_grid_overlap",
		Snap.has_clearance(at(second_prop),size,deg_to_rad(float(second_prop.rotation)),first_neighbor),
		[at(first_prop),at(second_prop)])
	check("building_alignment_preserves_small_street_gap",
		at(second_prop).distance_to(Vector2(312.02,200))<.05,at(second_prop))
	# Multi-object operations must not sidestep building clearance.
	# Inspector-style transformations and toolbar nudges must not let a
	# previously clear building expand or rotate through its neighbor.
	e._choose_tool("move_prop")
	e.source_id=first
	e._refresh_authoring()
	var original_count: int=e.authoring.history.size()
	e._resize_selected(1.2)
	check("resize_does_not_expand_through_neighbor",
		is_equal_approx(float(e.authoring.prop_at_id(first).scale),1.0) and
		e.authoring.history.size()==original_count)
	e._rotate_selected(45)
	check("rotation_rejects_overlapping_wall",
		is_equal_approx(float(e.authoring.prop_at_id(first).rotation),0.0) and
		e.authoring.history.size()==original_count)
	var one_selected: Array[String]=[second]
	e._set_multi(one_selected)
	var prior_group_history: int=e.authoring.history.size()
	check("group_move_rejects_colliding_footprint",
		not e._group_action("move",Vector2(-12,0)) and
		at(e.authoring.prop_at_id(second)).distance_to(Vector2(312.02,200))<.05 and
		e.authoring.history.size()==prior_group_history)
	var cleared_group: Array[String]=[]
	e._set_multi(cleared_group)
	var previous_count: int=e.authoring.doc.props.size()
	var bad: String=place(e,Vector2(301,200))
	check("impossible_placement_is_rejected_atomically",
		bad.is_empty() and e.authoring.doc.props.size()==previous_count)
	# A move that tries to occupy an existing building must leave the
	# source and its undo state intact, even when preview is invalid.
	e._choose_tool("move_prop")
	e.source_id=second
	e._refresh_authoring()
	var old_pos: Vector2=at(e.authoring.prop_at_id(second))
	var old_history: int=e.authoring.history.size()
	e.pending_drag={"kind":"prop","id":second,"from":old_pos*20,
		"to":old_pos*20,"grab":old_pos*20}
	e._refresh_authoring()
	e._update_drag_preview(at(first_prop)*20)
	check("invalid_drag_shows_collision_preview",bool(e.pending_drag.get("invalid",false)))
	e._finish_source_drag(at(first_prop)*20)
	check("invalid_drag_preserves_original_position_and_undo",
		at(e.authoring.prop_at_id(second)).distance_to(old_pos)<.001 and
		e.authoring.history.size()==old_history)
	# Duplicates must also respect clearance, not simply offset by 12 m.
	e.source_id=second
	e._refresh_authoring()
	e._duplicate_selected()
	var copied: Dictionary=e.authoring.prop_at_id(e.source_id)
	check("duplicate_does_not_overlap_parent",
		not copied.is_empty() and Snap.has_clearance(at(copied),size,
			deg_to_rad(float(copied.rotation)),
			[{"p":old_pos,"size":size,"angle":deg_to_rad(float(second_prop.rotation))}]),
		copied.get("id",""))
	check("duplicate_does_not_overlap_other_nearby_building",
		not copied.is_empty() and Snap.has_clearance(at(copied),size,
			deg_to_rad(float(copied.rotation)),first_neighbor))
	e._discard_draft()
	scene.queue_free()
	await process_frame
	print("BUILDING CLEARANCE SNAPPING: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
