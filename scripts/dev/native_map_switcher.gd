extends RefCounted
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Terrain=preload("res://scripts/dev/custom_map_terrain.gd")
var selector: OptionButton
var dialog: ConfirmationDialog
var map_name: LineEdit
var width: SpinBox
var height: SpinBox
var base: OptionButton
var custom:=false
var current_file:=""
var original_session
var original_world: Dictionary={}
var terrain: Node2D
var revision:=-1
var drag_revision:=""
var recovery_revision:=-1
func build(e,parent: Node) -> void:
	var row:=HBoxContainer.new();parent.add_child(row)
	selector=OptionButton.new();selector.custom_minimum_size=Vector2(150,28);selector.fit_to_longest_item=false;row.add_child(selector)
	selector.item_selected.connect(func(index):select(e,index))
	e._btn("New map",row,func():show_create(e)).custom_minimum_size.y=26
	reload_list()
	dialog=ConfirmationDialog.new();dialog.title="Create a new map";dialog.ok_button_text="Create map";dialog.min_size=Vector2i(390,280);dialog.process_mode=Node.PROCESS_MODE_ALWAYS;e.add_child(dialog)
	var fields:=VBoxContainer.new();dialog.add_child(fields)
	var help:=Label.new();help.text="Choose the map size in metres.";fields.add_child(help)
	map_name=LineEdit.new();map_name.placeholder_text="Map name";map_name.max_length=60;fields.add_child(map_name)
	width=e._number(fields,"Width m",600,24000,2400);width.step=100;width.value=2400
	height=e._number(fields,"Height m",600,24000,1800);height.step=100;height.value=1800
	base=e._options(fields,"Base terrain",["grass","forest","beach","desert","ocean"])
	dialog.confirmed.connect(func():create_map(e))
func reload_list() -> void:
	selector.clear();selector.add_item("Morrow Coast");selector.set_item_metadata(0,"")
	for map in Library.list_maps():
		selector.add_item(map.name);selector.set_item_metadata(selector.item_count-1,map.file)
	for i in selector.item_count:
		if str(selector.get_item_metadata(i))==current_file:selector.select(i)
func ready_to_switch(e) -> bool:
	if e._editing_locked() or not e.draft_points.is_empty() or not e.pending_drag.is_empty():e._notice("Finish or cancel the current edit before switching maps.");return false
	if custom:return save_current(e)
	if e.source_ready and e.authoring.dirty:e._notice("Save or discard Morrow Coast edits before switching maps.");return false
	return true
func show_create(e) -> void:
	if ready_to_switch(e):map_name.text="Untitled map";dialog.popup_centered();map_name.grab_focus()
func create_map(e) -> void:
	if map_name.text.strip_edges().is_empty():dialog.popup_centered();e._notice("Enter a map name.");return
	if not ready_to_switch(e):return
	var doc:=Library.create(map_name.text,int(width.value),int(height.value),e._option_value(base))
	var file:=Library.save(doc)
	if file.is_empty():e._notice("Map could not be written. Check the saved-map folder.");return
	activate(e,doc,file);reload_list();e._notice("New blank map created. Choose terrain, roads or scenery; Ctrl+S saves this map separately.")
func select(e,index: int) -> void:
	var file:=str(selector.get_item_metadata(index))
	if file==current_file:return
	if not ready_to_switch(e):reload_list();return
	if file.is_empty():restore(e);e._refresh_authoring();e._fit_map();return
	var doc:=Library.load_map(file)
	var probe:=Session.new()
	if not probe._valid_source(doc):e._notice("Saved map is invalid; the current map was kept.");reload_list();return
	activate(e,doc,file)
