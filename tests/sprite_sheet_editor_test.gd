extends SceneTree
const Art=preload("res://scripts/world/coast_art.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/sprite-sheets/recovery.json")
	OS.set_environment("STREETBOUND_MAP_LIBRARY","res://.runtime/sprite-sheets/maps")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/sprite-sheets"))
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 8:await process_frame
	var e=scene.native_world_editor
	var sprites: Array=e.asset_entries.filter(func(item):return item.get("region",[]).size()==4 and "/Sprite Sheets/" in str(item.get("path","")))
	check("six_supplied_sheets_expose_271_individual_sprites",sprites.size()==271)
	check("atlas_regions_match_actual_texture_dimensions",sprites.all(func(item):return item.texture is AtlasTexture and item.texture.filter_clip and item.texture.get_width()==item.region[2] and item.texture.get_height()==item.region[3]))
	check("raw_full_sheets_are_not_in_the_placement_palette",not e.asset_entries.any(func(item):return "/Sprite Sheets/" in str(item.get("path","")) and item.get("region",[]).is_empty()))
	e._choose_tool("place:house");e.asset_category.select(8);e._filter_assets()
	check("sprite_sheet_filter_lists_only_individual_crops",e.asset_grid.get_child_count()==271)
	e.map_switcher.map_name.text="Sprite sheet props";e.map_switcher.width.value=1800;e.map_switcher.height.value=1200;e.map_switcher.create_map(e)
	var names: Array[String]=["Wooden pallet upright","Blue steel drum","Traffic cone tall","Fuel island red single","Parked excavator","Garden shed","Palm tree canopy","Grey rock large","Oil stain rainbow"]
	var expected: Array=[]
	for i in names.size():
		var entry: Dictionary={}
		for item in sprites:
			if item.name==names[i]:entry=item;break
		if entry.is_empty():check("find_"+names[i],false);continue
		e._select_asset(entry);e._source_click(Vector2(450+(i%3)*45,300+(i/3)*45)*20)
		var prop: Dictionary=e.authoring.prop_at_id(e.source_id)
		check("place_"+names[i],not prop.is_empty() and prop.assetRegion==entry.region and prop.assetId==entry.project_id and prop.type==entry.kind and Vector2(prop.assetSize[0],prop.assetSize[1]).is_equal_approx(Vector2(entry.world_size[0],entry.world_size[1])))
		expected.append({"id":prop.id,"path":entry.path,"region":entry.region,"asset_id":entry.project_id,"collision":entry.collision,"type":entry.kind,"size":entry.world_size})
	check("same_sheet_sprites_keep_separate_saved_ids",e.authoring.doc.props[0].assetPath==e.authoring.doc.props[1].assetPath and e.authoring.doc.props[0].assetId!=e.authoring.doc.props[1].assetId)
	var selected: String=expected[0].id;e._choose_tool("move_prop");e.source_id=selected;e._refresh_authoring()
	e.inspector_scale_x.value=1.2;e.inspector_scale_y.value=.8;e.inspector_rotation.value=25
	e.source_id="";e._refresh_authoring();e.source_id=selected;e._refresh_authoring()
	check("reselecting_keeps_crop_size_and_rotation",e.authoring.prop_at_id(selected).assetRegion==expected[0].region and is_equal_approx(e.inspector_scale_x.value,1.2) and is_equal_approx(e.inspector_rotation.value,25))
	check("runtime_crop_cache_preserves_region_identity",Art.project_sprite(expected[0].path,expected[0].region).get_size()==Vector2(expected[0].region[2],expected[0].region[3]) and Art.project_sprite(expected[0].path,expected[0].region)!=Art.project_sprite(expected[1].path,expected[1].region))
	check("solid_props_have_colliders_and_decals_and_foliage_do_not",expected.all(func(item):
		var exists: bool=e.gizmos.preview_body.get_children().any(func(node):return str(node.get_meta("draft_prop_id",""))==str(item.id))
		return exists==(item.collision=="solid")))
	check("cropped_assets_survive_map_save_and_reload",e.map_switcher.save_current(e) and e.authoring._fingerprint(Library.load_map(e.map_switcher.current_file))==e.authoring._fingerprint(e.authoring.doc))
	var output=FileAccess.open("res://.runtime/sprite-sheets/source.json",FileAccess.WRITE);output.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));output.close()
	output=FileAccess.open("res://.runtime/sprite-sheets/expected.json",FileAccess.WRITE);output.store_string(JSON.stringify(expected));output.close()
	if DisplayServer.get_name()!="headless":
		e.editor_camera.position=Vector2(490,350)*20;e.editor_camera.zoom=Vector2.ONE*.18;e._position_camera_canvas();e._update_view(true)
		e._choose_tool("place:house");e.asset_category.select(8);e.asset_search.text="pallet";e._filter_assets()
		for i in 15:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://.runtime/sprite-sheets/editor.png")
	e.map_switcher.restore(e);e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("SPRITE SHEET EDITOR: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
