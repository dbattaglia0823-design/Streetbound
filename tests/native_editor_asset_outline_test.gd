extends SceneTree
## Editor-selection chrome must not leak onto saved or newly placed scenery.
const Gizmos=preload("res://scripts/dev/native_world_editor_gizmos.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)

func _run() -> void:
	var gizmos: Variant=Gizmos.new()
	root.add_child(gizmos)
	var first: Dictionary={"id":"prop-native-0","type":"house","hidden":false}
	var second: Dictionary={"id":"prop-native-1","type":"warehouse","hidden":false}
	var hidden_prop: Dictionary={"id":"prop-native-2","type":"house","hidden":true}
	# Both new and modified scenery are drawn by coast_scenery even when
	# none is selected, but the editor must not draw a box on either.
	gizmos.selected_source_id=""
	check("deselected_new_asset_has_no_outline",not gizmos._show_prop_outline(first))
	check("deselected_other_asset_has_no_outline",not gizmos._show_prop_outline(second))
	gizmos.selected_source_id=str(first.id)
	check("selected_asset_has_outline",gizmos._show_prop_outline(first))
	check("other_placed_asset_has_no_outline",not gizmos._show_prop_outline(second))
	gizmos.selected_source_id=str(second.id)
	check("changing_selection_moves_the_only_outline",not gizmos._show_prop_outline(first) and gizmos._show_prop_outline(second))
	# No dependence on whether the selected object differs from its saved
	# baseline: reopened, unmodified assets must still show selection chrome.
	check("unchanged_saved_asset_can_be_selected",gizmos._show_prop_outline(second))
	gizmos.drag_preview={"kind":"prop","id":str(second.id),"to":Vector2(20,20)}
	check("drag_uses_single_dedicated_outline",not gizmos._show_prop_outline(second))
	gizmos.drag_preview={}
	gizmos.layer_flags.scenery=false
	check("hidden_scenery_layer_has_no_outline",not gizmos._show_prop_outline(second))
	gizmos.layer_flags.scenery=true
	gizmos.selected_source_id=str(hidden_prop.id)
	check("hidden_asset_has_no_outline",not gizmos._show_prop_outline(hidden_prop))
	gizmos.selected_source_id=str(first.id)
	gizmos.runtime_playtest=true
	check("test_drive_has_no_editor_boxes",not gizmos._show_prop_outline(first))
	gizmos.runtime_playtest=false
	gizmos.selected_source_id=""
	check("clearing_selection_removes_all_boxes",not gizmos._show_prop_outline(first) and not gizmos._show_prop_outline(second))
	gizmos.queue_free()
	await process_frame
	print("NATIVE EDITOR ASSET OUTLINES: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
