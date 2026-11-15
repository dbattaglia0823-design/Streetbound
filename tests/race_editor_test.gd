extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/race-editor-test"))
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/race-editor-test/recovery.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.runtime/race-editor-test/recovery.json"))
	var archive_hash:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor;var form=e.race_editor
	form.begin_route(e);form.title.text="Laurel Editor Circuit";form.mode.select(1);form.laps.value=3
	e.draft_points.assign([Vector2(2500,3200),Vector2(2485,3080),Vector2(2500,2870)])
	e._update_context_panels();check("race_drawing_has_finish_control",not e.finish_button.disabled and form.panel.visible)
	e._finish_shape()
	var id: String=e.source_id;var race: Dictionary=e.authoring.race_at_id(id)
	check("editor_creates_named_circuit_with_laps",not race.is_empty() and race.name=="Laurel Editor Circuit" and race.mode=="circuit" and int(race.laps)==3)
	e._choose_tool("move_prop");e.source_id=id;e.source_anchor=1;e._refresh_authoring()
	check("race_has_checkpoint_picker_and_settings",e.point_picker.visible and not e.split_road_button.visible and form.panel.visible and e.point_picker.item_count==4)
	e._add_point();check("add_checkpoint_changes_race_only",e.authoring.race_at_id(id).points.size()==4)
	e._undo();check("checkpoint_add_is_undoable",e.authoring.race_at_id(id).points.size()==3)
	e.source_anchor=1;e._refresh_authoring()
	var old: Dictionary=e.authoring.race_at_id(id).duplicate(true)
	e.inspector_x.value=float(old.points[1].x)+2
	check("checkpoint_coordinates_move_one_gate",e.authoring.race_at_id(id).points[0]==old.points[0] and is_equal_approx(float(e.authoring.race_at_id(id).points[1].x),float(old.points[1].x)+2))
	e._undo()
	var copy: String=e.authoring.duplicate_entity(id)
	check("race_duplicate_and_delete_are_supported",not copy.is_empty() and e.authoring.delete_entity(copy) and e.authoring.doc.races.size()==1)
	e.source_id=id;e.source_anchor=-1;e._refresh_authoring()
	var found:=false
	for i in e.entity_list.item_count:found=found or str(e.entity_list.get_item_metadata(i))==id
	check("race_is_listed_with_world_objects",found)
	var file=FileAccess.open("res://.runtime/race-editor-test/source.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));file.close()
	var restored=e.authoring.get_script().new();check("race_source_can_be_reopened",restored.load_source("res://.runtime/race-editor-test/source.json") and restored.doc.races[0].name==race.name)
	var stamp:=JSON.stringify(e.authoring.doc)
	var bad: Array[Vector2]=[Vector2(2000,2000),Vector2(2001,2000)]
	check("invalid_race_does_not_modify_draft",e.authoring.save_race(bad,{"name":"Bad","mode":"sprint"}).is_empty() and stamp==JSON.stringify(e.authoring.doc))
	for i in 3:await process_frame
	check("race_controls_fit_in_settings_sidebar",e.settings_panel.get_rect().end.x<=e.canvas_rect.position.x)
	if DisplayServer.get_name()!="headless":
		e.editor_camera.global_position=Vector2(2490,3080)*20;e.editor_camera.zoom=Vector2.ONE*.13;e._position_camera_canvas();e._update_view(true)
		for i in 6:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://.runtime/race-editor-test/editor.png")
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	check("race_editor_does_not_write_playable_archive",FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==archive_hash)
	print("RACE EDITOR: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
