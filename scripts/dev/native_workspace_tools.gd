extends RefCounted
## Native editor productivity dialogs. Local preferences never enter a bake.
const Data=preload("res://scripts/dev/native_editor_workspace.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const PREFS="user://streetbound-editor-workspace.json"
var e
var prefs: Dictionary={}
var loaded:=false
var dialog: AcceptDialog
var list: ItemList
var name_field: LineEdit
var query: LineEdit
var category: OptionButton
var kind_field: LineEdit
var filter_elevation: OptionButton
var region_only: CheckBox
var width: SpinBox
var height: SpinBox
var captured_ids: Array[String]=[]
var commands: Array=[]
var reference_file: FileDialog
var reference: Sprite2D
var reference_width: SpinBox
var reference_x: SpinBox
var reference_y: SpinBox
var reference_alpha: SpinBox
var reference_rotation: SpinBox
var reference_key:=""
var measure_points: Array[Vector2]=[]

func setup(editor) -> void:
	e=editor
	_load()

func _load() -> void:
	if loaded:return
	loaded=true
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PREFS)) if FileAccess.file_exists(PREFS) else {}
	if parsed is Dictionary:prefs=parsed
	for key in ["favorites","maps"]:
		if not prefs.get(key) is Dictionary:prefs[key]={}

func _save() -> bool:
	var out:=FileAccess.open(PREFS+".tmp",FileAccess.WRITE)
	if out==null:return false
	out.store_string(JSON.stringify(prefs));out.flush();out.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(PREFS+".tmp"),ProjectSettings.globalize_path(PREFS))==OK

func _map_key() -> String:
	return str(e.map_switcher.current_file) if e.map_switcher.custom else "morrow-coast"

func _map_prefs() -> Dictionary:
	var key:=_map_key()
	if not prefs.maps.has(key):prefs.maps[key]={"bookmarks":[],"snapshots":[]}
	return prefs.maps[key]

func _ready_to_edit() -> bool:
	return e.source_ready and not e._editing_locked() and e.pending_drag.is_empty() and e.draft_points.is_empty()

func _new(title: String,minimum: Vector2i=Vector2i(540,440)) -> VBoxContainer:
	if is_instance_valid(dialog):dialog.hide();dialog.queue_free()
	dialog=AcceptDialog.new()
	dialog.title=title;dialog.ok_button_text="Close";dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	e.root_ui.add_child(dialog)
	var panel:=VBoxContainer.new();panel.custom_minimum_size=Vector2(minimum)
	dialog.add_child(panel)
	return panel

func _show() -> void:dialog.popup_centered()

func _text(panel: VBoxContainer,value: String) -> void:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(label)

func _list(panel: VBoxContainer) -> ItemList:
	var result:=ItemList.new();result.custom_minimum_size=Vector2(480,220)
	result.size_flags_vertical=Control.SIZE_EXPAND_FILL;panel.add_child(result);return result

func _picked() -> int:
	var rows:=list.get_selected_items()
	return -1 if rows.is_empty() else rows[0]

func _ids() -> Array[String]:
	var ids: Array[String]=e.multi_selection.duplicate()
	if ids.is_empty() and not str(e.source_id).is_empty():ids.append(str(e.source_id))
	return ids

func open_layers() -> void:
	if not _ready_to_edit():return
	if not e.map_switcher.custom:e._notice("Named layers are available on custom maps.");return
	captured_ids=_ids()
	var panel:=_new("Named layers")
	_text(panel,"Hide or lock an entire group of authored objects. Select objects before opening to assign them.")
	name_field=LineEdit.new();name_field.placeholder_text="New layer name";panel.add_child(name_field)
	e._btn("Create layer",panel,_create_layer)
	list=_list(panel);_fill_layers()
	e._btn("Assign captured selection",panel,_assign_layer)
	e._btn("Select layer objects",panel,_select_layer)
	e._btn("Toggle visibility",panel,_toggle_layer.bind("visible"))
	e._btn("Toggle lock",panel,_toggle_layer.bind("locked"))
	e._btn("Remove layer (keep objects)",panel,_remove_layer)
	_show()

func _fill_layers() -> void:
	list.clear()
	for layer in e.authoring.doc.get("editorLayers",[]):
		list.add_item("%s · %d objects · %s / %s"%[layer.name,layer.ids.size(),"visible" if layer.visible else "hidden","locked" if layer.locked else "editable"])

