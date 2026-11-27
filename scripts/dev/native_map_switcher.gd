extends RefCounted
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Terrain=preload("res://scripts/dev/custom_map_terrain.gd")
const WorldPublication=preload("res://scripts/world/world_publication.gd")
const ReleaseComparison=preload("res://scripts/dev/map_release_comparison.gd")
const RELEASE="res://tools/world_release.py"
const PUBLISHER="res://tools/publish_custom_world.py"
const COMPACT_PRESET="res://map-editor/maps/compact-boroughs.world.json"
const COMPACT_FILE="compact-boroughs.world.json"
const DRIFT_PRESET="res://map-editor/maps/drift-grounds.world.json"
const DRIFT_FILE="drift-grounds.world.json"
var selector: OptionButton
var dialog: ConfirmationDialog
var map_name: LineEdit
var width: SpinBox
var height: SpinBox
var base: OptionButton
var weather_option: OptionButton
var publish_button: Button
var restore_button: Button
var import_published_button: Button
var publication_status: Label
var publish_dialog: ConfirmationDialog
var restore_dialog: ConfirmationDialog
var custom:=false
var current_file:=""
var original_session
var original_world: Dictionary={}
var original_world_node: MorrowCoast
var custom_world: MorrowCoast
var terrain: Node2D
var revision:=-1
var drag_revision:=""
var recovery_revision:=-1
func build(e,parent: Node) -> void:
	var row:=HBoxContainer.new();parent.add_child(row)
	selector=OptionButton.new();selector.custom_minimum_size=Vector2(150,28);selector.fit_to_longest_item=false;row.add_child(selector)
	selector.item_selected.connect(func(index):select(e,index))
	e._btn("New map",row,func():show_create(e)).custom_minimum_size.y=26
	var compact_button=e._btn("Compact Boroughs",row,func():open_compact_preset(e))
	compact_button.custom_minimum_size.y=26
	compact_button.tooltip_text="Open a compact, fully editable three-district map, independent of Morrow Coast."
	var drift_button=e._btn("Drift Grounds",row,func():open_drift_preset(e))
	drift_button.custom_minimum_size.y=26
	drift_button.tooltip_text="Open a compact linked skidpad, technical S-corners and tandem drift loop."
	reload_list()
	dialog=ConfirmationDialog.new();dialog.title="Create a new map";dialog.ok_button_text="Create map";dialog.min_size=Vector2i(390,280);dialog.process_mode=Node.PROCESS_MODE_ALWAYS;e.add_child(dialog)
	var fields:=VBoxContainer.new();dialog.add_child(fields)
	var help:=Label.new();help.text="Choose the map size in metres.";fields.add_child(help)
	map_name=LineEdit.new();map_name.placeholder_text="Map name";map_name.max_length=60;fields.add_child(map_name)
	width=e._number(fields,"Width m",600,24000,2400);width.step=100;width.value=2400
	height=e._number(fields,"Height m",600,24000,1800);height.step=100;height.value=1800
	base=e._options(fields,"Base terrain",["grass","forest","beach","desert","ocean"])
	dialog.confirmed.connect(func():create_map(e))
