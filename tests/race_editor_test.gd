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
	check("race_setup_opens_automatically_after_placement",form.dialog_race_id==id and form.dialog.visible)
	for i in 4:await process_frame
	var available: Vector2=e.get_viewport().get_visible_rect().size
	var target: Vector2i=form.dialog_target_size(available)
	check("race_dialog_targets_compact_viewport_size",
		form.dialog_target_size(Vector2(1920,1080))==Vector2i(980,620) and
		form.dialog_target_size(Vector2(800,600))==Vector2i(720,516))
	check("race_dialog_fits_parent_viewport",
		form.dialog.size.x<=maxi(target.x,int(available.x)) and
		form.dialog.size.y<=maxi(target.y,int(available.y)))
	var pages_scrollable:=true
	for tab in form.dialog_tabs.get_children():
		if not tab is ScrollContainer or tab.vertical_scroll_mode!=ScrollContainer.SCROLL_MODE_AUTO:
			pages_scrollable=false
	check("race_tabs_scroll_independently_with_fixed_save_footer",
		pages_scrollable and not form.dialog_tabs.is_ancestor_of(form.dialog_save_button) and
		form.dialog_save_button.is_visible_in_tree() and form.dialog.get_ok_button().is_visible_in_tree())

	form.dialog_type.select(1)
	form.dialog_opponents.value=3
	form.dialog_cash.value=12500
	form.dialog_driver_xp.value=275
	form.dialog_car_xp.value=150
	var tab_titles: Array[String]=[]
	for index in form.dialog_tabs.get_tab_count():
		tab_titles.append(form.dialog_tabs.get_tab_title(index))
	check("race_editor_has_multiplayer_rewards_tab_and_default_controls",
		tab_titles.has("Race Setup") and tab_titles.has("Career & Unlocks") and
		tab_titles.has("Underground & Stakes") and tab_titles.has("Multiplayer Rewards") and
		not form.online_use_custom.button_pressed and not form.online_cash.editable)
	# Exercise the actual shortcut button: the new Underground tab displaced
	# the old multiplayer index, so index-based navigation opened the wrong page.
	form.multiplayer_rewards_button.pressed.emit()
	check("multiplayer_rewards_shortcut_opens_correct_tab",
		form.dialog_tabs.get_tab_title(form.dialog_tabs.current_tab)=="Multiplayer Rewards")
	form.dialog_tabs.current_tab=0
	check("multiplayer_reward_inputs_have_no_gameplay_caps",
		form.online_cash.max_value>=1000000000 and
		form.online_driver_xp.max_value>=1000000000 and
		form.online_car_xp.max_value>=1000000000)
	form.online_use_custom.button_pressed=true
	form.online_cash.value=250000000
	form.online_driver_xp.value=2800000
	form.online_car_xp.value=1600000
	form.online_part_chance.value=25
	form._update_online_rewards()
	check("multiplayer_rewards_preview_first_place_and_part_chance",
		form.online_cash.editable and
		form.online_preview.text.contains("$250,000,000") and
		form.online_preview.text.contains("25% PART"))
	form.pool_search.text="Audi RS3";form._refresh_pool()
	var audi_found:=false
	for i in form.pool_list.item_count:
		if str(form.pool_list.get_item_metadata(i))=="audi-rs3":
			form._pool_selected(i,true);audi_found=true;break
	form.pool_search.text="Acura Integra";form._refresh_pool()
	var acura_found:=false
	for i in form.pool_list.item_count:
		if str(form.pool_list.get_item_metadata(i))=="acura-integra":
			form._pool_selected(i,true);acura_found=true;break
	check("race_pool_search_keeps_selection_across_filters",audi_found and acura_found and form.selected_pool.size()==2)
	var history_before: int=e.authoring.history.size()
	form._save_dialog(e)
	var configured: Dictionary=e.authoring.race_at_id(id)
	var saved_ok: bool=e.authoring.history.size()==history_before+1 and configured.enemy_starts.size()==3 and \
		configured.get("opponent_pool",[]).has("audi-rs3") and configured.get("opponent_pool",[]).has("acura-integra") and \
		int(configured.get("reward_cash",0))==12500 and int(configured.get("reward_player_xp",0))==275 and int(configured.get("reward_car_xp",0))==150 and \
		bool(configured.get("multiplayer_reward_custom",false)) and int(configured.get("multiplayer_reward_cash",0))==250000000 and \
		int(configured.get("multiplayer_reward_player_xp",0))==2800000 and int(configured.get("multiplayer_reward_car_xp",0))==1600000 and \
		int(configured.get("multiplayer_reward_part_chance",0))==25
	if not saved_ok:
		print("RACE SAVE AUDIT: history ",history_before,"=>",e.authoring.history.size(),
			" rivals=",configured.get("enemy_starts",[]).size()," pool=",configured.get("opponent_pool",[]),
			" payout=",configured.get("reward_cash",-1),"/",configured.get("reward_player_xp",-1),"/",
			configured.get("reward_car_xp",-1)," error=",form.dialog_message.text)
	check("edit_race_saves_pool_enemy_count_and_revenue",saved_ok)
	e._undo()
	check("race_edit_settings_are_undoable",not e.authoring.race_at_id(id).has("opponent_pool") or e.authoring.race_at_id(id).get("opponent_pool",[]).is_empty())
	e._redo()
	form.open_for(e,id)
	check("race_editor_reopens_with_saved_multiplayer_prizes",
		form.online_use_custom.button_pressed and int(form.online_cash.value)==250000000 and
		int(form.online_driver_xp.value)==2800000 and int(form.online_part_chance.value)==25)
	form.dialog_type.select(2)
	form._save_dialog(e)
	check("race_type_time_trial_has_zero_ai",e.authoring.race_at_id(id).enemy_starts.is_empty())
	form.open_for(e,id)
	form.dialog_type.select(1)
	form.dialog_opponents.value=3
	form._save_dialog(e)
	check("race_type_circuit_restores_ai",e.authoring.race_at_id(id).enemy_starts.size()==3)
	form.open_for(e,id)
	form.dialog_type.select(0)
	form._save_dialog(e)
	check("race_type_point_to_point_is_sprint",e.authoring.race_at_id(id).mode=="sprint")
	form.open_for(e,id)
	form.dialog_type.select(1)
	form._save_dialog(e)
	check("race_type_circuit_reloads_and_keeps_rewards",
		e.authoring.race_at_id(id).mode=="circuit" and int(e.authoring.race_at_id(id).reward_cash)==12500)
	check("edit_race_button_available_after_placement",not form.edit_button.disabled)
	e._choose_tool("move_prop");e.source_id=id;e.source_anchor=1;e._refresh_authoring()
	check("race_has_checkpoint_picker_and_settings",e.point_picker.visible and not e.split_road_button.visible and form.panel.visible and e.point_picker.item_count==4)
	var nearest_road: Dictionary=e.authoring.doc.roads[0]
	var sample_path: PackedVector2Array=e._source_road_path(nearest_road)
	var road_at: Vector2=sample_path[sample_path.size()/2]
	var snapped: Vector2=e._road_draw_point(road_at+Vector2(2,3),true,true)
	check("race_checkpoints_snap_to_real_roads",snapped.is_finite() and snapped.distance_to(road_at)<20)
	check("race_rejects_off_road_gate_clicks",not e._road_draw_point(Vector2(1,1),true,true).is_finite())
	e._add_point()
	check("add_checkpoint_activates_road_click_mode",e.tool_name=="race_checkpoint" and e.source_id==id and e.source_anchor==1)
	e._source_click(road_at*20)
	check("mapped_checkpoint_added_in_selected_order",e.authoring.race_at_id(id).points.size()==4 and e.source_anchor==2 and Vector2(e.authoring.race_at_id(id).points[2].x,e.authoring.race_at_id(id).points[2].y).distance_to(road_at)<2)
	e._undo();check("checkpoint_add_is_undoable",e.authoring.race_at_id(id).points.size()==3)
	e._choose_tool("move_prop");e.source_id=id;e.source_anchor=1;e._refresh_authoring()
	var gate_before: Dictionary=e.authoring.race_at_id(id).duplicate(true)
	check("race_start_cannot_be_deleted",not e.authoring.change_race_points(id,0,true) and gate_before==e.authoring.race_at_id(id))
	check("cannot_reorder_race_start",not e.authoring.reorder_race_checkpoint(id,0,1))
	check("race_checkpoint_order_can_change",e.authoring.reorder_race_checkpoint(id,1,1) and e.authoring.race_at_id(id).points[1]==gate_before.points[2])
	e._undo()
	form.competition.select(1);form.change_competition(e)
	check("time_trial_removes_all_AI_opponents",e.authoring.race_at_id(id).get("enemy_starts",[]).is_empty())
	form.competition.select(0);form.change_competition(e);form.opponents.value=4
	check("AI_race_can_have_four_opponents",e.authoring.race_at_id(id).get("enemy_starts",[]).size()==4)
	form.competition.select(1);form.change_competition(e)
	check("race_can_switch_back_to_solo",e.authoring.race_at_id(id).get("enemy_starts",[]).size()==0)
	e.source_anchor=1;e._refresh_authoring()
	var old: Dictionary=e.authoring.race_at_id(id).duplicate(true)
	e.inspector_x.value=0
	check("checkpoint_coordinates_reject_off_road_edits",e.authoring.race_at_id(id).points==old.points)
	check("race_point_edit_is_undoable",e.authoring.move_race_point(id,1,Vector2(float(old.points[1].x)+2,float(old.points[1].y))))
	e._undo()
	var copy: String=e.authoring.duplicate_entity(id)
	check("race_duplicate_and_delete_are_supported",not copy.is_empty() and e.authoring.delete_entity(copy) and e.authoring.doc.races.size()==1)
	e.source_id=id;e.source_anchor=-1;e._refresh_authoring()
	var found:=false
	for i in e.entity_list.item_count:found=found or str(e.entity_list.get_item_metadata(i))==id
	check("race_is_listed_with_world_objects",found)
	var file=FileAccess.open("res://.runtime/race-editor-test/source.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));file.close()
	var restored=e.authoring.get_script().new();check("race_source_can_be_reopened",restored.load_source("res://.runtime/race-editor-test/source.json") and restored.doc.races[0].name==race.name and
		int(restored.doc.races[0].get("multiplayer_reward_cash",0))==250000000)
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
