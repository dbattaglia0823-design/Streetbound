extends SceneTree
## Production world must load via its checked-in manifest, not Test Drive meta.
const Publication=preload("res://scripts/world/world_publication.gd")
const RenderHealth=preload("res://scripts/world/world_render_health.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String,ok: bool,extra: Variant="") -> void:
	print("%s %s %s"%["PASS" if ok else "FAIL",label,str(extra)])
	if not ok:failures.append(label)

func _run() -> void:
	check("default_rejects_untrusted_archive_paths",
		not Publication.is_published_archive_path("res://worlds/published/../../worlds/morrow-coast.world.json") and
		not Publication.is_published_archive_path("user://streetbound-maps/private.world.json") and
		not Publication.is_published_archive_path("res://worlds/morrow-coast.world.json"))
	check("invalid_publish_manifest_falls_back_to_morrow",
		not bool(Publication.resolve_manifest({"format":"streetbound.active-world",
			"version":1,"mode":"published","id":"custom.world.json",
			"archive":"res://worlds/../../secret.world.json","source":"res://unsafe"}).published))
	var selected: Dictionary=Publication.current()
	check("release_manifest_selects_published_world",
		bool(selected.get("published",false)) and selected.name=="Published CI District")
	var main: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 15:await process_frame
	check("normal_main_scene_loads_selected_published_archive",
		bool(main.published_game_world) and not bool(main.custom_test_drive) and
		main.ground.initialization_complete and
		str(main.ground.data.get("name",""))=="Published CI District")
	check("published_world_has_full_streamed_junctions",
		main.ground.data.junctions.size()>=2 and
		main.ground.data.road_connections.size()>0 and
		RenderHealth.audit(main.ground.data).compatible)
	check("published_world_uses_main_hud_traffic_and_marker_systems",
		is_instance_valid(main.vehicle) and
		is_instance_valid(main.progression_hud) and
		is_instance_valid(main.authored_map_markers) and
		main.authored_map_markers.markers.size()==1 and
		main.ground.get_node_or_null("AmbientTraffic")!=null)
	check("published_events_staged_without_morrow_only_events",
		main.extra_races.size()==1 and
		main.drag_race==null and main.circuit_race==null and
		main.street_race==null and main.player_garage==null)
	check("production_save_is_enabled_unlike_test_drive",
		is_instance_valid(main.vehicle_ownership) and main.vehicle_ownership.persist_enabled)
	check("world_identity_is_stable_for_career_events",
		str(main.ground.data.get("editor_world_id",""))=="published-ci.world.json")
	main.queue_free()
	await process_frame
	print("PUBLISHED WORLD GAMEPLAY: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