## Publishing is separate from Save (draft source) and F6 (sandbox test).
## This workflow writes a real res:// release world and a switchable manifest.
func build_publish_ui(e,parent: Node) -> void:
	parent.add_child(HSeparator.new())
	var heading:=Label.new()
	heading.text="GAME WORLD / PUBLISH"
	parent.add_child(heading)
	# Keep the fixed-height BuilderHeader reserved for map selection.
	# Weather lives with publish options in the scrollable settings sidebar,
	# preventing this control from pushing the header into BuilderTools.
	var rain_row := HBoxContainer.new()
	parent.add_child(rain_row)
	var rain_label := Label.new()
	rain_label.text="Map weather"
	rain_row.add_child(rain_label)
	weather_option=OptionButton.new()
	for choice in ["Clear","Light rain","Rain","Heavy rain"]:
		weather_option.add_item(choice)
	rain_row.add_child(weather_option)
	weather_option.tooltip_text="Weather for this custom map's Test Drive and published game. Save the source before publishing."
	weather_option.item_selected.connect(func(index: int): _change_weather(e,index))
	_sync_weather(e)
	publication_status=Label.new()
	publication_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(publication_status)
	e._btn("World Release Center...",parent,func():open_release_center(e))
	publish_button=e._btn("Build Game World...",parent,func():_show_publish(e))
	publish_button.tooltip_text="Package the selected saved custom map as the main playable world. Test Drive remains a sandbox."
	import_published_button=e._btn("Open Published Source...",parent,func():_open_published_source(e))
	import_published_button.tooltip_text="Restore the compiled game's editable source snapshot into your map library without overwriting different local edits."
	restore_button=e._btn("Restore Morrow Coast...",parent,func():_show_restore(e))
	restore_button.tooltip_text="Set Morrow Coast as the active game without deleting your published map or editing source."
	publish_dialog=ConfirmationDialog.new()
	publish_dialog.title="Build selected map as main game world"
	publish_dialog.ok_button_text="Validate & Publish"
	publish_dialog.min_size=Vector2i(550,275)
	publish_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	publish_dialog.confirmed.connect(func():_publish(e,false))
	e.add_child(publish_dialog)
	restore_dialog=ConfirmationDialog.new()
	restore_dialog.title="Restore original Morrow Coast game world?"
	restore_dialog.dialog_text="Set Morrow Coast as the active PLAY world. Your published map, source copy, and backups remain intact."
	restore_dialog.ok_button_text="Restore Morrow Coast"
	restore_dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	restore_dialog.confirmed.connect(func():_publish(e,true))
	e.add_child(restore_dialog)
	_refresh_publication_ui()

func _refresh_publication_ui() -> void:
	if not is_instance_valid(publication_status):return
	var active: Dictionary=WorldPublication.current()
	publication_status.text="PLAY loads: "+str(active.name)+("\nCustom map ready to publish." if custom else "\nSelect a saved custom map to publish.")
	publish_button.disabled=not custom
	import_published_button.disabled=not bool(active.get("published",false))
	restore_button.disabled=not bool(active.get("published",false))

func _open_published_source(e) -> void:
	var current: Dictionary=WorldPublication.current()
	if not bool(current.get("published",false)):
		e._notice("No published custom game world is available.")
		return
	if not ready_to_switch(e):return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(str(current.source)))
	var probe:=Session.new()
	if not parsed is Dictionary or not probe._valid_source(parsed):
		e._notice("Published source snapshot could not be opened. The current map was kept.")
		return
	var requested: String=str(current.id)
	var existing: Dictionary=Library.load_map(requested) if FileAccess.file_exists(
		Library.folder().path_join(requested)) else {}
	if not existing.is_empty() and probe._fingerprint(existing)!=probe._fingerprint(parsed):
		# Never overwrite the player's newer local draft while importing an
		# older published version from the project source snapshot.
		requested="published-copy-%d.world.json"%Time.get_ticks_usec()
		e._notice("Saved another copy because the local map had newer edits.")
	if existing.is_empty() or requested!=str(current.id):
		if Library.save(parsed,requested).is_empty():
			e._notice("Unable to import published source into the writable map library.")
			return
	activate(e,parsed,requested)
	reload_list()
	e._notice("Loaded editable source for published game world "+str(parsed.get("name","Custom Map"))+".")

func _show_publish(e) -> void:
	if not custom:
		e._notice("Select a custom map before publishing.")
		return
	if not _can_publish(e):return
	publish_dialog.dialog_text="Publish '%s' as the real game world?\n\nThis will package saved roads, junctions, terrain, art references, races, markers, and dealerships. The compiler requires one drivable road and a Player Spawn clear of solid scenery. It will back up the previous game selection. Your Morrow Coast world and career save remain untouched.\n\nAfter publishing, return to the title screen and select PLAY."%str(e.authoring.doc.get("name","Custom Map"))
	publish_dialog.popup_centered()

