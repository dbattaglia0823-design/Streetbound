extends CanvasLayer
## First native Streetbound world editor milestone: directly inspect the real
## rendered Morrow Coast, paved junctions, source props, and traffic network.
## Source edits are undoable drafts; writes use the existing validated Python rebaker.
const Geometry = preload("res://scripts/world/map_geometry.gd")
const Gizmos = preload("res://scripts/dev/native_world_editor_gizmos.gd")
const EditSession = preload("res://scripts/dev/native_map_edit_session.gd")
const Sidewalks = preload("res://scripts/dev/sidewalk_topology.gd")
const LocalBridge = preload("res://scripts/dev/native_map_bridge.gd")
const Scenery = preload("res://scripts/world/coast_scenery.gd")
const Art = preload("res://scripts/world/coast_art.gd")
const BuildingSelection=preload("res://scripts/dev/building_selection_footprint.gd")
const Roads = preload("res://scripts/world/coast_roads.gd")
const TrafficPreview=preload("res://scripts/dev/native_traffic_preview.gd")
const Overview=preload("res://scripts/dev/editor_world_overview.gd")
const RenderTiles=preload("res://scripts/dev/editor_render_tiles.gd")
const Layout=preload("res://scripts/dev/native_editor_layout.gd")
const DealerEditor=preload("res://scripts/dev/native_dealership_editor.gd")
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
var _asset_refresh_elapsed := 0.0
var _asset_catalog_signature := ""
var root_ui: Control
var inspector_panel: PanelContainer
var asset_dock: PanelContainer
var edit_actions: Control
var draft_points: Array[Vector2] = []
var preview_hidden: Dictionary = {}
var synced_preview_revision := -1
var synced_prop_drag:=""
var _overview_dirty:=false
var _last_road_drag_ms:=-1000
var _snap_neighbors_key:=""
var _snap_neighbors: Array=[]
var _runtime_prop_stamp:=-1
var _runtime_props_by_source: Dictionary={}
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
const MultiSelect=preload("res://scripts/dev/native_editor_multiselect.gd")
const WorkspaceData=preload("res://scripts/dev/native_editor_workspace.gd")
const WorkspaceUI=preload("res://scripts/dev/native_workspace_tools.gd")
var workspace_tools:=WorkspaceUI.new()
const GameplayAuthoring=preload("res://scripts/dev/native_gameplay_authoring.gd")
var gameplay_authoring:=GameplayAuthoring.new()
var last_asset_entry: Dictionary={}
const AdvancedConstruction=preload("res://scripts/dev/advanced_world_construction.gd")
const Construction=preload("res://scripts/dev/native_city_construction.gd")
const TerrainHeight=preload("res://scripts/world/authored_height_field.gd")
var landscape_dialog: AcceptDialog
var landscape_fields: Dictionary={}
var landscape_mode: OptionButton
var landscape_file: FileDialog
var landscape_settings: Dictionary={}
var landscape_session: RefCounted
var construction_dialog: AcceptDialog
var construction_mode: OptionButton
var construction_fields: Dictionary={}
var construction_summary: Label
var construction_canvas: Control
var construction_plan: Dictionary={}
var construction_revision:=-1
var construction_session: RefCounted
var construction_center:=Vector2.ZERO
var construction_road_id:=""
var multi_selection: Array[String]=[]
var marquee_start:=Vector2.ZERO
var marquee_tracking:=false
var marquee_additive:=false
var group_move_start:=Vector2.ZERO
var group_moving:=false
var _hidden_game_ui: Dictionary = {}
var authoring
var bridge
var source_ready := false
var tool_name := "move_prop"
const MapSwitcher=preload("res://scripts/dev/native_map_switcher.gd")
var map_switcher=MapSwitcher.new()
const RaceEditor=preload("res://scripts/dev/native_race_editor.gd")
const MarkerEditor=preload("res://scripts/dev/native_marker_editor.gd")
var race_editor=RaceEditor.new()
var marker_editor=MarkerEditor.new()
var dealer_editor=DealerEditor.new()
const RoadShapeTools=preload("res://scripts/dev/native_road_shape_tools.gd")
var road_shapes=RoadShapeTools.new()
const BuildingSnap=preload("res://scripts/dev/building_snap.gd")
const RoadBuildingSnap=preload("res://scripts/dev/road_building_snap.gd")
var road_building_snap:=RoadBuildingSnap.new()
var _road_snap_revision:=-1
var _road_snap_context:=""
var building_snap_enabled:=true
var building_snap_button: Button
var sidewalk_width: SpinBox
var guardrail_width: SpinBox
var source_id := ""
var source_anchor := -1
var pending_drag: Dictionary = {}
var drag_position := Vector2.ZERO
var snap_m := 1.0
var grid_spacing_m := 1.0
var road_selection_layer := 99
var isolate_road_layer:=false
var lock_other_roads:=false
var angle_snap_degrees:=0.0
var prefab_dialog: AcceptDialog
var prefab_list: ItemList
var prefab_name: LineEdit
var prefab_records: Array[Dictionary]=[]
var copied_group: Dictionary={}
var bulk_dialog: AcceptDialog
var bulk_category: OptionButton
var bulk_property: OptionButton
var bulk_value: LineEdit
var history_dialog: AcceptDialog
var history_items: ItemList
const MIN_EDITOR_ZOOM := 0.00025
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
const EditorContext=preload("res://scripts/dev/native_editor_context.gd")
var tool_options: Container
var tool_help: Label
var mountain_help: Label
var sidewalk_settings: Control
var guardrail_settings: Control
var race_settings: Control
var dealership_settings: Control
var inspector_tabs: TabContainer
var settings_tabs: TabContainer
var selection_fields: Control
var road_layer_settings: Control
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
var inspector_road_facing: CheckBox
var inspector_road_front: OptionButton
var inspector_scale: SpinBox
var inspector_scale_x: SpinBox
var inspector_scale_y: SpinBox
var point_picker: OptionButton
var remove_point_button: Button
var add_point_button: Button
var split_road_button: Button
var reconnect_road_button: Button
var connection_label: Label
var asset_dimensions_label: Label
var terrain_transforms: VBoxContainer
var inspector_terrain_width: SpinBox
var inspector_terrain_height: SpinBox
var inspector_terrain_percent: SpinBox
var terrain_shrink_button: Button
var terrain_expand_button: Button
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
var road_elevation_controls: VBoxContainer
var road_start_layer: SpinBox
var road_jump_enabled: CheckBox
var road_jump_reverse: CheckBox
var road_jump_fields: Dictionary = {}
var road_jump_options: VBoxContainer
var road_end_layer: SpinBox
var road_point_elevation_fields: VBoxContainer
var road_point_layer_inputs: Array[SpinBox] = []
var road_point_profile_key := ""
var road_class: OptionButton
var inspector_road_type: OptionButton
var inspector_road_type_fields: Control
var inspector_junction_start: OptionButton
var inspector_junction_end: OptionButton
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
	dealer_editor.build(self)
	bridge = Node.new()
	bridge.set_script(LocalBridge)
	bridge.completed.connect(_on_apply_completed)
	add_child(bridge)
	root_ui.visible = false
	get_node("/root/MenuNavigation").register_scope(root_ui,31,close_editor)
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
		var warnings: Array=world.data.get("editor_warnings",[])
		if not warnings.is_empty():_notice("Map loaded. %d placement/network warning(s): %s"%[warnings.size(),str(warnings[0])])

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


func _current_asset_library_signature() -> String:
	var found: Array[String] = []
	_collect_asset_files("res://assets/Buildings",found)
	_collect_asset_files("res://assets/Map Building Assets",found)
	return "|".join(found).sha256_text()


func _collect_asset_files(folder: String, found: Array[String]) -> void:
	var directory := DirAccess.open(folder)
	if directory==null:
		return
	directory.list_dir_begin()
	var entry:=directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var child:=folder.path_join(entry)
			if directory.current_is_dir():
				_collect_asset_files(child,found)
			elif entry.get_extension().to_lower() in ["png","webp","svg","json"]:
				found.append(child+":"+str(FileAccess.get_modified_time(child)))
		entry=directory.get_next()
	directory.list_dir_end()


func _scan_asset_library() -> void:
	var signature := _current_asset_library_signature()
	if signature==_asset_catalog_signature and not asset_entries.is_empty():
		return
	_asset_catalog_signature=signature
	asset_entries.clear()
	# Same folder hierarchy and project-id hashing used by the browser
	# asset catalog and Python source importer.
	_walk_building_assets("res://assets/Buildings")
	_walk_building_assets("res://assets/Map Building Assets")
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
				var texture: Texture2D = Art.project_sprite(child.trim_prefix("res://assets/"))
				if texture != null:
					var relative := child.trim_prefix("res://assets/")
					var meta := _read_asset_metadata(child.get_basename()+".asset.json")
					var sheet_path := child.get_basename()+".sheet.json"
					if FileAccess.file_exists(sheet_path):
						var sheet := _read_asset_metadata(sheet_path)
						var sprites: Array = sheet.get("sprites",[]).duplicate(true) if sheet.get("sprites",[]) is Array else []
						var grid: Dictionary = sheet.get("grid",{}) if sheet.get("grid",{}) is Dictionary else {}
						if not grid.is_empty():
							var cw := int(grid.get("width",0))
							var ch := int(grid.get("height",0))
							if cw>0 and ch>0 and int(texture.get_width()/cw)*int(texture.get_height()/ch)<=512:
								var index := 0
								for gy in range(int(texture.get_height()/ch)):
									for gx in range(int(texture.get_width()/cw)):
										index+=1
										sprites.append({"name":"Sprite %d"%index,"region":[gx*cw,gy*ch,cw,ch]})
						if sprites.size()<=512:
							for item in sprites:
								if not item is Dictionary:
									continue
								var region: Array = item.get("region",[])
								if region.size()!=4:
									continue
								var x:=int(region[0])
								var y:=int(region[1])
								var w:=int(region[2])
								var h:=int(region[3])
								if x<0 or y<0 or w<1 or h<1 or x+w>texture.get_width() or y+h>texture.get_height():
									continue
								var crop:=AtlasTexture.new()
								crop.atlas=texture
								crop.region=Rect2(x,y,w,h)
								crop.filter_clip=true
								var sprite_meta:=meta.duplicate(true)
								sprite_meta.merge(item,true)
								_register_project_asset(relative,str(item.get("name","Sprite")),crop,sprite_meta,region)
					else:
						_register_project_asset(relative,entry.get_basename(),texture,meta,[])
		entry = directory.get_next()
	directory.list_dir_end()


