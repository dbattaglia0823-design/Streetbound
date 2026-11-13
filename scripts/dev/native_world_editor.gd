extends CanvasLayer
## First native Streetbound world editor milestone: directly inspect the real
## rendered Morrow Coast, paved junctions, source props, and traffic network.
## READ ONLY until a source/bake/reload transaction can be verified.
const Geometry = preload("res://scripts/world/map_geometry.gd")
const Gizmos = preload("res://scripts/dev/native_world_editor_gizmos.gd")
const EditSession = preload("res://scripts/dev/native_map_edit_session.gd")
const LocalBridge = preload("res://scripts/dev/native_map_bridge.gd")
const PPM := 20.0
const PANEL_COLOR := Color(0.035,0.065,0.080,0.94)
const ACCENT := Color(0.98,0.67,0.35)
var world
var player: VehicleController2D
var driving_camera: Camera2D
var traffic_network
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
var details: Label
var status: Label
var lane_button: Button
var junction_button: Button
var selected: Dictionary = {}
var _hidden_game_ui: Dictionary = {}
var authoring
var bridge
var source_ready := false
var tool_name := "inspect"
var source_id := ""
var source_anchor := -1
var pending_drag: Dictionary = {}
var drag_position := Vector2.ZERO
var snap_m := 1.0
var authoring_notice: Label
var mode_label: Label
var reload_button: Button
var apply_button: Button
var source_revision := ""
static var resume_after_rebuild := false
static var resume_editor_position := Vector2.ZERO


func _ready() -> void:
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
	var panel := _panel(Vector2(12,542),Vector2(1170,128))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",4)
	panel.add_child(rows)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",5)
	rows.add_child(heading)
	mode_label = Label.new()
	mode_label.name = "NativeEditMode"
	mode_label.text = "EDIT SOURCE"
	mode_label.custom_minimum_size.x = 120
	mode_label.add_theme_color_override("font_color",ACCENT)
	heading.add_child(mode_label)
	_btn("INSPECT",heading,_choose_tool.bind("inspect"))
	_btn("ROAD ANCHOR",heading,_choose_tool.bind("anchor"))
	_btn("MOVE ASSET",heading,_choose_tool.bind("move_prop"))
	_btn("HOUSE",heading,_choose_tool.bind("place:house"))
	_btn("SHOP",heading,_choose_tool.bind("place:shop"))
	_btn("TREE",heading,_choose_tool.bind("place:tree"))
	_btn("ROCK",heading,_choose_tool.bind("place:rock"))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",5)
	rows.add_child(actions)
	_btn("UNDO [Ctrl+Z]",actions,_undo)
	_btn("REDO [Ctrl+Y]",actions,_redo)
	_btn("ROTATE -15",actions,_rotate_selected.bind(-15.0))
	_btn("ROTATE +15",actions,_rotate_selected.bind(15.0))
	_btn("DELETE",actions,_delete_selected)
	_btn("DISCARD",actions,_discard_draft)
	_btn("START BACKEND",actions,_start_backend)
	apply_button = _btn("APPLY TO GAME",actions,_apply_draft)
	reload_button = _btn("RELOAD WORLD",actions,_reload_world)
	reload_button.disabled = true
	authoring_notice = Label.new()
	authoring_notice.name = "NativeEditStatus"
	authoring_notice.clip_text = true
	authoring_notice.add_theme_font_size_override("font_size",11)
	authoring_notice.add_theme_color_override("font_color",Color(0.98,0.80,0.54))
	authoring_notice.text = "Source drafts only. The Python backend validates and safely rebuilds the real game."
	rows.add_child(authoring_notice)

func _notice(message: String) -> void:
	if is_instance_valid(authoring_notice):
		authoring_notice.text = message

func _choose_tool(mode: String) -> void:
	if not source_ready and mode != "inspect":
		_notice("Source unavailable. The map can still be inspected.")
		return
	tool_name = mode
	pending_drag.clear()
	source_id = ""
	source_anchor = -1
	mode_label.text = ("EDIT: "+mode.to_upper()).substr(0,25)
	_notice("Drag a source anchor or asset; click the world to place selected artwork.")
	_refresh_authoring()

func _refresh_authoring() -> void:
	if not is_instance_valid(gizmos):
		return
	if source_ready:
		gizmos.set_draft(authoring.doc,authoring.initial,pending_drag,
			source_id,source_anchor)
		if is_instance_valid(apply_button):
			apply_button.disabled = not authoring.dirty or bridge.phase != ""
	else:
		gizmos.set_draft({},{})