func _commit_layers(layers: Array,index: int=-1) -> void:
	if not _ready_to_edit():return
	if e.authoring.set_named_layers(layers):
		e._refresh_authoring();_fill_layers()
		if index>=0 and index<list.item_count:list.select(index)
	else:e._notice(e.authoring.last_error)

func _create_layer() -> void:
	var label:=name_field.text.strip_edges().left(60)
	if label.is_empty():return
	var layers: Array=e.authoring.doc.get("editorLayers",[]).duplicate(true)
	for layer in layers:
		if layer.name==label:e._notice("Layer already exists.");return
	layers.append({"name":label,"ids":[],"visible":true,"locked":false})
	_commit_layers(layers,layers.size()-1)

func _assign_layer() -> void:
	var i:=_picked()
	if i<0 or captured_ids.is_empty():return
	var layers: Array=e.authoring.doc.get("editorLayers",[]).duplicate(true)
	if layers[i].locked:e._notice("Unlock the destination layer first.");return
	for layer in layers:
		if layer.locked:
			for id in captured_ids:
				if id in layer.ids:e._notice("Unlock the source layer first.");return
	for layer in layers:
		for id in captured_ids:layer.ids.erase(id)
	layers[i].ids.append_array(captured_ids)
	_commit_layers(layers,i)

func _select_layer() -> void:
	var i:=_picked()
	if i<0:return
	var layer: Dictionary=e.authoring.doc.editorLayers[i]
	if layer.locked or not layer.visible:e._notice("Show and unlock the layer before selecting it.");return
	var ids: Array[String]=[]
	var live:=Data.records(e.authoring.doc)
	for id in layer.ids:
		if live.has(id):ids.append(str(id))
		if ids.size()>=1200:break
	dialog.hide();e._choose_tool("move_prop");e._set_multi(ids);e._refresh_authoring()

func _toggle_layer(key: String) -> void:
	var i:=_picked()
	if i<0:return
	var layers: Array=e.authoring.doc.editorLayers.duplicate(true)
	layers[i][key]=not bool(layers[i][key]);_commit_layers(layers,i)

func _remove_layer() -> void:
	var i:=_picked()
	if i<0:return
	var layers: Array=e.authoring.doc.editorLayers.duplicate(true)
	if layers[i].locked:e._notice("Unlock the layer first.");return
	layers.remove_at(i);_commit_layers(layers)

func open_filters() -> void:
	if not _ready_to_edit():return
	var panel:=_new("Select by filter",Vector2i(480,210))
	category=e._options(panel,"Object category",["all","roads","regions","props","markers","races"])
	kind_field=LineEdit.new();kind_field.placeholder_text="Exact road class, biome or asset type (blank = all)";panel.add_child(kind_field)
	query=LineEdit.new();query.placeholder_text="Name or ID contains…";panel.add_child(query)
	filter_elevation=e._options(panel,"Road elevation",["all","-2","-1","0","1","2"])
	region_only=CheckBox.new();region_only.text="Inside currently selected terrain region";panel.add_child(region_only)
	e._btn("Select matching objects",panel,_apply_filter)
	_show()

func _apply_filter() -> void:
	var district: Dictionary={}
	if region_only.button_pressed:
		var record: Dictionary=e._selected_record()
		if record.get("category","")!="regions":e._notice("Select a terrain region first.");return
		district=record.item
	var wanted: String=e._option_value(category)
	var kind:=kind_field.text.strip_edges().to_lower()
	var elevation: String=e._option_value(filter_elevation)
	var ids: Array[String]=[]
	for group in Data.CATEGORIES:
		if wanted!="all" and wanted!=group:continue
		for item in e.authoring.doc.get(group,[]):
			if not e._workspace_selectable(str(item.id)) or bool(item.get("hidden",false)):continue
			if elevation!="all" and (group!="roads" or not Session.road_touches_layer(item,int(elevation))):continue
			if Data.matches(item,group,kind if not kind.is_empty() else "all",query.text,district):ids.append(str(item.id))
			if ids.size()>=1200:break
		if ids.size()>=1200:break
	dialog.hide();e._choose_tool("move_prop");e.source_id="";e.source_anchor=-1
	if ids.size()==1:e.source_id=ids[0]
	e._set_multi(ids);e._refresh_authoring()
	e._notice("Selected %d matching objects (selection limit 1200)."%ids.size())

func asset_key(entry: Dictionary) -> String:
	return str(entry.get("project_id",entry.get("kind","")))