func _read_asset_metadata(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>100000:
		return {}
	var decoded=JSON.parse_string(file.get_as_text())
	return decoded if decoded is Dictionary else {}


func _register_project_asset(relative: String, label: String, texture: Texture2D,
		meta: Dictionary, region: Array) -> void:
	var lower := (relative+"/"+label).to_lower()
	var kind := "industrial_prop"
	var category := "industrial"
	if "ground decal" in lower or "decal" in lower:
		kind="ground_decal"
		category="decals"
	elif "road" in lower or "infrastructure" in lower or "barrier" in lower:
		kind="road_prop"
		category="roads"
	elif "house" in lower and not "warehouse" in lower:
		kind="house"
		category="house"
	elif "warehouse" in lower:
		kind="warehouse"
		category="building"
	elif "garage" in lower:
		kind="garage"
		category="garage"
	elif relative.begins_with("Buildings/") or "buildings/" in lower:
		kind="building"
		category="building"
	kind=str(meta.get("type",kind))
	if kind not in ["house","building","warehouse","garage","gas_station","industrial_prop","road_prop","ground_decal","oak","pine","palm","bush","rock","boulder"]:
		return
	if kind=="ground_decal":
		category="decals"
	elif kind=="industrial_prop":
		category="industrial"
	elif kind=="road_prop":
		category="roads"
	elif kind=="house":
		category="house"
	elif kind=="garage":
		category="garage"
	elif kind in ["building","warehouse","gas_station"]:
		category="building"
	elif kind in ["oak","pine","palm","bush","rock","boulder"]:
		category="nature"
	var collision:=str(meta.get("collision","none" if kind=="ground_decal" else "solid"))
	if collision not in ["solid","none"]:
		return
	var name:=label.replace("_"," ").replace("-"," ")
	# Keep the hash based on the exact sprite manifest label, matching Python.
	var key:=relative+("#"+label if region.size()==4 else "")
	var size: Array = meta.get("worldSize",[]) if meta.get("worldSize",[]) is Array else []
	asset_entries.append({"name":name,"kind":kind,"category":category,"texture":texture,
		"path":relative,"project":true,"project_id":"project-"+key.sha256_text().substr(0,24),
		"region":region.duplicate(),"collision":collision,"world_size":size})


func _open_workspace_commands() -> void:
	workspace_tools.setup(self);workspace_tools.open_commands()

func _toggle_asset_favorite() -> void:
	workspace_tools.setup(self);workspace_tools.toggle_favorite(last_asset_entry)

func _filter_assets() -> void:
	workspace_tools.setup(self)
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
		if category == 5 and entry.category != "industrial":
			continue
		if category == 6 and entry.category != "roads":
			continue
		if category == 7 and entry.category != "decals":
			continue
		if category == 8 and entry.get("region",[]).size()!=4:
			continue
		if category == 9 and not workspace_tools.favorite(entry):continue
		var button := Button.new()
		button.name = "Asset_"+str(count)
		button.custom_minimum_size = Vector2(98,106)
		button.tooltip_text = ("Favorite · " if workspace_tools.favorite(entry) else "")+str(entry.name)
		if entry.get("region",[]).size()==4:button.tooltip_text+="\nSheet: "+str(entry.path).get_file().get_basename()
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
	last_asset_entry=entry
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
	var record:=_selected_record()
	var context:=EditorContext.resolve(tool_name,str(record.get("category","")),
		str(record.get("item",{}).get("type","")),multi_selection.size())
	road_settings.visible=bool(context.road)
	terrain_settings.visible=bool(context.terrain)
	marker_settings.visible=bool(context.marker)
	race_settings.visible=bool(context.race)
	sidewalk_settings.visible=bool(context.sidewalk)
	guardrail_settings.visible=bool(context.guardrail)
	dealership_settings.visible=bool(context.dealership)
	grid_button.visible=bool(context.snap)
	building_snap_button.visible=bool(context.building_snap)
	tool_help.text=str(context.help)
	road_shapes.update(self)
	race_editor.update(self)
	marker_editor.update(self)
	marker_editor.edit_button.visible=bool(context.marker) and record.get("category","")=="markers"
	marker_kind.visible=tool_name=="place_marker"
	asset_dock.visible=bool(context.assets)
	finish_button.visible=bool(context.shape_actions) or tool_name=="draw_river"
	cancel_button.visible=bool(context.shape_actions) or tool_name=="draw_river" or not pending_drag.is_empty()
	var road_selected: bool=bool(context.road) and record.get("category","")=="roads"
	finish_button.disabled=draft_points.size()<(2 if tool_name in ["draw_road","draw_sidewalk","draw_guardrail","draw_river"] else 3)
	if tool_name=="draw_race":finish_button.disabled=draft_points.size()<race_editor.minimum_points(self)
	cancel_button.disabled=draft_points.is_empty() and pending_drag.is_empty()
	road_elevation_controls.visible=road_selected and tool_name!="draw_road"
	if road_selected and tool_name!="draw_road":
		_setting_controls=true
		var road: Dictionary=authoring.road_at_id(source_id)
		road_width.value=float(road.width);road_lanes.value=int(road.lanes)
		var jump: Dictionary = road.get("jump",{})
		road_jump_enabled.set_pressed_no_signal(not jump.is_empty())
		road_jump_options.visible = not jump.is_empty()
		road_jump_reverse.button_pressed = bool(jump.get("reverse",false))
		var fields: Dictionary = preload("res://scripts/world/road_jump.gd").FIELDS
		for key in road_jump_fields:
			road_jump_fields[key].value = float(jump.get(key,fields[key][2]))
		var elevation: Dictionary=road.get("elevation",{})
		road_start_layer.value=float(elevation.get("start_layer",0))
		road_end_layer.value=float(elevation.get("end_layer",0))
		_refresh_point_elevation_fields(road)
		for option in [road_class,road_surface]:
			var value:=("track" if str(road.surface)=="track" else str(road.roadClass)) if option==road_class else str(road.surface)
			for i in option.item_count:
				if str(option.get_item_metadata(i))==value:option.select(i);break
		_setting_controls=false
	if bool(context.terrain) and record.get("category","")=="regions" and tool_name!="draw_terrain":
		_setting_controls=true
		for i in terrain_biome.item_count:
			if str(terrain_biome.get_item_metadata(i))==str(record.item.biome):terrain_biome.select(i);break
		terrain_barrier.button_pressed=bool(record.item.get("barrier",false))
		terrain_elevation.value=float(record.item.get("elevation",0))
		_setting_controls=false
	terrain_elevation.editable=terrain_barrier.button_pressed
	terrain_elevation.visible=terrain_barrier.button_pressed
	mountain_help.visible=terrain_barrier.button_pressed


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
	var dragging_prop: String=str(pending_drag.get("id","")) if pending_drag.get("kind","")=="prop" else ""
	if synced_preview_revision == authoring.edit_revision and synced_prop_drag==dragging_prop:
		return
	synced_preview_revision = authoring.edit_revision
	synced_prop_drag=dragging_prop
	var next_hidden: Dictionary = {}
	if not dragging_prop.is_empty():next_hidden["authored:"+dragging_prop]=true
	# Linked guardrails are derived from roads, not editable source props.
	# Replace baked visuals with the current draft preview while editing.
	for prop in world.data.props:
		if str(prop.get("authoring_id","")).begins_with("prop-auto-rail-"):
			next_hidden[Scenery.editor_key(prop)]=true
	# Baked archive objects are immutable for this editor session. Avoid
	# re-hashing thousands of nested prop dictionaries on every committed edit.
	var runtime_stamp: int=hash([world.get_instance_id(),world.data.props.size(),map_switcher.current_file])
	if runtime_stamp!=_runtime_prop_stamp:
		_runtime_prop_stamp=runtime_stamp;_runtime_props_by_source.clear()
		for original in world.data.props:
			_runtime_props_by_source[_prop_source_key(original.kind,original.seed,original.p)]=original
	var originals: Dictionary={};var current_ids: Dictionary={}
	for old in authoring.initial.get("props",[]):originals[str(old.id)]=old
	for prop in authoring.doc.get("props",[]):
		current_ids[str(prop.id)]=true
		var initial_prop: Dictionary = originals.get(str(prop.id),{})
		if not initial_prop.is_empty() and initial_prop != prop:
			next_hidden["authored:"+str(prop.id)] = true
		if prop.has("replaces"):
			var source: Dictionary = prop.replaces
			var pos: Array = source.get("p",[])
			if pos.size()==2:
				var original: Dictionary=_runtime_props_by_source.get(_prop_source_key(source.kind,source.seed,pos),{})
				if not original.is_empty():next_hidden[Scenery.editor_key(original)]=true
	for id in originals:
		if not current_ids.has(id):next_hidden["authored:"+id]=true
	if next_hidden != preview_hidden:
		preview_hidden = next_hidden
		Scenery.editor_hidden = preview_hidden.duplicate()
		_redraw_visible_scenery()
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

func _prop_source_key(kind: Variant,seed_value: Variant,p: Array) -> String:
	return "%s:%d:%.2f,%.2f"%[str(kind),int(seed_value),float(p[0]),float(p[1])]

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

func _workspace_selectable(id: String) -> bool:
	return not layer_flags.get("workspace_excluded",{}).has(id)

func _prune_multi_selection() -> void:
	if multi_selection.is_empty():return
	var live: Dictionary={}
	for category in ["props","markers","regions","roads"]:
		for entry in authoring.doc.get(category,[]):
			if not bool(entry.get("hidden",false)) and _workspace_selectable(str(entry.id)):live[str(entry.get("id",""))]=true
	var valid: Array[String]=[]
	for id in multi_selection:
		if live.has(id):valid.append(id)
	if valid.size()!=multi_selection.size():_set_multi(valid)

func _select_all() -> void:
	if not active or not source_ready:return
	if tool_name!="move_prop":
		_choose_tool("move_prop")
		if tool_name!="move_prop":return
	_set_multi(MultiSelect.all_visible(authoring.doc,layer_flags))
	_notice("%d editable objects selected."%multi_selection.size())

func _set_multi(ids: Array[String]) -> void:
	multi_selection=ids.duplicate()
	if is_instance_valid(gizmos):
		gizmos.group_selected_ids=multi_selection.duplicate()
		gizmos.group_selected_lookup.clear()
		for id in multi_selection:gizmos.group_selected_lookup[id]=true
		gizmos.queue_redraw()
	if not multi_selection.is_empty():
		selected={}
		gizmos.set_selection({})
	if multi_selection.size()>1:
		source_id=""
		if is_instance_valid(details):
			details.text="%d OBJECTS SELECTED\nDrag a selected object to move all.\nCtrl+D duplicate · Delete remove · Shift+drag add/remove."%multi_selection.size()

func _selection_hit(at: Vector2) -> String:
	if road_selection_layer!=99:return str(_pick_source_road(at).get("id",""))
	for hit in [_pick_source_prop(at),_pick_source_marker(at),_pick_source_mountain(at),_pick_source_road(at),_pick_source_region(at)]:
		var id:=str(hit.get("id",""))
		if not id.is_empty():return id
	return ""

func _canvas_pointer_available(screen_at: Vector2) -> bool:
	if not active or not source_ready or not is_instance_valid(editor_camera):
		return false
	# Do not steal clicks from the header, toolbars, inspector or minimap.
	if not canvas_rect.has_point(screen_at):return false
	if is_instance_valid(minimap) and minimap.is_visible_in_tree() and minimap.get_global_rect().has_point(screen_at):
		return false
	return true

func _start_canvas_selection(at: Vector2,additive: bool=false) -> void:
	if tool_name=="select_box" or additive:
		_begin_marquee(at,additive)
		return
	var hit:=_selection_hit(at)
	if multi_selection.size()>1 and multi_selection.has(hit):
		group_moving=true
		group_move_start=at
		return
	# Do not invoke source/baked picking until we know whether this is a
	# click or a drag. It previously swallowed blank-space marquee starts.
	if hit.is_empty():
		_begin_marquee(at,false)
		return
	_source_click(at)
	if not source_id.is_empty():
		_set_multi([source_id])

func _select_baked_with_marquee(area: Rect2,ids: Array[String]) -> void:
	if road_selection_layer!=99 or map_switcher.custom or not bool(layer_flags.get("scenery",true)):return
	var garage=preload("res://scripts/world/garage_geometry.gd")
	for index in MultiSelect.baked_indices_in_rect(world.data,area):
		var item: Dictionary=world.data.props[index]
		if Scenery.editor_hidden.has(Scenery.editor_key(item)) or garage.is_player_garage(item):continue
		var id: String=_ensure_editable_runtime_prop(item)
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
			if ids.size()>=MultiSelect.LIMIT:break

func _begin_marquee(at: Vector2,additive: bool) -> void:
	marquee_tracking=true
	marquee_start=at
	marquee_additive=additive

func _update_marquee(at: Vector2) -> void:
	gizmos.marquee_active=true
	gizmos.marquee_rect=Rect2(marquee_start,at-marquee_start).abs()
	gizmos.queue_redraw()

func _end_marquee(at: Vector2) -> void:
	marquee_tracking=false
	gizmos.marquee_active=false
	var ids: Array[String]=[]
	if marquee_additive:ids=multi_selection.duplicate()
	if marquee_start.distance_to(at)<6.0/maxf(.003,editor_camera.zoom.x):
		if not marquee_additive:
			# A short click still selects/adopts one asset. The dedicated
			# Box Select tool never turns this into an object drag.
			if tool_name=="select_box":
				var clicked:=_selection_hit(at)
				if clicked.is_empty() and not map_switcher.custom and road_selection_layer==99:
					var nearest: Dictionary=_nearest_prop(at)
					if nearest.get("kind","")=="prop":
						clicked=_ensure_editable_runtime_prop(world.data.props[int(nearest.index)])
				if not clicked.is_empty():ids.append(clicked)
			else:
				_source_click(at)
				pending_drag.clear()
				if not source_id.is_empty():ids.append(source_id)
		else:
			var hit:=_selection_hit(at)
			if hit.is_empty() and not map_switcher.custom and road_selection_layer==99:
				var nearest: Dictionary=_nearest_prop(at)
				if nearest.get("kind","")=="prop":
					hit=_ensure_editable_runtime_prop(world.data.props[int(nearest.index)])
			if not hit.is_empty():
				if ids.has(hit):ids.erase(hit)
				else:ids.append(hit)
	else:
		var bounds:=Rect2(marquee_start/PPM,(at-marquee_start)/PPM).abs()
		for id in MultiSelect.within_rect(authoring.doc,bounds,layer_flags):
			if marquee_additive and ids.has(id):ids.erase(id)
			elif not ids.has(id):ids.append(id)
		# The live city's buildings are often generated props, not entries in
		# the editable source document. Adopt only actual rectangle hits.
		var baked: Array[String]=[]
		if ids.size()<MultiSelect.LIMIT:_select_baked_with_marquee(bounds,baked)
		for id in baked:
			if marquee_additive and ids.has(id):ids.erase(id)
			elif not ids.has(id):ids.append(id)
	source_id=ids[0] if ids.size()==1 else ""
	source_anchor=-1
	selected={}
	_set_multi(ids)
	_refresh_authoring()
	if ids.size()>1:_set_multi(ids)
	elif ids.is_empty():_update_selection({})

func _end_group_move(at: Vector2,duplicate: bool=false) -> void:
	group_moving=false
	gizmos.group_drag_offset=Vector2.ZERO
	var delta: Vector2=(at-group_move_start)/PPM
	if snap_m>0:delta=delta.snapped(Vector2.ONE*snap_m)
	if delta.length()<.01:
		gizmos.queue_redraw()
		return
	_group_action("duplicate" if duplicate else "move",delta)

func _group_action(operation: String,delta: Vector2=Vector2.ZERO) -> bool:
	if _editing_locked() or not source_ready or multi_selection.is_empty():return false
	var count: int=multi_selection.size()
	# Groups may overlap intentionally. Never reject or auto-separate buildings.
	var revision_before: int=authoring.edit_revision
	var affected: Array[String]=authoring.batch_entities(multi_selection,delta,operation)
	# A successful deletion returns no new IDs; its revision still advances.
	if authoring.edit_revision==revision_before:
		_notice(authoring.last_error)
		return false
	_set_multi([] if operation=="delete" else affected)
	_refresh_authoring()
	_set_multi([] if operation=="delete" else affected)
	_notice("%d objects %s in one undo step."%[count,operation])
	return true

func _open_dealership_editor() -> void:
	dealer_editor.open()


func _choose_tool(mode: String) -> void:
	if _editing_locked():
		return
	if mode!="measure":workspace_tools.clear_measure()
	if not source_ready and mode != "inspect":
		_notice("Source unavailable. The map can still be inspected.")
		return
	# Box Select is a selection subtool, not a reason to discard the
	# selected group. Switching back to V must allow an immediate group drag.
	var keep_selection: bool=tool_name in ["move_prop","select_box"] and mode in ["move_prop","select_box"]
	tool_name = mode
	if is_instance_valid(settings_tabs):settings_tabs.current_tab=0
	if not keep_selection:_set_multi([])
	marquee_tracking=false
	group_moving=false
	if is_instance_valid(gizmos):
		gizmos.marquee_active=false
		gizmos.group_drag_offset=Vector2.ZERO
	draft_points.clear()
	if is_instance_valid(gizmos):
		gizmos.source_anchor_mode = mode == "anchor"
		gizmos.set_pending_shape(draft_points,mode)
	pending_drag.clear()
	if mode not in ["move_prop","select_box","anchor","race_grid","race_checkpoint"]:source_id = ""
	selected={}
	gizmos.set_selection({})
	source_anchor = -1
	mode_label.text={"select_box":"BOX SELECT","place_circle_road":"CIRCULAR ROAD","draw_race":"RACE ROUTE","draw_sidewalk":"BRANCHING SIDEWALKS","draw_guardrail":"GUARDRAILS","move_prop":"SELECT / EDIT","draw_road":"DRAW ROAD","draw_terrain":"TERRAIN REGION",
		"place_marker":"GAME MARKER","place_dealership":"PLACE DEALERSHIP","race_grid":"RACE START GRID","race_checkpoint":"ADD RACE CHECKPOINT","anchor":"ROAD / PATH POINTS","pan":"PAN VIEW"}.get(mode,"SCENERY")
	_update_active_tool_style()
	_update_context_panels()
	_notice({"move_prop":"Drag empty space to select several objects, or drag a selection to move it. Use Box Select to start on any object.",
		"select_box":"Drag a rectangle anywhere to select buildings, roads and scenery. Shift+drag adds or removes.",
		"draw_road":"Click road points, then FINISH or Enter. Double-click also finishes. Escape cancels.",
		"place_circle_road":"Set Radius, width and lanes, then click the center of your circular road. Select it afterwards to resize.",
		"draw_sidewalk":"Set walk width, click points to draw paths. Tips snap to existing sidewalks, including their middles, for T/X branches. Finish or Enter saves; Select/Edit drags junction anchors.",
		"draw_guardrail":"Set rail width, click path points like a road, then Finish/Enter. Solid rails block vehicles; Select/Edit or Road Points reshapes them.",
		"draw_race":"Click the road for start, checkpoints and finish, in order. Enter saves; a circuit loops back to start.",
		"race_checkpoint":"Click on a road to insert a checkpoint after the selected gate. Esc returns to Select/Edit.",
		"race_grid":"Click to place the chosen grid slot. Drag a saved slot to move it; Esc returns to Select/Edit.",
		"draw_terrain":"Choose a material, click polygon vertices, then FINISH or Enter.",
		"place_marker":"Choose a marker type and click to place.",
		"place_dealership":"Click a clear lot center at least 35 m from a road.",
		"pan":"Drag to pan; the mouse wheel zooms around the cursor.",
		"anchor":"Drag road or sidewalk anchors to reshape; Alt-drag detaches connected path branches."}.get(mode,"Choose artwork, then click the map to place it."))
	_refresh_authoring()

func _refresh_authoring() -> void:
	if not is_instance_valid(gizmos):
		return
	workspace_tools.setup(self)
	workspace_tools.refresh()
	if source_ready:
		layer_flags["workspace_excluded"]=WorkspaceData.excluded(authoring.doc,true)
		gizmos.layer_flags=layer_flags.duplicate()
		_prune_multi_selection()
	if source_ready and not source_id.is_empty():
		var record:=_selected_record()
		if record.is_empty() or bool(record.item.get("hidden",false)) or not _workspace_selectable(source_id):source_id="";source_anchor=-1
		elif record.category=="roads" and source_anchor>=record.item.points.size():source_anchor=-1
	_sync_editor_preview()
	var preview_doc: Dictionary=authoring.road_preview_source(pending_drag) if source_ready else {}
	if source_ready and not map_switcher.custom:
		_sync_mountain_preview(preview_doc)
		bridge_preview.update(world.data,preview_doc,authoring.initial)
		gizmos.bridge_overrides=bridge_preview.by_road
		gizmos.bridge_redraw_roads=bridge_preview.redraw_roads
		if BridgeArt.editor_hidden!=bridge_preview.hidden:
			BridgeArt.editor_hidden=bridge_preview.hidden.duplicate()
			_redraw_roads();_update_overview_mask()
	if not map_switcher.custom:_sync_road_preview(preview_doc)
	elif is_instance_valid(gizmos):gizmos.layer_flags=layer_flags.duplicate()
	_update_source_details()
	_save_recovery()
	_update_context_panels()
	_refresh_inspector()
	_refresh_entity_list()
	if source_ready:
		gizmos.dealership_records=authoring.dealership_list() if not map_switcher.custom else []
		gizmos.road_width_scale=float(world.data.get("road_width_scale",1.0))/float(authoring.doc.get("morrowRoadWidthScale",1.0))
		# Only committed road edits trigger topology work, never pointer motion.
		traffic_preview.request(world.data,authoring.doc,{"roads":[]} if map_switcher.custom else authoring.initial)
		_update_traffic_preview()
		gizmos.set_draft(WorkspaceData.preview(preview_doc) if map_switcher.custom else preview_doc,{} if map_switcher.custom else authoring.initial,
			{} if pending_drag.get("kind","") in ["road","road_move","region"] else pending_drag,
			source_id,source_anchor)
		gizmos.group_selected_ids=multi_selection.duplicate()
		gizmos.group_selected_lookup.clear()
		for id in multi_selection:gizmos.group_selected_lookup[id]=true
		gizmos.set_pending_shape(draft_points,tool_name)
		if map_switcher.custom:map_switcher.refresh(self)
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
		_prune_multi_selection()
		_refresh_authoring()
		_notice("Undid the previous source edit. Changes remain unbaked.")

func _redo() -> void:
	if _editing_locked():
		return
	if source_ready and authoring.redo():
		pending_drag.clear()
		_prune_multi_selection()
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


func _resize_selected_region(scale: Vector2) -> void:
	if _editing_locked() or not source_ready or source_id.is_empty():return
	if _selected_record().get("category","")!="regions":return
	if authoring.resize_region(source_id,scale.x,scale.y):
		_refresh_authoring()
		_notice("Terrain resized. Save to Game when ready; Undo restores its previous footprint.")
	else:
		_notice(authoring.last_error)
		_refresh_inspector()

func _resize_region_by_percentage(direction: float) -> void:
	# Expand and Shrink read the current input on every click, not a fixed step.
	var percent: float=inspector_terrain_percent.value
	if not is_finite(percent) or percent<=0.0:
		_notice("Enter a positive terrain resize percentage.")
		return
	if direction<0.0 and percent>=100.0:
		_notice("Shrinking by 100% or more would erase the terrain. Enter a lower percentage.")
		return
	var factor:=1.0+direction*percent/100.0
	_resize_selected_region(Vector2(factor,factor))

func _region_bounds(region: Dictionary) -> Rect2:
	var points: Array=region.get("points",[])
	if points.is_empty():return Rect2()
	var first:=Vector2(float(points[0].x),float(points[0].y))
	var result:=Rect2(first,Vector2.ZERO)
	for point in points:result=result.expand(Vector2(float(point.x),float(point.y)))
	return result

func _commit_terrain_size(axis: String) -> void:
	if _updating_inspector or _editing_locked() or not source_ready:return
	var record:=_selected_record()
	if record.get("category","")!="regions":return
	var dimensions: Vector2=_region_bounds(record.item).size
	var current: float=dimensions.x if axis=="x" else dimensions.y
	var desired: float=inspector_terrain_width.value if axis=="x" else inspector_terrain_height.value
	if current<=0.0 or desired<=0.0:return
	_resize_selected_region(Vector2(desired/current,1.0) if axis=="x" else Vector2(1.0,desired/current))

func _rotate_selected(degrees: float) -> void:
	if _editing_locked():
		return
	if not source_ready or source_id.is_empty():
		return
	if angle_snap_degrees>0.0 and not Input.is_physical_key_pressed(KEY_ALT):
		var prop: Dictionary=authoring.prop_at_id(source_id)
		if not prop.is_empty():degrees=snappedf(float(prop.rotation)+degrees,angle_snap_degrees)-float(prop.rotation)
	if authoring.rotate_prop(source_id,degrees):
		_refresh_authoring()
		_notice("Asset and collision rotated %.0f° in editor. Save to Game when ready." % degrees)

func _set_angle_spacing(value: float) -> void:
	angle_snap_degrees=value
	if is_instance_valid(gizmos):gizmos.angle_guide_degrees=value;gizmos.queue_redraw()

func _angle_snap_point(origin: Vector2,target: Vector2) -> Vector2:
	if angle_snap_degrees<=0.0 or Input.is_physical_key_pressed(KEY_ALT):return target
	var delta:=target-origin
	if delta.length()<.01:return target
	var angle:=snappedf(delta.angle(),deg_to_rad(angle_snap_degrees))
	return origin+Vector2.RIGHT.rotated(angle)*delta.length()

func _arrange_selection(mode: String,axis: int) -> void:
	if _editing_locked() or not source_ready:return
	if authoring.arrange_props(multi_selection,mode,axis):
		_refresh_authoring();_notice("Aligned selection in one undo step." if mode=="align" else "Distributed selection in one undo step.")
	else:_notice(authoring.last_error)

func _set_grid_spacing(value: float) -> void:
	grid_spacing_m=value
	if snap_m>0:snap_m=value
	_refresh_grid_label()

func _refresh_grid_label() -> void:
	grid_button.text="Snap to grid: off" if snap_m==0 else "Snap to grid: "+str(snap_m)+" m"

func _toggle_snap() -> void:
	snap_m = 0.0 if snap_m > 0.0 else grid_spacing_m
	_refresh_grid_label()
	_notice("Grid snapping disabled." if snap_m==0 else "Grid snapping set to "+str(snap_m)+" m.")

func _bulk_fields() -> void:
	bulk_property.clear()
	var category:=_option_value(bulk_category)
	var fields: Array={"roads":["width","lanes","roadClass","surface","elevation","markings"],"props":["scale","scaleX","scaleY","rotation","roadFacing"],"regions":["biome","elevation","barrier"]}[category]
	for field in fields:
		bulk_property.add_item(str(field));bulk_property.set_item_metadata(bulk_property.item_count-1,field)
	bulk_property.select(0)
	_bulk_hint()

func _bulk_hint() -> void:
	var field:=_option_value(bulk_property)
	var examples: Dictionary={"width":"6–160 metres","lanes":"1–6","roadClass":"city / highway / country / mountain / service / track / alley / onramp","surface":"asphalt / concrete / gravel / dirt / track","elevation":"Road layer -2 to +2; region height in metres","markings":"true / false","roadFacing":"true / false","barrier":"true / false","biome":"grass / forest / rock / mountain / beach / lake / ocean / farmland / city / desert","scale":"0.2–5","scaleX":"0.2–5","scaleY":"0.2–5","rotation":"Degrees"}
	bulk_value.placeholder_text=str(examples.get(field,"Value"))
	bulk_value.text=""

func _open_bulk_edit() -> void:
	if _editing_locked() or not source_ready:return
	if multi_selection.is_empty() and source_id.is_empty():
		_notice("Select objects before opening Bulk edit.")
		return
	if not is_instance_valid(bulk_dialog):
		bulk_dialog=AcceptDialog.new()
		bulk_dialog.title="Bulk edit selected objects"
		bulk_dialog.ok_button_text="Apply in one undo step"
		bulk_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
		root_ui.add_child(bulk_dialog)
		var panel:=VBoxContainer.new();bulk_dialog.add_child(panel)
		bulk_category=_options(panel,"Apply to selected category",["roads","props","regions"])
		bulk_property=OptionButton.new();panel.add_child(bulk_property)
		bulk_value=LineEdit.new();panel.add_child(bulk_value)
		bulk_category.item_selected.connect(func(_i: int)->void:_bulk_fields())
		bulk_property.item_selected.connect(func(_i: int)->void:_bulk_hint())
		bulk_dialog.confirmed.connect(_apply_bulk_edit)
	_bulk_fields()
	bulk_dialog.popup_centered(Vector2i(540,185))

func _apply_bulk_edit() -> void:
	if _editing_locked():return
	var ids: Array[String]=multi_selection.duplicate()
	if ids.is_empty() and not source_id.is_empty():ids.append(source_id)
	var category:=_option_value(bulk_category)
	var key:=_option_value(bulk_property)
	var raw:=bulk_value.text.strip_edges().to_lower()
	var value: Variant=raw
	if key in ["markings","roadFacing","barrier"]:
		if raw not in ["true","false"]:_notice("Enter true or false.");return
		value=raw=="true"
	elif key=="elevation" and category=="roads":
		if not raw.is_valid_int() or absi(int(raw))>2:_notice("Enter a road layer from -2 to +2.");return
		value={"start_layer":int(raw),"end_layer":int(raw)}
	elif key in ["width","lanes","elevation","scale","scaleX","scaleY","rotation"]:
		if not raw.is_valid_float() or not is_finite(float(raw)):_notice("Enter a finite number.");return
		if key=="lanes":
			if not raw.is_valid_int():_notice("Lane count must be a whole number.");return
			value=int(raw)
		else:value=float(raw)
	if key=="biome" and raw not in ["grass","forest","rock","mountain","beach","lake","ocean","farmland","city","desert","dirt","asphalt"]:_notice("Unknown terrain material.");return
	if key=="elevation" and category=="regions" and (float(value)<0 or float(value)>2000):_notice("Height must be between 0 and 2000 m.");return
	if authoring.bulk_properties(ids,category,{key:value}):
		_refresh_authoring();_notice("Bulk property updated in one undo step.")
	else:_notice(authoring.last_error)

func _open_history() -> void:
	if _editing_locked() or not source_ready:return
	if not is_instance_valid(history_dialog):
		history_dialog=AcceptDialog.new();history_dialog.title="Edit history"
		history_dialog.ok_button_text="Restore selected state"
		history_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
		root_ui.add_child(history_dialog)
		history_items=ItemList.new();history_items.custom_minimum_size=Vector2(520,300)
		history_dialog.add_child(history_items)
		history_dialog.confirmed.connect(_restore_history)
	history_items.clear()
	for i in authoring.history.size():
		_add_history_row(authoring.history[i],i-authoring.history.size())
	_add_history_row(authoring.doc,0)
	history_items.select(history_items.item_count-1)
	for i in range(authoring.future.size()-1,-1,-1):_add_history_row(authoring.future[i],authoring.future.size()-i)
	history_dialog.popup_centered(Vector2i(560,370))

func _add_history_row(state: Dictionary,offset: int) -> void:
	var title: String="Current state" if offset==0 else ("%d edits earlier"%(-offset) if offset<0 else "%d edits later"%offset)
	history_items.add_item("%s  |  %d roads · %d props · %d regions"%[title,state.roads.size(),state.props.size(),state.regions.size()])
	history_items.set_item_metadata(history_items.item_count-1,offset)

func _restore_history() -> void:
	if _editing_locked() or not draft_points.is_empty() or not pending_drag.is_empty():return
	var selection:=history_items.get_selected_items()
	if selection.is_empty():return
	var offset:=int(history_items.get_item_metadata(selection[0]))
	for i in absi(offset):
		if offset<0:
			if not authoring.undo():_notice(authoring.last_error);break
		else:
			if not authoring.redo():_notice(authoring.last_error);break
	_prune_multi_selection();_refresh_authoring()
	_notice("Restored selected edit history state.")


func _delete_selected() -> void:
	if _editing_locked():
		return
	if multi_selection.size()>1:
		_group_action("delete")
		return
	if not source_ready or source_id.is_empty():
		return
	if authoring.delete_entity(source_id):
		source_id = ""
		_set_multi([])
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
	if map_switcher.custom:
		if not draft_points.is_empty() or not pending_drag.is_empty():_notice("Finish or cancel the current shape before saving.");return
		map_switcher.save_current(self);return
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
				prior.get("p",[]).size()==2 and Vector2(prior.p[0],prior.p[1]).distance_to(Vector2(item.p[0],item.p[1]))<.025:
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
		if not _workspace_selectable(str(road.id)):continue
		if not MultiSelect.road_matches_layer(road,road_selection_layer):continue
		for i in road.points.size():
			var point := Vector2(float(road.points[i].x),
				float(road.points[i].y))*PPM
			if not MultiSelect.road_point_matches_layer(road,point/PPM,road_selection_layer):continue
			var distance := point.distance_to(world_px)
			if distance < best:
				best = distance
				result = {"kind":"road","id":str(road.id),"index":i,
					"from":point}
	return result

func _pick_sidewalk_anchor(world_px: Vector2) -> Dictionary:
	if not source_ready or not layer_flags.scenery:
		return {}
	var best:=12.0/maxf(.003,editor_camera.zoom.x)
	var result: Dictionary={}
	for raw in authoring.doc.props:
		var prop: Dictionary=raw
		if str(prop.get("type","")) not in ["sidewalk","guardrail"] or bool(prop.get("hidden",false)):
			continue
		if tool_name!="anchor" and str(prop.id)!=source_id:
			continue
		var path: Array[Vector2]=Sidewalks.world_points(prop)
		for i in path.size():
			var at: Vector2=path[i]*PPM
			var delta:=at.distance_to(world_px)
			if delta<best:
				best=delta
				result={"kind":"sidewalk_point","id":str(prop.id),
					"index":i,"from":at}
	return result


func _pick_source_prop(world_px: Vector2) -> Dictionary:
	if not source_ready or not layer_flags.scenery:
		return {}
	var at: Vector2 = world_px/PPM
	var best := minf(1.0,4.0/(maxf(.003,editor_camera.zoom.x)*PPM))
	var hit: Dictionary = {}
	for index in range(authoring.doc.props.size()-1,-1,-1):
		var prop: Dictionary=authoring.doc.props[index]
		if not _workspace_selectable(str(prop.id)):continue
		if bool(prop.get("hidden",false)):
			continue
		if str(prop.get("type",""))=="guardrail":
			# A long curved guardrail should only be selectable near its actual
			# rail, not anywhere within its enormous axis-aligned bounding box.
			var rail_points: Array[Vector2]=Sidewalks.world_points(prop)
			var nearest:=INF
			for n in range(1,rail_points.size()):
				nearest=minf(nearest,at.distance_to(
					Geometry2D.get_closest_point_to_segment(at,rail_points[n-1],rail_points[n])))
			if nearest<best:
				best=nearest
				hit={"kind":"prop","id":str(prop.id),
					"from":Vector2(float(prop.x),float(prop.y))*PPM}
			continue
		var center := Vector2(float(prop.x),float(prop.y))
		var local := (at-center).rotated(-deg_to_rad(float(prop.get("rotation",0))))
		var half: Vector2=gizmos._prop_size(prop)/PPM*.5
		var distance := Vector2(maxf(0,absf(local.x)-half.x),
			maxf(0,absf(local.y)-half.y)).length()
		# Preserve guardrail centerline picks above; only tighten sprite roofs.
		if distance<best and BuildingSelection.is_building_kind(str(prop.get("type",""))):
			distance=BuildingSelection.hit_gap(at,center,
				deg_to_rad(float(prop.get("rotation",0.0))),half*2.0,
				gizmos._prop_texture(prop))
		if distance < best:
			best = distance
			hit = {"kind":"prop","id":str(prop.id),"from":center*PPM}
	return hit

func _source_click(world_px: Vector2) -> void:
	if _editing_locked():
		return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null:focus.release_focus()
	if tool_name=="measure":
		workspace_tools.measure_click(world_px/PPM);return
	if tool_name=="landscape_brush":
		_landscape_stamp(_snap_point(world_px/PPM));return
	if tool_name=="draw_river":
		var p:=_snap_point(world_px/PPM)
		if draft_points.is_empty() or draft_points[-1].distance_to(p)>.5:
			draft_points.append(p);_refresh_authoring()
		return
	if tool_name=="place_dealership":
		dealer_editor.place_at(_snap_point(world_px/PPM))
		return
	if tool_name=="race_checkpoint":
		var snapped_checkpoint: Vector2=_road_draw_point(world_px/PPM,true,true)
		if not snapped_checkpoint.is_finite():
			_notice("Checkpoint must be on an authored road. Zoom in and click the road surface.")
			return
		var added: int=authoring.insert_race_checkpoint(source_id,snapped_checkpoint,source_anchor)
		if added>=0:
			source_anchor=added
			_refresh_authoring()
			_notice("Checkpoint %d placed on road. Click the next road gate or press Esc."%added)
		else:_notice(authoring.last_error)
		return
	if tool_name=="race_grid":
		var grid_handle:=_pick_race_grid_handle(world_px)
		if not grid_handle.is_empty():
			var choice:=int(grid_handle.get("index",-1))+1
			if choice>=0 and choice<race_editor.grid_slot.item_count:
				race_editor.grid_slot.select(choice)
				race_editor._sync_rotation(self)
			pending_drag=grid_handle
			pending_drag["grab"]=world_px
			pending_drag["to"]=grid_handle.from
			_refresh_authoring()
		else:race_editor.place_grid_slot(self,world_px/PPM)
		return
	if tool_name=="place_circle_road":
		road_shapes.place(self,_snap_point(world_px/PPM));return
	if tool_name in ["draw_road","draw_sidewalk","draw_guardrail","draw_race"]:
		var point:=_road_draw_point(world_px/PPM,tool_name=="draw_race",tool_name=="draw_race") if tool_name in ["draw_road","draw_race"] else _snap_point(world_px/PPM)
		if tool_name=="draw_race" and not point.is_finite():
			_notice("Race start, checkpoints and finish must be placed on a road.")
			return
		var connection: Dictionary={}
		if tool_name=="draw_sidewalk":
			connection=Sidewalks.snap(authoring.doc.props,point,Sidewalks.SNAP_RADIUS_M)
			if not connection.is_empty():
				point=connection.point
		if draft_points.is_empty() or draft_points[-1].distance_to(point)>=.5:
			draft_points.append(point)
		_refresh_authoring()
		if tool_name=="draw_sidewalk":
			_notice("%d path points. %sFinish / Enter to keep every connected branch; Esc cancels."%
				[draft_points.size(),"Snapped to a sidewalk. " if not connection.is_empty() else ""])
		elif tool_name=="draw_guardrail":
			_notice("%d guardrail points. FINISH / Enter creates solid rails; Esc cancels."%draft_points.size())
		elif tool_name=="draw_race":
			_notice("%d race route points on roads. FINISH / Enter saves; Esc cancels."%draft_points.size())
		else:
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
		if not source_id.is_empty():marker_editor.open_for(self,source_id)
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
			var preferred: Array = active_project_asset.get("world_size",[])
			if preferred.size()==2 and float(preferred[0])>0.0 and float(preferred[1])>0.0:
				footprint=Vector2(float(preferred[0]),float(preferred[1]))
			id = authoring.add_project_prop(str(active_project_asset.path),
				str(active_project_asset.kind),world_px/PPM,footprint,
				str(active_project_asset.get("project_id","")),
				active_project_asset.get("region",[]),
				str(active_project_asset.get("collision","solid")),
				str(active_project_asset.get("name","")))
		else:
			id = authoring.add_prop(kind,world_px/PPM)
		if id != "":
			var prop: Dictionary=authoring.prop_at_id(id)
			var snapped:=_snap_building_transform(prop,Vector2(prop.x,prop.y))
			# Fold automatic snapping into the placement's existing undo step.
			# Overlapping buildings are valid authored placements.
			prop.x=snapped.position.x;prop.y=snapped.position.y;prop.rotation=snapped.rotation
			source_id = id
			source_anchor = -1
			_refresh_authoring()
			_notice("Placed "+kind+" with live artwork and collision preview. Save to Game when ready.")
		else:
			_notice(authoring.last_error)
		return
	if tool_name=="move_prop" and not map_switcher.custom and road_selection_layer==99:
		var dealer_id:=dealer_editor.pick(world_px)
		if not dealer_id.is_empty():
			dealer_editor.open_for(dealer_id)
			return
	if tool_name not in ["anchor","move_prop"]:
		select_at(world_px)
		return
	var race_handle: Dictionary=_pick_race_handle(world_px) if road_selection_layer==99 else {}
	if race_handle.is_empty() and tool_name=="move_prop" and road_selection_layer==99:
		var race_id: String=_pick_any_race_start(world_px)
		if not race_id.is_empty():
			source_id=race_id;source_anchor=-1
			selected={};gizmos.set_selection({})
			_refresh_authoring()
			_notice("Race selected. Drag checkpoints or edit race type, opponent count and route in Tool Settings.")
			return
	if not race_handle.is_empty():
		selected={};gizmos.set_selection({})
		source_anchor=int(race_handle.index);pending_drag=race_handle;pending_drag.grab=world_px;pending_drag.to=race_handle.from
		_refresh_authoring();return
	var hit: Dictionary={}
	if road_selection_layer!=99:
		hit=_pick_source_anchor(world_px) if tool_name=="anchor" else _pick_source_road(world_px)
	elif tool_name=="anchor":
		hit=_pick_source_anchor(world_px)
		if hit.is_empty():hit=_pick_sidewalk_anchor(world_px)
	else:
		hit=_pick_sidewalk_anchor(world_px)
		if hit.is_empty():hit=_pick_source_marker(world_px)
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
		if tool_name=="move_prop" and road_selection_layer==99:
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
			source_id="";source_anchor=-1;_update_selection({});_refresh_authoring()
			return
	source_id = str(hit.id)
	selected={}
	gizmos.set_selection({})
	source_anchor = int(hit.get("index",-1))
	pending_drag = hit.duplicate(true)
	pending_drag["grab"]=world_px
	pending_drag["to"] = hit.from
	if hit.kind=="sidewalk_point":
		var picked_path: Dictionary=authoring.prop_at_id(source_id)
		if str(picked_path.get("type",""))=="guardrail":
			details.text="SOLID GUARDRAIL ANCHOR\n%s\nPoint %d\n\nDrag to reshape the hitbox."%[source_id,source_anchor+1]
		else:
			details.text="SIDEWALK BRANCH ANCHOR\\n%s\\nPoint %d\\n\\nDrag to reshape joined branches. Alt-drag detaches this point."%[source_id,source_anchor+1]
	elif hit.kind=="road":
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
	if str(drag.kind)=="sidewalk_point":
		ok=authoring.move_sidewalk_point(str(drag.id),int(drag.index),
			_snap_point(destination_m),Sidewalks.SNAP_RADIUS_M,
			not Input.is_physical_key_pressed(KEY_ALT))
	elif str(drag.kind)=="road":
		var temporary=EditSession.new();temporary.doc=authoring.doc
		ok=temporary.move_road_point(str(drag.id),int(drag.index),destination_m,snap_m)
		if ok:
			var road: Dictionary=temporary.road_at_id(str(drag.id))
			if int(drag.index) in [0,road.points.size()-1] and not Input.is_physical_key_pressed(KEY_ALT):temporary.reconnect_endpoint(str(drag.id),int(drag.index),clampf(12.0/(editor_camera.zoom.x*PPM),2.0,12.0))
			ok=authoring._commit(temporary.doc)
	elif str(drag.kind)=="prop":
		var item: Dictionary=authoring.prop_at_id(str(drag.id))
		if str(item.get("type","")) in ["sidewalk","guardrail"]:
			ok=authoring.move_prop(str(drag.id),
				_snap_point((Vector2(drag.from)+world_px-Vector2(drag.grab))/PPM),0.0,
				not Input.is_physical_key_pressed(KEY_ALT))
		else:
			var snapped:=_snap_building_transform(item,
				(Vector2(drag.from)+world_px-Vector2(drag.grab))/PPM)
			ok=authoring.edit_entity(str(drag.id),{"rotation":snapped.rotation},snapped.position)
	elif str(drag.kind)=="race_grid":
		ok=authoring.set_race_grid_slot(str(drag.id),int(drag.index),
			_snap_point((Vector2(drag.from)+world_px-Vector2(drag.grab))/PPM))
	elif str(drag.kind)=="race_point":
		var snapped_gate: Vector2=_road_draw_point(destination_m,true,true)
		if snapped_gate.is_finite():ok=authoring.move_race_point(str(drag.id),int(drag.index),snapped_gate)
		else:authoring.last_error="Drag the checkpoint onto an authored road."
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
	b.focus_mode=Control.FOCUS_ALL
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
	map_switcher.restore(self)
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
	# Restore actual player collision geometry before physics resumes.
	var player_cell:=Vector2i((player.global_position/PPM/float(world.chunk_m)).floor())
	if not world.chunks.has(player_cell):
		world.pending.erase(player_cell)
		world._build_chunk(player_cell)
	for index in world.chunks:
		world.chunks[index].set_stream_active(world._stream_cell_distance(index,world.current_cell,world.secondary_current_cell)<=1)
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false

func _recenter() -> void:
	if active:
		editor_camera.global_position = player.global_position if is_instance_valid(player) else world.spawn_position()
		_update_view(true)

func _test_drive_from_cursor() -> void:
	var screen:=get_viewport().get_mouse_position()
	if not source_ready or not _canvas_pointer_available(screen):
		_notice("Hover over the map before pressing Ctrl+F6.");return
	var at:=_event_world_position(screen)/PPM
	if not authoring._in_bounds(at):
		_notice("Choose a position inside the map.");return
	var layer:=0 if road_selection_layer==99 else road_selection_layer
	_test_drive({"position":at*PPM,"layer":layer})

func _test_drive(cursor_spawn: Dictionary={}) -> void:
	if not active:
		return
	if not draft_points.is_empty() or not pending_drag.is_empty():
		_notice("Finish or cancel the current shape or drag before Test Drive.")
		return
	if is_instance_valid(bridge) and bridge.phase != "":
		_notice("Wait for the current map save to complete before Test Drive.")
		return
	if map_switcher.custom:
		# A custom drive is isolated from Morrow Coast and career progression.
		# Saving first guarantees the test and return both use this revision.
		if not map_switcher.save_current(self):
			return
		get_tree().set_meta("streetbound_test_drive_source_hash",authoring._fingerprint(authoring.doc))
		get_tree().set_meta("streetbound_test_drive_map",map_switcher.current_file)
		get_tree().set_meta("streetbound_test_drive_cursor",cursor_spawn)
		get_tree().set_meta("streetbound_editor_return_position",
			editor_camera.global_position)
		get_tree().paused = false
		var outcome := get_tree().change_scene_to_file("res://scenes/custom_map_test_drive.tscn")
		if outcome != OK:
			get_tree().remove_meta("streetbound_test_drive_map")
			get_tree().remove_meta("streetbound_test_drive_cursor")
			get_tree().remove_meta("streetbound_test_drive_source_hash")
			get_tree().remove_meta("streetbound_editor_return_position")
			_notice("Could not launch this custom map for Test Drive.")
		return
	# Bundled maps also start a clean production scene instead of
	# resuming the paused editor-backed vehicle with stale preview geometry.
	if authoring.dirty or (is_instance_valid(bridge) and bridge.phase != ""):
		_notice("Save to Game or DISCARD before Test Drive.")
		return
	get_tree().set_meta("streetbound_test_drive_source_hash",authoring._fingerprint(authoring.doc))
	get_tree().set_meta("streetbound_editor_test_drive",true)
	get_tree().set_meta("streetbound_test_drive_cursor",cursor_spawn)
	get_tree().set_meta("streetbound_editor_return_position",editor_camera.global_position)
	if not standalone_mode:
		_clear_editor_preview()
		_restore_gameplay_render()
	get_tree().paused = false
	var result:=get_tree().change_scene_to_file("res://scenes/main.tscn")
	if result!=OK:
		get_tree().remove_meta("streetbound_editor_test_drive")
		get_tree().remove_meta("streetbound_test_drive_cursor")
		get_tree().remove_meta("streetbound_test_drive_source_hash")
		get_tree().remove_meta("streetbound_editor_return_position")
		_notice("Could not launch full-game Test Drive.")


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
	_asset_refresh_elapsed+=dt
	if _asset_refresh_elapsed>=3.0 and pending_drag.is_empty():
		_asset_refresh_elapsed=0.0
		_scan_asset_library()
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
	if map_switcher.custom:
		map_switcher.update_view(self);return
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
	# Configure the current zoom's tile coverage and update the preview mask
	# first. Otherwise a detail-to-overview transition uses the previous
	# ready_to_show value, leaving a dirty atlas until the next camera update.
	# Consume the invalidation once, before the overview is displayed.
	if _overview_dirty and pending_drag.is_empty() and is_instance_valid(overview_renderer) and is_instance_valid(render_tiles) and not render_tiles.ready_to_show:
		_overview_dirty=false
		overview_renderer.refresh()
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
				_consume_input()
				return
			if active and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
				if tool_name in ["race_grid","race_checkpoint","landscape_brush","draw_river","measure"]:
					if not pending_drag.is_empty() or not draft_points.is_empty():_cancel_gesture()
					else:_choose_tool("move_prop")
					_consume_input()
					return
				if marquee_tracking or group_moving or not multi_selection.is_empty():
					marquee_tracking=false;group_moving=false
					gizmos.marquee_active=false;gizmos.group_drag_offset=Vector2.ZERO
					_set_multi([])
					_consume_input()
					return
				if not draft_points.is_empty() or not pending_drag.is_empty():
					_cancel_gesture()
				else:
					close_editor()
				_consume_input()
				return
			if active and tool_name in ["draw_terrain","draw_road","draw_sidewalk","draw_guardrail","draw_race","draw_river"] and key.keycode in [KEY_ENTER,KEY_KP_ENTER]:
				_finish_shape()
				_consume_input()
				return
			# Mirror the browser map editor's V/R/T/P/M/H tool shortcuts.
			# Never intercept typing in the searchable asset browser.
			var focused := get_viewport().gui_get_focus_owner()
			if active and not key.ctrl_pressed and not key.alt_pressed and \
					not (focused is LineEdit or focused is TextEdit):
				var shortcut := ""
				match key.physical_keycode:
					KEY_V: shortcut = "move_prop"
					KEY_B: shortcut = "select_box"
					KEY_R: shortcut = "draw_road"
					KEY_T: shortcut = "draw_terrain"
					KEY_P: shortcut = "place:house"
					KEY_M: shortcut = "place_marker"
					KEY_H: shortcut = "pan"
				if not shortcut.is_empty():
					_choose_tool(shortcut)
					_consume_input()
					return
			if active and key.ctrl_pressed and (key.keycode in [KEY_Z,KEY_Y] or
					key.physical_keycode in [KEY_Z,KEY_Y]):
				if key.keycode==KEY_Y or key.physical_keycode==KEY_Y or key.shift_pressed:
					_redo()
				else:
					_undo()
				_consume_input()
				return
			if active and key.ctrl_pressed and key.keycode==KEY_S:
				_apply_draft();_consume_input();return
			if active and key.ctrl_pressed and key.keycode==KEY_K:
				workspace_tools.open_commands();_consume_input();return
			if active and key.ctrl_pressed and key.keycode==KEY_C:
				_copy_selected_group();_consume_input();return
			if active and key.ctrl_pressed and key.keycode==KEY_V:
				_paste_selected_group();_consume_input();return
			if active and key.ctrl_pressed and key.keycode==KEY_D:
				_duplicate_selected();_consume_input();return
			if active and key.ctrl_pressed and key.keycode==KEY_A and tool_name=="move_prop":
				_select_all()
				_consume_input();return
			if active and key.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN] and (not source_id.is_empty() or multi_selection.size()>1):
				_nudge_selected({KEY_LEFT:Vector2.LEFT,KEY_RIGHT:Vector2.RIGHT,KEY_UP:Vector2.UP,KEY_DOWN:Vector2.DOWN}[key.keycode],key.shift_pressed)
				_consume_input();return
			if active and key.keycode==KEY_F:
				_fit_map();_consume_input();return
			if active and key.keycode in [KEY_DELETE,KEY_BACKSPACE]:
				_delete_selected();_consume_input();return
	if not active:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			_right_drag = mouse.pressed
			_consume_input()
		elif mouse.pressed and mouse.button_index in [
				MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.13 if mouse.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.13
			_set_zoom(editor_camera.zoom.x*factor,mouse.position)
			_consume_input()
		elif mouse.button_index==MOUSE_BUTTON_LEFT:
			if tool_name == "pan" or Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE):
				_right_drag = mouse.pressed
				_space_pan=mouse.pressed and tool_name!="pan"
				_consume_input()
				return
			var hit_position: Vector2 = _event_world_position(mouse.position)
			if mouse.pressed:
				if tool_name in ["move_prop","select_box"]:
					if _canvas_pointer_available(mouse.position):
						_start_canvas_selection(hit_position,mouse.shift_pressed)
					_consume_input()
					return
				_source_click(hit_position)
				if mouse.double_click and tool_name in ["draw_road","draw_terrain","draw_sidewalk","draw_guardrail","draw_race","draw_river"]:_finish_shape()
			elif marquee_tracking:
				_end_marquee(hit_position)
			elif group_moving:
				_end_group_move(hit_position,mouse.alt_pressed)
			elif not pending_drag.is_empty():
				_finish_source_drag(hit_position)
			_consume_input()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _right_drag:
			editor_camera.global_position -= motion.relative/editor_camera.zoom
			_consume_input()
		elif marquee_tracking:
			_update_marquee(_event_world_position(motion.position))
			_consume_input()
		elif group_moving:
			var offset: Vector2=_event_world_position(motion.position)-group_move_start
			if snap_m>0:offset=(offset/PPM).snapped(Vector2.ONE*snap_m)*PPM
			gizmos.group_drag_offset=offset
			gizmos.queue_redraw()
			_consume_input()
		elif not pending_drag.is_empty():
			_update_drag_preview(_event_world_position(motion.position))
			_consume_input()

