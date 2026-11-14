extends CanvasLayer
## First native Streetbound world editor milestone: directly inspect the real
## rendered Morrow Coast, paved junctions, source props, and traffic network.
## Source edits are undoable drafts; writes use the existing validated Python rebaker.
const Geometry = preload("res://scripts/world/map_geometry.gd")
const Gizmos = preload("res://scripts/dev/native_world_editor_gizmos.gd")
const EditSession = preload("res://scripts/dev/native_map_edit_session.gd")
const LocalBridge = preload("res://scripts/dev/native_map_bridge.gd")
const Scenery = preload("res://scripts/world/coast_scenery.gd")
const Roads = preload("res://scripts/world/coast_roads.gd")
const TrafficPreview=preload("res://scripts/dev/native_traffic_preview.gd")
const Overview=preload("res://scripts/dev/editor_world_overview.gd")
const RenderTiles=preload("res://scripts/dev/editor_render_tiles.gd")
const Layout=preload("res://scripts/dev/native_editor_layout.gd")
const BridgePreview=preload("res://scripts/dev/native_bridge_preview.gd")
const BridgeArt=preload("res://scripts/world/coast_bridges.gd")
const MountainArt=preload("res://scripts/world/coast_mountain_barriers.gd")
const MountainGeometry=preload("res://scripts/world/mountain_barrier_geometry.gd")
const PPM := 20.0
const PANEL_COLOR := Color("#141e2b")
const ACCENT := Color("#f4a667")
var world
var standalone_mode := false
var render_tiles: Node2D
var player: VehicleController2D
var driving_camera: Camera2D
var traffic_network
var traffic_preview:=TrafficPreview.new()
var bridge_preview:=BridgePreview.new()
var editor_camera: Camera2D
var gizmos: Node2D
var active := false
var _owns_pause := false
var _right_drag := false
var _player_camera_enabled := true
var _player_camera_physics := true
var _player_camera_input := true
var _last_cell := Vector2i(-999,-999)
var _refresh_elapsed := 0.0
var root_ui: Control
var inspector_panel: PanelContainer
var asset_dock: PanelContainer
var edit_actions: Control
var draft_points: Array[Vector2] = []
var preview_hidden: Dictionary = {}
var synced_preview_revision := -1
var overview_sprite: Sprite2D
var overview_renderer: Node2D
var _game_render_visibility: Dictionary={}
var _owns_render_tiles:=false
var details: Label
var selected_preview: TextureRect
var status: Label
var lane_button: Button
var junction_button: Button
var selected: Dictionary = {}
var _hidden_game_ui: Dictionary = {}
var authoring
var bridge
var source_ready := false
var tool_name := "move_prop"
var source_id := ""
var source_anchor := -1
var pending_drag: Dictionary = {}
var drag_position := Vector2.ZERO
var snap_m := 1.0
const MIN_EDITOR_ZOOM := 0.003
const MAX_EDITOR_ZOOM := 5.0
var authoring_notice: Label
var mode_label: Label
var mode_buttons: Dictionary = {}
var asset_grid: GridContainer
var asset_search: LineEdit
var asset_category: OptionButton
var asset_count: Label
var asset_entries: Array[Dictionary] = []
var active_project_asset: Dictionary = {}
var finish_button: Button
var cancel_button: Button
var tool_options: Container
var settings_panel: PanelContainer
var canvas_bar: PanelContainer
var canvas_rect:=Rect2()
var road_settings: Control
var terrain_settings: Control
var marker_settings: Control
var prop_transforms: Control
var minimap: Control
var zoom_label: Label
var inspector_name: LineEdit
var inspector_x: SpinBox
var inspector_y: SpinBox
var inspector_rotation: SpinBox
var inspector_scale: SpinBox
var point_picker: OptionButton
var remove_point_button: Button
var add_point_button: Button
var split_road_button: Button
var entity_search: LineEdit
var entity_list: ItemList
var _entity_revision:=-1
var _updating_inspector:=false
var layer_flags: Dictionary={"terrain":true,"roads":true,"scenery":true,"markers":true,"grid":false}
var _landmark_visibility: Dictionary={}
var _space_pan:=false
var road_surface: OptionButton
var road_width: SpinBox
var road_lanes: SpinBox
var road_class: OptionButton
var terrain_biome: OptionButton
var terrain_barrier: CheckBox
var terrain_elevation: SpinBox
var marker_kind: OptionButton
var _setting_controls:=false
var grid_button: Button
var recovery_path: String="user://native-map-draft-"+ProjectSettings.globalize_path("res://").sha256_text().substr(0,12)+".json"
var _recovery_revision:=-1
var _auto_quit_before:=true
var reload_button: Button
var apply_button: Button
var source_revision := ""
var loaded_world_sha := ""
var submitted_source: Dictionary = {}
static var resume_after_rebuild := false
static var resume_editor_position := Vector2.ZERO


func _ready() -> void:
	if OS.has_environment("STREETBOUND_EDITOR_RECOVERY_PATH"):
		recovery_path=OS.get_environment("STREETBOUND_EDITOR_RECOVERY_PATH")
	name = "NativeWorldEditor"
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Never create the editor in a release export. Even debug builds only
	# inspect data: they cannot overwrite generated worlds or source edits.
	root_ui = Control.new()
	root_ui.name = "MapEditorUI"
	root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ui)
	_build_ui()
	_build_authoring_ui()
	_build_asset_browser()
	authoring = EditSession.new()
	bridge = Node.new()
	bridge.set_script(LocalBridge)
	bridge.completed.connect(_on_apply_completed)
	add_child(bridge)
	root_ui.visible = false
	gizmos = Node2D.new()
	gizmos.set_script(Gizmos)
	gizmos.world = world
	gizmos.network = traffic_network
	get_parent().add_child.call_deferred(gizmos)
	set_process(false)
	if resume_after_rebuild:
		var saved_position := resume_editor_position
		resume_after_rebuild = false
		call_deferred("_reopen_baked_world",saved_position)

func _reopen_baked_world(where: Vector2) -> void:
	if not is_inside_tree() or not is_instance_valid(world):
		return
	if open_editor():
		editor_camera.global_position = where
		_update_view(true)
		_notice("Rebuilt map loaded: inspect refreshed intersections and traffic.")

func _build_authoring_ui() -> void:
	_update_active_tool_style()
	_update_context_panels()


func _update_active_tool_style() -> void:
	for key in mode_buttons:
		var button: Button = mode_buttons[key]
		var chosen: bool=key==tool_name or (key=="place:house" and tool_name.begins_with("place:"))
		var skin: StyleBoxFlat=button.get_theme_stylebox("normal").duplicate()
		skin.bg_color=Color("#433325") if chosen else Color("#1d2b3d")
		skin.border_color=ACCENT if chosen else Color("#334257")
		button.add_theme_stylebox_override("normal",skin)
		button.add_theme_color_override("font_color",
			ACCENT if key == tool_name or (key == "place:house" and
			tool_name.begins_with("place:")) else Color("#eef0ef"))
		button.add_theme_color_override("font_hover_color",ACCENT)


func _build_asset_browser() -> void:
	_scan_asset_library()
	_update_context_panels()


func _scan_asset_library() -> void:
	asset_entries.clear()
	# Same folder hierarchy and project-id hashing used by the browser
	# asset catalog and Python source importer.
	_walk_building_assets("res://assets/Buildings")
	var atlas: Texture2D = load("res://assets/scenery/morrow-atlas-v1.png")
	var names := [
		["House roof","house",Rect2(103,28,261,391),"house"],
		["Coastal house","coastal_house",Rect2(532,14,273,409),"house"],
		["Shop / cafe","shop",Rect2(968,26,278,396),"building"],
		["Garage / showroom","garage",Rect2(1411,21,281,396),"garage"],
		["Tree","tree",Rect2(26,477,397,380),"nature"],
		["Pine","pine",Rect2(472,467,388,389),"nature"],
		["Palm","palm",Rect2(910,467,406,387),"nature"],
		["Rock","rock",Rect2(1366,500,361,323),"nature"]]
	if atlas != null:
		for item in names:
			var crop := AtlasTexture.new()
			crop.atlas = atlas
			crop.region = item[2]
			asset_entries.append({"name":item[0],"kind":item[1],
				"category":item[3],"texture":crop,"project":false})
	asset_entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	_filter_assets()


func _walk_building_assets(folder: String) -> void:
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var child := folder.path_join(entry)
			if directory.current_is_dir():
				_walk_building_assets(child)
			elif entry.get_extension().to_lower() in ["png","webp","svg"]:
				var texture: Texture2D = load(child) as Texture2D
				if texture != null:
					var relative := child.trim_prefix("res://assets/")
					var name := entry.get_basename().replace("_"," ").replace("-"," ")
					var lower := name.to_lower()
					var kind := "house" if "house" in lower and not "warehouse" in lower else \
						"warehouse" if "warehouse" in lower else \
						"garage" if "garage" in lower else "building"
					var category := "house" if kind == "house" else \
						"garage" if kind == "garage" else "building"
					asset_entries.append({"name":name,"kind":kind,"category":category,
						"texture":texture,"path":relative,"project":true})
		entry = directory.get_next()
	directory.list_dir_end()