func _show_restore(e) -> void:
	if e._editing_locked() or not e.draft_points.is_empty() or not e.pending_drag.is_empty():
		e._notice("Finish or cancel your current edit before changing the game world.")
		return
	restore_dialog.popup_centered()

func _can_publish(e) -> bool:
	if not e.active or not custom or not e.source_ready:
		e._notice("Open a saved custom map to publish it.")
		return false
	if e._editing_locked() or not e.draft_points.is_empty() or not e.pending_drag.is_empty() or \
			(is_instance_valid(e.bridge) and e.bridge.phase!=""):
		e._notice("Finish or cancel the current edit and save before publishing.")
		return false
	if not e.authoring._valid_source(e.authoring.doc):
		e._notice("Map has invalid race dependencies, markers, or geometry. Fix them before publishing.")
		return false
	return true

func _publish(e,restore_default: bool) -> void:
	if not restore_default:
		if not _can_publish(e) or not save_current(e):return
	if not FileAccess.file_exists(PUBLISHER):
		e._notice("Missing production publisher script. No game files were changed.")
		return
	var project: String=ProjectSettings.globalize_path("res://")
	var backups: String=ProjectSettings.globalize_path(Library.folder().path_join("publish-backups"))
	var args:=PackedStringArray([ProjectSettings.globalize_path(PUBLISHER),
		"--project",project,"--backup-dir",backups])
	if restore_default:
		args.append("--restore")
	else:
		args.append_array(PackedStringArray([
			"--source",ProjectSettings.globalize_path(Library.folder().path_join(current_file))]))
	var program: String="py" if OS.get_name()=="Windows" else "python3"
	if OS.get_name()=="Windows":args.insert(0,"-3")
	var output: Array=[]
	var result: int=OS.execute(program,args,output,true)
	_refresh_publication_ui()
	if result!=0:
		e._notice("Game world was NOT changed: "+str(output).left(280))
		return
	var detail: Variant=JSON.parse_string(str(output[0]).strip_edges()) if not output.is_empty() else {}
	if restore_default:
		e._notice("Morrow Coast is the active game world. Published maps and backups were preserved.")
	else:
		var summary: Dictionary=detail if detail is Dictionary else {}
		e._notice("Published %s to PLAY: %d roads, %d junctions, %d races. Return to the title menu to play it."%[
			str(summary.get("name",e.authoring.doc.name)),int(summary.get("roads",0)),
			int(summary.get("junctions",0)),int(summary.get("races",0))])

func _change_weather(e,index: int) -> void:
	if not custom or not e.source_ready or e._editing_locked():
		_sync_weather(e)
		return
	var values := [0.0,0.3,0.65,1.0]
	if index < 0 or index >= values.size():
		return
	var next: Dictionary=e.authoring.doc.duplicate(true)
	next["rain_intensity"]=values[index]
	if e.authoring._commit(next):
		e._notice("Map weather changed. Save to retain it in Test Drive and published PLAY.")
	else:
		_sync_weather(e)


func _sync_weather(e) -> void:
	if not is_instance_valid(weather_option):
		return
	weather_option.disabled=not custom
	var value: float=float(e.authoring.doc.get("rain_intensity",0.0)) if custom else 0.0
	var values := [0.0,0.3,0.65,1.0]
	var best := 0
	for i in values.size():
		if absf(values[i]-value)<absf(values[best]-value):
			best=i
	weather_option.select(best)


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
## Import a bundled starter into the user's writable map library once. Never
## replace a customized local map; reopening this preset resumes their edits.
func open_compact_preset(e) -> void:
	_open_bundled_preset(e,COMPACT_PRESET,COMPACT_FILE,"Compact Boroughs")


func open_drift_preset(e) -> void:
	_open_bundled_preset(e,DRIFT_PRESET,DRIFT_FILE,"Drift Grounds")


