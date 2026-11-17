extends SceneTree
## Simulate real mouse press/move/release through _input, not a geometry-only
## helper, to catch event-routing regressions in the native Map Builder.
const Multi=preload("res://scripts/dev/native_editor_multiselect.gd")
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("_run")

func check(label: String,ok: bool,details: Variant="") -> void:
	print("%s %s %s"%["PASS" if ok else "FAIL",label,str(details)])
	if not ok:failures.append(label)

func screen_to_m(e: Variant,screen: Vector2) -> Vector2:
	return e._event_world_position(screen)/20.0

func click(e: Variant,screen: Vector2,shift: bool=false) -> void:
	var down:=InputEventMouseButton.new()
	down.button_index=MOUSE_BUTTON_LEFT;down.position=screen
	down.pressed=true;down.shift_pressed=shift
	e._input(down)
	var up:=InputEventMouseButton.new()
	up.button_index=MOUSE_BUTTON_LEFT;up.position=screen
	up.pressed=false;up.shift_pressed=shift
	e._input(up)

func drag_box(e: Variant,from_screen: Vector2,to_screen: Vector2,shift: bool=false) -> bool:
	var press:=InputEventMouseButton.new()
	press.position=from_screen;press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true;press.shift_pressed=shift
	e._input(press)
	var started: bool=e.marquee_tracking
	var motion:=InputEventMouseMotion.new()
	motion.position=to_screen;motion.relative=to_screen-from_screen
	e._input(motion)
	var drawing: bool=e.gizmos.marquee_active
	var release:=InputEventMouseButton.new()
	release.position=to_screen;release.button_index=MOUSE_BUTTON_LEFT
	release.pressed=false;release.shift_pressed=shift
	e._input(release)
	return started and drawing and not e.marquee_tracking

func _run() -> void:
	var folder: String="res://.runtime/marquee-canvas-input-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH",folder+"/draft.json")
	var scene: Node=load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(scene)
	for i in 8:await process_frame
	var e: Variant=scene.native_world_editor
	e.map_switcher.map_name.text="Marquee native input"
	e.map_switcher.width.value=1200
	e.map_switcher.height.value=1000
	e.map_switcher.create_map(e)
	e._choose_tool("move_prop")
	var rect: Rect2=e.canvas_rect
	var begin: Vector2=rect.position+rect.size*Vector2(.24,.28)
	var finish: Vector2=rect.position+rect.size*Vector2(.67,.7)
	var spot_a: Vector2=rect.position+rect.size*Vector2(.35,.40)
	var spot_b: Vector2=rect.position+rect.size*Vector2(.55,.58)
	var spot_c: Vector2=rect.position+rect.size*Vector2(.81,.8)
	var a: String=e.authoring.add_prop("house",screen_to_m(e,spot_a))
	var b: String=e.authoring.add_prop("house",screen_to_m(e,spot_b))
	var c: String=e.authoring.add_prop("house",screen_to_m(e,spot_c))
	e._refresh_authoring()
	check("map_has_three_editable_assets",not a.is_empty() and not b.is_empty() and not c.is_empty())
	check("marquee_starts_inside_canvas_not_sidebar",e._canvas_pointer_available(begin) and
		not e._canvas_pointer_available(e.settings_panel.position+Vector2(20,20)))
	check("select_edit_direct_mouse_press_draws_box",drag_box(e,begin,finish))
	check("select_edit_marquee_selects_both_visible_assets",
		e.multi_selection.has(a) and e.multi_selection.has(b) and not e.multi_selection.has(c),e.multi_selection)
	check("select_edit_highlights_group",
		e.gizmos.group_selected_lookup.has(a) and e.gizmos.group_selected_lookup.has(b))
	e._choose_tool("select_box")
	check("box_select_can_begin_on_existing_building",drag_box(e,spot_a,finish))
	check("box_select_from_building_selects_entire_rectangle",
		e.multi_selection.has(a) and e.multi_selection.has(b) and not e.multi_selection.has(c),e.multi_selection)
	e._choose_tool("move_prop")
	check("switch_to_move_tool_preserves_group_for_drag",
		e.multi_selection.has(a) and e.multi_selection.has(b) and e.gizmos.group_selected_lookup.has(b))
	e._choose_tool("select_box")
	click(e,spot_a,true)
	check("shift_click_removes_one_member",not e.multi_selection.has(a) and e.multi_selection.has(b))
	click(e,spot_a,true)
	check("shift_click_restores_member",e.multi_selection.has(a) and e.multi_selection.has(b))
	# Baked scenery needs a rectangle query even before individual assets
	# have been converted to authored source objects.
	var baked: Dictionary={"props":[
		{"kind":"house","p":[50.0,50.0],"size":[12.0,17.0],"angle":0.0},
		{"kind":"house","p":[150.0,150.0],"size":[12.0,17.0],"angle":0.0},
		{"kind":"house","p":[53.0,52.0],"size":[12.0,17.0],"angle":PI*.25},
		{"kind":"shop","p":[56.0,50.0],"size":[12.0,17.0],"angle":0.0,"poi":1}]}
	var baked_hits: Array[int]=Multi.baked_indices_in_rect(baked,Rect2(Vector2(43,43),Vector2(15,15)))
	check("live_baked_and_rotated_buildings_are_marquee_candidates",
		baked_hits.size()==2 and baked_hits.has(0) and baked_hits.has(2) and not baked_hits.has(1))
	check("protected_baked_landmarks_are_excluded",not baked_hits.has(3))
	e._discard_draft()
	scene.queue_free()
	await process_frame
	print("NATIVE EDITOR MARQUEE INPUT: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
