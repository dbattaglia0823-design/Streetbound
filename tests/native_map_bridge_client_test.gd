extends SceneTree
## Test the actual Godot HTTPRequest handshake while the editor scene is paused.
## A Python harness hosts an isolated copy of the source and playable archive.
const Session = preload("res://scripts/dev/native_map_edit_session.gd")
const Bridge = preload("res://scripts/dev/native_map_bridge.gd")
var failures: Array[String] = []
var bridge

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL",label])
	if not okay:
		failures.append(label)

func _run() -> void:
	var source = Session.new()
	check("client_reads_authoritative_source",source.load_source())
	if source.doc.is_empty():
		quit(1)
		return
	var new_id: String = source.add_prop("tree",Vector2(2420,3040))
	check("client_prepares_valid_undoable_source_change",not new_id.is_empty() and source.dirty)
	bridge = Bridge.new()
	root.add_child(bridge)
	bridge.completed.connect(_on_completed)
	var version: String = FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	paused = true
	check("native_http_client_starts_while_scene_is_paused",
		bridge.apply_source(source.doc,source.baseline_hash,version))
	if not failures.is_empty():
		paused = false
		quit(1)

func _on_completed(ok: bool, message: String, new_sha: String) -> void:
	check("real_native_http_handshake_and_rebuild_completed",ok)
	check("backend_emits_new_world_revision",new_sha.length()==64)
	check("bridge_unlocked_after_transaction",bridge.phase=="")
	if not ok:
		print("BRIDGE FAILURE: ",message)
	paused = false
	print("NATIVE BRIDGE HTTP ROUNDTRIP: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
