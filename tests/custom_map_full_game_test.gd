extends SceneTree
## An authored map must launch the REAL driving scene: same streamed junctions,
## AI lane network, audio, HUD, map, car menu and vehicle physics as Morrow Coast.
const Library=preload("res://scripts/dev/native_map_library.gd")
const Catalog=preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Ownership=preload("res://scripts/vehicle/vehicle_ownership.gd")
const TrafficCar=preload("res://scripts/world/traffic_car.gd")
const ResourceService=preload("res://scripts/world/vehicle_damage_service.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(name: String,ok: bool,detail: Variant="") -> void:
	print("%s %s %s"%["PASS" if ok else "FAIL",name,str(detail)])
	if not ok:failures.append(name)

func road(id: int,name: String,coords: Array) -> Dictionary:
	var points: Array=[]
	for p in coords:points.append({"x":p[0],"y":p[1]})
	return {"id":"road-%d"%id,"name":name,"roadClass":"city",
		"surface":"asphalt","width":12,"lanes":2,"points":points}

func _run() -> void:
	var folder: String="user://streetbound-maps/full-game-test-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	var doc: Dictionary=Library.create("Full Game Custom Test",1200,1000,"grass")
	doc["roads"]=[
		road(0,"East West",[[100,500],[1100,500]]),
		road(1,"North South",[[500,100],[500,900]]),
		road(2,"T Branch",[[840,500],[840,780]])]
	doc["markers"]=[
		{"id":"marker-0","type":"player_spawn","name":"Spawn","x":480,"y":500,"rotation":90.0},
		{"id":"marker-1","type":"mission","name":"Map Mission","x":480,"y":500,
			"rotation":0.0,"properties":{"race_id":"race-0","radius_m":12}},
		{"id":"marker-2","type":"fast_travel","name":"Station West","x":500,"y":500,
			"rotation":0.0,"properties":{"radius_m":12}},
		{"id":"marker-3","type":"fast_travel","name":"Station East","x":800,"y":500,
			"rotation":0.0,"properties":{"radius_m":12}},
		{"id":"marker-4","type":"traffic_spawn","name":"Traffic Start","x":620,"y":500,
			"rotation":0.0,"properties":{"traffic_weight":8}},
		{"id":"marker-5","type":"garage","name":"Test Garage","x":700,"y":500,
			"rotation":0.0,"properties":{"radius_m":12}}]
	doc["props"]=[{"id":"prop-house","name":"House","type":"house","assetId":"game-house",
		"x":280,"y":280,"scale":1.0,"rotation":0.0}]
	doc["races"]=[{"id":"race-0","name":"Map Race","mode":"sprint","laps":1,
		"points":[{"x":200,"y":500},{"x":800,"y":500}],"enemy_starts":[]}]
	var file: String=Library.save(doc,"full-test.world.json")
	check("custom_map_saved_without_touching_main_world",not file.is_empty())
	var source_path: String=Library.folder().path_join(file)
	var archive: String=Library.folder().path_join(file+".test-drive.stream.json")
	var process_output: Array=[]
	var result: int=OS.execute("python3",PackedStringArray([
		ProjectSettings.globalize_path("res://tools/build_custom_test_world.py"),
		"--source",ProjectSettings.globalize_path(source_path),
		"--output",ProjectSettings.globalize_path(archive)]),process_output,true)
	check("temporary_full_game_archive_baked",result==0 and FileAccess.file_exists(archive),process_output)
	if result!=0:
		print("FULL GAME CUSTOM TEST DRIVE: FAIL");quit(1);return
	set_meta("streetbound_test_drive_archive",archive)
	set_meta("streetbound_test_drive_map",file)
	var resource_before:=FileAccess.get_file_as_bytes(ResourceService.RESOURCE_PATH) if FileAccess.file_exists(ResourceService.RESOURCE_PATH) else PackedByteArray()
	var ownership_before:=FileAccess.get_file_as_bytes(Ownership.SAVE_PATH) if FileAccess.file_exists(Ownership.SAVE_PATH) else PackedByteArray()
	var saved_model:=Ownership.new()
	var main: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 16:await process_frame
	var world: Node=main.ground
	check("uses_real_morrow_coast_gameplay_world",bool(main.custom_test_drive) and
		world.initialization_complete and world.data.get("editor_custom_test_drive",false))
	check("production_baked_intersections_exist",world.data.junctions.size()>=2 and
		world._junction_polygons.size()==world.data.junctions.size())
	var visual_junctions:=false
	for chunk in world.chunks.values():
		if not chunk.junction_list.is_empty():visual_junctions=true;break
	check("streamed_world_contains_real_intersection_render_batches",visual_junctions)
	var ambient: Node=world.get_node_or_null("AmbientTraffic")
	check("uses_real_traffic_with_connected_junction_lane_graph",
		is_instance_valid(ambient) and ambient.network.edges.size()>0 and
		ambient.network.source_road_count==doc.roads.size())
	check("uses_full_game_hud_and_pause_settings",
		is_instance_valid(main.pause_menu) and is_instance_valid(main.progression_hud)
		and get_first_node_in_group("streetbound_world_map_hud")!=null)
	check("uses_full_vehicle_system_and_camera",is_instance_valid(main.vehicle) and
		main.vehicle.surface_provider==world and is_instance_valid(main.local_split_screen))
	check("custom_map_races_use_normal_authored_gameplay_system",
		main.extra_races.size()==1 and main.extra_races[0].get("definition").name=="Map Race")
	check("no_morrow_only_dealers_or_fixed_track_races_spawn",
		main.drag_race==null and main.street_race==null and main.circuit_race==null and
		main.dealership_world==null)
	check("test_driver_cannot_modify_real_player_progression",
		not main.vehicle_ownership.persist_enabled)
	check("real_single_player_damage_fuel_police_contracts_present",
		is_instance_valid(main.vehicle_damage_service) and is_instance_valid(main.police_pursuit)
		and is_instance_valid(main.driving_contracts) and not main.vehicle_damage_service.persist_enabled)
	var entry: Dictionary=Catalog.find_by_id(saved_model.active_id)
	var expected:=Catalog.make_configuration(entry)
	saved_model.apply_car_upgrades(expected,saved_model.active_id)
	var actual: VehicleConfig=main.vehicle.config
	check("test_drive_restores_real_car_and_tuning",main.vehicle_ownership.active_id==saved_model.active_id
		and is_equal_approx(actual.mass_kg,expected.mass_kg)
		and is_equal_approx(actual.engine_power_kw,expected.engine_power_kw))
	var body: Sprite2D=main.vehicle.get_node("Art/Sprite")
	check("player_uses_catalog_artwork",ResourceLoader.exists(str(entry.texture),"Texture2D")
		and body.texture!=null and body.texture.resource_path==str(entry.texture))
	var all_traffic_art:=true
	for index in TrafficCar.model_count():
		if TrafficCar.appearance_for(index).is_empty():all_traffic_art=false
	check("real_traffic_artwork_is_available",all_traffic_art)
	var mark: Node=main.authored_map_markers
	check("game_instantiates_all_authored_marker_types",
		is_instance_valid(mark) and mark.markers.size()==6)
	check("traffic_markers_drive_actual_lane_spawner",
		ambient.authored_spawn_sources.size()>=1)
	mark._nearby=mark.nearest_marker()
	check("mission_marker_detects_nearby_race",str(mark._nearby.get("type",""))=="mission")
	mark.activate()
	check("mission_launches_actual_authored_race",
		main.extra_races[0].state=="countdown" and main.vehicle.global_position.distance_to(Vector2(200,500)*20)<400)
	main.extra_races[0].quit_race()
	main.vehicle.global_position=Vector2(500,500)*20
	main.vehicle.linear_velocity=Vector2.ZERO
	mark._nearby=mark.nearest_marker()
	check("nearby_fast_travel_station_detected",str(mark._nearby.get("type",""))=="fast_travel")
	mark.activate()
	check("fast_travel_opens_destination_picker",mark._dialog_open and mark.destinations.get_child_count()>=1)
	if mark._dialog_open:
		mark._travel_to(doc.markers[3])
		check("fast_travel_moves_to_authored_drivable_destination",
			main.vehicle.global_position.distance_to(Vector2(800,500)*20)<1 and not paused)
	main.vehicle.global_position=Vector2(700,500)*20
	mark._nearby=mark.nearest_marker()
	mark._process(.3)
	check("garage_marker_unlocks_actual_owned_car_selector",
		mark._nearby.get("type","")=="garage" and main.get_node("VehicleSelector").remote_garage_allowed)

	check("test_drive_has_clear_return_to_builder",
		main.has_node("TestDriveReturn/ReturnToMapEditor"))
	main.vehicle_damage_service.damage.integrity=42.0
	main.vehicle_damage_service.fuel.remaining=1.0
	check("test_condition_updates_are_memory_only",main.vehicle_damage_service._save_resources())
	main.vehicle_ownership.credit(100)
	main.queue_free()
	await process_frame
	check("real_career_save_unchanged",ownership_before==(FileAccess.get_file_as_bytes(Ownership.SAVE_PATH) if FileAccess.file_exists(Ownership.SAVE_PATH) else PackedByteArray()))
	check("real_vehicle_condition_save_unchanged",resource_before==(FileAccess.get_file_as_bytes(ResourceService.RESOURCE_PATH) if FileAccess.file_exists(ResourceService.RESOURCE_PATH) else PackedByteArray()))
	for key in ["streetbound_test_drive_archive","streetbound_test_drive_map"]:
		if has_meta(key):remove_meta(key)
	for p in [source_path,archive]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("FULL GAME CUSTOM TEST DRIVE: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
