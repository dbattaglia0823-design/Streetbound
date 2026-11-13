extends Node
## Application-level scene navigation. No world objects or career state are
## duplicated just to display a menu. Unit tests can still instantiate the
## standalone res://scenes/main.tscn scene as before.
const TITLE := "res://scenes/title_menu.tscn"
const WORLD := "res://scenes/main.tscn"
var pending_mode := ""
var last_error := ""

func supports_native_editor() -> bool:
	# Source editing and Python-rebake tools never appear in release exports.
	return OS.has_feature("editor") or OS.has_feature("debug")

func start_game(mode: String = "play") -> bool:
	if mode not in ["play","map_editor","multiplayer"]:
		last_error = "Unknown play mode."
		return false
	if mode == "map_editor" and not supports_native_editor():
		last_error = "Map Editor is available in development builds only."
		return false
	if mode == "multiplayer" and Input.get_connected_joypads().is_empty():
		last_error = "Connect a controller for local split-screen."
		return false
	pending_mode = mode
	last_error = ""
	get_tree().paused = false
	var error := get_tree().change_scene_to_file(WORLD)
	if error != OK:
		pending_mode = ""
		last_error = "Could not open Streetbound: "+error_string(error)
		return false
	return true

func consume_launch_mode() -> String:
	var result := pending_mode
	pending_mode = ""
	return result

func return_to_title() -> bool:
	pending_mode = ""
	get_tree().paused = false
	var error := get_tree().change_scene_to_file(TITLE)
	if error != OK:
		last_error = "Could not open the main menu: "+error_string(error)
		return false
	last_error = ""
	return true