func favorite(entry: Dictionary) -> bool:
	return prefs.get("favorites",{}).has(asset_key(entry))

func toggle_favorite(entry: Dictionary) -> void:
	if entry.is_empty():e._notice("Choose an asset first.");return
	var key:=asset_key(entry)
	if prefs.favorites.has(key):prefs.favorites.erase(key)
	else:prefs.favorites[key]=true
	if not _save():e._notice("Could not save asset favorites.")
	e._filter_assets()

func open_replace() -> void:
	if not _ready_to_edit():return
	captured_ids=_ids()
	if captured_ids.is_empty():e._notice("Select scenery to replace.");return
	var panel:=_new("Replace selected scenery")
	_text(panel,"Keep each selected object's position, rotation and scale. The new asset supplies artwork and collision footprint.")
	query=LineEdit.new();query.placeholder_text="Search replacement assets";panel.add_child(query)
	list=_list(panel);query.text_changed.connect(func(_v: String)->void:_fill_assets())
	_fill_assets()
	e._btn("Replace all selected",panel,_replace)
	_show()

func _fill_assets() -> void:
	list.clear()
	for i in e.asset_entries.size():
		var entry: Dictionary=e.asset_entries[i]
		if query.text.to_lower() not in str(entry.name).to_lower():continue
		list.add_item(str(entry.name));list.set_item_metadata(list.item_count-1,i)

func _replace() -> void:
	var i:=_picked()
	if i<0 or not _ready_to_edit():return
	var asset_index:=int(list.get_item_metadata(i))
	if asset_index>=e.asset_entries.size():return
	if e.authoring.replace_assets(captured_ids,e.asset_entries[asset_index]):
		dialog.hide();e._refresh_authoring();e._notice("Replaced assets in one undo step.")
	else:e._notice(e.authoring.last_error)

func open_resize() -> void:
	if not _ready_to_edit() or not e.map_switcher.custom:e._notice("Resize is available on custom maps.");return
	var panel:=_new("Resize custom map",Vector2i(480,190))
	_text(panel,"Expand or crop from the east and south edges. Existing coordinates remain unchanged. Crops that exclude objects are rejected.")
	width=e._number(panel,"Width m",600,24000,e.authoring.doc.world.width)
	height=e._number(panel,"Height m",600,24000,e.authoring.doc.world.height)
	e._btn("Apply size",panel,_resize)
	_show()

func _resize() -> void:
	if not _ready_to_edit():return
	if e.authoring.resize_custom_world(int(width.value),int(height.value)):
		dialog.hide();e._refresh_authoring();e._fit_map();e._notice("Map resized. Ctrl+Z restores previous size.")
	else:e._notice(e.authoring.last_error)

func open_bookmarks() -> void:
	if not e.source_ready:return
	var panel:=_new("Camera bookmarks")
	name_field=LineEdit.new();name_field.placeholder_text="Bookmark name";panel.add_child(name_field)
	e._btn("Save current camera",panel,_save_bookmark)
	list=_list(panel);_fill_bookmarks()
	e._btn("Go to bookmark",panel,_go_bookmark)
	e._btn("Delete bookmark",panel,_delete_bookmark)
	_show()

func _fill_bookmarks() -> void:
	list.clear()
	for item in _map_prefs().get("bookmarks",[]):list.add_item(str(item.name))

func _save_bookmark() -> void:
	var label:=name_field.text.strip_edges().left(60)
	if label.is_empty():return
	var bookmarks: Array=_map_prefs().get("bookmarks",[])
	if bookmarks.size()>=100:return
	for item in bookmarks:
		if item.name==label:e._notice("Use a unique bookmark name.");return
	var p: Vector2=e.editor_camera.global_position
	bookmarks.append({"name":label,"x":p.x,"y":p.y,"zoom":e.editor_camera.zoom.x})
	_map_prefs()["bookmarks"]=bookmarks
	_save();_fill_bookmarks()

func _go_bookmark() -> void:
	var i:=_picked()
	if i<0:return
	var bookmark: Dictionary=_map_prefs().bookmarks[i]
	e.editor_camera.global_position=Vector2(bookmark.x,bookmark.y)
	e.editor_camera.zoom=Vector2.ONE*clampf(float(bookmark.zoom),e.MIN_EDITOR_ZOOM,e.MAX_EDITOR_ZOOM)
	e._position_camera_canvas();e._update_view(true);dialog.hide()