func _event_world_position(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse()*screen_position

func _exit_tree() -> void:
	traffic_preview.finish()
	map_switcher.dispose()
	_restore_gameplay_render()
	if is_instance_valid(overview_renderer):overview_renderer.queue_free()
	if _owns_render_tiles and is_instance_valid(render_tiles):render_tiles.queue_free()
	if standalone_mode:get_tree().auto_accept_quit=_auto_quit_before
	Roads.editor_hidden={}
	BridgeArt.editor_hidden={}
	MountainArt.editor_hidden={}
	Scenery.editor_hidden={}

func _save_recovery() -> void:
	if map_switcher.custom:
		map_switcher.save_recovery(self);return
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
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_F6:
		_consume_input();_test_drive_from_cursor();return
	# _input runs before GUI consumption. Marquee must begin here; relying on
	# _unhandled_input dropped left presses over parts of the editor canvas.
	if event is InputEventMouseButton and event.pressed:
		var mouse:=event as InputEventMouseButton
		if mouse.button_index==MOUSE_BUTTON_LEFT and tool_name in ["move_prop","select_box"] and \
				not _editing_locked() and _canvas_pointer_available(mouse.position) and \
				not _space_pan and not Input.is_key_pressed(KEY_SPACE):
			_start_canvas_selection(_event_world_position(mouse.position),mouse.shift_pressed)
			_consume_input()
			return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE] or (event.button_index==MOUSE_BUTTON_LEFT and (tool_name=="pan" or _space_pan)):
			_right_drag=false
			_space_pan=false
		if event.button_index==MOUSE_BUTTON_LEFT and marquee_tracking:
			_end_marquee(_event_world_position(event.position))
			_consume_input()
		elif event.button_index==MOUSE_BUTTON_LEFT and group_moving:
			_end_group_move(_event_world_position(event.position),event.alt_pressed)
			_consume_input()
		elif event.button_index==MOUSE_BUTTON_LEFT and not pending_drag.is_empty():
			_finish_source_drag(_event_world_position(event.position))
			_consume_input()
	elif event is InputEventMouseMotion:
		if marquee_tracking:
			_update_marquee(_event_world_position(event.position))
			_consume_input()
		elif group_moving:
			var offset: Vector2=_event_world_position(event.position)-group_move_start
			if snap_m>0:offset=(offset/PPM).snapped(Vector2.ONE*snap_m)*PPM
			gizmos.group_drag_offset=offset
			gizmos.queue_redraw()
			_consume_input()
		elif not pending_drag.is_empty():
			_update_drag_preview(_event_world_position(event.position))
			_consume_input()
		elif _right_drag:
			editor_camera.global_position-=event.relative/editor_camera.zoom
			_consume_input()
	elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and not pending_drag.is_empty():
		_cancel_gesture();_consume_input()

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
		marquee_tracking=false;group_moving=false
		if is_instance_valid(gizmos):
			gizmos.marquee_active=false
			gizmos.group_drag_offset=Vector2.ZERO
		if not pending_drag.is_empty():
			pending_drag.clear()
			_refresh_authoring()

