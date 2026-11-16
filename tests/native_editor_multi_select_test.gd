extends SceneTree
const Multi=preload("res://scripts/dev/native_editor_multiselect.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func _run() -> void:
	var session: Variant=Session.new()
	if not session.load_source():
		print("NATIVE MULTI SELECT: FAIL source not loaded")
		quit(1);return
	var a: String=session.add_prop("house",Vector2(2300,3200))
	var b: String=session.add_prop("house",Vector2(2310,3200))
	var c: String=session.add_prop("house",Vector2(2450,3200))
	var box:=Rect2(Vector2(2280,3170),Vector2(60,60))
	var selected: Array[String]=Multi.within_rect(session.doc,box,{"scenery":true,"roads":false,"terrain":false,"markers":false})
	check("marquee_selects_nearby_assets",selected.has(a) and selected.has(b))
	check("marquee_ignores_distant_assets",not selected.has(c))
	var group: Array[String]=[a,b]
	var history: int=session.history.size()
	var moved: Array[String]=session.batch_entities(group,Vector2(20,10),"move")
	check("two_objects_move_in_one_undo_step",moved.size()==2 and session.history.size()==history+1)
	check("group_move_keeps_relative_spacing",absf(float(session.prop_at_id(a).x)-float(session.prop_at_id(b).x))<10.01)
	check("one_undo_restores_both_positions",session.undo() and is_equal_approx(float(session.prop_at_id(a).x),2300.0) and is_equal_approx(float(session.prop_at_id(b).x),2310.0))
	session.redo()
	var before: int=session.doc.props.size()
	var duplicate: Array[String]=session.batch_entities(group,Vector2(12,12),"duplicate")
	check("group_duplicate_assigns_unique_ids",duplicate.size()==2 and duplicate[0]!=duplicate[1] and not duplicate.has(a))
	check("group_duplicate_preserves_relative_offset",duplicate.size()==2 and is_equal_approx(float(session.prop_at_id(duplicate[0]).x),2332.0))
	check("one_undo_deletes_entire_duplicate_group",session.doc.props.size()==before+2 and session.undo() and session.doc.props.size()==before)
	check("out_of_bounds_group_translation_rejected",session.batch_entities(group,Vector2(-3000,0),"move").is_empty())
	check("failed_translation_leaves_originals_untouched",is_equal_approx(float(session.prop_at_id(a).x),2320.0))
	check("hidden_scenery_layer_not_selectable",Multi.within_rect(session.doc,box,{"scenery":false,"roads":false,"terrain":false,"markers":false}).is_empty())
	var deleted: Array[String]=session.batch_entities(group,Vector2.ZERO,"delete")
	check("delete_group_then_undo_recovers_every_object",deleted.is_empty() and session.doc.props.size()==before-2 and session.undo() and session.doc.props.size()==before)
	print("NATIVE MULTI SELECT: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