func _filter_assets() -> void:
	if not is_instance_valid(asset_grid):
		return
	for node in asset_grid.get_children():
		asset_grid.remove_child(node)
		node.queue_free()
	var keyword := asset_search.text.strip_edges().to_lower()
	var category := asset_category.selected
	var count := 0
	for entry in asset_entries:
		if not keyword.is_empty() and keyword not in str(entry.name).to_lower():
			continue
		if category == 1 and entry.category != "house":
			continue
		if category == 2 and entry.category != "building":
			continue
		if category == 3 and entry.category != "garage":
			continue
		if category == 4 and entry.category != "nature":
			continue
		var button := Button.new()
		button.name = "Asset_"+str(count)
		button.custom_minimum_size = Vector2(98,106)
		button.tooltip_text = str(entry.name)
		button.pressed.connect(_select_asset.bind(entry))
		var tile := VBoxContainer.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(tile)
		tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile.offset_left = 5
		tile.offset_top = 5
		tile.offset_right = -5
		tile.offset_bottom = -5
		var photo := TextureRect.new()
		photo.texture = entry.texture
		photo.custom_minimum_size = Vector2(86,68)
		photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(photo)
		var label := Label.new()
		label.text = str(entry.name)
		label.clip_text = true
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",11)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(label)
		asset_grid.add_child(button)
		count += 1
	asset_count.text = "%d assets  /  click to place" % count


func _select_asset(entry: Dictionary) -> void:
	if _editing_locked():
		return
	if bool(entry.get("project",false)):
		active_project_asset = entry.duplicate()
		_choose_tool("place:project")
	else:
		active_project_asset.clear()
		_choose_tool("place:"+str(entry.kind))
	if tool_name.begins_with("place:"):
		_notice("Selected "+str(entry.name)+". Click to place with live artwork and collision.")


func _update_context_panels() -> void:
	if not is_instance_valid(tool_options):return
	var road_selected: bool=source_ready and not authoring.road_at_id(source_id).is_empty()
	var record:=_selected_record()
	road_settings.visible=tool_name in ["move_prop","anchor","pan","draw_road"] or road_selected
	if record.get("category","")=="regions":road_settings.visible=false
	terrain_settings.visible=tool_name=="draw_terrain" or record.get("category","")=="regions"
	marker_settings.visible=tool_name=="place_marker"
	asset_dock.visible=tool_name.begins_with("place:")
	finish_button.disabled=draft_points.size()<(2 if tool_name=="draw_road" else 3)
	cancel_button.disabled=draft_points.is_empty() and pending_drag.is_empty()
	if road_selected and tool_name!="draw_road":
		_setting_controls=true
		var road: Dictionary=authoring.road_at_id(source_id)
		road_width.value=float(road.width);road_lanes.value=int(road.lanes)
		for option in [road_class,road_surface]:
			var value:=str(road.roadClass) if option==road_class else str(road.surface)
			for i in option.item_count:
				if str(option.get_item_metadata(i))==value:option.select(i);break
		_setting_controls=false
	if record.get("category","")=="regions" and tool_name!="draw_terrain":
		_setting_controls=true
		for i in terrain_biome.item_count:
			if str(terrain_biome.get_item_metadata(i))==str(record.item.biome):terrain_biome.select(i);break
		terrain_barrier.button_pressed=bool(record.item.get("barrier",false))
		terrain_elevation.value=float(record.item.get("elevation",0))
		_setting_controls=false
	terrain_elevation.editable=terrain_barrier.button_pressed


func _redraw_visible_scenery() -> void:
	if not is_instance_valid(world):
		return
	var loaded: Array = world.chunks.values()
	if is_instance_valid(render_tiles):
		loaded = render_tiles.tiles.values()
	for chunk in loaded:
		if not is_instance_valid(chunk):
			continue
		for canvas in chunk.get_children():
			if canvas is Node2D and (canvas.get_script() == \
					preload("res://scripts/world/coast_scenery.gd") or \
					canvas.get_script() == preload("res://scripts/world/coast_shadows.gd")):
				canvas.queue_redraw()
	_update_overview_mask()


func _restore_colliders() -> void:
	if not is_instance_valid(world):
		return
	for chunk in world.chunks.values():
		if not is_instance_valid(chunk) or not is_instance_valid(chunk.collider_body):
			continue
		for collider in chunk.collider_body.get_children():
			if collider is CollisionShape2D and collider.has_meta("editor_prop_key"):
				collider.disabled = false
			if collider is CollisionPolygon2D and collider.has_meta("editor_terrain_key"):collider.disabled=false


func _clear_editor_preview() -> void:
	Roads.editor_hidden={}
	BridgeArt.editor_hidden={}
	MountainArt.editor_hidden={}
	_redraw_mountains()
	_update_overview_mask()
	_redraw_roads()
	synced_preview_revision = -1
	if not preview_hidden.is_empty():
		preview_hidden.clear()
		Scenery.editor_hidden = {}
		_redraw_visible_scenery()
	_restore_colliders()
	if is_instance_valid(overview_sprite):
		overview_sprite.visible = false


func _sync_editor_preview() -> void:
	if not active or not source_ready or not is_instance_valid(world):
		return
	if synced_preview_revision == authoring.edit_revision:
		return
	synced_preview_revision = authoring.edit_revision
	var next_hidden: Dictionary = {}
	for prop in authoring.doc.get("props",[]):
		var initial_prop: Dictionary = {}
		for old in authoring.initial.get("props",[]):
			if str(old.get("id","")) == str(prop.get("id","")):
				initial_prop = old
				break
		if not initial_prop.is_empty() and JSON.stringify(initial_prop) != JSON.stringify(prop):
			next_hidden["authored:"+str(prop.id)] = true
		if prop.has("replaces"):
			var source: Dictionary = prop.replaces
			var pos: Array = source.get("p",[])
			if pos.size()==2:
				var source_pos := Vector2(float(pos[0]),float(pos[1]))
				for original in world.data.get("props",[]):
					var original_pos: Array = original.get("p",[])
					if original_pos.size()==2 and \
							str(original.get("kind","")) == str(source.get("kind","")) and \
							int(original.get("seed",-1)) == int(source.get("seed",-2)) and \
							Vector2(float(original_pos[0]),float(original_pos[1])).distance_to(
								source_pos) < 0.025:
						next_hidden[Scenery.editor_key(original)] = true
						break
	if next_hidden != preview_hidden:
		preview_hidden = next_hidden
		Scenery.editor_hidden = preview_hidden.duplicate()
		_redraw_visible_scenery()
		if is_instance_valid(render_tiles):
			render_tiles.redraw_scenery()
	# Source previews have their own real CollisionShape2D, and stale
	# baked shapes are disabled only for the editing session.
	for chunk in world.chunks.values():
		if not is_instance_valid(chunk) or not is_instance_valid(chunk.collider_body):
			continue
		for collider in chunk.collider_body.get_children():
			if collider is CollisionShape2D and collider.has_meta("editor_prop_key"):
				collider.disabled = preview_hidden.has(
					str(collider.get_meta("editor_prop_key")))


func _fit_map() -> void:
	if not active or not is_instance_valid(world):
		return
	var size_m: Array = world.data.get("size",[6400,4800])
	var world_px := Vector2(float(size_m[0]),float(size_m[1]))*PPM
	var screen := canvas_rect.size-Vector2(36,36)
	var zoom := clampf(minf(screen.x/world_px.x,
		screen.y/world_px.y),MIN_EDITOR_ZOOM,MAX_EDITOR_ZOOM)
	editor_camera.zoom = Vector2.ONE*zoom
	editor_camera.global_position = world_px*0.5
	_position_camera_canvas()
	_update_view(true)

func _layout_workspace() -> void:
	Layout.resize(self)
	if active:
		_position_camera_canvas()
		_update_view(true)

func _position_camera_canvas() -> void:
	if not is_instance_valid(editor_camera):return
	editor_camera.offset=(get_viewport().get_visible_rect().size*.5-canvas_rect.get_center())/editor_camera.zoom
	editor_camera.force_update_scroll()

func _zoom_button(factor: float) -> void:
	_set_zoom(editor_camera.zoom.x*factor,canvas_rect.get_center())

func _set_zoom(value: float,anchor: Vector2) -> void:
	var before:=_event_world_position(anchor)
	editor_camera.zoom=Vector2.ONE*clampf(value,MIN_EDITOR_ZOOM,MAX_EDITOR_ZOOM)
	_position_camera_canvas()
	editor_camera.global_position+=before-_event_world_position(anchor)
	editor_camera.force_update_scroll()
	_update_view(true)


func _build_overview() -> void:
	if is_instance_valid(overview_sprite):
		return
	overview_renderer=Overview.new()
	overview_renderer.process_mode=Node.PROCESS_MODE_ALWAYS
	get_parent().add_child(overview_renderer)
	overview_renderer.setup(world)
	overview_sprite=overview_renderer.sprite
	overview_sprite.visible = false

func _prepare_render_tiles() -> void:
	if not is_instance_valid(render_tiles):
		render_tiles=RenderTiles.new();render_tiles.world=world
		get_parent().add_child(render_tiles);_owns_render_tiles=true
	_hide_gameplay_chunks()

func _hide_gameplay_chunks() -> void:
	if standalone_mode:return
	for chunk in world.chunks.values():
		if not _game_render_visibility.has(chunk):_game_render_visibility[chunk]=chunk.visible
		chunk.visible=false

func _restore_gameplay_render() -> void:
	for node in _game_render_visibility:
		if is_instance_valid(node):node.visible=bool(_game_render_visibility[node])
	_game_render_visibility.clear()
	for node in _landmark_visibility:
		if is_instance_valid(node):node.visible=bool(_landmark_visibility[node])
	_landmark_visibility.clear()
	if is_instance_valid(render_tiles):render_tiles.visible=false


func _notice(message: String) -> void:
	if is_instance_valid(authoring_notice):
		authoring_notice.text = message