func _update_drag_preview(at: Vector2) -> void:
	if pending_drag.kind=="prop":
		var prop: Dictionary=authoring.prop_at_id(str(pending_drag.id))
		if str(prop.get("type","")) in ["sidewalk","guardrail"]:
			# Paths move as geometry, not as buildings that snap to neighboring walls.
			pending_drag.to=_snap_point((Vector2(pending_drag.from)+at-Vector2(pending_drag.grab))/PPM)*PPM
			pending_drag.erase("rotation")
			pending_drag["invalid"]=false
		else:
			var snapped:=_snap_building_transform(prop,(Vector2(pending_drag.from)+at-Vector2(pending_drag.grab))/PPM)
			pending_drag.to=Vector2(snapped.position)*PPM;pending_drag["rotation"]=snapped.rotation
			pending_drag["invalid"]=not bool(snapped.valid)
		gizmos.update_prop_drag(pending_drag)
		return
	elif pending_drag.kind in ["road_move","region","marker"]:
		pending_drag.to=Vector2(pending_drag.from)+_snap_point((at-Vector2(pending_drag.grab))/PPM)*PPM
	elif pending_drag.kind=="race_grid":
		pending_drag.to=_snap_point((Vector2(pending_drag.from)+at-Vector2(pending_drag.grab))/PPM)*PPM
	elif pending_drag.kind=="race_point":
		var target: Vector2=_road_draw_point(at/PPM,true,true)
		pending_drag.to=(target*PPM if target.is_finite() else Vector2(pending_drag.from))
	elif pending_drag.kind=="sidewalk_point":
		var proposed:=_snap_point(at/PPM)
		var selected_path: Dictionary=authoring.prop_at_id(str(pending_drag.id))
		if str(selected_path.get("type",""))=="sidewalk" and not Input.is_physical_key_pressed(KEY_ALT):
			var match_info:=Sidewalks.snap(authoring.doc.props,proposed,
				Sidewalks.SNAP_RADIUS_M,str(pending_drag.id))
			if not match_info.is_empty():proposed=match_info.point
		pending_drag.to=proposed*PPM
	else:pending_drag.to=_snap_point(at/PPM)*PPM
	if Time.get_ticks_msec()-_last_road_drag_ms<50:return
	_last_road_drag_ms=Time.get_ticks_msec()
	_refresh_authoring()

