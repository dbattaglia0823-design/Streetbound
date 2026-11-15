extends SceneTree
## The compact on-location race card exposes the real event and goes through
## the existing gated start method; it never starts from outside the marker.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(name: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL", name])
	if not okay:
		failures.append(name)

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var car: VehicleController2D = game.vehicle
	car.set_physics_process(false)
	var drag: Node = game.drag_race
	drag.set_physics_process(false)
	var hud: Control = drag.get("_status_strip")
	var card: PanelContainer = hud.get("start_panel")
	check("race_entry_card_is_under_half_concept_width",
		card.size.x <= 340.0 and card.size.y >= 320 and
		card.position.x > card.get_viewport_rect().size.x * .55)
	check("event_name_type_and_real_quarter_mile",
		str(card.get("name_label").text).contains("Ashford") and
		str(card.get("kind_label").text).contains("DRAG") and
		str(card.get("distance_label").text) == "0.25 MI")
	var art: Control = card.get("route_preview")
	var route: PackedVector2Array = art.get("route_m")
	check("hero_graphic_uses_true_staging_and_finish",
		route.size() == 2 and route[0].distance_to(drag.start_m) < .01 and
		route[1].distance_to(drag.start_m + drag.direction * 402.336) < .01)
	car.global_position = drag.start_m * 20.0
	car.rotation = drag.direction.angle() + PI / 2.0
	car.linear_velocity = Vector2.RIGHT * 7.0
	drag._refresh_overlay()
	check("above_15_mph_does_not_open_start_card",
		not card.visible and not drag.can_stage())
	car.linear_velocity = Vector2.RIGHT * 6.7056
	car.velocity = car.linear_velocity * 20.0
	drag._refresh_overlay()
	var button: Button = card.get("start_button")
	check("rolling_at_15_mph_opens_card_and_enables_start",
		card.visible and not button.disabled and
		button.text.contains("[F]") and not hud.get("panel").visible)
	button.pressed.emit()
	check("click_starts_same_race_as_F_with_zero_rolling_headstart",
		drag.state == "countdown" and car.linear_velocity.is_zero_approx() and
		car.velocity.is_zero_approx() and not card.visible and
		hud.get("panel").visible)
	drag.quit_race()
	hud.call("dismiss")
	drag._refresh_overlay()
	check("dismiss_preserves_race_state_and_shows_restore_chip",
		drag.state == "idle" and not card.visible and hud.get("restore_button").visible)
	hud.call("restore")
	check("restore_returns_to_start_event_card",
		card.visible and not hud.get("panel").visible)
	# Other race categories must expose actual distances and modes, not
	# illustrative entry fees or fictional prize values.
	for race in [game.circuit_race, game.street_race]:
		var other_hud: Control = race.get("status_strip")
		var other_card: PanelContainer = other_hud.get("start_panel")
		check(str(race.race_title) + "_real_route_and_practice_reward",
			float(other_card.get("data").get("distance_m", 0)) > 500.0 and
			str(other_card.get("rewards_label").text) == "PRACTICE" and
			other_card.get("route_preview").get("route_m").size() >= 2)
	print("RACE START SIDE PANEL: ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