func _choose_tool(mode: String) -> void:
	if _editing_locked():
		return
	if not source_ready and mode != "inspect":
		_notice("Source unavailable. The map can still be inspected.")
		return
	tool_name = mode
	draft_points.clear()
	if is_instance_valid(gizmos):
		gizmos.source_anchor_mode = mode == "anchor"
		gizmos.set_pending_shape(draft_points,mode)
	pending_drag.clear()
	if mode not in ["move_prop","anchor"]:source_id = ""
	selected={}
	gizmos.set_selection({})
	source_anchor = -1
	mode_label.text={"move_prop":"SELECT / EDIT","draw_road":"DRAW ROAD","draw_terrain":"TERRAIN REGION",
		"place_marker":"GAME MARKER","anchor":"ROAD POINTS","pan":"PAN VIEW"}.get(mode,"SCENERY")
	_update_active_tool_style()
	_update_context_panels()
	_notice({"move_prop":"Drag roads or objects to move. Drag a selected road handle to reshape; Shift-click to add a point.",
		"draw_road":"Click road points, then FINISH or Enter. Double-click also finishes. Escape cancels.",
		"draw_terrain":"Choose a material, click polygon vertices, then FINISH or Enter.",
		"place_marker":"Choose a marker type and click to place.","anchor":"Drag the orange road handles to reshape roads.",
		"pan":"Drag to pan; the mouse wheel zooms around the cursor."}.get(mode,"Choose artwork, then click the map to place it."))
	_refresh_authoring()

func _refresh_authoring() -> void:
	if not is_instance_valid(gizmos):
		return
	if source_ready and not source_id.is_empty():
		var record:=_selected_record()
		if record.is_empty() or bool(record.item.get("hidden",false)):source_id="";source_anchor=-1
		elif record.category=="roads" and source_anchor>=record.item.points.size():source_anchor=-1
	_sync_editor_preview()
	var preview_doc: Dictionary=authoring.road_preview_source(pending_drag) if source_ready else {}
	if source_ready:
		_sync_mountain_preview(preview_doc)
		bridge_preview.update(world.data,preview_doc,authoring.initial)
		gizmos.bridge_overrides=bridge_preview.by_road
		gizmos.bridge_redraw_roads=bridge_preview.redraw_roads
		if BridgeArt.editor_hidden!=bridge_preview.hidden:
			BridgeArt.editor_hidden=bridge_preview.hidden.duplicate()
			_redraw_roads();_update_overview_mask()
	_sync_road_preview(preview_doc)
	_update_source_details()
	_save_recovery()
	_update_context_panels()
	_refresh_inspector()
	_refresh_entity_list()
	if source_ready:
		gizmos.road_width_scale=float(world.data.get("road_width_scale",1.0))/float(authoring.doc.get("morrowRoadWidthScale",1.0))
		traffic_preview.request(world.data,preview_doc,authoring.initial)
		_update_traffic_preview()
		gizmos.set_draft(preview_doc,authoring.initial,
			{} if pending_drag.get("kind","") in ["road","road_move","region"] else pending_drag,
			source_id,source_anchor)
		gizmos.set_pending_shape(draft_points,tool_name)
		if is_instance_valid(apply_button):
			apply_button.disabled = not authoring.dirty or bridge.phase != ""
	else:
		gizmos.set_draft({},{})

func _editing_locked() -> bool:
	if is_instance_valid(bridge) and bridge.phase != "":
		_notice("Map rebuild is running. Source edits are locked until it finishes.")
		return true
	if not source_revision.is_empty():
		_notice("World rebuilt. Select RELOAD WORLD before creating more edits.")
		return true
	return false

func _undo() -> void:
	if _editing_locked():
		return
	if not draft_points.is_empty():
		draft_points.pop_back();_refresh_authoring();_notice("Removed the last unfinished shape point.");return
	if source_ready and authoring.undo():
		pending_drag.clear()
		_refresh_authoring()
		_notice("Undid the previous source edit. Changes remain unbaked.")

func _redo() -> void:
	if _editing_locked():
		return
	if source_ready and authoring.redo():
		pending_drag.clear()
		_refresh_authoring()
		_notice("Redid the source edit. Intersections rebuild only after Apply.")

func _discard_draft() -> void:
	if _editing_locked():
		return
	if source_ready:
		authoring.discard_changes()
		pending_drag.clear()
		draft_points.clear()
		source_id = ""
		source_anchor = -1
		_refresh_authoring()
		_notice("All unsaved edits discarded; original authoring source restored.")

func _resize_selected(factor: float) -> void:
	if _editing_locked() or not source_ready or source_id.is_empty():
		return
	if authoring.resize_prop(source_id,factor):
		_refresh_authoring()
		_notice("Asset size and draft collision updated. Save to Game when ready.")


func _rotate_selected(degrees: float) -> void:
	if _editing_locked():
		return
	if not source_ready or source_id.is_empty():
		return
	if authoring.rotate_prop(source_id,degrees):
		_refresh_authoring()
		_notice("Asset and collision rotated %.0f° in editor. Save to Game when ready." % degrees)

func _toggle_snap() -> void:
	snap_m = 0.0 if snap_m > 0.0 else 1.0
	grid_button.text="Snap to grid: off" if snap_m==0 else "Snap to grid: 1 m"
	_notice("Grid snapping %s; linked endpoints stay connected." % [
		"disabled" if snap_m == 0.0 else "set to 1 metre"])

func _delete_selected() -> void:
	if _editing_locked():
		return
	if not source_ready or source_id.is_empty():
		return
	if authoring.delete_entity(source_id):
		source_id = ""
		_refresh_authoring()
		_notice("Object deleted from draft. Undo is available.")
	else:
		_notice(authoring.last_error)

func _start_backend() -> void:
	if bridge.start_backend():
		_notice("Local Python rebaker ready. Save to Game uses validation and rollback.")
	else:
		_notice(bridge.last_error)

func _apply_draft() -> void:
	if _editing_locked():
		return
	if not draft_points.is_empty() or not pending_drag.is_empty():
		_notice("Finish or cancel the current shape or drag before saving.")
		return
	if not source_ready or not authoring.dirty:
		_notice("No authoring edits to apply.")
		return
	if not authoring._valid_source(authoring.doc):
		_notice("Source validation failed; changes were not saved.")
		return
	if bridge.apply_source(authoring.doc,authoring.baseline_hash,loaded_world_sha):
		submitted_source = authoring.doc.duplicate(true)
		_notice("Verifying map revision and source, then rebuilding Morrow Coast...")
		_refresh_authoring()
	else:
		_notice(bridge.last_error)

func _on_apply_completed(ok: bool, message: String, new_sha: String) -> void:
	if ok:
		# The submitted snapshot, never an unverified later draft, is what
		# the transactional backend actually wrote to the source directory.
		authoring.accepted_remote(submitted_source)
		source_revision = new_sha
		reload_button.disabled = false
		_refresh_authoring()
		_notice(message)
		if standalone_mode and get_tree().current_scene==get_parent():
			call_deferred("_reload_world")
	else:
		_refresh_authoring()
		_notice("APPLY FAILED (original files restored): "+message)
	submitted_source.clear()

func _reload_world() -> void:
	if not active or source_revision.is_empty() or authoring.dirty:
		_notice("Apply or discard outstanding edits before reloading.")
		return
	if bridge.phase != "":
		_notice("World is still rebuilding.")
		return
	resume_editor_position = editor_camera.global_position
	resume_after_rebuild = true
	# The actual scene/world and traffic must reload from the freshly baked
	# archive. Never reuse the old runtime's road geometry after saving.
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")

func _ensure_editable_runtime_prop(item: Dictionary) -> String:
	var known: String = authoring.index_of_runtime_prop(item)
	if not known.is_empty():
		return known
	for prop in authoring.doc.get("props",[]):
		var prior: Dictionary = prop.get("replaces",{})
		if not prior.is_empty() and str(prior.get("kind","")) == str(item.get("kind","")) and \
				int(prior.get("seed",-1)) == int(item.get("seed",-2)) and \
				prior.get("p",[]) == item.get("p",[]):
			return str(prop.id)
	# Converts a regular generated prop into an editable replacement
	# automatically. Protected landmarks remain protected.
	return authoring.adopt_runtime_prop(item)


func _adopt_selected() -> void:
	if _editing_locked() or not source_ready:
		return
	if selected.get("kind","")!="prop":
		_notice("Inspect a real game building, tree or rock before selecting ADOPT.")
		return
	var index := int(selected.get("index",-1))
	if index<0 or index>=world.data.props.size():
		return
	var item: Dictionary = world.data.props[index]
	# The primary garage and gameplay POI structures must never be
	# adopted or replaced through a convenience button.
	var garage_geometry := preload("res://scripts/world/garage_geometry.gd")
	if garage_geometry.is_player_garage(item) or item.has("poi"):
		_notice("Protected garage or gameplay landmark: cannot replace it.")
		return
	var id: String = _ensure_editable_runtime_prop(item)
	if id.is_empty():
		_notice(authoring.last_error)
		return
	source_id = id
	source_anchor = -1
	tool_name = "move_prop"
	mode_label.text = "SELECT / EDIT"
	var source_item: Dictionary = authoring.prop_at_id(id)
	details.text = "SELECTED GAME ASSET\n%s\n\nDrag, rotate, resize or delete.\nUnsaved changes are visible now." % [
		str(source_item.get("name",""))]
	_refresh_authoring()
	_notice("Selected asset is editable; its art and collision now follow edits.")

func _pick_source_anchor(world_px: Vector2) -> Dictionary:
	if not source_ready or not layer_flags.roads:
		return {}
	var best := 11.0 / maxf(0.003,editor_camera.zoom.x)
	var result: Dictionary = {}
	for road in authoring.doc.roads:
		for i in road.points.size():
			var point := Vector2(float(road.points[i].x),
				float(road.points[i].y))*PPM
			var distance := point.distance_to(world_px)
			if distance < best:
				best = distance
				result = {"kind":"road","id":str(road.id),"index":i,
					"from":point}
	return result