func _sync_road_preview(preview_doc: Dictionary={}) -> void:
	if not source_ready:return
	var document: Dictionary=authoring.doc if preview_doc.is_empty() else preview_doc
	var changed_sources: Dictionary={}
	var current: Dictionary={}
	for item in document.roads:current[str(item.id)]=item
	for original in authoring.initial.get("roads",[]):
		var road: Dictionary=current.get(str(original.id),{})
		if road!=original:changed_sources[int(str(original.id).trim_prefix("road-"))]=true
	if pending_drag.get("kind","") in ["road","road_move"]:
		changed_sources[int(str(pending_drag.id).trim_prefix("road-"))]=true
	var hidden: Dictionary={}
	for road in world.data.roads:
		var id:=int(road.id)
		var source:=int(road.get("editor_grade_source_id",id))
		if changed_sources.has(source) or (isolate_road_layer and not MultiSelect.road_matches_layer(road,road_selection_layer)):
			hidden[id]=true
	if hidden!=Roads.editor_hidden:
		# Dirty only tiles with a changed road/junction/bridge reference.
		var dirty: Dictionary={}
		for id in Roads.editor_hidden:
			if not hidden.has(id):dirty[id]=true
		for id in hidden:
			if not Roads.editor_hidden.has(id):dirty[id]=true
		Roads.editor_hidden=hidden
		_redraw_roads(dirty)
		_update_overview_mask()

func _update_traffic_preview() -> void:
	var fresh:=traffic_preview.is_current()
	var graph: RefCounted=traffic_preview.network if fresh else (null if map_switcher.custom else traffic_network)
	if gizmos.network==graph and gizmos.network_is_draft==fresh:return
	gizmos.network=graph
	gizmos.network_is_draft=fresh
	gizmos.preview_junctions=traffic_preview.data.get("junctions",[]) if fresh else []
	gizmos.queue_redraw()

func _update_overview_mask() -> void:
	# The 4096px atlas is expensive. Keep it cached while editing at detail LOD.
	_overview_dirty=true

func _redraw_roads(dirty: Dictionary={}) -> void:
	if not is_instance_valid(world):return
	var loaded: Array=render_tiles.tiles.values() if is_instance_valid(render_tiles) else world.chunks.values()
	for tile in loaded:
		if not dirty.is_empty():
			var touches:=false
			for batch in tile.road_batches:
				if dirty.has(int(batch.road.id)):touches=true;break
			if not touches:
				for junction in tile.junction_list:
					for id in junction.get("roads",[]):
						if dirty.has(int(id)):touches=true;break
					if touches:break
			if not touches:continue
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

func _select_road_option(control: OptionButton,value: String) -> void:
	for i in control.item_count:
		if str(control.get_item_metadata(i))==value:
			control.select(i);return

func _change_inspector_road_type(index: int) -> void:
	if _updating_inspector or _setting_controls:return
	road_class.select(index)
	_change_road_type(index)

func _change_road_type(_index: int) -> void:
	if _setting_controls:return
	var kind:=_option_value(road_class)
	# Racing asphalt is a paved track, not a dirt road with painted kerbs.
	if kind=="alley":
		_select_road_option(road_surface,"asphalt")
		if tool_name in ["draw_road","place_circle_road"]:
			_setting_controls=true
			road_width.value=6.0
			road_lanes.value=1
			_setting_controls=false
	elif kind=="onramp":
		_select_road_option(road_surface,"asphalt")
		_setting_controls=true
		road_width.value=8.0
		road_lanes.value=1
		_setting_controls=false
		_notice("1 lane: directional highway merge. 2 lanes: two-way ramp or tunnel approach.")
	elif kind=="track":_select_road_option(road_surface,"track")
	elif _option_value(road_surface)=="track":_select_road_option(road_surface,"asphalt")
	_commit_road_type_and_surface()

func _change_road_surface(_index: int) -> void:
	if _setting_controls:return
	var surface:=_option_value(road_surface)
	if surface=="track":_select_road_option(road_class,"track")
	elif _option_value(road_class)=="track" and surface in ["gravel","dirt"]:
		_select_road_option(road_class,"country")
	_commit_road_type_and_surface()

func _commit_road_type_and_surface() -> void:
	if _setting_controls or not source_ready or tool_name in ["draw_road","place_circle_road"] or _editing_locked():return
	if authoring.set_road_settings(source_id,{"roadClass":_option_value(road_class),
		"surface":_option_value(road_surface)}):
		_refresh_authoring()
		_notice("Road type and surface updated. Geometry and dimensions preserved.")

func _change_road_jump() -> void:
	if not source_ready or _editing_locked():return
	var jump: Variant = null
	if road_jump_enabled.button_pressed:
		jump = {"reverse":road_jump_reverse.button_pressed}
		for key in road_jump_fields:
			jump[key] = road_jump_fields[key].value
	if authoring.set_road_settings(source_id,{"jump":jump}):
		_refresh_authoring()
		_notice("Stunt jump updated")
	else:
		_notice(authoring.last_error)


func _refresh_point_elevation_fields(road: Dictionary) -> void:
	var key := str(road.id)+str(road.points)+str(road.get("elevation",{}))
	if key==road_point_profile_key:return
	road_point_profile_key=key
	for child in road_point_elevation_fields.get_children():
		road_point_elevation_fields.remove_child(child)
		child.queue_free()
	road_point_layer_inputs.clear()
	var points: Array=road.points
	var total:=0.0
	for i in range(1,points.size()):
		total+=Vector2(points[i-1].x,points[i-1].y).distance_to(Vector2(points[i].x,points[i].y))
	var station:=0.0
	for i in points.size():
		if i>0:station+=Vector2(points[i-1].x,points[i-1].y).distance_to(Vector2(points[i].x,points[i].y))
		var values: Array=road.get("elevation",{}).get("point_layers",[])
		var layer:=float(values[i]) if values.size()==points.size() else floorf(lerpf(road_start_layer.value,road_end_layer.value,station/maxf(total,.001))+.5)
		var spin:=_number(road_point_elevation_fields,"Point %d (%.0f, %.0f)"%[i+1,float(points[i].x),float(points[i].y)],-2,2,layer)
		spin.step=1.0
		spin.value=layer
		road_point_layer_inputs.append(spin)


func _apply_point_elevations() -> void:
	if not source_ready or _editing_locked():return
	var layers: Array = []
	for spin in road_point_layer_inputs:layers.append(int(spin.value))
	if authoring.apply_point_elevations(source_id,layers):
		road_point_profile_key=""
		_refresh_authoring()
		_notice("Saved individual elevations on the selected road.")
	else:_notice(authoring.last_error)


func _change_road_elevation() -> void:
	if not source_ready or _editing_locked():return
	var elevation:={"start_layer":int(road_start_layer.value),"end_layer":int(road_end_layer.value)}
	if authoring.set_road_settings(source_id,{"elevation":elevation}):
		_refresh_authoring()
		_notice("Road elevation updated in the draft.")
	else:
		_notice(authoring.last_error)


func _open_auto_guardrails() -> void:
	if _editing_locked() or not source_ready:return
	var identity:=source_id
	var road: Dictionary=authoring.road_at_id(identity)
	if road.is_empty():return
	if not EditSession.AutoRails.ground(road):
		_notice("Auto guardrails currently support ground-level roads. Raised decks use existing bridge rails.");return
	var revision: int=authoring.edit_revision
	var session: RefCounted=authoring
	var dialog:=AcceptDialog.new()
	dialog.title="Road-linked guardrails"
	dialog.ok_button_text="Apply guardrails"
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(dialog)
	var panel:=VBoxContainer.new()
	panel.custom_minimum_size=Vector2(370,260)
	dialog.add_child(panel)
	var info:=Label.new()
	var length:=0.0
	var path:=EditSession.road_path(road)
	for i in range(1,path.size()):length+=path[i-1].distance_to(path[i])
	info.text="Road length ≈ %.0f m. Left/right follow first → last control point. Junctions and merges leave automatic gaps."%length
	info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(info)
	var controls: Dictionary={}
	for side in ["left","right"]:
		var enabled:=CheckButton.new()
		enabled.text=side.capitalize()+" guardrail"
		panel.add_child(enabled)
		var settings: Dictionary=road.get("autoGuardrails",{})
		enabled.button_pressed=settings.has(side)
		var interval: Array=settings.get(side,[0,100])
		var row:=HBoxContainer.new();panel.add_child(row)
		var start:=_number(row,"Start %",0,100,float(interval[0]))
		var end:=_number(row,"End %",0,100,float(interval[1]))
		start.step=.1;end.step=.1
		controls[side]=[enabled,start,end]
	var status:=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(status)
	dialog.confirmed.connect(func():
		if _editing_locked() or authoring!=session or authoring.edit_revision!=revision or source_id!=identity:
			_notice("Road changed. Reopen Auto guardrails.");dialog.queue_free();return
		var settings: Dictionary={}
		for side in controls:
			var row: Array=controls[side]
			if row[0].button_pressed:settings[side]=[row[1].value,row[2].value]
		if authoring.set_auto_guardrails(identity,settings):
			_refresh_authoring();_notice("Road-linked guardrails updated. Undo restores previous ranges.")
			dialog.queue_free()
		else:
			status.text=authoring.last_error
			dialog.call_deferred("popup_centered"))
	dialog.canceled.connect(dialog.queue_free)
	_btn("Remove both sides",panel,func():
		for side in controls:controls[side][0].button_pressed=false)
	dialog.popup_centered()

func _change_road_settings() -> void:
	if _setting_controls or not source_ready or tool_name in ["draw_road","place_circle_road"] or _editing_locked():return
	if authoring.set_road_settings(source_id,{"roadClass":_option_value(road_class),
		"surface":_option_value(road_surface),"width":road_width.value,"lanes":int(road_lanes.value)}):
		_refresh_authoring()
		_notice("Road settings updated in the draft.")

func _selected_record() -> Dictionary:
	if not source_ready or source_id.is_empty():return {}
	for category in ["roads","regions","props","markers","races"]:
		for item in authoring.doc.get(category,[]):
			if str(item.id)==source_id:return {"category":category,"item":item}
	return {}

func _record_position(record: Dictionary) -> Vector2:
	var item: Dictionary=record.item
	if item.has("points"):
		if record.category in ["roads","races"] and source_anchor>=0 and source_anchor<item.points.size():
			return Vector2(item.points[source_anchor].x,item.points[source_anchor].y)
		if record.category=="roads":
			var circle:=EditSession.RoadShapes.circle(item.points)
			if not circle.is_empty():return circle.center
		var center:=Vector2.ZERO
		for p in item.points:center+=Vector2(p.x,p.y)
		return center/item.points.size()
	return Vector2(item.x,item.y)

func _refresh_inspector() -> void:
	if not is_instance_valid(inspector_name):return
	_updating_inspector=true
	var record:=_selected_record()
	var context:=EditorContext.resolve(tool_name,str(record.get("category","")),str(record.get("item",{}).get("type","")),multi_selection.size())
	var exists:=bool(context.selected_fields)
	selection_fields.visible=exists
	inspector_road_type_fields.visible=exists and record.get("category","")=="roads"
	if inspector_road_type_fields.visible:
		var kind:=str(record.item.get("roadClass","city"))
		if str(record.item.get("surface",""))=="track":kind="track"
		_select_road_option(inspector_road_type,kind)
		_select_road_option(inspector_junction_start,str(record.item.get("junctionStart","auto")))
		_select_road_option(inspector_junction_end,str(record.item.get("junctionEnd","auto")))
	edit_actions.visible=bool(context.selection_actions)
	if multi_selection.size()>1:
		details.text="%d OBJECTS SELECTED\nDrag to move the group. Duplicate or delete the selection."%multi_selection.size()
		selected_preview.hide()
	inspector_name.editable=exists
	for spin in [inspector_x,inspector_y,inspector_rotation,inspector_scale,inspector_scale_x,inspector_scale_y]:spin.editable=exists
	terrain_transforms.visible=exists and record.category=="regions"
	for spin in [inspector_terrain_width,inspector_terrain_height]:spin.editable=terrain_transforms.visible
	prop_transforms.visible=exists and record.category=="props"
	point_picker.visible=exists and record.category in ["roads","races"]
	remove_point_button.visible=point_picker.visible
	add_point_button.visible=point_picker.visible
	split_road_button.visible=point_picker.visible and record.category=="roads"
	reconnect_road_button.visible=split_road_button.visible
	connection_label.visible=split_road_button.visible
	var race_selected: bool=exists and record.category=="races"
	add_point_button.text="Place checkpoint on road" if race_selected else "Add road point"
	remove_point_button.text="Remove checkpoint" if race_selected else "Remove selected road point"
	point_picker.clear()
	if exists:
		var item: Dictionary=record.item
		inspector_name.text=str(item.get("name",""))
		var at:=_record_position(record);inspector_x.value=at.x;inspector_y.value=at.y
		inspector_rotation.value=float(item.get("rotation",0));inspector_scale.value=float(item.get("scale",1))
		inspector_scale_x.value=float(item.get("scaleX",1));inspector_scale_y.value=float(item.get("scaleY",1))
		if record.category=="regions":
			var region_size: Vector2=_region_bounds(item).size
			inspector_terrain_width.value=region_size.x
			inspector_terrain_height.value=region_size.y
		if record.category=="props":
			var size: Vector2=gizmos._prop_size(item)/PPM
			asset_dimensions_label.text="Footprint: %.2f × %.2f m"%[size.x,size.y]
			var path_prop:=str(item.get("type","")) in ["sidewalk","guardrail"]
			prop_transforms.visible=not path_prop
			var building:=RoadBuildingSnap.supports(item)
			inspector_road_facing.visible=building;inspector_road_front.visible=building
			inspector_road_facing.set_pressed_no_signal(RoadBuildingSnap.enabled(item))
			inspector_road_front.disabled=not RoadBuildingSnap.enabled(item)
			for i in inspector_road_front.item_count:
				if int(inspector_road_front.get_item_metadata(i))==int(item.get("roadFront",90)):inspector_road_front.select(i);break
		if race_selected and source_anchor<0:
			inspector_x.editable=false;inspector_y.editable=false
		if record.category in ["roads","races"]:
			point_picker.add_item("Whole race (center)" if race_selected else "Whole road (center)")
			for i in item.points.size():
				var title: String="Control point %d"%[i+1]
				if race_selected:title="Start" if i==0 else ("Finish" if item.mode=="sprint" and i==item.points.size()-1 else "Checkpoint %d"%i)
				point_picker.add_item(title)
			point_picker.select(clampi(source_anchor+1,0,item.points.size()))
			remove_point_button.disabled=item.points.size()<=(3 if race_selected and item.mode=="circuit" else 2)
			split_road_button.text="Detach junction" if source_anchor==0 or source_anchor==item.points.size()-1 else "Split road here"
			reconnect_road_button.disabled=source_anchor not in [0,item.points.size()-1]
			connection_label.text="Ends move independently" if bool(item.get("independentEnds",false)) else "Touching ends move together"
	else:
		inspector_name.text="";inspector_x.value=0;inspector_y.value=0
	_updating_inspector=false