func _undo() -> void:
	if source_ready and authoring.undo():
		pending_drag.clear()
		_refresh_authoring()
		_notice("Undid the previous source edit. Changes remain unbaked.")

func _redo() -> void:
	if source_ready and authoring.redo():
		pending_drag.clear()
		_refresh_authoring()
		_notice("Redid the source edit. Intersections rebuild only after Apply.")

func _discard_draft() -> void:
	if source_ready:
		authoring.discard_changes()
		pending_drag.clear()
		source_id = ""
		source_anchor = -1
		_refresh_authoring()
		_notice("All unsaved edits discarded; original authoring source restored.")

func _rotate_selected(degrees: float) -> void:
	if not source_ready or source_id.is_empty():
		return
	if authoring.rotate_prop(source_id,degrees):
		_refresh_authoring()
		_notice("Asset rotated %.0f°. Apply to regenerate the actual art/collision." % degrees)

func _delete_selected() -> void:
	if not source_ready or source_id.is_empty():
		return
	if authoring.delete_prop(source_id):
		source_id = ""
		_refresh_authoring()
		_notice("Authored prop deleted from draft. Undo is available.")
	else:
		_notice(authoring.last_error)

func _start_backend() -> void:
	if bridge.start_backend():
		_notice("Local Python rebaker launched. APPLY TO GAME uses validated backup/rollback.")
	else:
		_notice(bridge.last_error)

func _apply_draft() -> void:
	if not source_ready or not authoring.dirty:
		_notice("No authoring edits to apply.")
		return
	if not authoring._valid_source(authoring.doc):
		_notice("Source validation failed; changes were not saved.")
		return
	if bridge.apply_source(authoring.doc,authoring.baseline_hash):
		_notice("Verifying map revision and source, then rebuilding Morrow Coast...")
		_refresh_authoring()
	else:
		_notice(bridge.last_error)

func _on_apply_completed(ok: bool, message: String, new_sha: String) -> void:
	if ok:
		authoring.accepted_remote(authoring.doc)
		source_revision = new_sha
		reload_button.disabled = false
		_refresh_authoring()
		_notice(message)
	else:
		_refresh_authoring()
		_notice("APPLY FAILED (no files modified): "+message)

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

func _pick_source_anchor(world_px: Vector2) -> Dictionary:
	if not source_ready:
		return {}
	var best := 20.0 / maxf(0.26,editor_camera.zoom.x)
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
	if not source_ready:
		return {}
	var at: Vector2 = world_px/PPM
	var best := 8.0
	var hit: Dictionary = {}
	for prop in authoring.doc.props:
		var art := str(prop.get("type",""))
		var width := 8.0
		if art in ["house","garage"]:
			width=12.0
		elif art in ["building","warehouse"]:
			width=20.0
		var center := Vector2(float(prop.x),float(prop.y))
		var distance := maxf(0.0,center.distance_to(at)-
			width*float(prop.get("scale",1.0))*0.5)
		if distance < best:
			best = distance
			hit = {"kind":"prop","id":str(prop.id),"from":center*PPM}
	return hit

func _source_click(world_px: Vector2) -> void:
	if tool_name.begins_with("place:"):
		var kind := tool_name.substr(6)
		var id: String = authoring.add_prop(kind,world_px/PPM)
		if id != "":
			source_id = id
			source_anchor = -1
			_refresh_authoring()
			_notice("Placed "+kind+" source preview. Undo or Apply to commit after rebuild.")
		else:
			_notice(authoring.last_error)
		return
	if tool_name not in ["anchor","move_prop"]:
		select_at(world_px)
		return
	var hit: Dictionary = _pick_source_anchor(world_px) if tool_name=="anchor" else \
		_pick_source_prop(world_px)
	if hit.is_empty():
		if tool_name=="move_prop":
			var inspected := select_at(world_px)
			if inspected.get("kind","")=="prop":
				var item: Dictionary = world.data.props[int(inspected.index)]
				_notice("Generated scenery is protected. Place a new authored asset instead."
					if authoring.index_of_runtime_prop(item)=="" else
					"Select the source asset footprint to drag it.")
		else:
			_notice("Click an existing editable source road anchor, not a baked junction.")
		return
	source_id = str(hit.id)
	source_anchor = int(hit.get("index",-1))
	pending_drag = hit.duplicate(true)
	pending_drag["to"] = world_px
	if hit.kind=="road":
		var road := authoring.road_at_id(source_id)
		details.text = "AUTHORING ROAD\n%s\nPoint %d of %d\n\nDrag this anchor. Other joined ends move together.\nJunctions / traffic stay baked until Apply." % [
			str(road.get("name","")),source_anchor+1,road.points.size()]
	else:
		var prop := authoring.prop_at_id(source_id)
		details.text = "AUTHORED ASSET\n%s\n\nDrag to move; Rotate and Delete are below.\nSource ID: %s" % [
			str(prop.get("name","")),source_id]
	_refresh_authoring()

