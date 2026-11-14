extends SceneTree
const Library=preload("res://scripts/dev/native_map_library.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	var folder="res://.runtime/map-library-test-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH",folder+"/draft.json")
	var map_hash:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor;var original=e.authoring;var switcher=e.map_switcher
	switcher.show_create(e)
	check("new_map_opens_size_dialog",switcher.dialog.visible and switcher.width.min_value==600 and switcher.width.max_value==24000)
	switcher.map_name.text="Lake district";switcher.width.value=1200;switcher.height.value=900;switcher.create_map(e);switcher.dialog.hide()
	check("new_map_is_blank_and_correctly_sized",switcher.custom and e.authoring.doc.world.width==1200 and e.authoring.doc.world.height==900 and e.authoring.doc.roads.is_empty() and e.authoring.doc.regions.is_empty() and e.world.data.props.is_empty())
	var first: String=switcher.current_file
	var lake_points: Array[Vector2]=[Vector2.ZERO,Vector2(1200,0),Vector2(1200,900),Vector2(0,900)]
	var island_points: Array[Vector2]=[Vector2(450,300),Vector2(650,300),Vector2(650,500),Vector2(450,500)]
	var lake: String=e.authoring.add_region(lake_points,"lake")
	var island: String=e.authoring.add_region(island_points,"forest")
	e._refresh_authoring()
	check("terrain_can_cover_every_map_edge",not lake.is_empty() and not island.is_empty())
	check("islands_draw_over_water_in_authored_order",switcher.terrain.get_child_count()==3 and switcher.terrain.get_child(1).material.shader==preload("res://scripts/dev/custom_water.gdshader") and switcher.terrain.get_child(2).material.shader==preload("res://scripts/world/mountain_ground.gdshader"))
	check("new_terrain_has_no_morrow_relief_texture",switcher.terrain.land_material.get_shader_parameter("relief").get_image().get_pixel(0,0).a==0)
	check("custom_map_save_is_successful",switcher.save_current(e) and not e.authoring.dirty)
	check("saved_map_can_be_overwritten_atomically",switcher.save_current(e) and Library.load_map(first).regions.size()==2)
	switcher.map_name.text="Desert loop";switcher.width.value=800;switcher.height.value=800;switcher.create_map(e)
	check("multiple_maps_appear_in_dropdown",switcher.selector.item_count==3 and Library.list_maps().size()==2)
	for i in switcher.selector.item_count:
		if str(switcher.selector.get_item_metadata(i))==first:switcher.select(e,i);break
	print("RESTORED MAP ",e.authoring.doc.name," ",e.world.data.size," regions ",e.authoring.doc.regions.size())
	check("switching_maps_restores_saved_terrain_and_size",e.authoring.doc.name=="Lake district" and e.authoring.doc.regions.size()==2 and Vector2(e.world.data.size[0],e.world.data.size[1])==Vector2(1200,900))
	check("saved_custom_terrain_can_be_deleted",e.authoring.delete_entity(lake))
	e._undo();check("terrain_deletion_supports_undo",e.authoring.doc.regions.size()==2)
	switcher.select(e,0)
	check("morrow_coast_returns_without_modification",not switcher.custom and e.authoring==original and not e.world.data.roads.is_empty() and FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==map_hash)
	for i in 5:await process_frame
	check("new_header_does_not_overlap_toolbar",e.root_ui.get_node("BuilderHeader").get_rect().end.y<=e.root_ui.get_node("BuilderTools").position.y)
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("MAP LIBRARY: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