func _commit_inspector(field: String="name") -> void:
	if _updating_inspector or not active or _editing_locked():return
	var record:=_selected_record()
	if record.is_empty():return
	var values: Dictionary={}
	if field=="name":values["name"]=inspector_name.text
	var destination:=_record_position(record)
	if field=="x":destination.x=inspector_x.value
	if field=="y":destination.y=inspector_y.value
	if record.category=="races" and field in ["x","y"]:
		if source_anchor<0:
			_notice("Select an individual start, checkpoint or finish gate to move it.")
			_refresh_inspector()
			return
		var snapped_coordinate: Vector2=_road_draw_point(destination,true,true)
		if not snapped_coordinate.is_finite():
			_notice("Checkpoint coordinates must be on an existing road.")
			_refresh_inspector()
			return
		destination=snapped_coordinate
	if record.category=="props":
		var controls: Dictionary={"rotation":inspector_rotation,"scale":inspector_scale,"scaleX":inspector_scale_x,"scaleY":inspector_scale_y}
		if controls.has(field):values[field]=controls[field].value
		if field=="roadFacing":values[field]=inspector_road_facing.button_pressed
		if field=="roadFront":values[field]=int(inspector_road_front.get_item_metadata(inspector_road_front.selected))
		if field in ["x","y","roadFacing","roadFront"]:
			var adjusted: Dictionary=record.item.duplicate();adjusted.merge(values,true)
			# Disabling this preference never moves or rotates the asset.
			if field!="roadFacing" or bool(values[field]):
				var snapped:=_snap_building_transform(adjusted,destination)
				destination=snapped.position;values["rotation"]=snapped.rotation
	if authoring.edit_entity(source_id,values,destination,source_anchor):
		_refresh_authoring()
	else:_notice(authoring.last_error);_refresh_inspector()

func _change_terrain_settings() -> void:
	if _setting_controls:return
	if _option_value(terrain_biome) not in ["mountain","rock"]:terrain_barrier.set_pressed_no_signal(false)
	terrain_elevation.editable=terrain_barrier.button_pressed
	terrain_elevation.visible=terrain_barrier.button_pressed
	mountain_help.visible=terrain_barrier.button_pressed
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

func _change_junction_mode(index: int, at_end: bool) -> void:
	if _updating_inspector or _editing_locked() or not source_ready:return
	var picker := inspector_junction_end if at_end else inspector_junction_start
	var mode := str(picker.get_item_metadata(index))
	var key := "junctionEnd" if at_end else "junctionStart"
	if authoring.set_road_settings(source_id,{key:mode}):
		_refresh_authoring()
		_notice("Connection mode changed. On-ramp requires a valid three-arm merge. Ctrl+Z undoes it.")
	else:
		_notice(authoring.last_error)
		_refresh_inspector()

func _select_point(index: int) -> void:
	if _updating_inspector:return
	source_anchor=index-1;_refresh_authoring()

func _remove_point() -> void:
	if _editing_locked() or not source_ready:return
	if not authoring.race_at_id(source_id).is_empty():
		if authoring.change_race_points(source_id,maxi(0,source_anchor),true):source_anchor=-1;_refresh_authoring()
		else:_notice(authoring.last_error)
		return
	var road: Dictionary=authoring.road_at_id(source_id)
	var index: int=source_anchor if source_anchor>=0 else road.get("points",[]).size()/2
	if authoring.remove_road_point(source_id,index):source_anchor=-1;_refresh_authoring()
	else:_notice(authoring.last_error)

func _reconnect_road() -> void:
	if _editing_locked() or not source_ready:return
	if authoring.reconnect_endpoint(source_id,source_anchor):
		_refresh_authoring();_notice("Endpoint snapped and reconnected. Touching road ends now move together. Undo restores the detached road.")
	else:_notice(authoring.last_error)

func _reset_asset_size() -> void:
	if _editing_locked() or not source_ready:return
	var record:=_selected_record()
	if record.is_empty() or record.category!="props":return
	if authoring.edit_entity(source_id,{"scale":1.0,"scaleX":1.0,"scaleY":1.0},_record_position(record)):
		_refresh_authoring();_notice("Original asset size restored. Position, rotation and artwork are preserved.")

func _duplicate_selected() -> void:
	if _editing_locked() or not source_ready:return
	if multi_selection.size()>1:
		_group_action("duplicate",Vector2(12,12))
		return
	var id: String=authoring.duplicate_entity(source_id)
	if id.is_empty():_notice(authoring.last_error);return
	var duplicate: Dictionary=authoring.prop_at_id(id)
	if not duplicate.is_empty() and RoadBuildingSnap.supports(duplicate):
		var snapped:=_snap_building_transform(duplicate,Vector2(float(duplicate.x),float(duplicate.y)))
		# Preserve the duplicate's single undo step, even when overlapping.
		duplicate.x=snapped.position.x
		duplicate.y=snapped.position.y
		duplicate.rotation=snapped.rotation
	source_id=id;source_anchor=-1;_set_multi([id]);_refresh_authoring();_notice("Created an editable copy. Ctrl+Z undoes it.")

func _nudge_selected(direction: Vector2,large: bool=false) -> void:
	if _editing_locked():return
	if multi_selection.size()>1:
		var stride: float=(snap_m if snap_m>0 else 1.0)*(10 if large else 1)
		_group_action("move",direction*stride)
		return
	var record:=_selected_record()
	if record.is_empty():return
	var step: float=(snap_m if snap_m>0 else 1.0)*(10 if large else 1)
	var destination:=_record_position(record)+direction*step
	var values: Dictionary={}
	if record.category=="props":
		var snapped:=_snap_building_transform(record.item,destination)
		destination=snapped.position;values["rotation"]=snapped.rotation
	if authoring.edit_entity(source_id,values,destination,source_anchor):_refresh_authoring()
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
	for category in ["roads","regions","props","markers","races"]:
		for item in authoring.doc.get(category,[]):
			if bool(item.get("hidden",false)) or not _workspace_selectable(str(item.id)):continue
			if road_selection_layer!=99 and (category!="roads" or not MultiSelect.road_matches_layer(item,road_selection_layer)):continue
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
	if is_instance_valid(inspector_tabs):inspector_tabs.current_tab=0

func _set_road_isolation(enabled: bool) -> void:
	if _editing_locked():return
	isolate_road_layer=enabled
	layer_flags["road_isolation_layer"]=road_selection_layer if enabled else 99
	gizmos.layer_flags=layer_flags.duplicate()
	_refresh_authoring();gizmos.queue_redraw()

func _set_other_road_lock(enabled: bool) -> void:
	if _editing_locked():return
	lock_other_roads=enabled
	authoring.unlocked_road_layer=road_selection_layer if enabled else 99
	_notice("Other road objects are locked against edits." if enabled and road_selection_layer!=99 else "Road edit lock released.")

func _set_road_selection_layer(index: int) -> void:
	if _editing_locked():return
	road_selection_layer=99 if index==0 else index-3
	layer_flags["road_selection_layer"]=road_selection_layer
	layer_flags["road_isolation_layer"]=road_selection_layer if isolate_road_layer else 99
	authoring.unlocked_road_layer=road_selection_layer if lock_other_roads else 99
	gizmos.layer_flags=layer_flags.duplicate()
	_set_multi([])
	source_id="";source_anchor=-1;pending_drag.clear()
	_update_selection({})
	_refresh_authoring()
	_refresh_entity_list(true)
	_notice("All object types selectable." if road_selection_layer==99 else "Road selection restricted to layer %d."%road_selection_layer)

func _copy_selected_group() -> void:
	if _editing_locked() or not source_ready:return
	var ids: Array[String]=multi_selection.duplicate()
	if ids.is_empty() and not source_id.is_empty():ids.append(source_id)
	var group: Dictionary=authoring.copy_group(ids)
	if group.is_empty():_notice(authoring.last_error);return
	copied_group=group
	_notice("Copied %d objects. Pan to a destination or switch maps, then Paste."%group.entries.size())

const PREFAB_PATH="user://streetbound-prefabs.json"

func _open_landscape() -> void:
	if _editing_locked() or not source_ready:return
	if not is_instance_valid(landscape_dialog):
		landscape_dialog=AcceptDialog.new();landscape_dialog.title="Terrain and landscaping"
		landscape_dialog.ok_button_text="Activate tool";landscape_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
		root_ui.add_child(landscape_dialog)
		var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(480,430);landscape_dialog.add_child(scroll)
		var panel:=VBoxContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(panel)
		landscape_mode=_options(panel,"Landscape mode",["raise","lower","smooth","flatten","paint","vegetation","grade selected road","river"])
		landscape_fields["radius"]=_number(panel,"Brush radius m",5,1000,100)
		landscape_fields["amount"]=_number(panel,"Height change m / strength %",1,100,25)
		landscape_fields["level"]=_number(panel,"Target height m",-1200,1200,0)
		landscape_fields["biome"]=_options(panel,"Paint material",["grass","forest","dirt","rock","beach","asphalt","desert","farmland","city","mountain"])
		landscape_fields["vegetation"]=_options(panel,"Vegetation",["tree","pine","palm","bush"])
		landscape_fields["density"]=_number(panel,"Vegetation density %",0,100,50)
		landscape_fields["seed"]=_number(panel,"Vegetation seed",0,2147483647,1847)
		landscape_fields["river_width"]=_number(panel,"River width m",6,160,24)
		landscape_fields["bank"]=_number(panel,"Bank width m",2,80,12)
		landscape_fields["depth"]=_number(panel,"Channel depth m",1,100,8)
		landscape_fields["import_min"]=_number(panel,"Import minimum m",-1200,1200,0)
		landscape_fields["import_max"]=_number(panel,"Import maximum m",-1200,1200,300)
		_btn("Import grayscale heightmap",panel,_open_heightmap)
		var help:=Label.new();help.text="Click to stamp brushes. River: click centreline points, then Finish. Grading uses selected road. Heights affect visual relief, not vehicle Z physics."
		help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(help)
		landscape_dialog.confirmed.connect(_activate_landscape)
	landscape_dialog.popup_centered(Vector2i(520,510))

func _collect_landscape() -> Dictionary:
	var settings: Dictionary={"mode":_option_value(landscape_mode)}
	for key in landscape_fields:
		var control: Control=landscape_fields[key]
		settings[key]=control.value if control is SpinBox else _option_value(control)
	return settings

func _activate_landscape() -> void:
	if _editing_locked():return
	landscape_settings=_collect_landscape()
	landscape_session=authoring
	var mode: String=landscape_settings.mode
	if mode=="grade selected road":
		var road: Dictionary=authoring.road_at_id(source_id)
		if road.is_empty():_notice("Select a road before grading its terrain.");return
		var field:=TerrainHeight.grade_road(authoring.doc.get("terrainHeight",{}),Vector2(authoring.doc.world.width,authoring.doc.world.height),EditSession.road_path(road),float(landscape_settings.radius),float(landscape_settings.level))
		if authoring.set_terrain_height(field):_refresh_authoring();_notice("Graded visual terrain along the selected road.")
		else:_notice(authoring.last_error)
		return
	_choose_tool("draw_river" if mode=="river" else "landscape_brush")
	mode_label.text="RIVER CENTERLINE" if mode=="river" else "TERRAIN "+mode.to_upper()
	_notice("Click river centreline points; Finish creates channel and banks." if mode=="river" else "Click the map to apply a brush stamp. Each stamp is undoable.")

func _open_heightmap() -> void:
	if _editing_locked():return
	landscape_settings=_collect_landscape();landscape_session=authoring
	if not is_instance_valid(landscape_file):
		landscape_file=FileDialog.new();landscape_file.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		landscape_file.access=FileDialog.ACCESS_FILESYSTEM;landscape_file.filters=PackedStringArray(["*.png ; PNG","*.jpg,*.jpeg ; JPEG","*.webp ; WebP"])
		root_ui.add_child(landscape_file);landscape_file.file_selected.connect(_import_heightmap)
	landscape_dialog.hide();landscape_file.popup_centered_ratio(.7)

func _import_heightmap(path: String) -> void:
	if _editing_locked() or landscape_session!=authoring:return
	var image:=Image.load_from_file(path)
	var field:=TerrainHeight.import_image(image,float(landscape_settings.import_min),float(landscape_settings.import_max))
	if field.is_empty():_notice("Invalid heightmap image or height range.");return
	if authoring.set_terrain_height(field):_refresh_authoring();_notice("Heightmap imported into the map source; Ctrl+Z to undo.")
	else:_notice(authoring.last_error)

func _landscape_stamp(at: Vector2) -> void:
	if landscape_session!=authoring:return
	var mode: String=landscape_settings.mode
	var radius:=float(landscape_settings.radius)
	if mode=="paint":
		var points: Array[Vector2]=[]
		var extent:=Vector2(authoring.doc.world.width,authoring.doc.world.height)
		for i in 24:
			var p:=at+Vector2.RIGHT.rotated(TAU*float(i)/24.0)*radius
			points.append(p.clamp(Vector2.ZERO,extent))
		if not authoring.add_region(points,str(landscape_settings.biome)).is_empty():_refresh_authoring();_notice("Painted terrain material.")
		else:_notice(authoring.last_error)
		return
	if mode=="vegetation":
		var plan:=Construction.plan_vegetation(_construction_source(),at,radius,float(landscape_settings.density)/100.0,str(landscape_settings.vegetation),int(landscape_settings.seed)+authoring.edit_revision,authoring.prop_limit())
		var ids: Array[String]=authoring.apply_construction(plan)
		if not ids.is_empty():_refresh_authoring();_notice("Placed %d vegetation objects."%ids.size())
		else:_notice(authoring.last_error)
		return
	var field:=TerrainHeight.apply(authoring.doc.get("terrainHeight",{}),Vector2(authoring.doc.world.width,authoring.doc.world.height),at,radius,float(landscape_settings.amount),mode,float(landscape_settings.level))
	if authoring.set_terrain_height(field):_refresh_authoring();_notice("Applied visual height brush.")
	else:_notice(authoring.last_error)

func _open_construction() -> void:
	if _editing_locked() or not source_ready:return
	if not draft_points.is_empty() or not pending_drag.is_empty():
		_notice("Finish or cancel the current edit first.");return
	construction_center=_snap_point(editor_camera.global_position/PPM)
	construction_road_id=source_id
	construction_plan={};construction_revision=-1
	if not is_instance_valid(construction_dialog):
		construction_dialog=AcceptDialog.new()
		construction_dialog.title="City construction tools"
		construction_dialog.ok_button_text="Apply preview"
		construction_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
		root_ui.add_child(construction_dialog)
		var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(520,540);construction_dialog.add_child(scroll)
		var panel:=VBoxContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(panel)
		construction_mode=_options(panel,"Construction mode",["advanced neighborhood","directional diamond","city grid","district fill","roadside decoration","interchange","property kit"])
		construction_fields["district"]=_options(panel,"District style",["residential","commercial","industrial","downtown"])
		construction_fields["neighborhood_style"]=_options(panel,"Neighborhood style",["mixed use","residential","commercial","industrial","downtown"])
		construction_fields["variation"]=_number(panel,"Block variation %",0,22,18)
		for label in [["parks","Include landscaped parks"],["parking","Include connected parking lots"]]:
			var choice:=CheckBox.new();choice.text=label[1];choice.button_pressed=true;panel.add_child(choice);construction_fields[label[0]]=choice
		var dimensions:=HBoxContainer.new();panel.add_child(dimensions)
		construction_fields["columns"]=_number(dimensions,"Columns",1,12,3)
		construction_fields["rows"]=_number(dimensions,"Rows",1,12,3)
		construction_fields["block"]=_number(panel,"Block spacing m",70,300,120)
		construction_fields["width"]=_number(panel,"Street width m",8,24,12)
		construction_fields["lanes"]=_number(panel,"Lanes",1,4,2)
		construction_fields["density"]=_number(panel,"Building density %",0,100,70)
		construction_fields["seed"]=_number(panel,"Layout seed",0,2147483647,1847)
		var buildings:=CheckBox.new();buildings.text="Fill blocks with buildings";buildings.button_pressed=true;panel.add_child(buildings);construction_fields["buildings"]=buildings
		var alleys:=CheckBox.new();alleys.text="Add central alleyways";panel.add_child(alleys);construction_fields["alleys"]=alleys
		for option in [["connect","Connect to existing road"],["sidewalks","Add block sidewalks"],["plots","Add editable building plots"]]:
			var toggle:=CheckBox.new();toggle.text=option[1];panel.add_child(toggle);construction_fields[option[0]]=toggle
		construction_fields["interchange"]=_options(panel,"Interchange template",["diamond","half diamond","three way","cloverleaf foundation","trumpet foundation","directional foundation"])
		construction_fields["interchange_span"]=_number(panel,"Interchange half-span m",180,500,240)
		construction_fields["property"]=_options(panel,"Property kit",["fuel station","garage","shopping center","convenience store","pawn shop","jewelry store","bank","dealership"])
		construction_fields["decoration"]=_options(panel,"Roadside decoration",["streetlight","tree","sign"])
		construction_fields["spacing"]=_number(panel,"Decoration spacing m",15,150,40)
		construction_summary=Label.new();construction_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		construction_summary.custom_minimum_size=Vector2(480,60);panel.add_child(construction_summary)
		construction_canvas=Control.new();construction_canvas.custom_minimum_size=Vector2(480,200);panel.add_child(construction_canvas)
		construction_canvas.draw.connect(_draw_construction_preview)
		_btn("Preview generation",panel,_preview_construction)
		_btn("Validate preview with production compiler",panel,_preflight_construction)
		construction_dialog.confirmed.connect(_apply_construction)
		construction_mode.item_selected.connect(func(_i: int)->void:_invalidate_construction())
		for control in construction_fields.values():
			if control is SpinBox:control.value_changed.connect(func(_v: float)->void:_invalidate_construction())
			elif control is OptionButton:control.item_selected.connect(func(_i: int)->void:_invalidate_construction())
			elif control is CheckBox:control.toggled.connect(func(_v: bool)->void:_invalidate_construction())
	_invalidate_construction()
	construction_dialog.popup_centered(Vector2i(540,600))