func _finish_source_drag(world_px: Vector2) -> void:
	if pending_drag.is_empty() or not source_ready:
		return
	var drag := pending_drag.duplicate(true)
	pending_drag.clear()
	var ok := false
	var destination_m: Vector2 = world_px/PPM
	if str(drag.kind)=="road":
		ok = authoring.move_road_point(str(drag.id),int(drag.index),
			destination_m,snap_m)
	elif str(drag.kind)=="prop":
		ok = authoring.move_prop(str(drag.id),destination_m,snap_m)
	_refresh_authoring()
	if ok and authoring.dirty:
		_notice("Source updated; amber/green geometry is a DRAFT, not actual rebuilt traffic.")
	elif not ok:
		_notice(authoring.last_error)

func _panel(where: Vector2, dimensions: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = where
	p.custom_minimum_size = dimensions
	p.size = dimensions
	var skin := StyleBoxFlat.new()
	skin.bg_color = PANEL_COLOR
	skin.border_color = Color(0.40,0.52,0.55,0.80)
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(10)
	skin.content_margin_left = 12
	skin.content_margin_right = 12
	skin.content_margin_top = 8
	skin.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel",skin)
	root_ui.add_child(p)
	return p

func _btn(text_value: String, parent: Node, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(110,32)
	b.add_theme_font_size_override("font_size",12)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _build_ui() -> void:
	var header := _panel(Vector2(12,12),Vector2(980,58))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	header.add_child(row)
	var title := Label.new()
	title.text = "STREETBOUND  /  WORLD EDITOR"
	title.add_theme_font_size_override("font_size",18)
	title.add_theme_color_override("font_color",ACCENT)
	title.custom_minimum_size.x = 306
	row.add_child(title)
	lane_button = _btn("LANES: ON",row,_toggle_lanes)
	junction_button = _btn("JUNCTIONS: ON",row,_toggle_junctions)
	_btn("CENTER ON CAR",row,_recenter)
	_btn("TEST DRIVE  [F6]",row,close_editor)
	var sidebar := _panel(Vector2(12,82),Vector2(330,395))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",9)
	sidebar.add_child(col)
	var heading := Label.new()
	heading.text = "ACTUAL GAME GEOMETRY"
	heading.add_theme_color_override("font_color",ACCENT)
	heading.add_theme_font_size_override("font_size",14)
	col.add_child(heading)
	var help := Label.new()
	help.text = "Left click: inspect     Right drag: pan\nMouse wheel: zoom     F6: test drive"
	help.add_theme_font_size_override("font_size",12)
	col.add_child(help)
	var divider := HSeparator.new()
	col.add_child(divider)
	details = Label.new()
	details.name = "SelectedWorldObject"
	details.text = "Click a road, intersection, or building to inspect the real game data."
	details.custom_minimum_size = Vector2(300,235)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size",13)
	col.add_child(details)
	var note := Label.new()
	note.text = "READ-ONLY FOUNDATION\nBrowser editing and safe Python rebake are unchanged."
	note.add_theme_color_override("font_color",Color(0.99,0.71,0.42))
	note.add_theme_font_size_override("font_size",11)
	col.add_child(note)
	var footer := _panel(Vector2(12,489),Vector2(550,44))
	status = Label.new()
	status.text = "Press F6 during free roam to inspect the live map."
	status.add_theme_font_size_override("font_size",12)
	footer.add_child(status)

func _can_enter() -> bool:
	# A split-screen game has two cameras and a different input owner. Keep
	# this development workspace exclusively in single-player free roam.
	var split: Variant = get_parent().get("local_split_screen")
	return not active and not get_tree().paused and \
		is_instance_valid(player) and is_instance_valid(world) and \
		bool(world.initialization_complete) and \
		is_instance_valid(driving_camera) and \
		(not is_instance_valid(split) or not bool(split.get("active")))


func _set_game_ui_visible(restore: bool) -> void:
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
	_owns_pause = not get_tree().paused
	if not source_ready:
		source_ready = authoring.load_source()
		if not source_ready:
			_notice("Source not loaded: "+authoring.last_error)
		else:
			_notice("Native source loaded. Select a tool; draft changes stay in memory.")
	_player_camera_enabled = driving_camera.enabled
	_player_camera_physics = driving_camera.is_physics_processing()
	_player_camera_input = driving_camera.is_processing_unhandled_input()
	editor_camera = Camera2D.new()
	editor_camera.name = "WorldEditorCamera"
	editor_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	editor_camera.position = driving_camera.global_position
	editor_camera.rotation = 0.0
	editor_camera.zoom = driving_camera.zoom
	editor_camera.zoom = editor_camera.zoom.clamp(
		Vector2(0.26,0.26),Vector2(3.0,3.0))
	get_parent().add_child(editor_camera)
	driving_camera.enabled = false
	driving_camera.set_physics_process(false)
	driving_camera.set_process_unhandled_input(false)
	editor_camera.make_current()
	active = true
	_set_game_ui_visible(false)
	root_ui.visible = true
	gizmos.visible = true
	_right_drag = false
	_last_cell = Vector2i(-999,-999)
	get_tree().paused = true
	set_process(true)
	_update_selection({})
	_refresh_authoring()
	_update_view(true)
	return true

func close_editor() -> void:
	if not active:
		return
	active = false
	root_ui.visible = false
	gizmos.visible = false
	pending_drag.clear()
	_set_game_ui_visible(true)
	_right_drag = false
	set_process(false)
	if is_instance_valid(editor_camera):
		editor_camera.enabled = false
		editor_camera.queue_free()
	editor_camera = null
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
	if active and is_instance_valid(player):
		editor_camera.global_position = player.global_position
		_update_view(true)

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
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		editor_camera.global_position += direction.normalized() * dt * \
			950.0 / maxf(0.26,editor_camera.zoom.x)
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
	if cell != _last_cell or force:
		world.stream_at(here)
		_last_cell = cell
	if not world.pending.is_empty():
		world._build_chunk(world.pending.pop_front())
	gizmos.set_view(here,get_viewport().get_visible_rect().size,
		editor_camera.zoom.x)
	var meters := here / PPM
	status.text = "WORLD  X %.0fm  Y %.0fm   |   %d roads   %d intersections   %d traffic links" % [
		meters.x,meters.y,world.data.roads.size(),world.data.junctions.size(),
		traffic_network.edges.size() if is_instance_valid(traffic_network) else 0]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_F6 or key.physical_keycode == KEY_F6:
				if active:
					close_editor()
				else:
					open_editor()
				get_viewport().set_input_as_handled()
				return
			if active and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
				close_editor()
				get_viewport().set_input_as_handled()
				return
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
			editor_camera.zoom = (editor_camera.zoom*factor).clamp(
				Vector2(0.26,0.26),Vector2(3.0,3.0))
			_update_view(true)
			get_viewport().set_input_as_handled()
		elif mouse.pressed and mouse.button_index==MOUSE_BUTTON_LEFT:
			select_at(world.get_global_mouse_position())
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _right_drag:
		var motion := event as InputEventMouseMotion
		editor_camera.global_position -= motion.relative/editor_camera.zoom
		get_viewport().set_input_as_handled()

func _nearest_prop(p: Vector2) -> Dictionary:
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
	gizmos.set_selection(selected)
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
		details.text = "WORLD OBJECT #%d\n\nType: %s\nArtwork: %s\nPosition: %.1f, %.1f metres\nSize: %.1f × %.1f metres\nSolid collision: %s\n\nUses the live game asset,\nnot a browser preview." % [
			index,str(prop.kind),asset,float(prop.p[0]),float(prop.p[1]),
			float(prop.size[0]),float(prop.size[1]),
			"yes" if bool(prop.get("solid",false)) else "no"]
	else:
		details.text = "Select a real road, intersection, or\nbuilding in the world to inspect it.\n\nYou are viewing Godot's actual\nrendering, geometry and traffic.\n\nNothing is saved or altered here."
	if not measured.is_empty():
		details.text += "\n\nSurface: %s  Grip: %.2f" % [
			str(measured.get("surface","")),float(measured.get("grip",0.0))]
