extends RefCounted
## The browser builder's workspace, using native controls and the live world.
const MiniMap=preload("res://scripts/dev/native_editor_minimap.gd")
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
	for item in [["Select / Edit  V","move_prop"],["Draw road  R","draw_road"],
		["Terrain region  T","draw_terrain"],["Scenery  P","place:house"],
		["Game marker  M","place_marker"],["Pan view  H","pan"]]:
		var button: Button=e._btn(item[0],tools,e._choose_tool.bind(item[1]))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;e.mode_buttons[item[1]]=button
	e.mode_buttons["anchor"]=e._btn("Road points",tools,e._choose_tool.bind("anchor"))
	e.settings_panel=e._panel(Vector2.ZERO,Vector2.ZERO);e.settings_panel.name="ToolSettings"
	var settings:=scroll_column(e.settings_panel)
	heading(settings,"TOOL SETTINGS")
	e.mode_label=Label.new();e.mode_label.text="SELECT / EDIT";settings.add_child(e.mode_label)
	e.grid_button=e._btn("Snap to grid: 1 m",settings,e._toggle_snap)
	e.building_snap_button=e._btn("Building edges: on",settings,e._toggle_building_snap)
	e.building_snap_button.tooltip_text="Snap parallel building edges within 2 m. Hold Alt to bypass. Works when placing and dragging buildings."
	e._btn("Draw sidewalk",settings,e._choose_tool.bind("draw_sidewalk"))
	e.sidewalk_width=e._number(settings,"Walk width m",.8,12,3);e.sidewalk_width.step=.1;e.sidewalk_width.value=3
	e.tool_options=VBoxContainer.new();settings.add_child(e.tool_options)
	e.road_settings=column(e.tool_options);heading(e.road_settings,"ROAD DESIGNER")
	e.road_class=e._options(e.road_settings,"Road class",["city","highway","country","mountain","service","track"])
	e.road_surface=e._options(e.road_settings,"Surface",["asphalt","concrete","gravel","dirt","track"])
	e.road_width=e._number(e.road_settings,"Width (m)",6,160,10)
	e.road_lanes=e._number(e.road_settings,"Lanes",1,6,2)
	for option in [e.road_class,e.road_surface]:option.item_selected.connect(func(_index: int)->void:e._change_road_settings())
	for spin in [e.road_width,e.road_lanes]:spin.value_changed.connect(func(_value: float)->void:e._change_road_settings())
	e.terrain_settings=column(e.tool_options);heading(e.terrain_settings,"TERRAIN MATERIAL")
	e.terrain_biome=e._options(e.terrain_settings,"Biome",["grass","forest","rock","mountain","beach","lake","ocean","farmland","city","desert"])
	e.terrain_biome.item_selected.connect(func(_index: int)->void:e._change_terrain_settings())
	e._btn("Draw mountain barrier",e.terrain_settings,e._mountain_tool)
	e.terrain_barrier=CheckBox.new();e.terrain_barrier.text="Block vehicles";e.terrain_barrier.focus_mode=Control.FOCUS_NONE
	e.terrain_barrier.toggled.connect(e._terrain_barrier_toggled);e.terrain_settings.add_child(e.terrain_barrier)
	e.terrain_elevation=e._number(e.terrain_settings,"Height m",0,2000,80)
	e.terrain_elevation.editable=false
	e.terrain_elevation.value_changed.connect(func(_value: float)->void:e._change_terrain_settings())
	var mountain_help:=Label.new()
	mountain_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	mountain_help.add_theme_font_size_override("font_size",11)
	mountain_help.text="Solid barriers block vehicles. Draw their outline along a map edge."
	e.terrain_settings.add_child(mountain_help)
	e.marker_settings=column(e.tool_options);heading(e.marker_settings,"GAME MARKER")
	e.marker_kind=e._options(e.marker_settings,"Marker type",["checkpoint","race_start","finish","traffic_spawn"])
	e.asset_dock=PanelContainer.new();e.asset_dock.name="NativeAssetBrowser"
	e.asset_dock.add_theme_stylebox_override("panel",StyleBoxEmpty.new());settings.add_child(e.asset_dock)
	var assets:=column(e.asset_dock);heading(assets,"SCENERY LIBRARY")
	e.asset_search=LineEdit.new();e.asset_search.name="AssetSearch";e.asset_search.placeholder_text="Search game assets..."
	e.asset_search.text_changed.connect(func(_value: String)->void:e._filter_assets());assets.add_child(e.asset_search)
	e.asset_category=OptionButton.new()
	for title_text in ["All assets","Houses","Buildings","Garages","Nature"]:e.asset_category.add_item(title_text)
	e.asset_category.item_selected.connect(func(_index: int)->void:e._filter_assets());assets.add_child(e.asset_category)
	e.asset_count=heading(assets,"")
	e.asset_grid=GridContainer.new();e.asset_grid.columns=2
	e.asset_grid.add_theme_constant_override("h_separation",6);e.asset_grid.add_theme_constant_override("v_separation",6)
	assets.add_child(e.asset_grid);e._btn("Refresh assets",assets,e._scan_asset_library)
	settings.add_child(HSeparator.new())
	var help:=heading(settings,"Click to select or draw.\nDrag a road to move it.\nDrag its handles to reshape.\nShift-click inserts a road point.\nEnter finishes a shape.\nSpace + drag or right drag pans.\nWheel zooms at the cursor.\nArrow keys nudge the selection.\nWASD pans the map.")
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	e.canvas_bar=e._panel(Vector2.ZERO,Vector2.ZERO);e.canvas_bar.name="CanvasActions"
	var bar:=HBoxContainer.new();bar.add_theme_constant_override("separation",5);e.canvas_bar.add_child(bar)
	e._btn("Undo",bar,e._undo).custom_minimum_size.x=48
	e._btn("Redo",bar,e._redo).custom_minimum_size.x=48
	e.finish_button=e._btn("Finish  Enter",bar,e._finish_shape);e.finish_button.custom_minimum_size.x=80
	e.cancel_button=e._btn("Cancel",bar,e._cancel_gesture);e.cancel_button.custom_minimum_size.x=53
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.add_child(spacer)
	e._btn("−",bar,e._zoom_button.bind(1.0/1.35)).custom_minimum_size.x=30
	e.zoom_label=heading(bar,"35%")
	e._btn("+",bar,e._zoom_button.bind(1.35)).custom_minimum_size.x=30
	e._btn("Fit",bar,e._fit_map).custom_minimum_size.x=36
	e._btn("Spawn",bar,e._recenter).custom_minimum_size.x=52
	e.inspector_panel=e._panel(Vector2.ZERO,Vector2.ZERO);e.inspector_panel.name="SelectedObjectInspector"
	var inspector:=scroll_column(e.inspector_panel)
	heading(inspector,"WORLD LAYERS")
	var layers:=GridContainer.new();layers.columns=2;inspector.add_child(layers)
	for item in [["Terrain","terrain"],["Roads","roads"],["Scenery","scenery"],["Markers","markers"],["Grid","grid"]]:
		var check:=CheckBox.new();check.text=item[0];check.button_pressed=item[1]!="grid"
		check.focus_mode=Control.FOCUS_NONE;check.toggled.connect(e._set_layer.bind(item[1]));layers.add_child(check)
	e.lane_button=e._btn("Lanes: on",layers,e._toggle_lanes);e.lane_button.custom_minimum_size=Vector2(96,28)
	e.junction_button=e._btn("Junctions: on",layers,e._toggle_junctions);e.junction_button.custom_minimum_size=Vector2(96,28)
	inspector.add_child(HSeparator.new());heading(inspector,"INSPECTOR")
	e.selected_preview=TextureRect.new();e.selected_preview.name="SelectedAssetPreview"
	e.selected_preview.custom_minimum_size=Vector2(210,60);e.selected_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	e.selected_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;inspector.add_child(e.selected_preview)
	e.details=Label.new();e.details.name="SelectedWorldObject";e.details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	e.details.add_theme_font_size_override("font_size",12);inspector.add_child(e.details)
	e.inspector_name=LineEdit.new();field(inspector,"Name",e.inspector_name)
	e.inspector_name.text_submitted.connect(func(_value: String)->void:e._commit_inspector())
	e.inspector_name.focus_exited.connect(e._commit_inspector)
	var xy:=HBoxContainer.new();inspector.add_child(xy)
	e.inspector_x=e._number(xy,"X m",0,100000,0);e.inspector_x.custom_minimum_size.x=100
	e.inspector_y=e._number(xy,"Y m",0,100000,0);e.inspector_y.custom_minimum_size.x=100
	for spin in [e.inspector_x,e.inspector_y]:spin.step=.001
	e.inspector_x.value_changed.connect(func(_value: float)->void:e._commit_inspector("x"))
	e.inspector_y.value_changed.connect(func(_value: float)->void:e._commit_inspector("y"))
	e.prop_transforms=VBoxContainer.new();inspector.add_child(e.prop_transforms)
	e.inspector_rotation=e._number(e.prop_transforms,"Rotation °",-3600,3600,0)
	e.inspector_scale=e._number(e.prop_transforms,"Scale",0.2,5,1);e.inspector_scale.step=.05
	e.inspector_scale_x=e._number(e.prop_transforms,"X size multiplier",0.2,5,1);e.inspector_scale_x.step=.05
	e.inspector_scale_y=e._number(e.prop_transforms,"Y size multiplier",0.2,5,1);e.inspector_scale_y.step=.05
	for spin in [e.inspector_rotation,e.inspector_scale,e.inspector_scale_x,e.inspector_scale_y]:spin.step=.001
	e.asset_dimensions_label=heading(e.prop_transforms,"")
	e._btn("Reset asset size",e.prop_transforms,e._reset_asset_size)
	for pair in [[e.inspector_rotation,"rotation"],[e.inspector_scale,"scale"],[e.inspector_scale_x,"scaleX"],[e.inspector_scale_y,"scaleY"]]:
		var field_name: String=pair[1]
		pair[0].value_changed.connect(func(_value: float)->void:e._commit_inspector(field_name))
	e.point_picker=OptionButton.new();inspector.add_child(e.point_picker)
	e.point_picker.item_selected.connect(e._select_point)
	e.remove_point_button=e._btn("Remove selected road point",inspector,e._remove_point)
	e.add_point_button=e._btn("Add road point",inspector,e._add_point)
	e.split_road_button=e._btn("Split road here",inspector,e._split_road)
	e.split_road_button.tooltip_text="Choose a road endpoint to detach a junction, or an interior control point to split the road. Drag afterwards to create a gap."
	e.reconnect_road_button=e._btn("Reconnect endpoint",inspector,e._reconnect_road)
	e.reconnect_road_button.tooltip_text="Select an endpoint, then snap it to the nearest compatible road end within 12 meters."
	e.connection_label=heading(inspector,"")
	e.connection_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	e.edit_actions=HFlowContainer.new();inspector.add_child(e.edit_actions)
	e._btn("Duplicate  Ctrl+D",e.edit_actions,e._duplicate_selected)
	e._btn("Delete",e.edit_actions,e._delete_selected)
	heading(inspector,"OBJECTS")
	e.entity_search=LineEdit.new();e.entity_search.placeholder_text="Find road, region or object...";inspector.add_child(e.entity_search)
	e.entity_search.text_changed.connect(func(_value: String)->void:e._refresh_entity_list(true))
	e.entity_list=ItemList.new();e.entity_list.custom_minimum_size=Vector2(0,150)
	e.entity_list.item_selected.connect(e._select_entity);inspector.add_child(e.entity_list)
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
	var left:=244.0;var right:=258.0
	if size.x<1150:left=220;right=232
	e.settings_panel.position=Vector2(10,139);e.settings_panel.size=Vector2(left,size.y-200)
	e.inspector_panel.position=Vector2(size.x-right-10,139);e.inspector_panel.size=Vector2(right,size.y-200)
	e.canvas_bar.position=Vector2(left+20,139);e.canvas_bar.size=Vector2(size.x-left-right-40,48)
	e.canvas_rect=Rect2(Vector2(left+20,195),Vector2(size.x-left-right-40,size.y-256))
	e.minimap.position=e.canvas_rect.end-Vector2(200,140);e.minimap.size=Vector2(190,130)