func _invalidate_construction() -> void:
	construction_plan={};construction_revision=-1
	construction_summary.text="Centre: %.0f, %.0f m. Preview before applying."%[construction_center.x,construction_center.y]
	match _option_value(construction_mode):
		"advanced neighborhood":construction_summary.text+="\n2–8 blocks per axis, 120–300 m spacing, 10–20 m street width. A custom map must pass production preflight."
		"directional diamond":construction_summary.text+="\nCustom maps only; production preflight is required."
		"roadside decoration","property kit":construction_summary.text+="\nUses the selected road."
	construction_dialog.get_ok_button().disabled=true
	if is_instance_valid(construction_canvas):construction_canvas.queue_redraw()

func _construction_source() -> Dictionary:
	var source: Dictionary=authoring.doc.duplicate(false)
	if map_switcher.custom:return source
	var blockers: Array=[]
	for prop in world.data.get("props",[]):
		if not bool(prop.get("solid",false)) or prop.get("p",[]).size()!=2 or prop.get("size",[]).size()!=2:continue
		blockers.append({"x":float(prop.p[0]),"y":float(prop.p[1]),"assetSize":prop.size,"scale":1.0})
	source["_runtime_blockers"]=blockers
	return source

func _preview_construction() -> void:
	if _editing_locked():return
	var settings: Dictionary={}
	for key in construction_fields:
		var control: Control=construction_fields[key]
		if control is SpinBox:settings[key]=control.value
		elif control is OptionButton:settings[key]=_option_value(control)
		elif control is CheckBox:settings[key]=control.button_pressed
	settings.density=float(settings.density)/100.0
	match _option_value(construction_mode):
		"advanced neighborhood":construction_plan=AdvancedConstruction.plan_neighborhood(_construction_source(),construction_center,settings,authoring.road_limit(),authoring.prop_limit())
		"directional diamond":construction_plan=AdvancedConstruction.plan_diamond(authoring.doc,construction_center,settings,authoring.road_limit())
		"city grid":construction_plan=Construction.plan_grid(_construction_source(),construction_center,settings,authoring.road_limit(),authoring.prop_limit())
		"district fill":construction_plan=Construction.plan_district(_construction_source(),construction_center,settings,authoring.prop_limit())
		"roadside decoration":construction_plan=Construction.plan_roadside(_construction_source(),construction_road_id,settings,authoring.prop_limit())
		"interchange":construction_plan=Construction.plan_interchange(authoring.doc,construction_center,settings,authoring.road_limit())
		"property kit":construction_plan=Construction.plan_property(_construction_source(),construction_road_id,construction_center,settings,authoring.road_limit(),authoring.prop_limit())
	if construction_plan.has("error"):
		construction_summary.text=str(construction_plan.error)
		construction_dialog.get_ok_button().disabled=true
		return
	construction_revision=authoring.edit_revision;construction_session=authoring
	var count: int=construction_plan.roads.size()+construction_plan.props.size()+construction_plan.get("regions",[]).size()+construction_plan.get("markers",[]).size()
	construction_summary.text="%s: %d roads, %d scenery, %d plots, %d gameplay markers. Apply is one undo step."%[construction_plan.label,construction_plan.roads.size(),construction_plan.props.size(),construction_plan.get("regions",[]).size(),construction_plan.get("markers",[]).size()]
	if construction_plan.has("stats"):construction_summary.text+="\n"+str(construction_plan.stats)
	construction_dialog.get_ok_button().disabled=count==0 or (map_switcher.custom and _option_value(construction_mode) in ["advanced neighborhood","directional diamond"])
	if map_switcher.custom and _option_value(construction_mode) in ["advanced neighborhood","directional diamond"]:construction_summary.text+="\nValidate the preview with the production compiler before applying."
	construction_canvas.queue_redraw()

func _preflight_construction() -> void:
	if _editing_locked() or construction_plan.is_empty() or construction_plan.has("error") or construction_session!=authoring or construction_revision!=authoring.edit_revision:
		_notice("Preview the current source first.");return
	var result:=AdvancedConstruction.preflight(authoring.doc,construction_plan)
	construction_summary.text+="\n"+str(result.message)
	if map_switcher.custom and _option_value(construction_mode) in ["advanced neighborhood","directional diamond"]:construction_dialog.get_ok_button().disabled=not bool(result.ok)

func _draw_construction_preview() -> void:
	var canvas:=construction_canvas
	canvas.draw_rect(Rect2(Vector2.ZERO,canvas.size),Color("#28353b"))
	if construction_plan.is_empty() or construction_plan.has("error"):return
	var area: Rect2=construction_plan.get("area",Rect2(construction_center-Vector2.ONE*20,Vector2.ONE*40))
	# Include gameplay markers in the framing, not just the building footprint.
	for marker in construction_plan.get("markers",[]):area=area.expand(Vector2(marker.x,marker.y))
	area=area.grow(12)
	var scale:=minf((canvas.size.x-20)/maxf(1,area.size.x),(canvas.size.y-20)/maxf(1,area.size.y))
	var origin:=canvas.size*.5-area.get_center()*scale
	for region in construction_plan.get("regions",[]):
		var polygon:=PackedVector2Array()
		for p in region.points:polygon.append(origin+Vector2(p.x,p.y)*scale)
		canvas.draw_colored_polygon(polygon,Color("#567a51") if str(region.get("biome",""))=="grass" else Color("#65717a"))
	for road in construction_plan.get("roads",[]):
		var points:=PackedVector2Array()
		for p in EditSession.road_path(road):points.append(origin+p*scale)
		var color:=Color("#b1b7b6")
		if road.has("elevation"):color=Color("#79b8dd")
		if points.size()>1:canvas.draw_polyline(points,color,maxf(1,float(road.width)*scale),true)
	for prop in construction_plan.get("props",[]):
		var p:=origin+Vector2(prop.x,prop.y)*scale
		if prop.get("type","")=="sidewalk":
			var path:=PackedVector2Array()
			for raw in prop.sidewalkPoints:path.append(p+Vector2(raw[0],raw[1])*scale)
			if path.size()>1:canvas.draw_polyline(path,Color("#dfd7c4"),maxf(1,2*scale),true)
		else:
			var footprint:=Vector2(12,17) if prop.type=="house" else Vector2(22,29)
			if prop.type in ["streetlight","sign","oak"]:footprint=Vector2(5,5)
			if prop.type=="parking":footprint=Vector2(38,28)
			if prop.has("assetSize"):footprint=Vector2(float(prop.assetSize[0]),float(prop.assetSize[1]))
			footprint*=float(prop.get("scale",1))
			var shape:=PackedVector2Array()
			for corner in [Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)]:shape.append(p+(corner*footprint).rotated(deg_to_rad(float(prop.get("rotation",0))))*scale)
			canvas.draw_colored_polygon(shape,Color("#869399") if prop.type=="parking" else (Color("#6d9b64") if prop.type in ["oak","pine","palm","bush"] else Color("#c4a17d")))
	for marker in construction_plan.get("markers",[]):canvas.draw_circle(origin+Vector2(marker.x,marker.y)*scale,4,Color("#ffc66e"))

func _apply_construction() -> void:
	if _editing_locked() or construction_plan.is_empty() or construction_session!=authoring or construction_revision!=authoring.edit_revision:
		_notice("Map changed; preview construction again.");return
	var ids: Array[String]=authoring.apply_construction(construction_plan)
	if ids.is_empty():_notice(authoring.last_error);return
	_set_multi(ids.slice(0,MultiSelect.LIMIT));source_anchor=-1
	source_id=ids[0] if ids.size()==1 else ""
	construction_plan={}
	_refresh_authoring();_notice("Created %d editable objects. Ctrl+Z undoes the entire construction."%ids.size())

func _open_prefabs() -> void:
	if _editing_locked() or not source_ready:return
	if not is_instance_valid(prefab_dialog):
		prefab_dialog=AcceptDialog.new()
		prefab_dialog.title="Reusable map groups"
		prefab_dialog.ok_button_text="Close"
		prefab_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
		root_ui.add_child(prefab_dialog)
		var panel:=VBoxContainer.new();prefab_dialog.add_child(panel)
		prefab_name=LineEdit.new();prefab_name.placeholder_text="New prefab name";panel.add_child(prefab_name)
		_btn("Save copied group",panel,_save_prefab)
		prefab_list=ItemList.new();prefab_list.custom_minimum_size=Vector2(500,240);panel.add_child(prefab_list)
		_btn("Load selected into clipboard",panel,_load_prefab)
		_btn("Delete selected prefab",panel,_delete_prefab)
	prefab_records.clear()
	if FileAccess.file_exists(PREFAB_PATH):
		var file:=FileAccess.open(PREFAB_PATH,FileAccess.READ)
		if file!=null and file.get_length()<16*1024*1024:
			var saved: Variant=JSON.parse_string(file.get_as_text())
			if saved is Array:
				for entry in saved:
					if entry is Dictionary and entry.get("group") is Dictionary and entry.get("name") is String:prefab_records.append(entry)
	_refresh_prefab_list()
	prefab_dialog.popup_centered(Vector2i(540,420))

func _refresh_prefab_list() -> void:
	prefab_list.clear()
	for entry in prefab_records:prefab_list.add_item(str(entry.name))

func _write_prefabs() -> bool:
	var raw:=JSON.stringify(prefab_records)
	if raw.to_utf8_buffer().size()>16*1024*1024:
		_notice("Prefab library exceeds 16 MB.");return false
	var file:=FileAccess.open(PREFAB_PATH+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(raw);file.flush();file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(PREFAB_PATH+".tmp"),ProjectSettings.globalize_path(PREFAB_PATH))==OK

func _save_prefab() -> void:
	var title:=prefab_name.text.strip_edges().left(80)
	if title.is_empty() or copied_group.is_empty():
		_notice("Copy a group and enter a prefab name first.");return
	if prefab_records.size()>=100:
		_notice("Prefab library supports 100 entries.");return
	for entry in prefab_records:
		if str(entry.name).nocasecmp_to(title)==0:
			_notice("Use a different prefab name.");return
	var group:=copied_group.duplicate(true)
	var origin:=Vector2(group.origin)
	group.origin=[origin.x,origin.y]
	prefab_records.append({"name":title,"group":group})
	if not _write_prefabs():
		prefab_records.pop_back();_notice("Could not save prefab.");return
	_refresh_prefab_list();_notice("Saved prefab "+title+".")

func _load_prefab() -> void:
	var ids:=prefab_list.get_selected_items()
	if ids.is_empty():return
	var group: Dictionary=prefab_records[ids[0]].group.duplicate(true)
	var origin: Variant=group.get("origin")
	if not origin is Array or origin.size()!=2 or not group.get("entries") is Array:
		_notice("Prefab data is invalid.");return
	group.origin=Vector2(float(origin[0]),float(origin[1]))
	copied_group=group
	prefab_dialog.hide();_notice("Prefab loaded. Paste at the camera centre.")

func _delete_prefab() -> void:
	var ids:=prefab_list.get_selected_items()
	if ids.is_empty():return
	var removed: Dictionary=prefab_records.pop_at(ids[0])
	if not _write_prefabs():
		prefab_records.insert(ids[0],removed);_notice("Could not update prefab library.");return
	_refresh_prefab_list()

func _paste_selected_group() -> void:
	if _editing_locked() or not source_ready or copied_group.is_empty():return
	var at:=_snap_point(editor_camera.global_position/PPM)
	var ids: Array[String]=authoring.paste_group(copied_group,at)
	if ids.is_empty():_notice(authoring.last_error);return
	_set_multi(ids)
	source_id=ids[0] if ids.size()==1 else ""
	source_anchor=-1
	_refresh_authoring()
	_notice("Pasted %d objects in one undo step."%ids.size())

func _set_layer(enabled: bool,key: String) -> void:
	layer_flags[key]=enabled
	if is_instance_valid(road_layer_settings):road_layer_settings.visible=bool(layer_flags.roads)
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
	var landmark_world=map_switcher.original_world_node if map_switcher.custom else world
	if is_instance_valid(landmark_world) and is_instance_valid(landmark_world.dealerships):
		var node: Node2D=landmark_world.dealerships
		if not _landmark_visibility.has(node):_landmark_visibility[node]=node.visible
		# Morrow's dynamically placed showrooms/forecourts are a separate
		# render layer, not authored objects in a blank custom map.
		node.visible=bool(layer_flags.scenery) and not map_switcher.custom

func _snap_point(point: Vector2) -> Vector2:
	return point.snapped(Vector2.ONE*snap_m) if snap_m>0 else point

func _road_draw_point(point: Vector2,any_surface: bool=false,require_road: bool=false) -> Vector2:
	var best:=INF
	var result:=_snap_point(point)
	if not require_road and tool_name=="draw_road" and not draft_points.is_empty():result=_angle_snap_point(draft_points[-1],result)
	for road in authoring.doc.get("roads",[]):
		if not _workspace_selectable(str(road.id)):continue
		if not MultiSelect.road_matches_layer(road,road_selection_layer):continue
		if not any_surface and (str(road.surface) in ["gravel","dirt"])!=(_option_value(road_surface) in ["gravel","dirt"]):continue
		var circle:=EditSession.RoadShapes.circle(road.points)
		if not circle.is_empty():
			var candidate:=EditSession.RoadShapes.closest_on_circle(circle,point)
			var distance:=point.distance_to(candidate)
			var radius: float=minf(25.0,maxf(9.0,float(road.width)*.5+4.0)) if require_road else maxf(float(road.width)*.5+1.0,8/(editor_camera.zoom.x*PPM))
			if distance<radius and distance<best:
				best=distance;result=candidate
			continue
		var path:=_source_road_path(road)
		for i in range(1,path.size()):
			var candidate:=Geometry2D.get_closest_point_to_segment(point,path[i-1],path[i])
			var distance:=point.distance_to(candidate)
			var radius: float=minf(25.0,maxf(9.0,float(road.width)*.5+4.0)) if require_road else maxf(float(road.width)*.5+1.0,8/(editor_camera.zoom.x*PPM))
			if distance<radius and distance<best:
				best=distance;result=candidate
	return Vector2.INF if require_road and best==INF else result