## An immutable bundled starter is copied only once to the local map library.
## Existing edits (or corrupt drafts) are never overwritten when reopening.
func _open_bundled_preset(e,resource_path: String,file_name: String,label: String) -> void:
	if not ready_to_switch(e):return
	var probe:=Session.new()
	var file:=file_name
	var destination:=Library.folder().path_join(file)
	var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(resource_path))
	if not source is Dictionary or not probe._valid_source(source) or not bool(source.get("customMap",false)):
		e._notice("Bundled "+label+" map could not be validated.")
		return
	var doc: Dictionary=source
	if FileAccess.file_exists(destination):
		var saved: Dictionary=Library.load_map(file)
		if not saved.is_empty() and probe._valid_source(saved):
			doc=saved
		else:
			# Keep an invalid personal file for manual recovery; make a new copy.
			file=file_name.trim_suffix(".world.json")+"-copy-%d.world.json"%Time.get_ticks_usec()
	if not FileAccess.file_exists(Library.folder().path_join(file)):
		if Library.save(doc,file).is_empty():
			e._notice("Could not save "+label+" into your writable map library.")
			return
	activate(e,doc,file)
	reload_list()
	e._notice(label+" loaded as a separate editable custom map. F6 test drives it without changing Morrow Coast.")


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
	if not custom:
		original_session=e.authoring;original_world=e.world.data;original_world_node=e.world
	custom=true;current_file=file
	_refresh_publication_ui()
	e._apply_landmark_layer()
	e.authoring=Session.new();e.authoring.doc=doc.duplicate(true);e.authoring.initial=doc.duplicate(true)
	e.authoring.unlocked_road_layer=e.road_selection_layer if e.lock_other_roads else 99
	e.authoring.baseline_hash=e.authoring._fingerprint(doc);e.authoring.draft_baseline_hash=e.authoring.baseline_hash;e.authoring.edit_revision+=1
	var journal:=Library.folder().path_join(file+".draft.json")
	if FileAccess.file_exists(journal):
		var recovered=JSON.parse_string(FileAccess.get_file_as_string(journal))
		if recovered is Dictionary and e.authoring._valid_source(recovered):
			e.authoring.doc=recovered;e.authoring.history.append(doc.duplicate(true));e.authoring.dirty=e.authoring._fingerprint(recovered)!=e.authoring.baseline_hash
	recovery_revision=-1
	_sync_weather(e)
	# Cached Morrow render canvases retain their original world owner. Swapping
	# that owner's data underneath queued draw calls left stale road/bridge
	# indices referencing empty arrays, even when their parent was hidden.
	if not is_instance_valid(custom_world):
		custom_world=MorrowCoast.new();custom_world.editor_render_only=true
		# Do not add this data-only world to the tree: _ready loads Morrow.
	e.world=custom_world;e.gizmos.world=custom_world
	e.world.data=original_world.duplicate();e.world.data.size=[doc.world.width,doc.world.height]
	for key in ["roads","segments","props","terrain","junctions","bridges","pois","relief_faces","mountain_rails"]:e.world.data[key]=[]
	for key in ["chunks","nodes","surface_index"]:e.world.data[key]={}
	e.world.data.road_width_scale=1.0
	e.world.data.spawn={"position":[doc.world.width*.5,doc.world.height*.5],"rotation":0.0}
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
		revision=e.authoring.edit_revision;drag_revision=drag_key;terrain.update_map(preload("res://scripts/dev/native_editor_workspace.gd").preview(e.authoring.road_preview_source(e.pending_drag)))
		e.world.data.size=[e.authoring.doc.world.width,e.authoring.doc.world.height]
		# Undo/redo and source switching must update the visible weather preset.
		_sync_weather(e)
	terrain.visible=e.layer_flags.terrain
func update_view(e) -> void:
	if is_instance_valid(e.overview_renderer):e.overview_renderer.visible=false
	if is_instance_valid(e.render_tiles):e.render_tiles.visible=false
	e.gizmos.set_view(e.editor_camera.global_position,e.get_viewport().get_visible_rect().size,e.editor_camera.zoom.x)
	e.zoom_label.text="%.1f%%"%(e.editor_camera.zoom.x*100)
	e.status.text="%s  |  %d × %d m  |  %d roads · %d regions · %d objects"%[e.authoring.doc.name,e.authoring.doc.world.width,e.authoring.doc.world.height,e.authoring.doc.roads.size(),e.authoring.doc.regions.size(),e.authoring.doc.props.size()]