func _delete_bookmark() -> void:
	var i:=_picked()
	if i>=0:_map_prefs().bookmarks.remove_at(i);_save();_fill_bookmarks()

func open_snapshots() -> void:
	if not _ready_to_edit() or not e.map_switcher.custom:e._notice("Named snapshots are available on custom maps.");return
	var panel:=_new("Version snapshots")
	_text(panel,"Store a full source copy locally. Restore into the current draft; restoring is undoable and does not publish.")
	name_field=LineEdit.new();name_field.placeholder_text="Snapshot name";panel.add_child(name_field)
	e._btn("Create snapshot",panel,_save_snapshot)
	list=_list(panel);_fill_snapshots()
	e._btn("Restore selected snapshot",panel,_restore_snapshot)
	e._btn("Delete selected snapshot",panel,_delete_snapshot)
	_show()

func _fill_snapshots() -> void:
	list.clear()
	for item in _map_prefs().get("snapshots",[]):list.add_item(str(item.name))

func _save_snapshot() -> void:
	if not _ready_to_edit():return
	var label:=name_field.text.strip_edges().left(60)
	var snapshots: Array=_map_prefs().get("snapshots",[])
	if label.is_empty() or snapshots.size()>=30:return
	var file: String="snapshot-%s-%d.json"%[str(Time.get_unix_time_from_system()).replace(".","-"),randi()]
	var root:=Library.folder().path_join("snapshots")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var path:=root.path_join(file)
	var out:=FileAccess.open(path,FileAccess.WRITE)
	if out==null:e._notice("Could not write snapshot.");return
	out.store_string(JSON.stringify(e.authoring.doc));out.flush();out.close()
	snapshots.append({"name":label,"file":file})
	_map_prefs()["snapshots"]=snapshots
	if not _save():snapshots.pop_back();DirAccess.remove_absolute(ProjectSettings.globalize_path(path));e._notice("Could not save snapshot index.");return
	_fill_snapshots()

func _snapshot_path(item: Dictionary) -> String:
	var file:=str(item.get("file",""))
	if file.get_file()!=file or not file.begins_with("snapshot-") or not file.ends_with(".json"):return ""
	return Library.folder().path_join("snapshots").path_join(file)

func _restore_snapshot() -> void:
	var i:=_picked()
	if i<0 or not _ready_to_edit():return
	var path:=_snapshot_path(_map_prefs().snapshots[i])
	if path.is_empty():return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and e.authoring.restore_snapshot(parsed):
		dialog.hide();e._refresh_authoring();e._fit_map();e._notice("Snapshot restored into draft.")
	else:e._notice("Snapshot could not be restored; unlock layers if necessary.")

func _delete_snapshot() -> void:
	var i:=_picked()
	if i<0:return
	var snapshots: Array=_map_prefs().snapshots
	var item: Dictionary=snapshots.pop_at(i)
	if not _save():snapshots.insert(i,item);return
	var path:=_snapshot_path(item)
	if not path.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_fill_snapshots()

func open_reference() -> void:
	if not e.source_ready:return
	var panel:=_new("Reference image overlay",Vector2i(480,260))
	_text(panel,"Trace a local image over the map. It is an editor-only overlay, never baked into the game.")
	var p: Vector2=e.editor_camera.global_position/20.0
	reference_width=e._number(panel,"Image width m",10,24000,1000)
	reference_x=e._number(panel,"Centre X m",0,e.authoring.doc.world.width,p.x)
	reference_y=e._number(panel,"Centre Y m",0,e.authoring.doc.world.height,p.y)
	reference_alpha=e._number(panel,"Opacity %",0,100,40)
	reference_rotation=e._number(panel,"Rotation degrees",-180,180,0)
	e._btn("Choose image",panel,_choose_reference)
	e._btn("Apply transform",panel,_transform_reference)
	e._btn("Remove overlay",panel,_remove_reference)
	_show()

func _choose_reference() -> void:
	if not is_instance_valid(reference_file):
		reference_file=FileDialog.new();reference_file.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		reference_file.access=FileDialog.ACCESS_FILESYSTEM
		reference_file.filters=PackedStringArray(["*.png ; PNG","*.jpg,*.jpeg ; JPEG","*.webp ; WebP"])
		e.root_ui.add_child(reference_file);reference_file.file_selected.connect(_load_reference)
	reference_file.popup_centered_ratio(.7)