func _pick_source_prop(world_px: Vector2) -> Dictionary:
	if not source_ready or not layer_flags.scenery:
		return {}
	var at: Vector2 = world_px/PPM
	var best := 6.0
	var hit: Dictionary = {}
	for index in range(authoring.doc.props.size()-1,-1,-1):
		var prop: Dictionary=authoring.doc.props[index]
		if bool(prop.get("hidden",false)):
			continue
		var center := Vector2(float(prop.x),float(prop.y))
		var footprint := Vector2(8,8)
		match str(prop.get("type","")):
			"house":footprint=Vector2(12,17)
			"building":footprint=Vector2(22,29)
			"warehouse":footprint=Vector2(28,37)
			"garage":footprint=Vector2(20,21)
			"parking":footprint=Vector2(38,28)
			"field":footprint=Vector2(90,70)
		if prop.has("assetSize") and prop.assetSize is Array and prop.assetSize.size()==2:
			footprint=Vector2(float(prop.assetSize[0]),float(prop.assetSize[1]))
		var local := (at-center).rotated(-deg_to_rad(float(prop.get("rotation",0))))
		var half := footprint*float(prop.get("scale",1))*0.5
		var distance := Vector2(maxf(0,absf(local.x)-half.x),
			maxf(0,absf(local.y)-half.y)).length()
		if distance < best:
			best = distance
			hit = {"kind":"prop","id":str(prop.id),"from":center*PPM}
	return hit

func _source_click(world_px: Vector2) -> void:
	if _editing_locked():
		return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null:focus.release_focus()
	if tool_name == "draw_road":
		var point:=_road_draw_point(world_px/PPM)
		if draft_points.is_empty() or draft_points[-1].distance_to(point)>=1.0:draft_points.append(point)
		_refresh_authoring()
		_notice("%d road points. FINISH / Enter to create the road; Esc cancels."%draft_points.size())
		return
	if tool_name == "draw_terrain":
		draft_points.append(_snap_point(world_px/PPM))
		_update_context_panels()
		gizmos.set_pending_shape(draft_points,tool_name)
		_notice("Terrain: click vertices, then press Enter to finish.")
		return
	if tool_name == "place_marker":
		source_id = authoring.add_marker(_snap_point(world_px/PPM),_option_value(marker_kind))
		_refresh_authoring()
		_notice("Game marker added to unsaved draft." if not source_id.is_empty() else authoring.last_error)
		return
	if tool_name.begins_with("place:"):
		var kind := tool_name.substr(6)
		var id := ""
		if kind == "project" and not active_project_asset.is_empty():
			var texture: Texture2D = active_project_asset.texture
			var base := Vector2(12,17)
			match str(active_project_asset.kind):
				"building": base = Vector2(22,29)
				"warehouse": base = Vector2(28,37)
				"garage": base = Vector2(20,21)
			var scale_factor: float = minf(base.x / maxf(1.0,texture.get_width()),
				base.y / maxf(1.0,texture.get_height()))
			var footprint := Vector2(texture.get_width(),texture.get_height()) * scale_factor
			id = authoring.add_project_prop(str(active_project_asset.path),
				str(active_project_asset.kind),world_px/PPM,footprint)
		else:
			id = authoring.add_prop(kind,world_px/PPM)
		if id != "":
			source_id = id
			source_anchor = -1
			_refresh_authoring()
			_notice("Placed "+kind+" with live artwork and collision preview. Save to Game when ready.")
		else:
			_notice(authoring.last_error)
		return
	if tool_name not in ["anchor","move_prop"]:
		select_at(world_px)
		return
	var hit: Dictionary={}
	if tool_name=="anchor":hit=_pick_source_anchor(world_px)
	else:
		hit=_pick_source_marker(world_px)
		if hit.is_empty():hit=_pick_source_mountain(world_px)
		if hit.is_empty():hit=_pick_source_prop(world_px)
		if hit.is_empty() and not source_id.is_empty() and not authoring.road_at_id(source_id).is_empty():
			var anchor:=_pick_source_anchor(world_px)
			if str(anchor.get("id",""))==source_id:hit=anchor
		if hit.is_empty():hit=_pick_source_road(world_px)
		if not hit.is_empty() and hit.kind=="road_move" and Input.is_physical_key_pressed(KEY_SHIFT):
			source_id=str(hit.id)
			authoring.insert_road_point(source_id,_snap_point(world_px/PPM))
			_refresh_authoring()
			return
		if hit.is_empty():hit=_pick_source_region(world_px)
	if hit.is_empty():
		if tool_name=="move_prop":
			var inspected: Dictionary = select_at(world_px)
			if inspected.get("kind","")=="prop":
				var item: Dictionary = world.data.props[int(inspected.index)]
				var editable_id := _ensure_editable_runtime_prop(item)
				if not editable_id.is_empty():
					var editable: Dictionary = authoring.prop_at_id(editable_id)
					hit = {"kind":"prop","id":editable_id,
						"from":Vector2(float(editable.x),float(editable.y))*PPM}
				else:
					_notice(authoring.last_error)
		else:
			_notice("Click an editable road control point.")
		if hit.is_empty():
			return
	source_id = str(hit.id)
	selected={}
	gizmos.set_selection({})
	source_anchor = int(hit.get("index",-1))
	pending_drag = hit.duplicate(true)
	pending_drag["grab"]=world_px
	pending_drag["to"] = hit.from
	if hit.kind=="road":
		var road: Dictionary = authoring.road_at_id(source_id)
		details.text = "AUTHORING ROAD\n%s\nPoint %d of %d\n\nDrag this anchor. Other joined ends move together.\nJunctions / traffic stay baked until Apply." % [
			str(road.get("name","")),source_anchor+1,road.points.size()]
	elif hit.kind=="prop":
		var prop: Dictionary = authoring.prop_at_id(source_id)
		details.text = "AUTHORED ASSET\n%s\n\nDrag to move; Rotate and Delete are below.\nSource ID: %s" % [
			str(prop.get("name","")),source_id]
	else:
		details.text="SELECTED %s\n%s\n\nDrag to move. Undo/Redo are available.\nRoad endpoints stay connected."%[str(hit.kind).to_upper(),source_id]
	_refresh_authoring()

func _finish_source_drag(world_px: Vector2) -> void:
	if _editing_locked():
		return
	if pending_drag.is_empty() or not source_ready:
		return
	var drag := pending_drag.duplicate(true)
	pending_drag.clear()
	var ok := false
	var destination_m: Vector2 = world_px/PPM
	if world_px.distance_to(drag.get("grab",drag.get("from",world_px)))<3.0/maxf(.003,editor_camera.zoom.x):
		_refresh_authoring()
		return
	if str(drag.kind)=="road":
		ok = authoring.move_road_point(str(drag.id),int(drag.index),
			destination_m,snap_m)
	elif str(drag.kind)=="prop":
		ok = authoring.move_prop(str(drag.id),(Vector2(drag.from)+world_px-Vector2(drag.grab))/PPM,snap_m)
	elif str(drag.kind) in ["road_move","region","marker"]:
		ok=authoring.move_shape({"road_move":"roads","region":"regions","marker":"markers"}[str(drag.kind)],
			str(drag.id),(world_px-Vector2(drag.grab))/PPM,snap_m)
	_refresh_authoring()
	if ok and authoring.dirty:
		_notice("Draft updated in memory. Save to Game when ready.")
	elif not ok:
		_notice(authoring.last_error)

