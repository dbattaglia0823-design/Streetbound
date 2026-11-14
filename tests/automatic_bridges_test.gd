extends SceneTree
const Geometry=preload("res://scripts/world/road_bridge_geometry.gd")
const Migration=preload("res://scripts/world/automatic_road_bridges.gd")
const Art=preload("res://scripts/world/coast_bridges.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)
func run() -> void:
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/road_bridges.json"))
	for fixture in fixtures:
		var mask:=Geometry.new();mask.prepare(fixture.terrain)
		var path:=PackedVector2Array()
		for p in fixture.path:path.append(Geometry.v(p))
		var wet:=mask.wet_intervals(path);var valid: bool=wet.size()==fixture.wet.size()
		if valid:
			for i in wet.size():valid=valid and wet[i].distance_to(Geometry.v(fixture.wet[i]))<.001
		check(str(fixture.name),valid,wet)
		var spans:=mask.spans_for_road({"id":0,"width":10.0,"kind":"rural","points":fixture.path})
		check(str(fixture.name)+"_bridge_geometry",spans.size()==wet.size() and spans.all(func(span: Dictionary)->bool:return span.points.size()>1 and span.end>span.start))
	var original_hash:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	for i in 3:await process_frame
	var world: Node=game.ground
	world.set_process(false)
	check("actual_game_generates_automatic_spans",world.data.bridges.size()>=3,world.bridge_diagnostics)
	check("old_bridge_rails_are_replaced_instead_of_duplicated",world.bridge_diagnostics.removed_legacy_rails>0 and world.data.bridge_wall_indices.size()>0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/bridges-audit"))
	var output:=FileAccess.open("res://.runtime/bridges-audit/runtime-spans.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(world.data.bridges));output.close()
	var shape: Shape2D=game.vehicle.get_node("CollisionShape2D").shape
	var blocked: Array=[];var surfaced:=true;var indexed:=true;var drawn:=true
	for id in world.data.bridges.size():
		var bridge: Dictionary=world.data.bridges[id]
		var path:=PackedVector2Array()
		for p in bridge.points:path.append(Geometry.v(p))
		for fraction in [0.0,.2,.4,.6,.8,1.0]:
			var station: float=lerpf(float(bridge.start),float(bridge.end),fraction)
			var tiny:=Geometry.slice_path(path,maxf(0,station-float(bridge.start)-.01),minf(float(bridge.end)-float(bridge.start),station-float(bridge.start)+.02))
			if tiny.size()<2:continue
			var p:=tiny[0]*20;var direction: Vector2=tiny[-1]-tiny[0]
			world.stream_at(p)
			while not world.pending.is_empty():world._build_chunk(world.pending.pop_front())
			await physics_frame
			var cell:=Vector2i((p/20/world.chunk_m).floor());var key: String="%d,%d"%[cell.x,cell.y]
			indexed=indexed and id in world.data.chunks[key].get("bridges",[])
			drawn=drawn and world.chunks[cell].has_node("BridgeDeckClip") and world.chunks[cell].has_node("BridgeRailsClip")
			surfaced=surfaced and str(world.surface_at(p).name) in ["ASPHALT","GRAVEL","DIRT"]
			var query:=PhysicsShapeQueryParameters2D.new();query.shape=shape;query.collision_mask=1
			query.transform=Transform2D(direction.angle()+PI*.5,p)
			if not root.world_2d.direct_space_state.intersect_shape(query,1).is_empty():blocked.append([bridge.road,fraction])
	check("bridge_art_and_data_are_present_in_every_touched_chunk",indexed and drawn)
	check("bridges_keep_the_existing_driving_surface",surfaced)
	check("vehicle_fits_on_bridge_and_both_approaches",blocked.is_empty(),blocked)
	var before:=JSON.stringify(world.data.bridges);var wall_count: int=world.data.walls.size()
	Migration.apply(world.data,world.data.bridges.duplicate(true))
	check("runtime_bridge_migration_is_idempotent",before==JSON.stringify(world.data.bridges) and wall_count==world.data.walls.size())
	var editor=game.native_world_editor
	check("editor_opens_with_automatic_bridges",editor!=null and editor.open_editor())
	var points: Array[Vector2]=[Vector2(1060,1490),Vector2(1660,1490)]
	var identity: String=editor.authoring.add_road_path(points,{"roadClass":"country","surface":"asphalt","width":10,"lanes":2})
	editor.source_id=identity;editor._refresh_authoring()
	var id:=int(identity.trim_prefix("road-"))
	check("new_editor_road_over_water_gets_a_bridge_immediately",not identity.is_empty() and editor.bridge_preview.by_road.get(id,[]).size()>0)
	var generations: int=editor.bridge_preview.generation_count
	editor._refresh_authoring()
	check("unchanged_editor_bridges_are_cached",editor.bridge_preview.generation_count==generations)
	editor.authoring.move_shape("roads",identity,Vector2(0,-650));editor._refresh_authoring()
	check("moving_road_back_onto_land_removes_bridge",editor.bridge_preview.by_road.get(id,[]).is_empty())
	editor._undo()
	check("undo_restores_the_automatic_bridge",editor.bridge_preview.by_road.get(id,[]).size()>0)
	editor._discard_draft()
	var water: Array[Vector2]=[Vector2(2460,3110),Vector2(2530,3110),Vector2(2530,3170),Vector2(2460,3170)]
	var region_id: String=editor.authoring.add_region(water,"lake");editor._refresh_authoring()
	check("painting_water_under_an_existing_road_adds_a_bridge",not region_id.is_empty() and editor.bridge_preview.by_road.get(0,[]).size()>0 and editor.bridge_preview.redraw_roads.has(0))
	editor._undo()
	check("undoing_water_edit_removes_derived_bridge",not editor.bridge_preview.by_road.has(0))
	editor._fit_map();await process_frame
	check("full_map_editor_includes_bridge_rendering",editor.overview_renderer.full_world.content.bridges.size()==world.data.bridges.size())
	editor._discard_draft();editor.close_editor()
	check("leaving_editor_clears_bridge_preview_masks",Art.editor_hidden.is_empty())
	check("automatic_generation_does_not_write_real_map_files",FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==original_hash)
	game.queue_free();await process_frame;await process_frame
	print("AUTOMATIC ROAD BRIDGES: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
