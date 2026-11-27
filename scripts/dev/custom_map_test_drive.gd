extends Node2D
## Development-only launcher. Custom Test Drive must use the SAME main.tscn
## gameplay pipeline, not a hand-painted source-preview scene without junctions,
## traffic, streamed road markings, career UI, or vehicle features.
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Builder="res://tools/build_custom_test_world.py"

func _ready() -> void:
	if not (OS.has_feature("debug") or OS.has_feature("editor")):
		get_tree().call_deferred("change_scene_to_file","res://scenes/title_menu.tscn")
		return
	var file: String=str(get_tree().get_meta("streetbound_test_drive_map",""))
	if file.is_empty() or file.get_file()!=file or not file.ends_with(".world.json"):
		_fail(file,"No valid custom map selected for Test Drive.")
		return
	var source: Dictionary=Library.load_map(file)
	if not bool(source.get("customMap",false)) or not Session.new()._valid_source(source):
		_fail(file,"Save a valid custom map before Test Drive.")
		return
	# These files stay in user://; the shipped Morrow Coast archive, source
	# overlays and player career data are NEVER rebuilt or replaced.
	var input_path: String=Library.folder().path_join(file)
	var output_path: String=Library.folder().path_join(file+".test-drive.stream.json")
	if not FileAccess.file_exists(Builder):
		_fail(file,"The full Test Drive compiler is missing.")
		return
	var python: String="py" if OS.get_name()=="Windows" else "python3"
	var args: PackedStringArray=PackedStringArray([
		ProjectSettings.globalize_path(Builder),"--source",
		ProjectSettings.globalize_path(input_path),"--output",
		ProjectSettings.globalize_path(output_path),"--cache",
		ProjectSettings.globalize_path(output_path+".cache.json")])
	if OS.get_name()=="Windows":args.insert(0,"-3")
	# Never start on an archive from a prior saved revision if Python fails.
	if FileAccess.file_exists(output_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
	var output: Array=[]
	var exit_code: int=OS.execute(python,args,output,true)
	if exit_code!=0 or not FileAccess.file_exists(output_path):
		_fail(file,"Full Test Drive world build failed. %s"%str(output).left(260))
		return
	get_tree().set_meta("streetbound_test_drive_archive",output_path)
	get_tree().call_deferred("change_scene_to_file","res://scenes/main.tscn")


func _fail(file: String,reason: String) -> void:
	push_error(reason)
	get_tree().remove_meta("streetbound_test_drive_map")
	if get_tree().has_meta("streetbound_test_drive_cursor"):get_tree().remove_meta("streetbound_test_drive_cursor")
	if get_tree().has_meta("streetbound_test_drive_source_hash"):get_tree().remove_meta("streetbound_test_drive_source_hash")
	if get_tree().has_meta("streetbound_test_drive_archive"):
		get_tree().remove_meta("streetbound_test_drive_archive")
	if not file.is_empty():get_tree().set_meta("streetbound_editor_resume_map",file)
	get_tree().set_meta("streetbound_test_drive_error",reason)
	get_tree().call_deferred("change_scene_to_file","res://scenes/world_editor.tscn")
