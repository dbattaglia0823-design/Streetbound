extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/road-edit-audit/asset-recovery.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.runtime/road-edit-audit/asset-recovery.json"))
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor
	var original: Dictionary={}
	for prop in scene.ground.data.props:
		if prop.kind=="house" and not prop.has("authoring_id") and not prop.has("poi") and not prop.get("protected",false):original=prop.duplicate(true);break
	var id: String=e.authoring.adopt_runtime_prop(original)
	check("real_house_can_be_adopted",not id.is_empty())
	e.source_id=id;e._refresh_authoring()
	var draft: Dictionary=e.authoring.prop_at_id(id)
	var preview: Dictionary={}
	for prop in e.gizmos.preview_scenery.prop_list:
		if prop.seed==original.seed:preview=prop
	check("selecting_house_preserves_exact_model_and_dimensions",not preview.is_empty() and preview.kind==original.kind and Vector2(preview.size[0],preview.size[1]).is_equal_approx(Vector2(original.size[0],original.size[1])) and preview.get("asset_kind")==original.get("asset_kind"))
	e.inspector_scale_x.value=.8;e.inspector_scale_y.value=.6
	e._refresh_authoring();draft=e.authoring.prop_at_id(id)
	var size: Vector2=e.gizmos._prop_size(draft)/20.0
	check("independent_xy_resize_is_applied",size.is_equal_approx(Vector2(original.size[0]*.8,original.size[1]*.6)))
	e.source_id="";e._refresh_authoring();e.source_id=id;e._refresh_authoring()
	check("reselection_keeps_model_and_xy_dimensions",e.authoring.prop_at_id(id).sourceAppearance.seed==original.seed and is_equal_approx(e.inspector_scale_x.value,.8) and is_equal_approx(e.inspector_scale_y.value,.6))
	var file=FileAccess.open("res://.runtime/road-edit-audit/asset-source.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));file.close()
	e.authoring.undo();check("axis_resize_supports_undo",is_equal_approx(float(e.authoring.prop_at_id(id).get("scaleY",1)),1))
	e.authoring.redo();check("axis_resize_supports_redo",is_equal_approx(float(e.authoring.prop_at_id(id).scaleY),.6))
	e.authoring.edit_entity(id,{"rotation":12.345,"scale":.783},Vector2(original.p[0],original.p[1]));e._refresh_authoring()
	e.inspector_name.text="Renamed house";e._commit_inspector()
	check("name_or_focus_changes_do_not_round_other_transform_fields",is_equal_approx(float(e.authoring.prop_at_id(id).rotation),12.345) and is_equal_approx(float(e.authoring.prop_at_id(id).scale),.783))
	e._reset_asset_size()
	check("size_reset_preserves_model_rotation_and_position",is_equal_approx(float(e.authoring.prop_at_id(id).scale),1) and is_equal_approx(float(e.authoring.prop_at_id(id).scaleX),1) and is_equal_approx(float(e.authoring.prop_at_id(id).scaleY),1) and is_equal_approx(float(e.authoring.prop_at_id(id).rotation),12.345) and e.authoring.prop_at_id(id).sourceAppearance.seed==original.seed)
	e._undo()
	check("size_reset_is_one_undo_step",is_equal_approx(float(e.authoring.prop_at_id(id).scale),.783) and is_equal_approx(float(e.authoring.prop_at_id(id).scaleX),.8) and is_equal_approx(float(e.authoring.prop_at_id(id).scaleY),.6))
	check("small_fractional_sizes_are_not_rounded_in_inspector",is_equal_approx(e.inspector_scale.value,.783))
	check("all_scenery_footprints_match_the_baker",e.gizmos._prop_size({"type":"field"}).is_equal_approx(Vector2(90,70)*20) and e.gizmos._prop_size({"type":"barrier"}).is_equal_approx(Vector2(3,1)*20))
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("EDITOR ASSET TRANSFORMS: ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