func activate(e,doc: Dictionary,file: String) -> void:
	if not custom:original_session=e.authoring;original_world=e.world.data
	custom=true;current_file=file
	e.authoring=Session.new();e.authoring.doc=doc.duplicate(true);e.authoring.initial=doc.duplicate(true)
	e.authoring.baseline_hash=e.authoring._fingerprint(doc);e.authoring.draft_baseline_hash=e.authoring.baseline_hash;e.authoring.edit_revision+=1
	var journal:=Library.folder().path_join(file+".draft.json")
	if FileAccess.file_exists(journal):
		var recovered=JSON.parse_string(FileAccess.get_file_as_string(journal))
		if recovered is Dictionary and e.authoring._valid_source(recovered):
			e.authoring.doc=recovered;e.authoring.history.append(doc.duplicate(true));e.authoring.dirty=e.authoring._fingerprint(recovered)!=e.authoring.baseline_hash
	recovery_revision=-1
	e.world.data=original_world.duplicate();e.world.data.size=[doc.world.width,doc.world.height]
	for key in ["roads","segments","props","terrain","junctions","bridges","pois","relief_faces","mountain_rails"]:e.world.data[key]=[]
	e.source_ready=true;e.source_id="";e.source_anchor=-1;e.source_revision="";e.selected={};e.synced_preview_revision=-1;e._entity_revision=-1
	e.gizmos.custom_terrain=true;e.gizmos.network=null;e.gizmos.network_is_draft=false;e.gizmos.preview_junctions=[]
	e.gizmos.bridge_overrides={};e.gizmos.bridge_redraw_roads={}
	if terrain==null:
		terrain=Terrain.new();terrain.z_index=-8;e.get_parent().add_child(terrain)
	revision=-1;e._refresh_authoring();e._fit_map();update_view(e)
func save_current(e) -> bool:
	if not custom:return true
	if not e.authoring._valid_source(e.authoring.doc):e._notice("Map validation failed; saved version was kept.");return false
	var file:=Library.save(e.authoring.doc,current_file)
	if file.is_empty():e._notice("Could not save map; your unsaved draft is still open.");return false
	current_file=file;e.authoring.accepted_remote(e.authoring.doc.duplicate(true));save_recovery(e);reload_list();e._notice("Saved "+str(e.authoring.doc.name)+".");return true
func save_recovery(e) -> void:
	if current_file.is_empty() or recovery_revision==e.authoring.edit_revision:return
	recovery_revision=e.authoring.edit_revision
	var path:=Library.folder().path_join(current_file+".draft.json")
	if not e.authoring.dirty:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path));return
	var stream:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if stream!=null:
		stream.store_string(JSON.stringify(e.authoring.doc));stream.flush();stream.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))
func refresh(e) -> void:
	var drag_key:=JSON.stringify(e.pending_drag)
	if revision!=e.authoring.edit_revision or drag_key!=drag_revision:
		revision=e.authoring.edit_revision;drag_revision=drag_key;terrain.update_map(e.authoring.road_preview_source(e.pending_drag))
	terrain.visible=e.layer_flags.terrain
func update_view(e) -> void:
	if is_instance_valid(e.overview_renderer):e.overview_renderer.visible=false
	if is_instance_valid(e.render_tiles):e.render_tiles.visible=false
	e.gizmos.zoom_level=e.editor_camera.zoom.x;e.gizmos.queue_redraw()
	e.status.text="%s  |  %d × %d m  |  %d roads · %d regions · %d objects"%[e.authoring.doc.name,e.authoring.doc.world.width,e.authoring.doc.world.height,e.authoring.doc.roads.size(),e.authoring.doc.regions.size(),e.authoring.doc.props.size()]
func restore(e) -> void:
	if not custom:return
	e.world.data=original_world;e.authoring=original_session;custom=false;current_file=""
	e.source_id="";e.source_anchor=-1;e.synced_preview_revision=-1;e._entity_revision=-1
	e.gizmos.custom_terrain=false;e.gizmos.network=e.traffic_network
	if terrain!=null:terrain.queue_free();terrain=null
	if is_instance_valid(e.overview_renderer):e.overview_renderer.visible=true
	reload_list()
