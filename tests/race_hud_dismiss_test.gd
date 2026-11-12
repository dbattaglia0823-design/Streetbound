extends SceneTree
## Regression for the three old overlapping and non-dismissible race popups.
## The new compact strip must not block gameplay or pop back after closing.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL", label])
	if not okay:
		failures.append(label)


func _check_strip(race: Node, hud: Control, title: String) -> void:
	check(title + "_hud_exists", is_instance_valid(hud) and
		hud.get("panel") is PanelContainer and hud.get("label") is Label)
	if not is_instance_valid(hud):
		return
	var panel: PanelContainer = hud.get("panel") as PanelContainer
	var close: Button = hud.get("close_button") as Button
	var restore: Button = hud.get("restore_button") as Button
	check(title + "_compact_near_top_not_center_screen",
		panel.position.y <= 24.0 and
		(panel.position.x > 395.0 if hud.get_viewport_rect().size.x > 1200.0 else panel.position.x >= 8.0) and
		panel.size.y <= 65.0 and panel.size.x <= 450.0)
	check(title + "_close_and_restore_are_real_buttons",
		close != null and restore != null and
		close.pressed.is_connected(Callable(hud, "dismiss")) and
		restore.pressed.is_connected(Callable(hud, "restore")))
	hud.call("set_status", "idle", true, "RACE / STOP / [ F ] START")
	check(title + "_can_be_shown_near_start", panel.visible)
	close.pressed.emit()
	check(title + "_close_actually_hides_hud",
		not panel.visible and restore.visible and bool(hud.get("dismissed")))
	hud.call("set_status", "idle", true, "RACE / [ F ] START")
	check(title + "_remains_closed_after_repeated_physics_updates",
		not panel.visible and restore.visible)
	hud.call("set_status", "running", true, "RACE / 13.42s")
	check(title + "_closing_does_not_reopen_mid_race", not panel.visible)
	restore.pressed.emit()
	check(title + "_can_be_reopened_without_restart",
		panel.visible and not restore.visible)
	hud.call("set_status", "running", true, "RACE / 14.92s")
	close.pressed.emit()
	hud.call("set_status", "results", true, "FINISH / +XP")
	check(title + "_results_respect_manual_close", not panel.visible)
	hud.call("set_status", "idle", false, "CLOSED")
	check(title + "_status_hides_when_far_from_event",
		not panel.visible and not restore.visible)
	hud.call("set_status", "countdown", true, "START IN 3")
	check(title + "_new_race_reopens_info",
		panel.visible and not bool(hud.get("dismissed")))
	hud.call("set_status", "idle", false, "IDLE")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var drag: Node = main.drag_race
	var circuit: Node = main.circuit_race
	var street: Node = main.street_race
	drag.set_physics_process(false)
	circuit.set_physics_process(false)
	street.set_physics_process(false)
	_check_strip(drag, drag.get("_status_strip") as Control, "drag")
	_check_strip(circuit, circuit.get("status_strip") as Control, "circuit")
	_check_strip(street, street.get("status_strip") as Control, "street")
	# The race still starts even if its information was closed before staging.
	var hud: Control = drag.get("_status_strip") as Control
	hud.call("set_status", "idle", true, "STAGING")
	hud.call("dismiss")
	car.global_position = drag.start_m * 20.0
	car.global_rotation = drag.direction.angle() + PI * 0.5
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	check("dismissed_hud_does_not_disable_race_start",
		drag.can_stage() and drag.start_race())
	drag._refresh_overlay()
	check("countdown_automatically_restores_status_for_new_race",
		not bool(hud.get("dismissed")) and (hud.get("panel") as PanelContainer).visible)
	hud.call("dismiss")
	drag._refresh_overlay()
	check("dismissed_hud_stays_closed_during_countdown",
		not (hud.get("panel") as PanelContainer).visible)
	check("closing_hud_does_not_stop_race",
		drag.state == "countdown")
	print("RACE HUD DISMISS AND POSITION: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