func _load_reference(path: String) -> void:
	var image:=Image.load_from_file(path)
	if image==null or image.is_empty() or image.get_width()>8192 or image.get_height()>8192:e._notice("Invalid image or image exceeds 8192 pixels.");return
	if not is_instance_valid(reference):
		reference=Sprite2D.new();reference.z_index=20;e.gizmos.add_child(reference)
	reference.texture=ImageTexture.create_from_image(image);reference_key=_map_key()
	_transform_reference()

func _transform_reference() -> void:
	if not is_instance_valid(reference):return
	reference.global_position=Vector2(reference_x.value,reference_y.value)*20
	reference.scale=Vector2.ONE*reference_width.value*20/reference.texture.get_width()
	reference.modulate.a=reference_alpha.value/100.0
	reference.rotation=deg_to_rad(reference_rotation.value)
	reference.visible=reference_key==_map_key()

func _remove_reference() -> void:
	if is_instance_valid(reference):reference.queue_free();reference=null

func refresh() -> void:
	if is_instance_valid(reference):reference.visible=reference_key==_map_key()

func begin_measure() -> void:
	if not _ready_to_edit():return
	measure_points.clear();e.gizmos.measurement_points.clear()
	e._choose_tool("measure");e.mode_label.text="MEASURE"
	e._notice("Click points to measure length, area and angle. Esc returns to editing.")

func measure_click(at: Vector2) -> void:
	if measure_points.size()>=100:measure_points.clear()
	measure_points.append(at)
	e.gizmos.measurement_points=measure_points.duplicate();e.gizmos.queue_redraw()
	var result:=Data.measure(measure_points)
	e._notice("Length %.1f m | closed area %.1f m² | angle %.1f°"%[result.length,result.area,result.angle])

func clear_measure() -> void:
	measure_points.clear()
	if is_instance_valid(e) and is_instance_valid(e.gizmos):e.gizmos.measurement_points.clear();e.gizmos.queue_redraw()

func open_commands() -> void:
	if not e.source_ready:return
	var panel:=_new("Search editor commands")
	query=LineEdit.new();query.placeholder_text="Type a command…";panel.add_child(query)
	list=_list(panel)
	commands=[["Named layers",open_layers],["Select by filter",open_filters],["Replace assets",open_replace],
		["Camera bookmarks",open_bookmarks],["Version snapshots",open_snapshots],["Resize map",open_resize],
		["Reference overlay",open_reference],["Measure distance area angles",begin_measure],["Road grade and clearance",measure_roads],
		["Build city",e._open_construction],["Landscape terrain",e._open_landscape],["Bulk edit",e._open_bulk_edit],
		["Prefabs",e._open_prefabs],["Edit history",e._open_history],["Fit map",e._fit_map],["Undo",e._undo],["Redo",e._redo],
		["Test Drive",e._test_drive]]
	query.text_changed.connect(func(_v: String)->void:_fill_commands())
	_fill_commands()
	e._btn("Run command",panel,_run_command)
	list.item_activated.connect(func(_i: int)->void:_run_command())
	_show();query.grab_focus()

func _fill_commands() -> void:
	list.clear()
	for i in commands.size():
		if query.text.to_lower() not in str(commands[i][0]).to_lower():continue
		list.add_item(str(commands[i][0]));list.set_item_metadata(list.item_count-1,i)
	if list.item_count>0:list.select(0)

func _run_command() -> void:
	var i:=_picked()
	if i<0:return
	var action: Callable=commands[int(list.get_item_metadata(i))][1]
	dialog.hide();action.call_deferred()

func measure_roads() -> void:
	var ids:=_ids()
	var roads: Array=[]
	for id in ids:
		var road: Dictionary=e.authoring.road_at_id(id)
		if not road.is_empty():roads.append(road)
	if roads.size() not in [1,2]:e._notice("Select one road to measure grades or two roads to measure crossing clearance.");return
	var panel:=_new("Road measurements",Vector2i(490,190))
	for road in roads:
		var result:=Data.road_metrics(road)
		_text(panel,"%s: %.1f m · maximum approximate grade %.1f%%"%[road.name,result.length,result.grade])
	if roads.size()==2:
		var clearance:=Data.crossing_clearance(roads[0],roads[1])
		_text(panel,"No crossing detected between control segments." if clearance<0 else "Minimum estimated vertical clearance %.2f m (production spline bake is authoritative)."%clearance)
	_show()
