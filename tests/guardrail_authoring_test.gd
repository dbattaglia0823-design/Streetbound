extends SceneTree
## Guardrail authoring, undo/redo, source bounds, chunk ownership and
## vehicle-blocking physics use the real source session and Godot shapes.
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const PathTools=preload("res://scripts/dev/sidewalk_topology.gd")
const Guardrail=preload("res://scripts/world/guardrail_geometry.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,str(detail)])
	if not ok:failures.append(label)

func run() -> void:
	var session=Session.new()
	check("loads_existing_source",session.load_source(),session.last_error)
	if session.doc.is_empty():
		quit(1)
		return
	var roads_before: int=session.doc.roads.size()
	var props_before: int=session.doc.props.size()
	var points: Array[Vector2]=[Vector2(300,300),Vector2(340,300),Vector2(370,330)]
	var guard_id: String=session.add_guardrail(points,.65)
	check("draw_like_roads_creates_one_editable_path",not guard_id.is_empty() and
		session.doc.props.size()==props_before+1 and session.doc.roads.size()==roads_before)
	var prop: Dictionary=session.prop_at_id(guard_id)
	check("guardrail_has_real_width_and_three_control_points",
		str(prop.get("type",""))=="guardrail" and
		is_equal_approx(float(prop.get("guardrailWidth",0)),.65) and
		(prop.get("guardrailPoints",[]) as Array).size()==3)
	var geometry: Array[Vector2]=PathTools.world_points(prop)
	check("authored_rail_points_roundtrip_in_world_metres",
		geometry.size()==3 and geometry[0].distance_to(points[0])<.001 and
		geometry[2].distance_to(points[2])<.001)
	check("path_anchor_reshapes_without_changing_roads",
		session.move_sidewalk_point(guard_id,1,Vector2(342,314)) and
		session.doc.roads.size()==roads_before,session.last_error)
	geometry=PathTools.world_points(session.prop_at_id(guard_id))
	check("rail_anchor_changes_saved_geometry",
		geometry[1].distance_to(Vector2(342,314))<.001,geometry)
	check("undo_restores_prior_guardrail_path",session.undo() and
		PathTools.world_points(session.prop_at_id(guard_id))[1].distance_to(points[1])<.001)
	check("redo_restores_guardrail_handle",session.redo() and
		PathTools.world_points(session.prop_at_id(guard_id))[1].distance_to(Vector2(342,314))<.001)
	var duplicate_id: String=session.duplicate_entity(guard_id)
	check("duplicate_retains_independent_solid_path",
		not duplicate_id.is_empty() and
		(session.prop_at_id(duplicate_id).get("guardrailPoints",[]) as Array).size()==3)
	var before_count: int=session.doc.props.size()
	check("rejects_out_of_bounds_guardrails",
		session.add_guardrail([Vector2(-5,20),Vector2(50,20)],.65).is_empty() and
		session.doc.props.size()==before_count)
	check("rejects_invalid_guardrail_width",
		session.add_guardrail(points,3.0).is_empty() and
		session.doc.props.size()==before_count)
	var serialized: Variant=JSON.parse_string(JSON.stringify(session.doc))
	check("saved_source_keeps_guardrail_geometry",
		serialized is Dictionary and
		(serialized.get("props",[]) as Array).size()==session.doc.props.size())
	var ground_id: String=""
	for road in session.doc.roads:
		if Session.AutoRails.ground(road):ground_id=str(road.id);break
	check("ground road available",not ground_id.is_empty())
	if not ground_id.is_empty():
		check("road linked left and right ranges",session.set_auto_guardrails(ground_id,{"left":[10,70],"right":[0,100]}),session.last_error)
		check("reject reversed range",not session.set_auto_guardrails(ground_id,{"left":[80,20]}))
		check("remove road linked rails",session.set_auto_guardrails(ground_id,{}))
		check("undo restores ranges",session.undo() and session.road_at_id(ground_id).has("autoGuardrails"))
		check("redo removes ranges",session.redo() and not session.road_at_id(ground_id).has("autoGuardrails"))
	var owner_a:=StaticBody2D.new()
	owner_a.collision_layer=1
	owner_a.collision_mask=0
	root.add_child(owner_a)
	var owner_b:=StaticBody2D.new()
	owner_b.collision_layer=1
	owner_b.collision_mask=0
	root.add_child(owner_b)
	var across:=PackedVector2Array([Vector2(180,310),Vector2(210,310)])
	var count_a: int=Guardrail.collision_shapes(owner_a,across,.65,Vector2.ZERO,
		Rect2(Vector2(0,288),Vector2(192,192)))
	var count_b: int=Guardrail.collision_shapes(owner_b,across,.65,Vector2.ZERO,
		Rect2(Vector2(192,288),Vector2(192,192)))
	check("cross_chunk_rails_have_unique_collision_span_owners",
		count_a+count_b==4 and count_a>0 and count_b>0,[count_a,count_b])
	await physics_frame
	var query:=PhysicsRayQueryParameters2D.create(Vector2(185,309)*20.0,
		Vector2(185,311)*20.0)
	query.collision_mask=1
	var hit: Dictionary=root.world_2d.direct_space_state.intersect_ray(query)
	check("guardrail_hitbox_stops_real_vehicle_collision_ray",
		not hit.is_empty() and hit.collider==owner_a,str(hit))
	owner_a.queue_free()
	owner_b.queue_free()
	print("GUARDRAIL AUTHORING: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
