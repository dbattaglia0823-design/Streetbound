extends Node2D
## Development-only launcher. Custom Test Drive must use the SAME main.tscn
## gameplay pipeline, not a hand-painted source-preview scene without junctions,
## traffic, streamed road markings, career UI, or vehicle features.
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Builder="res://tools/build_custom_test_world.py"
var build_thread: Thread
var build_file: String
var build_output: String
var build_source: String
var build_source_sha: String
var loading_label: Label
var started_ms:=0

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
	build_file=file;build_output=output_path;build_source=input_path
	build_source_sha=FileAccess.get_sha256(input_path)
	started_ms=Time.get_ticks_msec()
	var canvas:=CanvasLayer.new();add_child(canvas)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.add_child(center)
	loading_label=Label.new();loading_label.text="Preparing Test Drive…";center.add_child(loading_label)
	build_thread=Thread.new()
	var error:=build_thread.start(_run_compiler.bind(python,args))
	if error!=OK:
		build_thread=null;_fail(file,"Could not start Test Drive compiler.")

static func _run_compiler(python: String,args: PackedStringArray) -> Dictionary:
	var output: Array=[]
	var code:=OS.execute(python,args,output,true)
	return {"code":code,"output":str(output).left(260)}

func _process(_dt: float) -> void:
	if build_thread==null:return
	loading_label.text="Preparing Test Drive… %.1f s"%((Time.get_ticks_msec()-started_ms)/1000.0)
	if build_thread.is_alive():return
	var result: Dictionary=build_thread.wait_to_finish()
	build_thread=null
	if int(result.code)!=0 or not FileAccess.file_exists(build_output):
		_fail(build_file,"Full Test Drive world build failed. "+str(result.output));return
	if FileAccess.get_sha256(build_source)!=build_source_sha:
		_fail(build_file,"Saved source changed during Test Drive preparation. Save and retry.");return
	get_tree().set_meta("streetbound_test_drive_archive",build_output)
	get_tree().call_deferred("change_scene_to_file","res://scenes/main.tscn")

func _exit_tree() -> void:
	if build_thread!=null and build_thread.is_started():build_thread.wait_to_finish()


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
