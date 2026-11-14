extends SceneTree
const Mountains=preload("res://scripts/world/mountain_barrier_world.gd")
const Geometry=preload("res://scripts/world/mountain_barrier_geometry.gd")
const Art=preload("res://scripts/world/coast_mountain_barriers.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)
func blocked(at_m: Vector2) -> bool:
	var query:=PhysicsShapeQueryParameters2D.new();var circle:=CircleShape2D.new();circle.radius=2
	query.shape=circle;query.transform=Transform2D(0,at_m*20);query.collision_mask=1
	return not root.world_2d.direct_space_state.intersect_shape(query,1).is_empty()
func run() -> void:
	var world_sha:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var source_sha:=FileAccess.get_sha256("res://map-editor/maps/morrow-coast.edits.world.json")
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	for i in 3:await process_frame
	var world: Node=game.ground;game.vehicle.set_physics_process(false);world.set_process(false)
	check("old_mountain_biomes_remain_drivable",world.mountain_diagnostics.barriers==0)
	# Test-only terrain in the actual game scene. Keep the checked-in map intact.
	for chunk in world.chunks.values():chunk.free()
	world.chunks.clear();world.pending.clear();world.current_cell=Vector2i(-999,-999)
	world.data=world.data.duplicate(true);world.data.props=[]
	for chunk in world.data.chunks.values():chunk.props=[]
	var thin: Dictionary={"kind":"mountain","color":"87917d","barrier":true,"elevation":80,
		"authoring_id":"region-test-edge","points":[[0,1000],[12,1000],[12,1200],[0,1200]]}
	var concave: Dictionary={"kind":"rock","color":"92988a","barrier":true,"elevation":110,
		"authoring_id":"region-test-concave","points":[[100,500],[220,500],[220,580],[160,580],[160,660],[100,660]]}
	world.data.terrain.append(thin);world.data.terrain.append(concave)
	var report: Dictionary=Mountains.apply(world.data)
	check("solid_regions_are_indexed_and_replace_covered_outer_wall",report.barriers==2 and report.replaced_boundary_sections>0,report)
	world.stream_at(Vector2(20,1100)*20)
	while not world.pending.is_empty():world._build_chunk(world.pending.pop_front())
	await physics_frame
	check("visible_edge_mountain_is_a_real_obstacle",blocked(Vector2(6,1100)))
	check("old_invisible_wall_is_removed_in_front_of_thin_mountain",not blocked(Vector2(25,1100)))
	check("uncovered_edge_gaps_keep_the_safety_boundary",blocked(Vector2(25,1240)))
	game.vehicle.global_position=Vector2(35,1100)*20;game.vehicle.global_rotation=-PI*.5
	game.vehicle.linear_velocity=Vector2.LEFT*8;game.vehicle.reset_physics_interpolation()
	var closest:=35.0
	for i in 180:
		await physics_frame
		game.vehicle.step_vehicle(1.0/120,Vector4(.5,0,0,0))
		closest=minf(closest,game.vehicle.position.x/20)
	check("driving_hits_the_visible_mountain_not_the_old_wall",closest<20 and closest>=12,closest)
	game.vehicle.reset_vehicle();game.vehicle.set_physics_process(false)
	world.stream_at(Vector2(175,590)*20)
	while not world.pending.is_empty():world._build_chunk(world.pending.pop_front())
	await physics_frame
	check("concave_collision_matches_filled_mountain",blocked(Vector2(130,620)))
	check("concave_notch_stays_open",not blocked(Vector2(195,620)))
	var rendered:=0
	for chunk in world.chunks.values():
		if chunk.has_node("MountainArtworkClip"):rendered+=1
	check("mountain_art_follows_chunk_streaming",rendered>=2,rendered)
	var cache: Dictionary={};var first:=Geometry.bundle(concave,cache)
	check("mountain_has_real_shaded_peak_geometry",first.triangles>12 and first.mesh.get_surface_count()>0,first.triangles)
	var translated:=concave.duplicate(true)
	for p in translated.points:p[0]+=100;p[1]+=20
	check("moving_a_mountain_reuses_its_cached_mesh",Geometry.bundle(translated,cache).mesh==first.mesh)
	translated.elevation=180
	check("height_changes_update_the_rock_mesh",Geometry.bundle(translated,cache).mesh!=first.mesh)
	var walls: int=world.data.walls.size();Mountains.apply(world.data)
	check("boundary_replacement_is_idempotent",world.data.walls.size()==walls)
	var editor=game.native_world_editor
	check("native_editor_opens",editor.open_editor())
	editor._mountain_tool()
	check("mountain_tool_selects_solid_terrain_and_height",editor.tool_name=="draw_terrain" and editor.terrain_barrier.button_pressed and editor.terrain_elevation.value==80)
	var vertices: Array[Vector2]=[Vector2(300,1000),Vector2(470,1000),Vector2(470,1160),Vector2(300,1160)]
	editor.draft_points=vertices;editor._finish_shape()
	var id: String=editor.source_id;var record: Dictionary=editor._selected_record()
	check("drawn_mountain_is_undoable_source_data",not id.is_empty() and bool(record.item.get("barrier",false)) and record.item.elevation==80)
	check("preview_uses_the_same_art_and_polygon_collision",editor.gizmos.mountain_preview.regions.size()==1 and editor.gizmos.mountain_preview.body.get_child_count()==1)
	await physics_frame
	check("unsaved_editor_mountain_has_collision",blocked(Vector2(380,1080)))
	editor._choose_tool("move_prop");editor._source_click(Vector2(380,1080)*20)
	check("mountain_faces_can_be_selected_and_dragged",editor.pending_drag.get("kind","")=="region" and editor.source_id==id)
	editor._finish_source_drag(Vector2(395,1090)*20)
	check("dragging_keeps_the_mountain_settings",bool(editor._selected_record().item.barrier) and editor._selected_record().item.points[0].x==315)
	editor._undo()
	check("undo_restores_the_mountain_position",editor._selected_record().item.points[0].x==300)
	editor._fit_map();await process_frame
	check("full_map_contains_solid_mountain_art",editor.overview_renderer.full_world.content.mountains.size()==2)
	editor._set_layer(false,"terrain")
	check("terrain_layer_hides_mountain_preview_and_world_art",not editor.gizmos.mountain_preview.visible and not editor.overview_renderer.full_world.get_node("MountainArtworkClip").visible)
	editor._set_layer(true,"terrain");editor._discard_draft();editor.close_editor()
	check("editor_exit_disables_preview_collision_and_clears_masks",editor.gizmos.mountain_preview.body.collision_layer==0 and Art.editor_hidden.is_empty())
	check("real_archive_and_source_are_unchanged",FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==world_sha and FileAccess.get_sha256("res://map-editor/maps/morrow-coast.edits.world.json")==source_sha)
	game.queue_free();await process_frame;await process_frame
	print("MOUNTAIN BARRIERS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
