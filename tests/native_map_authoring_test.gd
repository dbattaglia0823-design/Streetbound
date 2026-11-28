extends SceneTree
## Native editor editing uses the authoring overlay, never the baked map.
## The production Python bridge handles actual generation and rollback.
const Session = preload("res://scripts/dev/native_map_edit_session.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, valid: bool) -> void:
	print("%s %s" % ["PASS" if valid else "FAIL",label])
	if not valid:
		errors.append(label)

func _run() -> void:
	var Elevation=preload("res://scripts/world/road_elevation.gd")
	var DrivingCamera=preload("res://scripts/camera/driving_camera.gd")
	var MarkerEditor=preload("res://scripts/dev/native_marker_editor.gd")
	var sample_road: Dictionary={"roadClass":"city","surface":"asphalt","points":[{"x":100,"y":700},{"x":500,"y":700}]}
	var tunnel: Dictionary=Elevation.whole_tunnel_profile(sample_road)
	check("whole_tunnel_two_portals",not tunnel.has("error") and tunnel.elevation.point_layers==[0,-1,-1,0] and tunnel.points.size()==4 and sample_road.points.size()==2)
	var preset: Dictionary=Elevation.structure_profile(sample_road,"overpass")
	check("automatic_overpass_profile",preset.has("road") and preset.road.elevation.point_layers==[0,1,1,0])
	var underground: Dictionary=Elevation.structure_profile(sample_road,"underground")
	check("automatic_underground_area",underground.has("road") and underground.road.width>=36 and underground.road.elevation=={"start_layer":-1,"end_layer":-1})
	check("regular_road_removes_height",not Elevation.structure_profile(underground.road,"regular").road.has("elevation"))
	check("tunnel_camera_zoom_and_surface_restore",is_equal_approx(DrivingCamera.tunnel_zoom_for(1.0,0.0),1.0) and is_equal_approx(DrivingCamera.tunnel_zoom_for(1.0,-6.0),1.45) and DrivingCamera.tunnel_zoom_for(1.0,-4.5)>1.0 and DrivingCamera.tunnel_zoom_for(1.0,6.0)==1.0)
	var cars: Array[Dictionary]=[{"id":"b","display_name":"Beta","price_usd":9},{"id":"a","display_name":"alpha","price_usd":100},{"id":"c","display_name":"Gamma","price_usd":9}]
	check("stock_sort_az",MarkerEditor.sorted_stock(cars,0).map(func(car: Dictionary)->String:return str(car.id))==["a","b","c"])
	check("stock_sort_za",MarkerEditor.sorted_stock(cars,1).map(func(car: Dictionary)->String:return str(car.id))==["c","b","a"])
	check("stock_sort_price_high",MarkerEditor.sorted_stock(cars,2).map(func(car: Dictionary)->String:return str(car.id))==["a","b","c"])
	check("stock_sort_price_low",MarkerEditor.sorted_stock(cars,3).map(func(car: Dictionary)->String:return str(car.id))==["b","c","a"] and cars[0].id=="b")
	var session = Session.new()
	check("authored_source_loads",session.load_source())
	if session.doc.is_empty():
		quit(1)
		return
	check("authoring_doc_is_world_forge_v2",
		session.doc.format=="gdt.racing-world" and
		int(session.doc.version)==2 and session.doc.roads.size()>=120)
	var remote: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://map-editor/maps/morrow-coast.edits.world.json"))
	check("native_client_source_revision_matches_loaded_authoring_source",
		remote is Dictionary and session.matches_remote(remote))
	var altered_remote: Dictionary = remote.duplicate(true)
	altered_remote["revision_marker"] = "external-change"
	check("external_source_edit_blocks_native_apply",not session.matches_remote(altered_remote))
	var LocalBackend = load("res://scripts/dev/native_map_bridge.gd")
	var backend: Node = LocalBackend.new()
	root.add_child(backend)
	check("stale_running_world_sha_blocks_native_apply_before_network",
		not backend.apply_source(session.doc,session.baseline_hash,
			"0000000000000000000000000000000000000000000000000000000000000000") and
		backend.phase=="")
	backend.queue_free()
	# Dealerships are editable source objects, but legacy shops do not
	# appear in the saved overrides until someone changes them.
	var dealer_session = Session.new()
	var DealerConfig = preload("res://scripts/world/dealership_config.gd")
	var Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
	check("dealer_editor_loads_source",dealer_session.load_source())
	check("all_curated_dealers_appear_without_source_overrides",
		dealer_session.dealership_list().size()==10 and
		dealer_session.doc.get("dealerships",[]).is_empty())
	var sample_vehicle: Dictionary = Catalog.all()[0]
	var sample_id := str(sample_vehicle.id)
	check("dealer_stock_overrides_are_undoable",
		dealer_session.update_dealership("budget",{
			"inventory_mode":"manual","inventory":[sample_id],
			"lot_width_m":40.0,"lot_depth_m":20.0}) and
		DealerConfig.available_inventory(dealer_session.dealership_at_id("budget")).size()==1 and
		DealerConfig.sells(dealer_session.dealership_at_id("budget"),sample_id) and
		dealer_session.undo() and
		dealer_session.dealership_at_id("budget").get("inventory_mode","automatic")=="automatic")
	check("new_dealerships_support_placement_and_undo",
		dealer_session.add_dealership(Vector2(3050,2570))=="custom-dealer-1" and
		dealer_session.dealership_list().size()==11 and
		dealer_session.undo() and dealer_session.dealership_list().size()==10)
	check("invalid_dealership_geometry_is_rejected",
		not dealer_session.update_dealership("budget",{"lot_width_m":200.0}) and
		dealer_session.dealership_at_id("budget").get("lot_width_m",32.0)==32.0)
	var new_vehicle: Dictionary = sample_vehicle.duplicate(true)
	new_vehicle.id="test-new-catalog-car"
	new_vehicle.dealership_id="budget"
	Catalog.all().append(new_vehicle)
	check("automatic_stock_tracks_new_catalog_cars",
		DealerConfig.sells(dealer_session.dealership_at_id("budget"),str(new_vehicle.id)))
	Catalog.all().erase(new_vehicle)
	var City=preload("res://scripts/dev/native_city_construction.gd")
	var Library=preload("res://scripts/dev/native_map_library.gd")
	var city_session=Session.new()
	city_session.doc=Library.create("City construction test",1800,1800,"grass")
	var city_before: Dictionary=city_session.doc.duplicate(true)
	var config: Dictionary={"columns":2,"rows":2,"block":140,"width":12,"lanes":2,"alleys":true,"density":1.0,"seed":42}
	var plan: Dictionary=City.plan_grid(city_session.doc,Vector2(900,900),config,city_session.road_limit(),city_session.prop_limit())
	check("city_grid_preview_deterministic",not plan.has("error") and plan.roads.size()==8 and plan.props.size()>0
		and plan==City.plan_grid(city_session.doc,Vector2(900,900),config,city_session.road_limit(),city_session.prop_limit())
		and city_session.doc==city_before)
	var generated: Array[String]=city_session.apply_construction(plan)
	check("city_grid_single_undo",generated.size()>8 and city_session.history.size()==1 and city_session.doc.roads.size()==8)
	check("grid_rejects_existing_roads",City.plan_grid(city_session.doc,Vector2(900,900),config,360,8000).has("error"))
	var decoration: Dictionary=City.plan_roadside(city_session.doc,"road-0",{"spacing":35,"decoration":"streetlight"},8000)
	check("roadside_preview_produces_props",not decoration.has("error") and decoration.props.size()>0)
	check("city_grid_undo_restores_document",city_session.undo() and city_session.doc==city_before)
	check("grid_rejects_out_of_bounds",City.plan_grid(city_session.doc,Vector2(10,10),config,360,8000).has("error"))
	var district: Dictionary=City.plan_district(city_session.doc,Vector2(900,900),config,8000)
	check("district_generation",district.props.size()>0 and not city_session.apply_construction(district).is_empty())
	var interchange: Dictionary=City.plan_interchange(city_before,Vector2(900,900),{"interchange":"diamond"},360)
	check("diamond_interchange_has_grade_connectors",not interchange.has("error") and interchange.roads.size()==6 and interchange.roads[0].elevation.start_layer==1)
	var clover: Dictionary=City.plan_interchange(city_before,Vector2(900,900),{"interchange":"cloverleaf foundation"},360)
	check("cloverleaf_foundation_has_loop_connectors",not clover.has("error") and clover.roads.size()==10)
	var trumpet: Dictionary=City.plan_interchange(city_before,Vector2(900,900),{"interchange":"trumpet foundation"},360)
	check("trumpet_foundation_has_loop_connector",not trumpet.has("error") and trumpet.roads.size()==5)
	var complete_grid: Dictionary=City.plan_grid(city_before,Vector2(900,900),config.merged({"sidewalks":true,"plots":true}),360,8000)
	check("grid_generates_sidewalks_and_plots",not complete_grid.has("error") and complete_grid.regions.size()==4 and complete_grid.props.any(func(p: Dictionary)->bool:return p.type=="sidewalk"))
	var property_session=Session.new()
	property_session.doc=Library.create("Property construction test",1800,1800,"grass")
	var frontage: String=property_session.add_road(Vector2(200,900),Vector2(1600,900))
	var property_before: Dictionary=property_session.doc.duplicate(true)
	var property_plan: Dictionary=City.plan_property(property_session.doc,frontage,Vector2(900,1040),{"property":"bank"},360,8000)
	check("property_kit_links_robbery_to_contact_and_dropoff",not property_plan.has("error") and property_plan.markers.size()==3
		and not property_session.apply_construction(property_plan).is_empty()
		and property_session.doc.markers.size()==3 and property_session.undo() and property_session.doc==property_before)
	var Height=preload("res://scripts/world/authored_height_field.gd")
	var landscape=Session.new()
	landscape.doc=Library.create("Terrain brush test",1280,1280,"grass")
	var landscape_before: Dictionary=landscape.doc.duplicate(true)
	var raised: Dictionary=Height.apply({},Vector2(1280,1280),Vector2(640,640),100,50,"raise")
	check("terrain_brush_raises_with_falloff",raised.values[64*129+64]==50.0 and raised.values[0]==0.0)
	var lowered: Dictionary=Height.apply(raised,Vector2(1280,1280),Vector2(640,640),100,20,"lower")
	check("terrain_brush_lowers",lowered.values[64*129+64]==30.0)
	var smooth: Dictionary=Height.apply(raised,Vector2(1280,1280),Vector2(640,640),100,100,"smooth")
	check("terrain_brush_smooths_peak",float(smooth.values[64*129+64])<50.0)
	var flat: Dictionary=Height.apply(raised,Vector2(1280,1280),Vector2(640,640),100,100,"flatten",5)
	check("terrain_flatten_and_undo",flat.values[64*129+64]==5.0 and landscape.set_terrain_height(flat)
		and landscape.history.size()==1 and landscape.undo() and landscape.doc==landscape_before)
	var image:=Image.create(2,2,false,Image.FORMAT_RGB8);image.fill(Color.WHITE)
	var imported: Dictionary=Height.import_image(image,-20,100)
	check("terrain_heightmap_import",Height.valid(imported) and imported.values[0]==100.0)
	var route:=PackedVector2Array([Vector2(300,640),Vector2(980,640)])
	var graded: Dictionary=Height.grade_road(raised,Vector2(1280,1280),route,100,0)
	check("terrain_road_grading",graded.values[64*129+64]==0.0)
	var river_points: Array[Vector2]=[Vector2(200,300),Vector2(640,400),Vector2(1000,300)]
	var river: Dictionary=City.plan_river(landscape.doc,river_points,30,20,8)
	check("river_banks_channel_atomic",not river.has("error") and river.regions.size()==2
		and not landscape.apply_construction(river).is_empty() and landscape.doc.terrainHeight.size==129
		and landscape.undo() and landscape.doc==landscape_before)
	var trees: Dictionary=City.plan_vegetation(landscape.doc,Vector2(640,640),80,.5,"tree",42,8000)
	check("vegetation_brush_deterministic",trees.props.size()>0 and trees==City.plan_vegetation(landscape.doc,Vector2(640,640),80,.5,"tree",42,8000))
	var Workspace=preload("res://scripts/dev/native_editor_workspace.gd")
	var workspace=Session.new()
	workspace.doc=Library.create("Workspace test",1800,1800,"grass")
	var workspace_road: String=workspace.add_road(Vector2(200,500),Vector2(1400,500))
	var workspace_prop: String=workspace.add_prop("house",Vector2(1000,800))
	var draw_order_original: Dictionary=workspace.prop_at_id(workspace_prop).duplicate(true)
	check("asset_draw_order_is_signed_visual_only",workspace.set_prop_draw_order(workspace_prop,-2)
		and int(workspace.prop_at_id(workspace_prop).drawOrder)==-2
		and workspace.set_prop_draw_order(workspace_prop,3)
		and int(workspace.prop_at_id(workspace_prop).drawOrder)==3
		and workspace.undo() and int(workspace.prop_at_id(workspace_prop).drawOrder)==-2
		and workspace.redo() and int(workspace.prop_at_id(workspace_prop).drawOrder)==3
		and not workspace.set_prop_draw_order(workspace_prop,11)
		and workspace.set_prop_draw_order(workspace_prop,0)
		and workspace.prop_at_id(workspace_prop)==draw_order_original)
	var workspace_ids: Array[String]=[workspace_road]
	var layer_data: Array=[{"name":"Main streets","visible":false,"locked":true,"ids":[workspace_road]}]
	check("named_layer_validates_and_hides_only_preview",workspace.set_named_layers(layer_data)
		and Workspace.preview(workspace.doc).roads.is_empty() and workspace.doc.roads.size()==1)
	check("named_layer_blocks_locked_road_edits",not workspace.bulk_properties(workspace_ids,"roads",{"width":20}))
	layer_data[0].locked=false
	layer_data[0].visible=true
	check("named_layer_unlock_allows_edit",workspace.set_named_layers(layer_data) and workspace.bulk_properties(workspace_ids,"roads",{"width":20}))
	var workspace_snapshot: Dictionary=workspace.doc.duplicate(true)
	check("custom_resize_rejects_outside_objects",not workspace.resize_custom_world(800,800) and workspace.doc==workspace_snapshot)
	check("custom_expansion_preserves_coordinates",workspace.resize_custom_world(2400,2000) and workspace.doc.world.width==2400
		and workspace.doc.roads==workspace_snapshot.roads and workspace.undo() and workspace.doc==workspace_snapshot)
	var replace_ids: Array[String]=[workspace_prop]
	check("bulk_asset_replacement_preserves_position",workspace.replace_assets(replace_ids,{"kind":"tree","name":"Tree"})
		and workspace.prop_at_id(workspace_prop).type=="oak" and workspace.prop_at_id(workspace_prop).x==1000)
	check("snapshot_restore_is_undoable",workspace.restore_snapshot(workspace_snapshot) and workspace.doc==workspace_snapshot and workspace.undo()
		and workspace.prop_at_id(workspace_prop).type=="oak")
	var measurement_points: Array[Vector2]=[Vector2.ZERO,Vector2(100,0),Vector2(100,100)]
	var metrics: Dictionary=Workspace.measure(measurement_points)
	check("measurement_distance_area_angle",is_equal_approx(metrics.length,200) and is_equal_approx(metrics.area,5000) and is_equal_approx(metrics.angle,90))
	check("measurement_road_clearance",is_equal_approx(Workspace.crossing_clearance(
		{"points":[{"x":0,"y":100},{"x":200,"y":100}],"elevation":{"start_layer":1,"end_layer":1}},
		{"points":[{"x":100,"y":0},{"x":100,"y":200}]}),6))
	var bulk_session=Session.new()
	check("bulk_fixture_loads",bulk_session.load_source())
	var bulk_ids: Array[String]=["road-0","road-1"]
	var bulk_before: Dictionary=bulk_session.doc.duplicate(true)
	check("bulk_road_width_changes_both_in_one_undo",bulk_session.bulk_properties(bulk_ids,"roads",{"width":14.0})
		and float(bulk_session.road_at_id("road-0").width)==14.0 and float(bulk_session.road_at_id("road-1").width)==14.0
		and bulk_session.history.size()==1 and bulk_session.undo() and bulk_session.doc==bulk_before)
	check("invalid_bulk_edit_is_atomic",not bulk_session.bulk_properties(bulk_ids,"roads",{"width":500.0})
		and bulk_session.doc==bulk_before and bulk_session.history.is_empty())
	check("unknown_bulk_property_is_rejected",not bulk_session.bulk_properties(bulk_ids,"roads",{"points":[]}))
	var clipboard: Dictionary=bulk_session.copy_group(bulk_ids)
	check("clipboard_copies_source_roads",clipboard.get("entries",[]).size()==2)
	var pasted: Array[String]=bulk_session.paste_group(clipboard,Vector2(3000,2400))
	check("clipboard_paste_uses_new_ids_and_undo",pasted.size()==2 and pasted[0]!="road-0" and bulk_session.undo() and bulk_session.doc==bulk_before)
	check("clipboard_out_of_bounds_rejected",bulk_session.paste_group(clipboard,Vector2(-10000,-10000)).is_empty() and bulk_session.doc==bulk_before)
	var Select=preload("res://scripts/dev/native_editor_multiselect.gd")
	check("selection_filter_distinguishes_stacked_road_levels",Select.road_matches_layer({"elevation":{"start_layer":1,"end_layer":1}},1) and not Select.road_matches_layer({"elevation":{"start_layer":-1,"end_layer":-1}},1))
	bulk_session.unlocked_road_layer=1
	check("locked_ground_roads_reject_bulk_edit",not bulk_session.bulk_properties(bulk_ids,"roads",{"width":14.0}) and bulk_session.doc==bulk_before)
	bulk_session.unlocked_road_layer=99
	var original_hash: String = session.baseline_hash
	var origin_road: Dictionary = session.road_at_id("road-0")
	check("stable_source_road_id",not origin_road.is_empty())
	var old_end := Vector2(float(origin_road.points[origin_road.points.size()-1].x),
		float(origin_road.points[origin_road.points.size()-1].y))
	var new_end := old_end + Vector2(4,3)
	check("moving_real_road_anchor_is_atomic",
		session.move_road_point("road-0",origin_road.points.size()-1,new_end,0.0))
	var joined: Dictionary = session.road_at_id("road-1")
	check("shared_endpoint_stays_connected_without_browser_approximation",
		Vector2(float(joined.points[0].x),float(joined.points[0].y)).distance_to(new_end)<0.01)
	check("road_edit_can_be_undone",session.undo() and
		Vector2(float(session.road_at_id("road-0").points[
			origin_road.points.size()-1].x),
			float(session.road_at_id("road-0").points[
			origin_road.points.size()-1].y)).distance_to(old_end)<0.01)
	check("redo_restores_both_joined_road_endpoints",session.redo() and
		Vector2(float(session.road_at_id("road-1").points[0].x),
			float(session.road_at_id("road-1").points[0].y)).distance_to(new_end)<0.01)
	check("reject_unsafe_road_teleport",
		not session.move_road_point("road-0",0,old_end+Vector2(2000,0)))
	check("reject_out_of_bounds_edits",
		not session.move_road_point("road-0",0,Vector2(-20,0)))
	var before_count: int = session.doc.props.size()
	var id: String = session.add_prop("house",Vector2(2300,3200))
	check("new_game_asset_has_stable_source_id",
		id.begins_with("prop-native-") and
		session.doc.props.size()==before_count+1 and
		session.prop_at_id(id).assetId=="game-house")
	var project_id: String = session.add_project_prop("Buildings/House.png",
		"house",Vector2(2250,3150),Vector2(12,16))
	check("native_browser_uses_same_project_asset_id_as_python_importer",
		project_id.begins_with("prop-native-") and
		session.prop_at_id(project_id).assetId==
			"project-"+"Buildings/House.png".sha256_text().substr(0,24) and
		session.prop_at_id(project_id).assetPath=="Buildings/House.png")
	check("native_project_asset_is_undoable",session.undo() and
		session.prop_at_id(project_id).is_empty())
	check("native_rejects_untrusted_asset_paths",
		session.add_project_prop("../outside.png","house",
			Vector2(2250,3150),Vector2(12,16)).is_empty())
	check("placement_does_not_move_other_objects",
		session.doc.roads.size()>=120 and
		session.doc.props.size()==before_count+1)
	check("authored_asset_moves_rotates_and_resizes",
		session.move_prop(id,Vector2(2320,3210)) and
		session.rotate_prop(id,15) and
		session.resize_prop(id,1.15) and
		absf(float(session.prop_at_id(id).rotation)-15)<0.01 and
		absf(float(session.prop_at_id(id).scale)-1.15)<0.01)
	check("authored_asset_deletion_undo_and_redo",
		session.delete_prop(id) and session.prop_at_id(id).is_empty() and
		session.undo() and not session.prop_at_id(id).is_empty() and
		session.redo() and session.prop_at_id(id).is_empty())
	check("dirty_state_and_unchanged_source_revision",
		session.dirty and session.baseline_hash==original_hash)
	session.discard_changes()
	check("discard_restores_clean_source_and_ids",
		not session.dirty and session.baseline_hash==original_hash and
		session.doc.props.size()==before_count and
		session.road_at_id("road-0").points==origin_road.points)
	check("runtime_procedural_assets_are_never_editable_by_position",
		session.index_of_runtime_prop({"kind":"tree","p":[2300,3200]})=="")
	var adopted: String = session.adopt_runtime_prop({
		"kind":"house","seed":1892,"p":[2240.0,3120.0],
		"size":[12.0,17.0],"angle":0.0
	})
	check("replaceable_original_can_be_adopted_by_stable_identity",
		adopted.begins_with("prop-native-") and
		session.prop_at_id(adopted).replaces.kind=="house" and
		int(session.prop_at_id(adopted).replaces.seed)==1892)
	check("duplicate_original_adoption_rejected",
		session.adopt_runtime_prop({
			"kind":"house","seed":1892,"p":[2240.0,3120.0],
			"size":[12.0,17.0]})=="")
	check("direct_delete_hides_adopted_original_without_losing_identity",
		session.delete_prop(adopted) and
		bool(session.prop_at_id(adopted).get("hidden",false)) and
		session.undo() and not bool(session.prop_at_id(adopted).get("hidden",false)))
	var poi_prop: String = session.adopt_runtime_prop({"kind":"house","seed":1,
		"p":[2240,3120],"poi":"Laurel Motor House"})
	check("poi_scenery_is_directly_editable_with_stable_identity",
		poi_prop.begins_with("prop-native-") and
		session.prop_at_id(poi_prop).replaces.kind=="house")
	check("explicitly_protected_and_unstable_props_stay_safe",
		session.adopt_runtime_prop({"kind":"house","seed":2,
			"p":[2240,3120],"protected":true})=="" and
		session.adopt_runtime_prop({"kind":"house",
			"p":[2240,3120]})=="")
	session.discard_changes()
	var road_count: int = session.doc.roads.size()
	var native_road := session.add_road(Vector2(1800,2700),Vector2(1840,2710))
	check("draw_road_uses_unsaved_undoable_browser_source",
		native_road=="road-%d" % road_count and
		session.doc.roads.size()==road_count+1 and session.undo())
	var region_count: int = session.doc.regions.size()
	var corners: Array[Vector2] = [Vector2(310,320),Vector2(390,320),Vector2(390,370)]
	var native_region := session.add_region(corners)
	check("terrain_region_is_previewed_without_world_rebake",
		not session.initial.regions.any(func(item: Dictionary)->bool:return str(item.id)==native_region) and
		session.doc.regions.size()==region_count+1 and session.undo())
	check("terrain_draw_order_undo_redo",session.redo() and session.set_prop_draw_order(native_region,-2) and
		session.doc.regions[-1].get("drawOrder")==-2 and session.set_prop_draw_order(native_region,3) and
		session.undo() and session.doc.regions[-1].get("drawOrder")==-2 and
		session.redo() and session.doc.regions[-1].get("drawOrder")==3 and
		not session.set_prop_draw_order(native_region,11) and session.set_prop_draw_order(native_region,0) and
		not session.doc.regions[-1].has("drawOrder"))
	session.discard_changes()
	var vertex_region:=session.add_region(corners)
	var before_vertices: Dictionary=session.region_at_id(vertex_region).duplicate(true)
	var inserted_vertex: int=session.insert_region_point(vertex_region,2,Vector2(350,345))
	check("terrain_vertex_insert_closing_edge_and_undo",
		inserted_vertex==3 and session.region_at_id(vertex_region).points.size()==4 and
		session.undo() and session.region_at_id(vertex_region)==before_vertices and
		session.redo() and session.region_at_id(vertex_region).points.size()==4)
	check("terrain_vertex_move_remove_and_triangle_minimum",
		session.move_region_point(vertex_region,3,Vector2(320,350)) and
		session.remove_region_point(vertex_region,3) and
		not session.remove_region_point(vertex_region,0) and
		session.region_at_id(vertex_region).points.size()==3)
	session.discard_changes()
	var marker_count: int = session.doc.markers.size()
	var native_marker := session.add_marker(Vector2(2350,3100))
	check("native_marker_uses_browser_source_contract",
		native_marker=="marker-%d" % marker_count and
		session.doc.markers.size()==marker_count+1 and session.undo())
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var editor: Variant = game.native_world_editor
	if editor == null:
		editor = load("res://scripts/dev/native_world_editor.gd").new()
		editor.world = game.ground
		editor.player = game.vehicle
		editor.driving_camera = get_first_node_in_group("player_camera")
		editor.traffic_network = game.ground.get_node("AmbientTraffic").get("network")
		game.add_child(editor)
		await process_frame
	check("draft_sprite_seed_matches_python_world_baker",
		editor.gizmos._source_seed("prop-native-1")==648520850 and
		editor.gizmos._source_seed("prop-native-2")==1068430632)
	check("actual_native_editor_opens_in_game",editor.open_editor())
	check("asset_browser_is_contextual_not_always_on",
		is_instance_valid(editor.asset_dock) and not editor.asset_dock.visible)
	editor._choose_tool("place:house")
	check("asset_browser_appears_only_in_scenery_mode",
		editor.asset_dock.visible)
	editor._choose_tool("move_prop")
	check("asset_browser_hides_for_selection",
		not editor.asset_dock.visible)
	check("draw_order_is_discoverable_even_before_selection",
		editor.inspector_draw_order.visible and not editor.inspector_draw_order.editable and
		editor.inspector_draw_order.name=="DrawOrderZ")
	var terrain_source: Dictionary=editor.authoring.doc.regions[0]
	editor.source_id=str(terrain_source.id)
	editor._refresh_authoring()
	check("draw_order_control_enables_for_terrain",
		editor.inspector_draw_order.editable and
		int(editor.inspector_draw_order.value)==int(terrain_source.get("drawOrder",0)))
	editor.source_id=""
	editor._refresh_authoring()
	editor._fit_map()
	check("fit_map_can_zoom_far_enough_to_show_the_entire_world",
		editor.editor_camera.zoom.x<0.03)
	editor._recenter()

	check("native_editor_has_searchable_asset_thumbnail_dock",
		is_instance_valid(editor.asset_grid) and
		is_instance_valid(editor.asset_search) and
		editor.asset_entries.size()>=8 and
		editor.asset_entries.any(func(asset: Dictionary) -> bool:
			return str(asset.get("path",""))=="Map Building Assets/Buildings/House.png"))
	var runtime_road_count: int = game.ground.data.roads.size()
	var runtime_prop_count: int = game.ground.data.props.size()
	editor._choose_tool("place:house")
	editor._source_click(Vector2(2300,3200)*20.0)
	check("editor_placement_creates_undoable_source_preview",
		editor.authoring.dirty and editor.authoring.doc.props.size()==before_count+1 and
		editor.gizmos.draft_doc.props.size()==before_count+1)
	check("runtime_map_and_traffic_unchanged_before_rebake",
		game.ground.data.roads.size()==runtime_road_count and
		game.ground.data.props.size()==runtime_prop_count and
		editor.traffic_network.connector_count>0)
	# A real generated tree can be selected and converted safely, but only
	# through its baked (kind, seed, position) identity, never by location.
	editor._discard_draft()
	var adopt_idx := -1
	for i in game.ground.data.props.size():
		var item: Dictionary = game.ground.data.props[i]
		var seed_value: Variant = item.get("seed")
		var is_integral_seed: bool = (typeof(seed_value) in [TYPE_INT,TYPE_FLOAT] and
			is_finite(float(seed_value)) and
			absf(float(seed_value)-roundf(float(seed_value)))<0.0001)
		if (str(item.get("kind",""))=="tree" and
				is_integral_seed and
				not item.has("poi") and not item.has("authoring_id")):
			adopt_idx = i
			break
	check("real_world_has_safe_generated_scenery_to_adopt",adopt_idx>=0)
	if adopt_idx>=0:
		editor._update_selection({"kind":"prop","index":adopt_idx})
		editor._adopt_selected()
		var preview_asset: Dictionary = editor.authoring.prop_at_id(editor.source_id)
		var runtime_asset: Dictionary = game.ground.data.props[adopt_idx]
		check("draft_asset_uses_real_game_artwork",
			editor.gizmos._prop_texture(preview_asset) != null)
		check("draft_asset_has_collision_preview_node",
			is_instance_valid(editor.gizmos.preview_body))
		var expected_solid := bool(runtime_asset.get("solid",false))
		var preview_has_collision: bool = is_instance_valid(editor.gizmos.preview_body) and \
			editor.gizmos.preview_body.get_child_count()>0
		print("DRAFT COLLISION DIAGNOSTIC expected_solid=",expected_solid,
			" preview_has_collision=",preview_has_collision,
			" count=",editor.gizmos.preview_body.get_child_count(),
			" source=",preview_asset.get("replaces",{}),
			" kind=",runtime_asset.get("kind",""),
			" original_size=",runtime_asset.get("size",[]))
		check("draft_collision_matches_original_asset_solidity",
			preview_has_collision == expected_solid)
		check("real_baked_tree_adoption_keeps_identity_and_preview",
			editor.authoring.dirty and editor.source_id.begins_with("prop-native-") and
			editor.authoring.prop_at_id(editor.source_id).replaces.kind=="tree")
		check("adoption_does_not_modify_live_tree_traffic_or_physics",
			game.ground.data.props.size()==runtime_prop_count and
			editor.traffic_network.connector_count>0)
		editor._discard_draft()
	editor._choose_tool("place:house")
	editor._source_click(Vector2(2300,3200)*20.0)
	editor._undo()
	check("native_undo_returns_to_original_authoring_source",
		not editor.authoring.dirty and
		editor.authoring.doc.props.size()==before_count)
	editor._redo()
	check("native_redo_restores_pending_asset",editor.authoring.dirty)
	editor.close_editor()
	check("test_drive_does_not_discard_unsaved_draft",
		not editor.active and editor.authoring.dirty and not paused)
	check("reopen_retains_editable_draft",editor.open_editor() and editor.authoring.dirty)
	editor._discard_draft()
	check("discard_removes_ghosts_and_disables_apply",
		not editor.authoring.dirty and editor.apply_button.disabled and
		editor.authoring.doc.props.size()==before_count)
	editor.close_editor()
	game.queue_free()
	paused = false
	print("NATIVE MAP AUTHORING: ","PASS" if errors.is_empty() else
		"FAIL "+str(errors))
	quit(0 if errors.is_empty() else 1)
