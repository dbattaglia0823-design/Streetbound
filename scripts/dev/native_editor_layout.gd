extends RefCounted
## The browser builder's workspace, using native controls and the live world.
const MiniMap=preload("res://scripts/dev/native_editor_minimap.gd")
const TransformArrows=preload("res://scripts/dev/native_transform_arrows.gd")
const INK=Color("#eaf0f7")
const MUTED=Color("#94a7bd")

static func heading(parent: Node, text: String) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_color_override("font_color",MUTED)
	label.add_theme_font_size_override("font_size",11);parent.add_child(label);return label

static func field(parent: Node, title: String, control: Control) -> void:
	heading(parent,title);control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(control)

static func column(panel: Node) -> VBoxContainer:
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",7)
	panel.add_child(box);return box

static func scroll_column(panel: Node) -> VBoxContainer:
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box:=column(scroll);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return box

static func build(e) -> void:
	var theme:=Theme.new();theme.default_font_size=13
	theme.set_color("font_color","Label",INK)
	for kind in ["LineEdit","OptionButton","SpinBox"]:
		var skin:=StyleBoxFlat.new();skin.bg_color=Color("#0d1622")
		skin.border_color=Color("#334257");skin.set_border_width_all(1)
		skin.set_corner_radius_all(5);skin.set_content_margin_all(6)
		theme.set_stylebox("normal",kind,skin)
	e.root_ui.theme=theme
	var header=e._panel(Vector2.ZERO,Vector2.ZERO);header.name="BuilderHeader"
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left=10;header.offset_right=-10;header.offset_top=8;header.offset_bottom=66
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);header.add_child(row)
	var brand:=VBoxContainer.new();brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(brand)
	var title:=heading(brand,"STREETBOUND  /  WORLD DESIGN");title.add_theme_color_override("font_color",e.ACCENT)
	e.map_switcher.build(e,brand)
	e._btn("Discard draft",row,e._discard_draft)
	e.reload_button=e._btn("Reload world",row,e._reload_world);e.reload_button.disabled=true
	e.apply_button=e._btn("Save to Game  Ctrl+S",row,e._apply_draft)
	e._btn("Test Drive  F6",row,e._test_drive)
	var toolbar=e._panel(Vector2.ZERO,Vector2.ZERO);toolbar.name="BuilderTools"
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_left=10;toolbar.offset_right=-10;toolbar.offset_top=74;toolbar.offset_bottom=131
	var tools:=HBoxContainer.new();tools.add_theme_constant_override("separation",7);toolbar.add_child(tools)
	for item in [["Select / Edit  V","move_prop"],["Box select  B","select_box"],["Draw road  R","draw_road"],
		["Terrain region  T","draw_terrain"],["Scenery  P","place:house"],
		["Game marker  M","place_marker"],["Pan view  H","pan"]]:
		var button: Button=e._btn(item[0],tools,e._choose_tool.bind(item[1]))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;e.mode_buttons[item[1]]=button
	e.mode_buttons["anchor"]=e._btn("Road points",tools,e._choose_tool.bind("anchor"))
	e.settings_panel=e._panel(Vector2.ZERO,Vector2.ZERO);e.settings_panel.name="ToolSettings"
	var left_tabs:=TabContainer.new();left_tabs.name="ToolAndWorldTabs";e.settings_tabs=left_tabs
	e.settings_panel.add_child(left_tabs)
	var tool_scroll:=ScrollContainer.new();tool_scroll.name="Tool"
	tool_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	left_tabs.add_child(tool_scroll)
	var settings:=column(tool_scroll);settings.size_flags_horizontal=Control.SIZE_EXPAND_FILL;tool_scroll.follow_focus=true
	var world_scroll:=ScrollContainer.new();world_scroll.name="World"
	world_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	left_tabs.add_child(world_scroll)
	var world_settings:=column(world_scroll);world_settings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading(settings,"TOOL SETTINGS")
	e.mode_label=Label.new();e.mode_label.text="SELECT / EDIT";settings.add_child(e.mode_label)
	e.grid_button=e._btn("Snap to grid: 1 m",settings,e._toggle_snap)
	e.grid_button.tooltip_text="Align free placement to the selected grid spacing. Building edge and corner snaps take precedence."
	var spacing: SpinBox=e._number(settings,"Grid spacing m",.25,100,1)
	spacing.step=.25;spacing.value=1
	spacing.value_changed.connect(e._set_grid_spacing)
	var angle: SpinBox=e._number(settings,"Angle snap ° (0 = off)",0,90,0)
	angle.step=5;angle.value=0;angle.value_changed.connect(e._set_angle_spacing)
	e.building_snap_button=e._btn("Building edges: on",settings,e._toggle_building_snap)
	e.building_snap_button.tooltip_text="Snap building walls and corners exactly together, ignoring the grid. Buildings may overlap intentionally. Hold Alt to bypass all snaps."
	var extra:=OptionButton.new();extra.name="AdditionalTools";extra.fit_to_longest_item=false
	for item in [["More tools…",""],["Draw race route","draw_race"],["Draw sidewalk","draw_sidewalk"],["Draw guardrail","draw_guardrail"],["Circular road","place_circle_road"],["Dealership areas & stock","dealership_manager"]]:
		extra.add_item(item[0]);extra.set_item_metadata(extra.item_count-1,item[1])
	extra.item_selected.connect(func(index: int)->void:
		var tool:=str(extra.get_item_metadata(index))
		extra.select(0)
		if tool=="dealership_manager":e._open_dealership_editor()
		elif tool=="draw_race":e.race_editor.begin_route(e)
		elif not tool.is_empty():e._choose_tool(tool))
	settings.add_child(extra)
	e.map_switcher.build_publish_ui(e,world_settings)
	e._btn("Environmental finishing",world_settings,func():e.workspace_tools.open_environment_finishing())
	e._btn("Dealership areas & stock",world_settings,e._open_dealership_editor)
	e._btn("Gameplay authoring",world_settings,func():e.gameplay_authoring.open(e))
	e._btn("World Validation Center",world_settings,func():e.gameplay_authoring.open_validation(e))
	e.sidewalk_settings=column(settings);heading(e.sidewalk_settings,"SIDEWALK")
	e.sidewalk_width=e._number(e.sidewalk_settings,"Walk width m",.8,12,3);e.sidewalk_width.step=.1;e.sidewalk_width.value=3
	e.guardrail_settings=column(settings);heading(e.guardrail_settings,"GUARDRAIL")
	e.guardrail_width=e._number(e.guardrail_settings,"Rail width m",.35,2.5,.65)
	e.guardrail_width.step=.05;e.guardrail_width.value=.65
	e.tool_options=VBoxContainer.new();settings.add_child(e.tool_options)
	e.race_settings=column(e.tool_options);e.race_editor.build(e,e.race_settings)
	e.dealership_settings=column(e.tool_options);heading(e.dealership_settings,"DEALERSHIP PLACEMENT")
	e._btn("Dealership areas & stock",e.dealership_settings,e._open_dealership_editor)
	e.road_settings=column(e.tool_options);heading(e.road_settings,"ROAD DESIGNER")
	heading(e.road_settings,"Road type")
	e.road_class=e._options(e.road_settings,"Road type",["city","highway","country","mountain","service","track","alley","onramp"])
	e.road_class.set_item_text(5,"Race track")
	e.road_class.set_item_text(6,"Alleyway")
	heading(e.road_settings,"Road surface")
	e.road_surface=e._options(e.road_settings,"Surface",["asphalt","concrete","gravel","dirt","track"])
	e.road_width=e._number(e.road_settings,"Width (m)",6,160,10)
	e.road_lanes=e._number(e.road_settings,"Lanes",1,6,2)
	e.road_class.item_selected.connect(e._change_road_type)
	e.road_surface.item_selected.connect(e._change_road_surface)
	for spin in [e.road_width,e.road_lanes]:spin.value_changed.connect(func(_value: float)->void:e._change_road_settings())
	e.road_elevation_controls=column(e.road_settings)
	heading(e.road_elevation_controls,"Road elevation (6 m per layer)")
	e.road_start_layer=e._number(e.road_elevation_controls,"Start layer",-2,2,0)
	e.road_end_layer=e._number(e.road_elevation_controls,"End layer",-2,2,0)
	e._btn("Apply road elevation",e.road_elevation_controls,e._change_road_elevation)
	var point_toggle := CheckButton.new()
	point_toggle.text="Individual point elevations"
	e.road_elevation_controls.add_child(point_toggle)
	var point_panel := column(e.road_elevation_controls)
	point_panel.visible=false
	point_toggle.toggled.connect(func(on: bool)->void:point_panel.visible=on)
	heading(point_panel,"Layers -2 to +2; 50 m per layer change")
	e.road_point_elevation_fields=column(point_panel)
	e._btn("Apply point elevations",point_panel,e._apply_point_elevations)
	e.road_jump_enabled=CheckBox.new()
	e.road_jump_enabled.text="Stunt jump"
	e.road_elevation_controls.add_child(e.road_jump_enabled)
	e.road_jump_options=column(e.road_elevation_controls)
	e.road_jump_reverse=CheckBox.new()
	e.road_jump_reverse.text="Launch toward road start"
	e.road_jump_options.add_child(e.road_jump_reverse)
	var fields: Dictionary = preload("res://scripts/world/road_jump.gd").FIELDS
	for key in fields:
		var spec: Array = fields[key]
		var input: SpinBox = e._number(e.road_jump_options,str(spec[3]),spec[0],spec[1],spec[2])
		input.step = .05
		input.value = float(spec[2])
		e.road_jump_fields[key] = input
	e.road_jump_enabled.toggled.connect(func(on: bool)->void:e.road_jump_options.visible=on)
	e._btn("Apply jump",e.road_elevation_controls,e._change_road_jump)
	e.road_shapes.build(e,e.road_settings)
	e.terrain_settings=column(e.tool_options);heading(e.terrain_settings,"TERRAIN MATERIAL")
	e.terrain_biome=e._options(e.terrain_settings,"Biome",["grass","forest","rock","mountain","beach","lake","ocean","farmland","city","desert","dirt","asphalt"])
	e.terrain_biome.item_selected.connect(func(_index: int)->void:e._change_terrain_settings())
	e._btn("Draw mountain barrier",e.terrain_settings,e._mountain_tool)
	e.terrain_barrier=CheckBox.new();e.terrain_barrier.text="Block vehicles";e.terrain_barrier.focus_mode=Control.FOCUS_ALL
	e.terrain_barrier.toggled.connect(e._terrain_barrier_toggled);e.terrain_settings.add_child(e.terrain_barrier)
	e.terrain_elevation=e._number(e.terrain_settings,"Height m",0,2000,80)
	e.terrain_elevation.editable=false
	e.terrain_elevation.value_changed.connect(func(_value: float)->void:e._change_terrain_settings())
	var mountain_help:=Label.new();e.mountain_help=mountain_help
	mountain_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	mountain_help.add_theme_font_size_override("font_size",11)
	mountain_help.text="Solid barriers block vehicles. Draw their outline along a map edge."
	e.terrain_settings.add_child(mountain_help)
	e.marker_settings=column(e.tool_options);heading(e.marker_settings,"GAME MARKER")
	e.marker_kind=e._options(e.marker_settings,"Marker type",preload("res://scripts/world/authored_marker_rules.gd").TYPES)
	e.marker_editor.build(e,e.marker_settings)
	e.asset_dock=PanelContainer.new();e.asset_dock.name="NativeAssetBrowser"
	e.asset_dock.add_theme_stylebox_override("panel",StyleBoxEmpty.new());settings.add_child(e.asset_dock)
	var assets:=column(e.asset_dock);heading(assets,"SCENERY LIBRARY")
	e.asset_search=LineEdit.new();e.asset_search.name="AssetSearch";e.asset_search.placeholder_text="Search game assets..."
	e.asset_search.text_changed.connect(func(_value: String)->void:e._filter_assets());assets.add_child(e.asset_search)
	e.asset_category=OptionButton.new()
	for title_text in ["All assets","Houses","Buildings","Garages","Nature","Industrial","Roadside","Ground decals","Sprite sheets","Favorites"]:e.asset_category.add_item(title_text)
	e.asset_category.item_selected.connect(func(_index: int)->void:e._filter_assets());assets.add_child(e.asset_category)
	e.asset_count=heading(assets,"")
	e.asset_grid=GridContainer.new();e.asset_grid.columns=2
	e.asset_grid.add_theme_constant_override("h_separation",6);e.asset_grid.add_theme_constant_override("v_separation",6)
	assets.add_child(e.asset_grid);e._btn("Refresh assets",assets,e._scan_asset_library)
	e._btn("Toggle selected favorite",assets,e._toggle_asset_favorite)
	settings.add_child(HSeparator.new())
	e.tool_help=heading(settings,"Select a tool or map object.")
	e.tool_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	e.canvas_bar=e._panel(Vector2.ZERO,Vector2.ZERO);e.canvas_bar.name="CanvasActions"
	var bar:=HBoxContainer.new();bar.add_theme_constant_override("separation",5);e.canvas_bar.add_child(bar)
	# Keep map zoom/fit actions visible even in a narrow window. Only the
	# longer edit-action row scrolls, rather than drawing underneath inspector.
	var action_scroll:=ScrollContainer.new()
	action_scroll.name="CanvasEditActionsScroll"
	action_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	action_scroll.custom_minimum_size=Vector2(0,44)
	action_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	action_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.follow_focus=true
	bar.add_child(action_scroll)
	var actions:=HBoxContainer.new()
	actions.add_theme_constant_override("separation",5)
	action_scroll.add_child(actions)
	e._btn("Undo",actions,e._undo).custom_minimum_size.x=48
	e._btn("Redo",actions,e._redo).custom_minimum_size.x=48
	e._btn("History",actions,e._open_history)
	e._btn("Bulk edit",actions,e._open_bulk_edit)
	e._btn("Select all",actions,e._select_all).tooltip_text="Select all visible authored objects (Ctrl+A)"
	e._btn("Duplicate",actions,e._duplicate_selected).tooltip_text="Duplicate the selection (Ctrl+D)"
	e._btn("Copy",actions,e._copy_selected_group).tooltip_text="Copy selected roads, regions and scenery (Ctrl+C)"
	e._btn("Paste",actions,e._paste_selected_group).tooltip_text="Paste group at camera centre (Ctrl+V)"
	e._btn("Prefabs",actions,e._open_prefabs)
	e._btn("Build city",actions,e._open_construction)
	e._btn("Landscape",actions,e._open_landscape)
	e._btn("Tools  Ctrl+K",actions,e._open_workspace_commands)
	e.finish_button=e._btn("Finish  Enter",actions,e._finish_shape);e.finish_button.custom_minimum_size.x=80
	e.cancel_button=e._btn("Cancel",actions,e._cancel_gesture);e.cancel_button.custom_minimum_size.x=53
	var zoom_controls:=HBoxContainer.new()
	zoom_controls.add_theme_constant_override("separation",4)
	bar.add_child(zoom_controls)
	e._btn("−",zoom_controls,e._zoom_button.bind(1.0/1.35)).custom_minimum_size.x=30
	e.zoom_label=heading(zoom_controls,"35%")
	e._btn("+",zoom_controls,e._zoom_button.bind(1.35)).custom_minimum_size.x=30
	e._btn("Fit",zoom_controls,e._fit_map).custom_minimum_size.x=36
	e._btn("Spawn",zoom_controls,e._recenter).custom_minimum_size.x=52
	e.inspector_panel=e._panel(Vector2.ZERO,Vector2.ZERO);e.inspector_panel.name="SelectedObjectInspector"
	e.inspector_tabs=TabContainer.new();e.inspector_tabs.name="InspectorTabs"
	e.inspector_panel.add_child(e.inspector_tabs)
	var inspector_scroll:=ScrollContainer.new();inspector_scroll.name="Inspector"
	inspector_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	e.inspector_tabs.add_child(inspector_scroll)
	var inspector:=column(inspector_scroll);inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inspector_scroll.follow_focus=true
	var layer_scroll:=ScrollContainer.new();layer_scroll.name="Layers"
	layer_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	e.inspector_tabs.add_child(layer_scroll)
	var layer_column:=column(layer_scroll);layer_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var object_scroll:=ScrollContainer.new();object_scroll.name="Objects"
	object_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	e.inspector_tabs.add_child(object_scroll)
	var objects:=column(object_scroll);objects.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading(layer_column,"WORLD LAYERS")
	e._btn("Named layers",layer_column,func():e.workspace_tools.open_layers())
	var layers:=GridContainer.new();layers.columns=2;layer_column.add_child(layers)
	for item in [["Terrain","terrain"],["Roads","roads"],["Scenery","scenery"],["Markers","markers"],["Grid","grid"]]:
		var check:=CheckBox.new();check.text=item[0];check.button_pressed=item[1]!="grid"
		check.focus_mode=Control.FOCUS_ALL;check.toggled.connect(e._set_layer.bind(item[1]));layers.add_child(check)
	heading(layer_column,"ROAD SELECTION FILTER")
	var road_picker:=OptionButton.new()
	for layer_caption in ["All objects","Roads -2 (-12 m)","Roads -1 (-6 m)","Roads 0 (ground)","Roads +1 (6 m)","Roads +2 (12 m)"]:road_picker.add_item(layer_caption)
	road_picker.tooltip_text="Restrict selection and marquee to roads on a chosen level; other art stays visible."
	layer_column.add_child(road_picker);road_picker.item_selected.connect(e._set_road_selection_layer)
	var isolate:=CheckBox.new();isolate.text="Hide other road levels";layer_column.add_child(isolate);isolate.toggled.connect(e._set_road_isolation)
	var lock:=CheckBox.new();lock.text="Lock other road objects";layer_column.add_child(lock);lock.toggled.connect(e._set_other_road_lock)
	e.road_layer_settings=column(layer_column);heading(e.road_layer_settings,"ROAD DEBUG OVERLAYS")
	e.lane_button=e._btn("Lanes: on",e.road_layer_settings,e._toggle_lanes);e.lane_button.custom_minimum_size=Vector2(96,28)
	e.junction_button=e._btn("Junctions: on",e.road_layer_settings,e._toggle_junctions);e.junction_button.custom_minimum_size=Vector2(96,28)
	heading(inspector,"INSPECTOR")
	e._btn("Replace assets",inspector,func():e.workspace_tools.open_replace())
	var align_tools:=OptionButton.new()
	for arrange_caption in ["Arrange selected scenery…","Align X centres","Align Y centres","Equal X spacing","Equal Y spacing"]:align_tools.add_item(arrange_caption)
	inspector.add_child(align_tools)
	align_tools.item_selected.connect(func(index: int)->void:
		if index>0:e._arrange_selection("align" if index<=2 else "distribute",0 if index in [1,3] else 1)
		align_tools.select(0))
	e.selected_preview=TextureRect.new();e.selected_preview.name="SelectedAssetPreview"
	e.selected_preview.custom_minimum_size=Vector2(210,60);e.selected_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	e.selected_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;inspector.add_child(e.selected_preview);e.selected_preview.hide()
	e.details=Label.new();e.details.name="SelectedWorldObject";e.details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	e.details.add_theme_font_size_override("font_size",12);inspector.add_child(e.details)
	e.selection_fields=column(inspector)
	e.inspector_name=LineEdit.new();field(e.selection_fields,"Name",e.inspector_name)
	e.inspector_name.text_submitted.connect(func(_value: String)->void:e._commit_inspector())
	e.inspector_name.focus_exited.connect(e._commit_inspector)
	e.inspector_road_type_fields=column(e.selection_fields)
	heading(e.inspector_road_type_fields,"ROAD TYPE")
	e.inspector_road_type=e._options(e.inspector_road_type_fields,"Change placed road type",["city","highway","country","mountain","service","track","alley","onramp"])
	e.inspector_road_type.set_item_text(6,"Alleyway")
	e.inspector_road_type.set_item_text(5,"Race track")
	e.inspector_road_type.item_selected.connect(e._change_inspector_road_type)
	e.inspector_junction_start=e._options(e.inspector_road_type_fields,"Start connection",["auto","intersection","merge"])
	e.inspector_junction_end=e._options(e.inspector_road_type_fields,"End connection",["auto","intersection","merge"])
	for picker in [e.inspector_junction_start,e.inspector_junction_end]:
		picker.set_item_text(0,"Automatic")
		picker.set_item_text(1,"Intersection")
		picker.set_item_text(2,"On-ramp")
		picker.tooltip_text="Swap connection type at this end without changing road geometry. Use the branch road of a three-arm junction."
	e._btn("Auto guardrails...",e.inspector_road_type_fields,e._open_auto_guardrails)
	e.inspector_junction_start.item_selected.connect(e._change_junction_mode.bind(false))
	e.inspector_junction_end.item_selected.connect(e._change_junction_mode.bind(true))
	var xy:=HBoxContainer.new();e.selection_fields.add_child(xy)
	e.inspector_x=e._number(xy,"X m",0,100000,0);e.inspector_x.custom_minimum_size.x=100
	e.inspector_y=e._number(xy,"Y m",0,100000,0);e.inspector_y.custom_minimum_size.x=100
	for spin in [e.inspector_x,e.inspector_y]:TransformArrows.attach(spin)
	e.inspector_x.value_changed.connect(func(_value: float)->void:e._commit_inspector("x"))
	e.inspector_y.value_changed.connect(func(_value: float)->void:e._commit_inspector("y"))
	e.prop_transforms=VBoxContainer.new();inspector.add_child(e.prop_transforms)
	e.inspector_road_facing=CheckBox.new();e.inspector_road_facing.text="Face nearby road";e.prop_transforms.add_child(e.inspector_road_facing)
	e.inspector_road_facing.tooltip_text="This asset only. Align its front and curb clearance while placing or moving beside a road. Building-edge snapping still works. Alt temporarily bypasses both."
	e.inspector_road_facing.toggled.connect(func(_enabled: bool)->void:e._commit_inspector("roadFacing"))
	e.inspector_road_front=OptionButton.new();e.inspector_road_front.tooltip_text="Which side of the unrotated artwork is the building's front?"
	for front in [["Artwork front: bottom",90],["Artwork front: right",0],["Artwork front: top",270],["Artwork front: left",180]]:
		e.inspector_road_front.add_item(front[0]);e.inspector_road_front.set_item_metadata(e.inspector_road_front.item_count-1,front[1])
	e.prop_transforms.add_child(e.inspector_road_front)
	e.inspector_road_front.item_selected.connect(func(_index: int)->void:e._commit_inspector("roadFront"))
	e.inspector_rotation=e._number(e.prop_transforms,"Rotation °",-3600,3600,0)
	e.inspector_scale=e._number(e.prop_transforms,"Scale",0.2,5,1);e.inspector_scale.step=.05
	e.inspector_scale_x=e._number(e.prop_transforms,"X size multiplier",0.2,5,1);e.inspector_scale_x.step=.05
	e.inspector_scale_y=e._number(e.prop_transforms,"Y size multiplier",0.2,5,1);e.inspector_scale_y.step=.05
	for spin in [e.inspector_rotation,e.inspector_scale,e.inspector_scale_x,e.inspector_scale_y]:TransformArrows.attach(spin)
	e.asset_dimensions_label=heading(e.prop_transforms,"")
	e._btn("Reset asset size",e.prop_transforms,e._reset_asset_size)
	for pair in [[e.inspector_rotation,"rotation"],[e.inspector_scale,"scale"],[e.inspector_scale_x,"scaleX"],[e.inspector_scale_y,"scaleY"]]:
		var field_name: String=pair[1]
		pair[0].value_changed.connect(func(_value: float)->void:e._commit_inspector(field_name))
	# Terrain size edits change the underlying polygon, not just a display scale.
	e.terrain_transforms=VBoxContainer.new();inspector.add_child(e.terrain_transforms)
	heading(e.terrain_transforms,"TERRAIN FOOTPRINT")
	e.inspector_terrain_width=e._number(e.terrain_transforms,"Width m",2,24000,10)
	e.inspector_terrain_height=e._number(e.terrain_transforms,"Height m",2,24000,10)
	for spin in [e.inspector_terrain_width,e.inspector_terrain_height]:
		spin.step=0.5
	e.inspector_terrain_width.value_changed.connect(func(_value: float)->void:e._commit_terrain_size("x"))
	e.inspector_terrain_height.value_changed.connect(func(_value: float)->void:e._commit_terrain_size("y"))
	# A single editable percentage drives both actions, with the input centered.
	var terrain_buttons:=HBoxContainer.new();e.terrain_transforms.add_child(terrain_buttons)
	e.terrain_shrink_button=e._btn("Shrink",terrain_buttons,e._resize_region_by_percentage.bind(-1.0))
	e.inspector_terrain_percent=SpinBox.new()
	e.inspector_terrain_percent.min_value=0.1
	e.inspector_terrain_percent.max_value=500.0
	e.inspector_terrain_percent.step=0.1
	e.inspector_terrain_percent.value=10.0
	e.inspector_terrain_percent.suffix="%"
	e.inspector_terrain_percent.tooltip_text="Percentage to resize the terrain; shrinking requires less than 100%"
	e.inspector_terrain_percent.custom_minimum_size.x=88
	e.inspector_terrain_percent.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	terrain_buttons.add_child(e.inspector_terrain_percent)
	e.terrain_expand_button=e._btn("Expand",terrain_buttons,e._resize_region_by_percentage.bind(1.0))
	var terrain_help:=heading(e.terrain_transforms,"Drag the terrain interior to move it. Enter a percentage above, then Shrink or Expand; or edit width and height directly.")
	terrain_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	e.point_picker=OptionButton.new();inspector.add_child(e.point_picker)
	e.point_picker.item_selected.connect(e._select_point)
	e.remove_point_button=e._btn("Remove selected road point",inspector,e._remove_point)
	e.add_point_button=e._btn("Add road point",inspector,e._add_point)
	e.split_road_button=e._btn("Split road here",inspector,e._split_road)
	e.split_road_button.tooltip_text="Choose a road endpoint to detach a junction, or an interior control point to split the road. Drag afterwards to create a gap."
	e.reconnect_road_button=e._btn("Reconnect endpoint",inspector,e._reconnect_road)
	e.reconnect_road_button.tooltip_text="Connect an endpoint to a compatible road end or any point along another road within 12 meters. Drag endpoints onto roads to make junctions; Alt bypasses snapping."
	e.connection_label=heading(inspector,"")
	e.connection_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	e.edit_actions=HFlowContainer.new();inspector.add_child(e.edit_actions)
	e._btn("Duplicate  Ctrl+D",e.edit_actions,e._duplicate_selected)
	e._btn("Delete",e.edit_actions,e._delete_selected)
	heading(objects,"MAP OBJECTS")
	e.entity_search=LineEdit.new();e.entity_search.placeholder_text="Find road, region or object...";objects.add_child(e.entity_search)
	e.entity_search.text_changed.connect(func(_value: String)->void:e._refresh_entity_list(true))
	e.entity_list=ItemList.new();e.entity_list.custom_minimum_size=Vector2(0,150)
	e.entity_list.item_selected.connect(e._select_entity);objects.add_child(e.entity_list)
	var footer=e._panel(Vector2.ZERO,Vector2.ZERO);footer.name="BuilderStatus"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left=10;footer.offset_right=-10;footer.offset_top=-53;footer.offset_bottom=-8
	var foot:=column(footer);foot.add_theme_constant_override("separation",1)
	e.status=heading(foot,"");e.status.clip_text=true
	e.authoring_notice=heading(foot,"Draft edits stay local until Save to Game.");e.authoring_notice.clip_text=true
	e.authoring_notice.add_theme_color_override("font_color",e.ACCENT)
	e.minimap=Control.new();e.minimap.set_script(MiniMap);e.minimap.editor=e
	e.minimap.custom_minimum_size=Vector2(190,130);e.root_ui.add_child(e.minimap)
	e.get_viewport().size_changed.connect(e._layout_workspace)
	resize(e)

static func resize(e) -> void:
	var size: Vector2=e.get_viewport().get_visible_rect().size
	# The inspector's Shrink | percentage | Expand row requires 310+ px
	# including panel margins. It must never be truncated by a 258px sidebar.
	var left:=244.0
	var right:=346.0
	if size.x<1150:
		left=208.0;right=330.0
	var canvas_width: float=maxf(1.0,size.x-left-right-40.0)
	e.settings_panel.position=Vector2(10,139);e.settings_panel.size=Vector2(left,size.y-200)
	e.inspector_panel.position=Vector2(size.x-right-10,139);e.inspector_panel.size=Vector2(right,size.y-200)
	e.canvas_bar.position=Vector2(left+20,139);e.canvas_bar.size=Vector2(canvas_width,58)
	e.canvas_rect=Rect2(Vector2(left+20,205),Vector2(canvas_width,size.y-266))
	e.minimap.position=e.canvas_rect.end-Vector2(200,140);e.minimap.size=Vector2(190,130)