func _panel(where: Vector2, dimensions: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = where
	p.custom_minimum_size = dimensions
	p.size = dimensions
	var skin := StyleBoxFlat.new()
	skin.bg_color = PANEL_COLOR
	skin.border_color = Color("#334257")
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(8)
	skin.content_margin_left = 10
	skin.content_margin_right = 10
	skin.content_margin_top = 7
	skin.content_margin_bottom = 7
	p.add_theme_stylebox_override("panel",skin)
	root_ui.add_child(p)
	return p

func _btn(text_value: String, parent: Node, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text_value
	b.focus_mode=Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(104,33)
	b.add_theme_font_size_override("font_size",12)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#1d2b3d")
	normal.border_color = Color("#334257")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal",normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#44382b")
	hover.border_color = ACCENT
	b.add_theme_stylebox_override("hover",hover)
	b.add_theme_stylebox_override("pressed",hover)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _build_ui() -> void:
	Layout.build(self)


func _can_enter() -> bool:
	if standalone_mode:
		return not active and is_instance_valid(world) and bool(world.initialization_complete)
	# A split-screen game has two cameras and a different input owner. Keep
	# this development workspace exclusively in single-player free roam.
	var split: Variant = get_parent().get("local_split_screen")
	return not active and not get_tree().paused and \
		is_instance_valid(player) and is_instance_valid(world) and \
		bool(world.initialization_complete) and \
		is_instance_valid(driving_camera) and \
		(not is_instance_valid(split) or not bool(split.get("active")))


func _set_game_ui_visible(restore: bool) -> void:
	if standalone_mode:
		return
	if restore:
		for node in _hidden_game_ui:
			if is_instance_valid(node):
				node.visible = bool(_hidden_game_ui[node])
		_hidden_game_ui.clear()
		return
	_hidden_game_ui.clear()
	for node in get_parent().get_children():
		if node is CanvasLayer and node != self:
			_hidden_game_ui[node] = node.visible
			node.visible = false

func open_editor() -> bool:
	if not _can_enter():
		return false
	if loaded_world_sha.is_empty():
		loaded_world_sha = FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	_owns_pause = not get_tree().paused
	if not source_ready:
		source_ready = authoring.load_source()
		if source_ready:source_ready=authoring.reconcile_runtime(world.data)
		if not source_ready:
			_notice("Source not loaded: "+authoring.last_error)
		else:
			_notice("Native source loaded. Select a tool; draft changes stay in memory.")
	if is_instance_valid(driving_camera):
		_player_camera_enabled = driving_camera.enabled
		_player_camera_physics = driving_camera.is_physics_processing()
		_player_camera_input = driving_camera.is_processing_unhandled_input()
	editor_camera = Camera2D.new()
	editor_camera.name = "WorldEditorCamera"
	editor_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	editor_camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	editor_camera.position = driving_camera.global_position if is_instance_valid(driving_camera) else world.spawn_position()
	editor_camera.rotation = 0.0
	editor_camera.zoom = driving_camera.zoom if is_instance_valid(driving_camera) else Vector2(0.35,0.35)
	editor_camera.zoom = editor_camera.zoom.clamp(
		Vector2(MIN_EDITOR_ZOOM,MIN_EDITOR_ZOOM),
		Vector2(MAX_EDITOR_ZOOM,MAX_EDITOR_ZOOM))
	get_parent().add_child(editor_camera)
	if is_instance_valid(driving_camera):
		driving_camera.enabled = false
		driving_camera.set_physics_process(false)
		driving_camera.set_process_unhandled_input(false)
	editor_camera.make_current()
	_position_camera_canvas()
	active = true
	if standalone_mode:
		_auto_quit_before=get_tree().auto_accept_quit
		get_tree().auto_accept_quit=false
	_restore_recovery()
	_build_overview()
	_prepare_render_tiles()
	overview_renderer.set_layers(layer_flags)
	render_tiles.set_layers(layer_flags)
	gizmos.layer_flags=layer_flags.duplicate()
	_apply_landmark_layer()
	_set_game_ui_visible(false)
	root_ui.visible = true
	gizmos.visible = true
	gizmos.set_preview_collision_enabled(not standalone_mode)
	_update_context_panels()
	_right_drag = false
	_last_cell = Vector2i(-999,-999)
	if not standalone_mode:
		get_tree().paused = true
	set_process(true)
	_update_selection({})
	_refresh_authoring()
	_update_view(true)
	return true

func close_editor() -> void:
	if not active:
		return
	if not draft_points.is_empty() or not pending_drag.is_empty():
		_notice("Finish or cancel the current shape or drag before leaving.")
		return
	if standalone_mode and source_ready and authoring.dirty:
		_notice("Unsaved changes. Save to Game or DISCARD before leaving.")
		return
	if is_instance_valid(bridge) and bridge.phase != "":
		_notice("Map save is still rebuilding. Exit after the transaction completes.")
		return
	active = false
	root_ui.visible = false
	gizmos.visible = false
	gizmos.set_preview_collision_enabled(false)
	_clear_editor_preview()
	_restore_gameplay_render()
	pending_drag.clear()
	_set_game_ui_visible(true)
	_right_drag = false
	set_process(false)
	if is_instance_valid(editor_camera):
		editor_camera.enabled = false
		editor_camera.queue_free()
	editor_camera = null
	if standalone_mode:
		get_tree().paused = false
		if get_tree().has_meta("streetbound_editor_return_position"):
			get_tree().remove_meta("streetbound_editor_return_position")
		if get_tree().has_meta("streetbound_editor_test_drive"):
			get_tree().remove_meta("streetbound_editor_test_drive")
		get_tree().change_scene_to_file("res://scenes/title_menu.tscn")
		return
	driving_camera.enabled = _player_camera_enabled
	driving_camera.set_physics_process(_player_camera_physics)
	driving_camera.set_process_unhandled_input(_player_camera_input)
	if _player_camera_enabled:
		driving_camera.make_current()
	# Restore normal stream focus before letting traffic/physics tick.
	world.stream_at(player.global_position)
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false

func _recenter() -> void:
	if active:
		editor_camera.global_position = player.global_position if is_instance_valid(player) else world.spawn_position()
		_update_view(true)

func _test_drive() -> void:
	if not active:
		return
	if not draft_points.is_empty() or not pending_drag.is_empty():
		_notice("Finish or cancel the current shape or drag before Test Drive.")
		return
	if standalone_mode:
		if authoring.dirty or bridge.phase != "":
			_notice("Save to Game or DISCARD before Test Drive.")
			return
		get_tree().set_meta("streetbound_editor_test_drive",true)
		get_tree().set_meta("streetbound_editor_return_position",
			editor_camera.global_position)
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		close_editor()


func _toggle_lanes() -> void:
	gizmos.show_lanes = not gizmos.show_lanes
	lane_button.text = "LANES: ON" if gizmos.show_lanes else "LANES: OFF"
	gizmos.queue_redraw()

func _toggle_junctions() -> void:
	gizmos.show_junctions = not gizmos.show_junctions
	junction_button.text = "JUNCTIONS: ON" if gizmos.show_junctions else "JUNCTIONS: OFF"
	gizmos.queue_redraw()

func _process(dt: float) -> void:
	if not active or not is_instance_valid(editor_camera):
		return
	traffic_preview.poll()
	_update_traffic_preview()
	if is_instance_valid(overview_sprite):overview_sprite.visible=not render_tiles.ready_to_show
	var direction := Vector2.ZERO
	var focus:=get_viewport().gui_get_focus_owner()
	var typing: bool=focus is LineEdit or focus is TextEdit
	if Input.is_physical_key_pressed(KEY_A) or (source_id.is_empty() and Input.is_physical_key_pressed(KEY_LEFT)):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or (source_id.is_empty() and Input.is_physical_key_pressed(KEY_RIGHT)):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or (source_id.is_empty() and Input.is_physical_key_pressed(KEY_UP)):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or (source_id.is_empty() and Input.is_physical_key_pressed(KEY_DOWN)):
		direction.y += 1.0
	if direction != Vector2.ZERO and not typing and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_ALT):
		editor_camera.global_position += direction.normalized() * dt * \
			950.0 / maxf(0.008,editor_camera.zoom.x)
	_refresh_elapsed += dt
	if _refresh_elapsed >= 0.12:
		_refresh_elapsed = 0.0
		_update_view()

func _update_view(force: bool = false) -> void:
	if not active:
		return
	# Morrow Coast normally streams around the player in _process(), which
	# is paused in this mode. Load one real, collision-bearing chunk per UI
	# update instead of creating a fake editor-only representation.
	var here: Vector2 = editor_camera.global_position
	var cell := Vector2i((here/PPM/float(world.chunk_m)).floor())
	if not standalone_mode:
		if cell != _last_cell or force:
			world.stream_at(here)
			_last_cell = cell
		if not world.pending.is_empty():
			world._build_chunk(world.pending.pop_front())
		_hide_gameplay_chunks()
	if is_instance_valid(render_tiles):
		render_tiles.configure(editor_camera.get_screen_center_position(),get_viewport().get_visible_rect().size,editor_camera.zoom.x)
		if is_instance_valid(overview_sprite):overview_sprite.visible=not render_tiles.ready_to_show
	_sync_editor_preview()
	gizmos.set_view(editor_camera.get_screen_center_position(),get_viewport().get_visible_rect().size,
		editor_camera.zoom.x)
	zoom_label.text="%.1f%%"%[editor_camera.zoom.x*100]
	var meters := here / PPM
	if is_instance_valid(render_tiles):
		status.text = "WORLD  X %.0fm  Y %.0fm  |  %d roads  %d junctions  |  %d visible tiles  |  %s" % [
			meters.x,meters.y,world.data.roads.size(),world.data.junctions.size(),
			render_tiles.total_visible,"DETAIL" if render_tiles.detailed else "OVERVIEW"]
	else:
		status.text = "WORLD  X %.0fm  Y %.0fm   |   %d roads   %d intersections   %d traffic links" % [
			meters.x,meters.y,world.data.roads.size(),world.data.junctions.size(),
			traffic_network.edges.size() if is_instance_valid(traffic_network) else 0]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			var focus:=get_viewport().gui_get_focus_owner()
			if active and (focus is LineEdit or focus is TextEdit):return
			if key.keycode == KEY_F6 or key.physical_keycode == KEY_F6:
				if active:
					_test_drive()
				elif bool(get_tree().get_meta("streetbound_editor_test_drive",false)):
					get_tree().remove_meta("streetbound_editor_test_drive")
					get_tree().paused = false
					get_tree().change_scene_to_file("res://scenes/world_editor.tscn")
				else:
					open_editor()
				get_viewport().set_input_as_handled()
				return
			if active and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
				if not draft_points.is_empty() or not pending_drag.is_empty():
					_cancel_gesture()
				else:
					close_editor()
				get_viewport().set_input_as_handled()
				return
			if active and tool_name in ["draw_terrain","draw_road"] and key.keycode in [KEY_ENTER,KEY_KP_ENTER]:
				_finish_shape()
				get_viewport().set_input_as_handled()
				return
			# Mirror the browser map editor's V/R/T/P/M/H tool shortcuts.
			# Never intercept typing in the searchable asset browser.
			var focused := get_viewport().gui_get_focus_owner()
			if active and not key.ctrl_pressed and not key.alt_pressed and \
					not (focused is LineEdit or focused is TextEdit):
				var shortcut := ""
				match key.physical_keycode:
					KEY_V: shortcut = "move_prop"
					KEY_R: shortcut = "draw_road"
					KEY_T: shortcut = "draw_terrain"
					KEY_P: shortcut = "place:house"
					KEY_M: shortcut = "place_marker"
					KEY_H: shortcut = "pan"
				if not shortcut.is_empty():
					_choose_tool(shortcut)
					get_viewport().set_input_as_handled()
					return
			if active and key.ctrl_pressed and (key.keycode in [KEY_Z,KEY_Y] or
					key.physical_keycode in [KEY_Z,KEY_Y]):
				if key.keycode==KEY_Y or key.physical_keycode==KEY_Y or key.shift_pressed:
					_redo()
				else:
					_undo()
				get_viewport().set_input_as_handled()
				return
			if active and key.ctrl_pressed and key.keycode==KEY_S:
				_apply_draft();get_viewport().set_input_as_handled();return
			if active and key.ctrl_pressed and key.keycode==KEY_D:
				_duplicate_selected();get_viewport().set_input_as_handled();return
			if active and key.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN] and not source_id.is_empty():
				_nudge_selected({KEY_LEFT:Vector2.LEFT,KEY_RIGHT:Vector2.RIGHT,KEY_UP:Vector2.UP,KEY_DOWN:Vector2.DOWN}[key.keycode],key.shift_pressed)
				get_viewport().set_input_as_handled();return
			if active and key.keycode==KEY_F:
				_fit_map();get_viewport().set_input_as_handled();return
			if active and key.keycode in [KEY_DELETE,KEY_BACKSPACE]:
				_delete_selected();get_viewport().set_input_as_handled();return
	if not active:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			_right_drag = mouse.pressed
			get_viewport().set_input_as_handled()
		elif mouse.pressed and mouse.button_index in [
				MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.13 if mouse.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.13
			_set_zoom(editor_camera.zoom.x*factor,mouse.position)
			get_viewport().set_input_as_handled()
		elif mouse.button_index==MOUSE_BUTTON_LEFT:
			if tool_name == "pan" or Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE):
				_right_drag = mouse.pressed
				_space_pan=mouse.pressed and tool_name!="pan"
				get_viewport().set_input_as_handled()
				return
			var hit_position: Vector2 = _event_world_position(mouse.position)
			if mouse.pressed:
				_source_click(hit_position)
				if mouse.double_click and tool_name in ["draw_road","draw_terrain"]:_finish_shape()
			elif not pending_drag.is_empty():
				_finish_source_drag(hit_position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _right_drag:
			editor_camera.global_position -= motion.relative/editor_camera.zoom
			get_viewport().set_input_as_handled()
		elif not pending_drag.is_empty():
			_update_drag_preview(_event_world_position(motion.position))
			get_viewport().set_input_as_handled()

func _event_world_position(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse()*screen_position

func _exit_tree() -> void:
	traffic_preview.finish()
	_restore_gameplay_render()
	if is_instance_valid(overview_renderer):overview_renderer.queue_free()
	if _owns_render_tiles and is_instance_valid(render_tiles):render_tiles.queue_free()
	if standalone_mode:get_tree().auto_accept_quit=_auto_quit_before
	Roads.editor_hidden={}
	BridgeArt.editor_hidden={}
	MountainArt.editor_hidden={}
	Scenery.editor_hidden={}

func _save_recovery() -> void:
	if not standalone_mode or not active or not source_ready or not pending_drag.is_empty() or _recovery_revision==authoring.edit_revision:return
	_recovery_revision=authoring.edit_revision
	if not authoring.dirty:
		if FileAccess.file_exists(recovery_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery_path))
		return
	var file:=FileAccess.open(recovery_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"source_hash":authoring.baseline_hash,"world_sha":loaded_world_sha,"doc":authoring.doc}))