func restore(e) -> void:
	if not custom:return
	e.world=original_world_node;e.gizmos.world=e.world;e.authoring=original_session;custom=false;current_file=""
	e.authoring.unlocked_road_layer=e.road_selection_layer if e.lock_other_roads else 99
	_sync_weather(e)
	_refresh_publication_ui()
	e._apply_landmark_layer()
	if is_instance_valid(custom_world):custom_world.free();custom_world=null
	e.source_id="";e.source_anchor=-1;e.synced_preview_revision=-1;e._entity_revision=-1
	e.gizmos.custom_terrain=false;e.gizmos.network=e.traffic_network
	if terrain!=null:terrain.queue_free();terrain=null
	if is_instance_valid(e.overview_renderer):e.overview_renderer.visible=true
	reload_list()

func dispose() -> void:
	if is_instance_valid(custom_world):custom_world.free();custom_world=null

func _release_command(arguments: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(RELEASE):return {"result":"blocked","error":"Missing release tool; use the source project."}
	var args:=PackedStringArray([ProjectSettings.globalize_path(RELEASE),"--project",ProjectSettings.globalize_path("res://")])
	args.append_array(PackedStringArray(arguments))
	var program: String="py" if OS.get_name()=="Windows" else "python3"
	if OS.get_name()=="Windows":args.insert(0,"-3")
	var output: Array=[]
	var code:=OS.execute(program,args,output,true)
	var parsed: Variant=JSON.parse_string(str(output[0]).strip_edges()) if not output.is_empty() else null
	if parsed is Dictionary:
		if code!=0:parsed.result="blocked"
		return parsed
	return {"result":"blocked","error":str(output).left(1000)}

func open_release_center(e) -> void:
	if not e.active or not e.source_ready:return
	var window:=AcceptDialog.new();window.title="World Release Center";window.ok_button_text="Close"
	window.process_mode=Node.PROCESS_MODE_ALWAYS;e.add_child(window)
	var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(610,470);window.add_child(box)
	var status:=RichTextLabel.new();status.custom_minimum_size=Vector2(600,250);status.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(status)
	status.text="Read-only release preflight, package export, backup comparison and verified rollback. Publishing still requires explicit confirmation. Static checks do not certify driving or FPS."
	var revision: int=e.authoring.edit_revision
	var session: RefCounted=e.authoring
	var file: String=current_file
	var valid:=func()->bool:return e.active and e.source_ready and session==e.authoring and revision==e.authoring.edit_revision and file==current_file and not e._editing_locked()
	var saved:=func()->bool:
		return valid.call() and custom and not e.authoring.dirty and not file.is_empty() and e.pending_drag.is_empty() and e.draft_points.is_empty()
	var show_result:=func(result: Dictionary):
		if result.get("result","")=="blocked":status.text="BLOCKED: "+str(result.get("error","Unknown failure"));return
		status.text=JSON.stringify(result,"  ")
	e._btn("Validate saved map / dependencies",box,func():
		if not saved.call():status.text="Save the map and reopen Release Center first.";return
		show_result.call(_release_command(["--preflight",ProjectSettings.globalize_path(Library.folder().path_join(file))])))
	e._btn("Export portable map ZIP (does not activate)",box,func():
		if not saved.call():status.text="Save the map and reopen Release Center first.";return
		var path:=Library.folder().path_join("releases").path_join(file.trim_suffix(".world.json")+"-%d.zip"%Time.get_ticks_usec())
		show_result.call(_release_command(["--export",ProjectSettings.globalize_path(Library.folder().path_join(file)),"--output",ProjectSettings.globalize_path(path)])))
	e._btn("Verify a release ZIP",box,func():
		var picker:=FileDialog.new();picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM
		picker.filters=PackedStringArray(["*.zip ; Streetbound map release"])
		window.add_child(picker);picker.file_selected.connect(func(path: String):
			show_result.call(_release_command(["--verify",path]));picker.queue_free())
		picker.canceled.connect(picker.queue_free);picker.popup_centered_ratio(.7))
	e._btn("Install verified ZIP as PLAY world...",box,func():
		if not valid.call():return
		var picker:=FileDialog.new();picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM
		picker.filters=PackedStringArray(["*.zip ; Streetbound map release"])
		window.add_child(picker)
		picker.file_selected.connect(func(path: String):
			picker.queue_free()
			var confirm:=ConfirmationDialog.new();confirm.title="Activate verified map package?"
			confirm.dialog_text="Requires matching project artwork and compiler. No external assets will be installed. The previous PLAY world is backed up; the current draft and career remain unchanged."
			window.add_child(confirm)
			confirm.confirmed.connect(func():
				if valid.call():
					var backup_root:=Library.folder().path_join("publish-backups")
					show_result.call(_release_command(["--install",path,"--backup-dir",ProjectSettings.globalize_path(backup_root)]))
					_refresh_publication_ui()
				confirm.queue_free())
			confirm.canceled.connect(confirm.queue_free);confirm.popup_centered())
		picker.canceled.connect(picker.queue_free);picker.popup_centered_ratio(.7))
	var versions:=OptionButton.new();box.add_child(versions)
	for name in Library.backups(file):
		versions.add_item(name);versions.set_item_metadata(versions.item_count-1,name)
	var compare_button: Button=e._btn("Compare selected automatic backup → current draft",box,func():
		if not valid.call() or versions.selected<0:return
		var before:=Library.load_backup(file,str(versions.get_item_metadata(versions.selected)))
		if before.is_empty():status.text="Backup unavailable.";return
		status.text=ReleaseComparison.text(before,e.authoring.doc))
	compare_button.disabled=versions.item_count==0
	var recover_button: Button=e._btn("Restore selected backup into draft (undoable)",box,func():
		if not valid.call() or versions.selected<0:return
		var before:=Library.load_backup(file,str(versions.get_item_metadata(versions.selected)))
		if not before.is_empty() and e.authoring.restore_snapshot(before):
			e._refresh_authoring();e._fit_map();window.hide();window.queue_free()
		else:status.text="Restore refused; source validation or locked layers prevented it.")
	recover_button.disabled=versions.item_count==0
	var published:=OptionButton.new();box.add_child(published)
	var backups_path: String=Library.folder().path_join("publish-backups")
	var dir:=DirAccess.open(backups_path)
	if dir!=null:
		var names:=dir.get_files();names.sort();names.reverse()
		for name in names:
			if name.begins_with("active-world-") and name.ends_with(".json"):
				published.add_item(name);published.set_item_metadata(published.item_count-1,name)
	var rollback_button: Button=e._btn("Roll back published PLAY world...",box,func():
		if not valid.call() or published.selected<0:return
		var path: String=backups_path.path_join(str(published.get_item_metadata(published.selected)))
		var confirm:=ConfirmationDialog.new();confirm.title="Restore historical published world?"
		confirm.dialog_text="Only the active PLAY world selection changes. Drafts and career saves stay unchanged. Archive and artwork integrity will be verified."
		window.add_child(confirm);confirm.confirmed.connect(func():
			if valid.call():
				show_result.call(_release_command(["--rollback",ProjectSettings.globalize_path(path),"--backup-dir",ProjectSettings.globalize_path(backups_path)]))
				_refresh_publication_ui()
			confirm.queue_free())
		confirm.canceled.connect(confirm.queue_free);confirm.popup_centered())
	rollback_button.disabled=published.item_count==0
	e._btn("Show current multiplayer world identity",box,func():
		status.text=JSON.stringify(WorldPublication.network_identity(),"  ")+"\nFriends must use the same game build and exact compiled map. Package checksums are not a live server or automatic download.")
	window.confirmed.connect(window.queue_free);window.canceled.connect(window.queue_free)
	window.popup_centered()