func _update_source_details() -> void:
	if not source_ready:return
	if source_id.is_empty():
		if selected.is_empty():
			details.text="Select an object to inspect its properties. Use the Objects tab to find it by name."
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
		if str(prop.get("type",""))=="guardrail":
			details.text="GUARDRAIL  /  %s\n%d path points · %.2fm collision width\nDrawn as a solid barrier. Select/Edit to move anchors; Save to Game to bake."%[
				source_id,(prop.get("guardrailPoints",[]) as Array).size(),float(prop.get("guardrailWidth",.65))]
		else:
			details.text=("SIDEWALK  /  %s\n%d path points · %.1fm wide\nSelect / Edit: drag point handles to branch or reshape.\nAlt-drag a handle to detach."%[source_id,prop.sidewalkPoints.size(),float(prop.sidewalkWidth)]) if str(prop.get("type",""))=="sidewalk" else "SCENERY  /  %s\n%s\nX %.1fm · Y %.1fm\nRotation %.0f° · Scale %.2f"%[
			source_id,str(prop.name),float(prop.x),float(prop.y),float(prop.get("rotation",0)),float(prop.get("scale",1))]
		selected_preview.texture=gizmos._prop_texture(prop)
		selected_preview.visible=selected_preview.texture!=null
		return
	var race: Dictionary=authoring.race_at_id(source_id)
	if not race.is_empty():
		details.text="RACE / %s\n%s · %d points · %d lap(s)\nDrag checkpoint handles to reshape the route."%[race.name,str(race.mode).capitalize(),race.points.size(),int(race.get("laps",1))];return
	for category in ["regions","markers"]:
		for item in authoring.doc.get(category,[]):
			if str(item.id)==source_id:
				if category=="regions" and MountainGeometry.solid(item):
					details.text="MOUNTAIN BARRIER / %s\n%s\nHeight %.0fm · blocks vehicles\nDrag the rock face to move it."%[source_id,str(item.get("name","")),float(item.elevation)]
					return
				details.text="%s / %s\n%s\n\nDrag its %s to move. New objects can be deleted; Undo restores edits."%[
					category.to_upper(),source_id,str(item.get("name","")),"interior" if category=="regions" else "center"]
				return

func _finish_shape() -> void:
	if _editing_locked() or not source_ready:return
	if tool_name=="draw_river":
		if landscape_session!=authoring:return
		var plan:=Construction.plan_river(_construction_source(),draft_points,float(landscape_settings.river_width),float(landscape_settings.bank),float(landscape_settings.depth))
		var ids: Array[String]=authoring.apply_construction(plan)
		if ids.is_empty():_notice(authoring.last_error);return
		draft_points.clear();_refresh_authoring();_notice("Created river and banks in one undo step.");return
	var identity: String=""
	if tool_name=="draw_road":
		identity=authoring.add_road_path(draft_points,{"roadClass":_option_value(road_class),
			"surface":_option_value(road_surface),"width":road_width.value,"lanes":int(road_lanes.value)})
	elif tool_name=="draw_terrain":identity=authoring.add_region(draft_points,_option_value(terrain_biome),terrain_barrier.button_pressed,terrain_elevation.value if terrain_barrier.button_pressed else 0)
	elif tool_name=="draw_sidewalk":identity=authoring.add_sidewalk(draft_points,sidewalk_width.value)
	elif tool_name=="draw_guardrail":identity=authoring.add_guardrail(draft_points,guardrail_width.value)
	elif tool_name=="draw_race":identity=race_editor.finish(self)
	if identity.is_empty():_notice(authoring.last_error);return
	source_id=identity;source_anchor=-1;draft_points.clear()
	var placed_race: bool=tool_name=="draw_race"
	if placed_race:tool_name="move_prop";mode_label.text="SELECT / EDIT";_update_active_tool_style()
	_refresh_authoring()
	_notice("Created "+identity+". Select/Edit to move it; Save to Game when ready.")
	# Open the full setup immediately after placing a new race, as well as
	# from Edit Race on any subsequently selected race.
	if placed_race:race_editor.open_for(self,identity)

func _cancel_gesture() -> void:
	pending_drag.clear();draft_points.clear();_right_drag=false
	_refresh_authoring();_notice("Unfinished edit canceled. Committed edits are unchanged.")

func _pick_source_road(at: Vector2) -> Dictionary:
	if not layer_flags.roads:return {}
	var best:=12.0/maxf(.003,editor_camera.zoom.x)
	var hit: Dictionary={}
	for road in authoring.doc.get("roads",[]):
		if not _workspace_selectable(str(road.id)):continue
		if not MultiSelect.road_matches_layer(road,road_selection_layer):continue
		var line:=_source_road_path(road)
		for i in range(1,line.size()):
			var nearest:=Geometry2D.get_closest_point_to_segment(at,line[i-1]*PPM,line[i]*PPM)
			if not MultiSelect.road_point_matches_layer(road,nearest/PPM,road_selection_layer):continue
			var distance:=nearest.distance_to(at)
			if distance<maxf(best,float(road.width)*PPM*.5) and (hit.is_empty() or distance<best):
				best=distance;hit={"kind":"road_move","id":str(road.id),"from":at}
	return hit

func _source_road_path(road: Dictionary) -> PackedVector2Array:
	for original in authoring.initial.get("roads",[]):
		if str(original.id)==str(road.id) and JSON.stringify(original)==JSON.stringify(road):
			var index:=int(str(road.id).trim_prefix("road-"))
			if index<world.data.roads.size():
				var path:=PackedVector2Array()
				for piece in world.data.roads:
					if int(piece.get("editor_grade_source_id",piece.id))!=index:continue
					for p in piece.points:
						var at:=Vector2(p[0],p[1])
						if path.is_empty() or path[-1].distance_to(at)>.001:path.append(at)
				return path
	return EditSession.road_path(road)

func _pick_source_marker(at: Vector2) -> Dictionary:
	if not layer_flags.markers:return {}
	for item in authoring.doc.get("markers",[]):
		if not _workspace_selectable(str(item.id)):continue
		var center:=Vector2(item.x,item.y)*PPM
		if center.distance_to(at)<12/maxf(.003,editor_camera.zoom.x):
			return {"kind":"marker","id":str(item.id),"from":center}
	return {}

func _pick_source_region(at: Vector2) -> Dictionary:
	if not source_ready or not layer_flags.terrain:return {}
	# Last-authored terrain is on top. Pick the filled interior as well as
	# its boundary so no precise edge click is required for whole-piece drags.
	for index in range(authoring.doc.regions.size()-1,-1,-1):
		var item: Dictionary=authoring.doc.regions[index]
		if not _workspace_selectable(str(item.id)):continue
		var polygon:=PackedVector2Array()
		for vertex in item.points:
			polygon.append(Vector2(float(vertex.x),float(vertex.y))*PPM)
		if polygon.size()<3:continue
		var inside:=Geometry2D.is_point_in_polygon(at,polygon)
		var near_edge:=false
		for i in polygon.size():
			if Geometry2D.get_closest_point_to_segment(at,polygon[i],
					polygon[(i+1)%polygon.size()]).distance_to(at)<8/maxf(.003,editor_camera.zoom.x):
				near_edge=true
				break
		if inside or near_edge:return {"kind":"region","id":str(item.id),"from":at}
	return {}

func _pick_source_mountain(at: Vector2) -> Dictionary:
	if not layer_flags.terrain:return {}
	for item in authoring.doc.get("regions",[]):
		if not _workspace_selectable(str(item.id)):continue
		if MountainGeometry.solid(item) and Geometry2D.is_point_in_polygon(at/PPM,MountainGeometry.polygon(item)):
			return {"kind":"region","id":str(item.id),"from":at}
	return {}

func _nearest_prop(p: Vector2) -> Dictionary:
	if not layer_flags.scenery:return {}
	# The actual baked per-chunk prop indices, not a separate browser index.
	var cell := Vector2i((p/PPM/float(world.chunk_m)).floor())
	var nearest := {}
	var best := minf(1.0,4.0/(maxf(.003,editor_camera.zoom.x)*PPM))
	for x in range(cell.x-1,cell.x+2):
		for y in range(cell.y-1,cell.y+2):
			var key := "%d,%d" % [x,y]
			var chunk: Dictionary = world.data.chunks.get(key,{})
			for raw_index in chunk.get("props",[]):
				var index := int(raw_index)
				var item: Dictionary = world.data.props[index]
				if Scenery.editor_hidden.has(Scenery.editor_key(item)):continue
				var c := Vector2(float(item.p[0]),float(item.p[1]))
				var half := Vector2(float(item.size[0]),float(item.size[1]))*0.5
				var local: Vector2 = (p/PPM-c).rotated(-float(item.get("angle",0.0)))
				var gap: float = Vector2(
					maxf(0.0,absf(local.x)-half.x),
					maxf(0.0,absf(local.y)-half.y)).length()
				if gap < best and BuildingSelection.is_building_kind(str(item.get("kind",""))):
					var texture: Texture2D=null
					if item.has("asset_path"):
						texture=Art.project_sprite(str(item.asset_path),item.get("asset_region",[]))
					else:
						texture=Art.sprite(str(item.kind),int(item.get("seed",0)))
					gap=BuildingSelection.hit_gap(p/PPM,c,
						float(item.get("angle",0.0)),half*2.0,texture)
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
			selected_preview.texture = Art.project_sprite(str(prop.asset_path),prop.get("asset_region",[]))
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
		details.text = "Select an object to inspect its properties. Use the Objects tab to find it by name."
	if not measured.is_empty():
		details.text += "\n\nSurface: %s  Grip: %.2f" % [
			str(measured.get("surface","")),float(measured.get("grip",0.0))]

func _add_point() -> void:
	if _editing_locked() or not source_ready:return
	if not authoring.race_at_id(source_id).is_empty():
		race_editor.begin_checkpoint(self)
		return
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
	if not id.is_empty():
		var detached: bool=id==source_id
		source_id=id
		if not detached:source_anchor=0
		_refresh_authoring()
		_notice("Junction detached. Drag this road or endpoint away; neighboring roads stay put." if detached else "Road split. Each half now moves independently. Drag the selected endpoint to create a gap.")
	else:_notice(authoring.last_error)

func _toggle_building_snap() -> void:
	building_snap_enabled=not building_snap_enabled
	building_snap_button.text="Building edges: on" if building_snap_enabled else "Building edges: off"

func _pick_race_grid_handle(at: Vector2) -> Dictionary:
	if not source_ready or not layer_flags.markers:return {}
	var race: Dictionary=authoring.race_at_id(source_id)
	if race.is_empty():return {}
	var slots: Array=[]
	var starting: Dictionary=race.get("player_start",{})
	if starting.is_empty():starting=preload("res://scripts/world/race_start_grid.gd").player_slot(race)
	slots.append(starting)
	slots.append_array(race.get("enemy_starts",[]))
	var nearest:=14.0/maxf(.003,editor_camera.zoom.x)
	var picked_slot: Dictionary={}
	for i in slots.size():
		var p:=Vector2(float(slots[i].x),float(slots[i].y))*PPM
		var distance:=p.distance_to(at)
		if distance<nearest:
			nearest=distance
			picked_slot={"kind":"race_grid","id":source_id,"index":i-1,"from":p}
	return picked_slot

func _pick_any_race_start(at: Vector2) -> String:
	if not source_ready or not layer_flags.markers:return ""
	var nearest: float=12.0/maxf(.003,editor_camera.zoom.x)
	var identity: String=""
	for race in authoring.doc.get("races",[]):
		if race.get("points",[]).is_empty():continue
		var start: Dictionary=race.points[0]
		var distance: float=Vector2(float(start.x),float(start.y)).distance_to(at/PPM)*PPM
		if distance<nearest:
			nearest=distance;identity=str(race.id)
	return identity

func _pick_race_handle(at: Vector2) -> Dictionary:
	if not source_ready or not layer_flags.markers:return {}
	var race: Dictionary=authoring.race_at_id(source_id)
	if race.is_empty():return {}
	for i in race.points.size():
		var p:=Vector2(race.points[i].x,race.points[i].y)*PPM
		if p.distance_to(at)<12/maxf(.003,editor_camera.zoom.x):return {"id":source_id,"kind":"race_point","index":i,"from":p}
	return {}

func _snap_building(prop: Dictionary,at: Vector2) -> Vector2:
	return _snap_building_transform(prop,at).position

func _ensure_road_building_index() -> void:
	var context: String="%d/%s/%d"%[world.get_instance_id(),map_switcher.current_file,authoring.get_instance_id()]
	if _road_snap_revision==authoring.edit_revision and _road_snap_context==context:return
	_road_snap_revision=authoring.edit_revision;_road_snap_context=context
	var key: String=context+JSON.stringify(authoring.doc.roads).sha256_text()
	if key==road_building_snap.stamp:return
	var roads: Array=[]
	var width_scale: float=float(world.data.get("road_width_scale",1))/float(authoring.doc.get("morrowRoadWidthScale",1))
	for road in authoring.doc.roads:
		roads.append({"id":road.id,"path":_source_road_path(road),"width":float(road.width)*width_scale,"shoulder":float(road.get("shoulder",2))})
	road_building_snap.rebuild(roads,key)

func _building_snap_neighbors(prop: Dictionary,at: Vector2) -> Array:
	var neighbors: Array=[]
	var cache_key: String="%s/%s/%d/%s/%s"%[map_switcher.current_file,str(authoring.doc.name),authoring.edit_revision,str(prop.id),str(Vector2i((at/100.0).floor()))]
	if cache_key==_snap_neighbors_key:return _snap_neighbors
	for other in authoring.doc.props:
		if str(other.id)==str(prop.id) or other.get("hidden",false) or str(other.type) not in ["house","building","warehouse","garage","gas_station"]:continue
		if Vector2(other.x,other.y).distance_to(at)>150:continue
		neighbors.append({"id":str(other.id),"p":Vector2(other.x,other.y),"size":gizmos._prop_size(other)/PPM,"angle":deg_to_rad(float(other.rotation))})
	for other in world.data.props:
		if other.has("authoring_id") or str(other.kind) not in ["house","building","warehouse","garage","shop","coastal_house","lodge","office","hotel","cafe","showroom","fuel"]:continue
		if preload("res://scripts/world/coast_scenery.gd").editor_hidden.has(preload("res://scripts/world/coast_scenery.gd").editor_key(other)):continue
		var p:=Vector2(other.p[0],other.p[1])
		if p.distance_to(at)<150:neighbors.append({"p":p,"size":Vector2(other.size[0],other.size[1]),"angle":float(other.angle)})
	_snap_neighbors_key=cache_key;_snap_neighbors=neighbors
	return neighbors

func _snap_building_transform(prop: Dictionary,at: Vector2) -> Dictionary:
	var base_angle: float=float(prop.get("rotation",0.0))
	var grid_position: Vector2=_snap_point(at)
	var fallback: Dictionary={"position":grid_position,"rotation":base_angle,"valid":true}
	if not RoadBuildingSnap.supports(prop):return fallback
	# Alt is an exact, unsnapped move even if grid mode is enabled.
	if Input.is_physical_key_pressed(KEY_ALT):
		return {"position":at,"rotation":base_angle,"valid":true}
	var size: Vector2=gizmos._prop_size(prop)/PPM
	var hit: Dictionary={}
	if RoadBuildingSnap.enabled(prop):
		_ensure_road_building_index()
		hit=road_building_snap.snap(prop,at,size)
	var road_position: Vector2=Vector2(hit.get("position",at))
	var road_angle: float=float(hit.get("angle",deg_to_rad(base_angle)))
	var neighbors: Array=_building_snap_neighbors(prop,at) if building_snap_enabled else []
	var angles: Array[float]=[road_angle]
	if building_snap_enabled:
		for other in neighbors:
			var reach: float=(size.length()+Vector2(other.size).length())*.5+BuildingSnap.EDGE_SNAP_RADIUS_M
			if Vector2(other.p).distance_to(at)>reach:continue
			var turn: float=wrapf(road_angle-float(other.angle),-PI*.25,PI*.25)
			if absf(turn)<.0001 or absf(turn)>deg_to_rad(8):continue
			var neighbor_angle: float=road_angle-turn
			var seen:=false
			for known in angles:
				if absf(neighbor_angle-known)<.002:seen=true;break
			if not seen:angles.append(neighbor_angle)
			if angles.size()>=6:break
	# Exact edge/corner coordinates beat the global metre grid. Score the
	# pointer and road-aligned anchor, favouring a consistent curb setback
	# when Face Nearby Road is enabled.
	var winner: Dictionary={}
	var best:=INF
	for candidate_angle in angles:
		var aligned_road: Vector2=road_position
		if not hit.is_empty() and not is_equal_approx(candidate_angle,road_angle):
			aligned_road=road_building_snap.pose(hit,size,candidate_angle)
		for anchor in [at,aligned_road]:
			var snap: Dictionary=BuildingSnap.match(anchor,size,candidate_angle,neighbors)
			if snap.is_empty():continue
			var trial: Vector2=snap.position
			if not authoring._in_bounds(trial):continue
			if not hit.is_empty() and not road_building_snap.clear_of_roads(trial,size,candidate_angle):continue
			var road_penalty: float=0.0
			if not hit.is_empty():
				road_penalty=2.0*absf((trial-aligned_road).dot(Vector2(hit.outward)))
			var score: float=trial.distance_to(at)+road_penalty+absf(candidate_angle-road_angle)*.5
			if score<best:
				best=score
				winner={"position":trial,"rotation":rad_to_deg(candidate_angle),"valid":true}
	if not winner.is_empty():return winner
	if not hit.is_empty() and authoring._in_bounds(road_position):
		return {"position":road_position,"rotation":rad_to_deg(road_angle),"valid":true}
	return fallback

func _consume_input() -> void:
	var viewport:=get_viewport()
	if is_instance_valid(viewport):viewport.set_input_as_handled()