func _restore_recovery() -> void:
	if not standalone_mode or not source_ready or not FileAccess.file_exists(recovery_path):return
	var stored: Variant=JSON.parse_string(FileAccess.get_file_as_string(recovery_path))
	if stored is Dictionary and str(stored.get("source_hash",""))==authoring.baseline_hash and str(stored.get("world_sha",""))==loaded_world_sha and stored.get("doc") is Dictionary and authoring._valid_source(stored.doc):
		authoring.doc=stored.doc.duplicate(true)
		authoring.history.clear()
		authoring.history.append(authoring.initial.duplicate(true))
		authoring.dirty=authoring._fingerprint(authoring.doc)!=authoring.draft_baseline_hash
		authoring.edit_revision+=1
		_notice("Recovered your unsaved editor draft. Review it, then Save to Game or Discard.")
	else:
		# Preserve old drafts without applying them to a different world revision.
		var backup:=recovery_path+".previous-"+str(Time.get_unix_time_from_system())+".json"
		DirAccess.rename_absolute(ProjectSettings.globalize_path(recovery_path),ProjectSettings.globalize_path(backup))
		_notice("An older recovery draft was retained separately; this editor uses the current world.")

# Gesture completion must run before GUI filtering. Releasing over a panel
# used to leave a drag stuck, because _unhandled_input never saw the release.
func _input(event: InputEvent) -> void:
	if not active:return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE] or (event.button_index==MOUSE_BUTTON_LEFT and (tool_name=="pan" or _space_pan)):
			_right_drag=false
			_space_pan=false
		if event.button_index==MOUSE_BUTTON_LEFT and not pending_drag.is_empty():
			_finish_source_drag(_event_world_position(event.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if not pending_drag.is_empty():
			_update_drag_preview(_event_world_position(event.position))
			get_viewport().set_input_as_handled()
		elif _right_drag:
			editor_camera.global_position-=event.relative/editor_camera.zoom
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and not pending_drag.is_empty():
		_cancel_gesture();get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and active and standalone_mode:
		if bridge.phase!="":
			_notice("Please wait for Save to Game to finish before closing the editor.")
		elif not draft_points.is_empty():
			_notice("Finish or cancel the unfinished shape before closing. Your committed draft is saved locally.")
		else:
			_save_recovery()
			get_tree().quit()
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_right_drag=false
		if not pending_drag.is_empty():
			pending_drag.clear()
			_refresh_authoring()

func _update_drag_preview(at: Vector2) -> void:
	if pending_drag.kind=="prop":
		pending_drag.to=_snap_point((Vector2(pending_drag.from)+at-Vector2(pending_drag.grab))/PPM)*PPM
	elif pending_drag.kind in ["road_move","region","marker"]:
		pending_drag.to=Vector2(pending_drag.from)+_snap_point((at-Vector2(pending_drag.grab))/PPM)*PPM
	else:pending_drag.to=_snap_point(at/PPM)*PPM
	_refresh_authoring()

func _sync_road_preview(preview_doc: Dictionary={}) -> void:
	if not source_ready:return
	var document: Dictionary=authoring.doc if preview_doc.is_empty() else preview_doc
	var hidden: Dictionary={}
	for original in authoring.initial.get("roads",[]):
		var road: Dictionary={}
		for item in document.roads:
			if str(item.id)==str(original.id):road=item;break
		if not road.is_empty() and JSON.stringify(road)!=JSON.stringify(original):
			hidden[int(str(original.id).trim_prefix("road-"))]=true
	if pending_drag.get("kind","") in ["road","road_move"]:
		hidden[int(str(pending_drag.id).trim_prefix("road-"))]=true
	if hidden!=Roads.editor_hidden:
		Roads.editor_hidden=hidden
		_redraw_roads()
		_update_overview_mask()

func _update_traffic_preview() -> void:
	var fresh:=traffic_preview.is_current()
	var graph: RefCounted=traffic_preview.network if fresh else traffic_network
	if gizmos.network==graph and gizmos.network_is_draft==fresh:return
	gizmos.network=graph
	gizmos.network_is_draft=fresh
	gizmos.preview_junctions=traffic_preview.data.get("junctions",[]) if fresh else []
	gizmos.queue_redraw()

func _update_overview_mask() -> void:
	if is_instance_valid(overview_renderer):overview_renderer.refresh()

func _redraw_roads() -> void:
	if not is_instance_valid(world):return
	var loaded: Array=render_tiles.tiles.values() if is_instance_valid(render_tiles) else world.chunks.values()
	for tile in loaded:
		tile.redraw_bridges()
		for child in tile.get_children():
			if child.get_script()==Roads:child.queue_redraw()

func _options(parent: Node,title: String,values: Array) -> OptionButton:
	var option:=OptionButton.new()
	option.tooltip_text=title
	option.custom_minimum_size.x=115
	for value in values:
		option.add_item(str(value).capitalize())
		option.set_item_metadata(option.item_count-1,str(value))
	parent.add_child(option)
	return option

func _number(parent: Node,title: String,minimum: float,maximum: float,start: float) -> SpinBox:
	var spin:=SpinBox.new()
	spin.tooltip_text=title;spin.prefix=("Width m" if title.begins_with("Width") else title)+" "
	spin.min_value=minimum;spin.max_value=maximum;spin.value=start
	spin.custom_minimum_size.x=145 if title.begins_with("Width") else 110
	parent.add_child(spin)
	return spin

func _option_value(option: OptionButton) -> String:
	return str(option.get_item_metadata(option.selected))

func _change_road_settings() -> void:
	if _setting_controls or not source_ready or tool_name=="draw_road" or _editing_locked():return
	if authoring.set_road_settings(source_id,{"roadClass":_option_value(road_class),
		"surface":_option_value(road_surface),"width":road_width.value,"lanes":int(road_lanes.value)}):
		_refresh_authoring()
		_notice("Road settings updated in the draft.")

func _selected_record() -> Dictionary:
	if not source_ready or source_id.is_empty():return {}
	for category in ["roads","regions","props","markers"]:
		for item in authoring.doc.get(category,[]):
			if str(item.id)==source_id:return {"category":category,"item":item}
	return {}

func _record_position(record: Dictionary) -> Vector2:
	var item: Dictionary=record.item
	if item.has("points"):
		if record.category=="roads" and source_anchor>=0 and source_anchor<item.points.size():
			return Vector2(item.points[source_anchor].x,item.points[source_anchor].y)
		var center:=Vector2.ZERO
		for p in item.points:center+=Vector2(p.x,p.y)
		return center/item.points.size()
	return Vector2(item.x,item.y)

func _refresh_inspector() -> void:
	if not is_instance_valid(inspector_name):return
	_updating_inspector=true
	var record:=_selected_record();var exists:=not record.is_empty()
	inspector_name.editable=exists
	for spin in [inspector_x,inspector_y,inspector_rotation,inspector_scale]:spin.editable=exists
	prop_transforms.visible=exists and record.category=="props"
	point_picker.visible=exists and record.category=="roads"
	remove_point_button.visible=point_picker.visible
	add_point_button.visible=point_picker.visible
	split_road_button.visible=point_picker.visible
	point_picker.clear()
	if exists:
		var item: Dictionary=record.item
		inspector_name.text=str(item.get("name",""))
		var at:=_record_position(record);inspector_x.value=at.x;inspector_y.value=at.y
		inspector_rotation.value=float(item.get("rotation",0));inspector_scale.value=float(item.get("scale",1))
		if record.category=="roads":
			point_picker.add_item("Whole road (center)")
			for i in item.points.size():point_picker.add_item("Control point %d"%[i+1])
			point_picker.select(clampi(source_anchor+1,0,item.points.size()))
			remove_point_button.disabled=item.points.size()<=2
	else:
		inspector_name.text="";inspector_x.value=0;inspector_y.value=0
	_updating_inspector=false

func _commit_inspector() -> void:
	if _updating_inspector or not active or _editing_locked():return
	var record:=_selected_record()
	if record.is_empty():return
	var values: Dictionary={"name":inspector_name.text}
	if record.category=="props":values.merge({"rotation":inspector_rotation.value,"scale":inspector_scale.value})
	if authoring.edit_entity(source_id,values,Vector2(inspector_x.value,inspector_y.value),source_anchor):
		_refresh_authoring()
	else:_notice(authoring.last_error);_refresh_inspector()

func _change_terrain_settings() -> void:
	if _setting_controls:return
	if _option_value(terrain_biome) not in ["mountain","rock"]:terrain_barrier.set_pressed_no_signal(false)
	terrain_elevation.editable=terrain_barrier.button_pressed
	if tool_name=="draw_terrain" or _editing_locked():return
	var record:=_selected_record()
	if record.get("category","")!="regions":return
	if authoring.edit_entity(source_id,{"biome":_option_value(terrain_biome),"barrier":terrain_barrier.button_pressed,"elevation":terrain_elevation.value},_record_position(record)):_refresh_authoring()

func _mountain_tool() -> void:
	_choose_tool("draw_terrain");_setting_controls=true
	for i in terrain_biome.item_count:
		if str(terrain_biome.get_item_metadata(i))=="mountain":terrain_biome.select(i);break
	terrain_barrier.set_pressed_no_signal(true);terrain_elevation.value=80
	_setting_controls=false;_change_terrain_settings()
	_notice("Click the mountain outline, then Finish / Enter. The visible rock face blocks vehicles.")

func _terrain_barrier_toggled(enabled: bool) -> void:
	if _setting_controls:return
	if enabled:
		_setting_controls=true
		if _option_value(terrain_biome) not in ["mountain","rock"]:
			for i in terrain_biome.item_count:
				if str(terrain_biome.get_item_metadata(i))=="mountain":terrain_biome.select(i);break
		if terrain_elevation.value<5:terrain_elevation.value=80
		_setting_controls=false
	_change_terrain_settings()

func _sync_mountain_preview(document: Dictionary) -> void:
	var current: Dictionary={}
	for region in document.get("regions",[]):current[str(region.id)]=region
	var hidden: Dictionary={}
	for original in authoring.initial.get("regions",[]):
		if MountainGeometry.solid(original) and (not current.has(str(original.id)) or JSON.stringify(current[str(original.id)])!=JSON.stringify(original)):hidden[str(original.id)]=true
	if hidden!=MountainArt.editor_hidden:
		MountainArt.editor_hidden=hidden;_redraw_mountains()
	for chunk in world.chunks.values():
		if not is_instance_valid(chunk.collider_body):continue
		for shape in chunk.collider_body.get_children():
			if shape is CollisionPolygon2D and shape.has_meta("editor_terrain_key"):shape.disabled=hidden.has(str(shape.get_meta("editor_terrain_key")))

func _redraw_mountains() -> void:
	if not is_instance_valid(world):return
	var nodes: Array=world.chunks.values()
	if is_instance_valid(render_tiles):nodes.append_array(render_tiles.tiles.values())
	for chunk in nodes:chunk.redraw_mountains()
	_update_overview_mask()

func _select_point(index: int) -> void:
	if _updating_inspector:return
	source_anchor=index-1;_refresh_authoring()

func _remove_point() -> void:
	if _editing_locked() or not source_ready:return
	var road: Dictionary=authoring.road_at_id(source_id)
	var index: int=source_anchor if source_anchor>=0 else road.get("points",[]).size()/2
	if authoring.remove_road_point(source_id,index):source_anchor=-1;_refresh_authoring()
	else:_notice(authoring.last_error)

func _duplicate_selected() -> void:
	if _editing_locked() or not source_ready:return
	var id: String=authoring.duplicate_entity(source_id)
	if id.is_empty():_notice(authoring.last_error);return
	source_id=id;source_anchor=-1;_refresh_authoring();_notice("Created an editable copy. Ctrl+Z undoes it.")

func _nudge_selected(direction: Vector2,large: bool=false) -> void:
	if _editing_locked():return
	var record:=_selected_record()
	if record.is_empty():return
	var step: float=(snap_m if snap_m>0 else 1.0)*(10 if large else 1)
	if authoring.edit_entity(source_id,{},_record_position(record)+direction*step,source_anchor):_refresh_authoring()
	else:_notice(authoring.last_error)

func _refresh_entity_list(force: bool=false) -> void:
	if not source_ready or not is_instance_valid(entity_list):return
	if not force and _entity_revision==authoring.edit_revision:
		entity_list.deselect_all()
		for i in entity_list.item_count:
			if str(entity_list.get_item_metadata(i))==source_id:entity_list.select(i);break
		return
	_entity_revision=authoring.edit_revision;entity_list.clear()
	var keyword:=entity_search.text.to_lower()
	for category in ["roads","regions","props","markers"]:
		for item in authoring.doc.get(category,[]):
			if bool(item.get("hidden",false)):continue
			var text: String=str(item.get("name",item.id))+"  ·  "+str(item.id)
			if not keyword.is_empty() and keyword not in text.to_lower():continue
			entity_list.add_item(text);entity_list.set_item_metadata(entity_list.item_count-1,str(item.id))
			if str(item.id)==source_id:entity_list.select(entity_list.item_count-1)

func _select_entity(index: int) -> void:
	_choose_tool("move_prop");source_id=str(entity_list.get_item_metadata(index));source_anchor=-1
	var record:=_selected_record()
	if record.is_empty():return
	editor_camera.global_position=_record_position(record)*PPM
	_refresh_authoring();_update_view(true)

func _set_layer(enabled: bool,key: String) -> void:
	layer_flags[key]=enabled
	if key in ["terrain","roads","scenery"]:
		if is_instance_valid(overview_renderer):overview_renderer.set_layers(layer_flags)
		if is_instance_valid(render_tiles):render_tiles.set_layers(layer_flags)
	if is_instance_valid(gizmos):
		gizmos.layer_flags=layer_flags.duplicate()
		if is_instance_valid(gizmos.preview_scenery):gizmos.preview_scenery.visible=bool(layer_flags.scenery)
		if is_instance_valid(gizmos.mountain_preview):gizmos.mountain_preview.visible=bool(layer_flags.terrain)
		gizmos.queue_redraw()
	_apply_landmark_layer()

func _apply_landmark_layer() -> void:
	if is_instance_valid(world) and is_instance_valid(world.dealerships):
		var node: Node2D=world.dealerships
		if not _landmark_visibility.has(node):_landmark_visibility[node]=node.visible
		node.visible=bool(layer_flags.scenery)

func _snap_point(point: Vector2) -> Vector2:
	return point.snapped(Vector2.ONE*snap_m) if snap_m>0 else point

func _road_draw_point(point: Vector2) -> Vector2:
	var best:=INF
	var result:=_snap_point(point)
	for road in authoring.doc.get("roads",[]):
		if (str(road.surface) in ["gravel","dirt"])!=(_option_value(road_surface) in ["gravel","dirt"]):continue
		var path:=_source_road_path(road)
		for i in range(1,path.size()):
			var candidate:=Geometry2D.get_closest_point_to_segment(point,path[i-1],path[i])
			var distance:=point.distance_to(candidate)
			if distance<maxf(float(road.width)*.5+1.0,8/(editor_camera.zoom.x*PPM)) and distance<best:
				best=distance;result=candidate
	return result

func _update_source_details() -> void:
	if not source_ready:return
	if source_id.is_empty():
		if selected.is_empty():
			details.text="Select a road, region, marker or scenery object. Edit its properties here, or find it in the list below."
			selected_preview.texture=null;selected_preview.visible=false
		return
	selected_preview.visible=false
	var road: Dictionary=authoring.road_at_id(source_id)
	if not road.is_empty():
		details.text="ROAD  /  %s\n%s\n%d control points · %.1fm · %d lanes"%[
			source_id,str(road.name),road.points.size(),float(road.width),int(road.lanes)]
		return
	var prop: Dictionary=authoring.prop_at_id(source_id)
	if not prop.is_empty():
		details.text="SCENERY  /  %s\n%s\nX %.1fm · Y %.1fm\nRotation %.0f° · Scale %.2f"%[
			source_id,str(prop.name),float(prop.x),float(prop.y),float(prop.get("rotation",0)),float(prop.get("scale",1))]
		selected_preview.texture=gizmos._prop_texture(prop)
		selected_preview.visible=selected_preview.texture!=null
		return
	for category in ["regions","markers"]:
		for item in authoring.doc.get(category,[]):
			if str(item.id)==source_id:
				if category=="regions" and MountainGeometry.solid(item):
					details.text="MOUNTAIN BARRIER / %s\n%s\nHeight %.0fm · blocks vehicles\nDrag the rock face to move it."%[source_id,str(item.get("name","")),float(item.elevation)]
					return
				details.text="%s / %s\n%s\n\nDrag its %s to move. New objects can be deleted; Undo restores edits."%[
					category.to_upper(),source_id,str(item.get("name","")),"edge" if category=="regions" else "center"]
				return

func _finish_shape() -> void:
	if _editing_locked() or not source_ready:return
	var identity: String=""
	if tool_name=="draw_road":
		identity=authoring.add_road_path(draft_points,{"roadClass":_option_value(road_class),
			"surface":_option_value(road_surface),"width":road_width.value,"lanes":int(road_lanes.value)})
	elif tool_name=="draw_terrain":identity=authoring.add_region(draft_points,_option_value(terrain_biome),terrain_barrier.button_pressed,terrain_elevation.value if terrain_barrier.button_pressed else 0)
	if identity.is_empty():_notice(authoring.last_error);return
	source_id=identity;source_anchor=-1;draft_points.clear()
	_refresh_authoring()
	_notice("Created "+identity+". Select/Edit to move it; Save to Game when ready.")

func _cancel_gesture() -> void:
	pending_drag.clear();draft_points.clear();_right_drag=false
	_refresh_authoring();_notice("Unfinished edit canceled. Committed edits are unchanged.")

func _pick_source_road(at: Vector2) -> Dictionary:
	if not layer_flags.roads:return {}
	var best:=12.0/maxf(.003,editor_camera.zoom.x)
	var hit: Dictionary={}
	for road in authoring.doc.get("roads",[]):
		var line:=_source_road_path(road)
		for i in range(1,line.size()):
			var distance:=Geometry2D.get_closest_point_to_segment(at,line[i-1]*PPM,line[i]*PPM).distance_to(at)
			if distance<maxf(best,float(road.width)*PPM*.5) and (hit.is_empty() or distance<best):
				best=distance;hit={"kind":"road_move","id":str(road.id),"from":at}
	return hit

func _source_road_path(road: Dictionary) -> PackedVector2Array:
	for original in authoring.initial.get("roads",[]):
		if str(original.id)==str(road.id) and JSON.stringify(original)==JSON.stringify(road):
			var index:=int(str(road.id).trim_prefix("road-"))
			if index<world.data.roads.size():
				var path:=PackedVector2Array()
				for p in world.data.roads[index].points:path.append(Vector2(p[0],p[1]))
				return path
	return EditSession.road_path(road)

func _pick_source_marker(at: Vector2) -> Dictionary:
	if not layer_flags.markers:return {}
	for item in authoring.doc.get("markers",[]):
		var center:=Vector2(item.x,item.y)*PPM
		if center.distance_to(at)<12/maxf(.003,editor_camera.zoom.x):
			return {"kind":"marker","id":str(item.id),"from":center}
	return {}

func _pick_source_region(at: Vector2) -> Dictionary:
	if not layer_flags.terrain:return {}
	for item in authoring.doc.get("regions",[]):
		for i in item.points.size():
			var a: Dictionary=item.points[i]
			var b: Dictionary=item.points[(i+1)%item.points.size()]
			if Geometry2D.get_closest_point_to_segment(at,Vector2(a.x,a.y)*PPM,Vector2(b.x,b.y)*PPM).distance_to(at)<8/maxf(.003,editor_camera.zoom.x):
				return {"kind":"region","id":str(item.id),"from":at}
	return {}

func _pick_source_mountain(at: Vector2) -> Dictionary:
	if not layer_flags.terrain:return {}
	for item in authoring.doc.get("regions",[]):
		if MountainGeometry.solid(item) and Geometry2D.is_point_in_polygon(at/PPM,MountainGeometry.polygon(item)):
			return {"kind":"region","id":str(item.id),"from":at}
	return {}

func _nearest_prop(p: Vector2) -> Dictionary:
	if not layer_flags.scenery:return {}
	# The actual baked per-chunk prop indices, not a separate browser index.
	var cell := Vector2i((p/PPM/float(world.chunk_m)).floor())
	var nearest := {}
	var best := 6.0 # max selection distance from a real asset footprint
	for x in range(cell.x-1,cell.x+2):
		for y in range(cell.y-1,cell.y+2):
			var key := "%d,%d" % [x,y]
			var chunk: Dictionary = world.data.chunks.get(key,{})
			for raw_index in chunk.get("props",[]):
				var index := int(raw_index)
				var item: Dictionary = world.data.props[index]
				var c := Vector2(float(item.p[0]),float(item.p[1]))
				var half := Vector2(float(item.size[0]),float(item.size[1]))*0.5
				var local: Vector2 = (p/PPM-c).rotated(-float(item.get("angle",0.0)))
				var gap: float = Vector2(
					maxf(0.0,absf(local.x)-half.x),
					maxf(0.0,absf(local.y)-half.y)).length()
				if gap < best:
					best = gap
					nearest = {"kind":"prop","index":index,"distance":gap}
	return nearest

func select_at(position_px: Vector2) -> Dictionary:
	if not active:
		return {}
	var info: Dictionary = Geometry.inspect(world,position_px)
	var meters := position_px/PPM
	var selected_object: Dictionary = {}
	var grid_cell := Vector2i((meters/float(world.data.surface_cell)).floor())
	var index_key := "%d,%d" % [grid_cell.x,grid_cell.y]
	for raw in world._junction_grid.get(index_key,[]):
		var index := int(raw)
		if Geometry2D.is_point_in_polygon(meters,world._junction_polygons[index]):
			selected_object = {"kind":"junction","index":index}
			break
	if selected_object.is_empty():
		selected_object = _nearest_prop(position_px)
	if selected_object.is_empty() and info.has("road_id") and \
			float(info.get("distance_to_road_edge_m",99.0))<=4.0:
		selected_object = {"kind":"road","index":int(info.road_id)}
	_update_selection(selected_object,info)
	return selected_object

func _update_selection(what: Dictionary, measured: Dictionary = {}) -> void:
	selected = what.duplicate()
	_update_context_panels()
	gizmos.set_selection(selected)
	selected_preview.visible = false
	selected_preview.texture = null
	var kind := str(what.get("kind",""))
	var index := int(what.get("index",-1))
	if kind == "road" and index>=0:
		var road: Dictionary = world.data.roads[index]
		var edge_count := 0
		if is_instance_valid(traffic_network):
			for edge in traffic_network.edges:
				if not bool(edge.connector) and int(edge.road)==index:
					edge_count+=1
		details.text = "ROAD #%d\n%s\n\nClass: %s\nSurface: %s\nWidth: %.1f metres\nLanes: %d\nTraffic lane edges: %d\n\nSource: baked game road" % [
			index,str(road.name),str(road.kind),str(road.surface),
			float(road.width),int(road.lanes),edge_count]
	elif kind == "junction" and index>=0:
		var j: Dictionary = world.data.junctions[index]
		var connectors := 0
		var incoming := 0
		var outgoing := 0
		if is_instance_valid(traffic_network):
			for edge in traffic_network.edges:
				if bool(edge.connector) and int(edge.start_j)==index:
					connectors+=1
				elif not bool(edge.connector) and int(edge.end_j)==index:
					incoming+=1
				elif not bool(edge.connector) and int(edge.start_j)==index:
					outgoing+=1
		details.text = "INTERSECTION #%d\n\nRoads: %s\nControl: %s\nApproaches: %d\nIncoming lanes: %d\nOutgoing lanes: %d\nLegal turn connectors: %d\n\nPink = baked pavement\nOrange = actual turn paths" % [
			index,str(j.get("roads",[])),str(j.get("control","none")),
			j.get("approaches",[]).size(),incoming,outgoing,connectors]
	elif kind=="prop" and index>=0:
		var prop: Dictionary = world.data.props[index]
		var asset := str(prop.get("asset_path",prop.get("asset_id","builtin")))
		if prop.has("asset_path"):
			var texture_path := "res://assets/"+str(prop.asset_path)
			if ResourceLoader.exists(texture_path):
				selected_preview.texture = load(texture_path) as Texture2D
				selected_preview.visible = selected_preview.texture != null
		elif prop.has("asset_id"):
			for item in asset_entries:
				if not bool(item.get("project",false)) and \
						str(item.kind) == str(prop.get("asset_kind",str(prop.get(
							"asset_id","")).trim_prefix("game-"))):
					selected_preview.texture = item.texture
					selected_preview.visible = true
					break
		details.text = "WORLD OBJECT #%d\n\nType: %s\nArtwork: %s\nPosition: %.1f, %.1f metres\nSize: %.1f × %.1f metres\nSolid collision: %s\n\nUses the live game asset,\nnot a browser preview." % [
			index,str(prop.kind),asset,float(prop.p[0]),float(prop.p[1]),
			float(prop.size[0]),float(prop.size[1]),
			"yes" if bool(prop.get("solid",false)) else "no"]
	else:
		details.text = "Select a road, region, marker or scenery object. Edit its properties here, or find it in the list below."
	if not measured.is_empty():
		details.text += "\n\nSurface: %s  Grip: %.2f" % [
			str(measured.get("surface","")),float(measured.get("grip",0.0))]

func _add_point() -> void:
	if _editing_locked() or not source_ready:return
	var road: Dictionary=authoring.road_at_id(source_id)
	if road.is_empty():return
	var index:=clampi(source_anchor,0,road.points.size()-2)
	if source_anchor<0:
		var longest:=0.0
		for i in range(1,road.points.size()):
			var length:=Vector2(road.points[i].x,road.points[i].y).distance_to(Vector2(road.points[i-1].x,road.points[i-1].y))
			if length>longest:longest=length;index=i-1
	var a:=Vector2(road.points[index].x,road.points[index].y);var b:=Vector2(road.points[index+1].x,road.points[index+1].y)
	if authoring.insert_road_point(source_id,(a+b)*.5):source_anchor=index+1;_refresh_authoring()

func _split_road() -> void:
	if _editing_locked() or not source_ready:return
	var id: String=authoring.split_road(source_id,source_anchor)
	if not id.is_empty():source_id=id;source_anchor=-1;_refresh_authoring();_notice("Road split into two editable roads. Move their points to separate them; Undo restores the original.")
	else:_notice(authoring.last_error)
