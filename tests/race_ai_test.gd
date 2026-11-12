extends SceneTree
## First hands-on race regression: drive-up trigger, identical physical vehicle
## capabilities, AI inputs without rubber-banding, and win/loss accounting.
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, value: bool) -> void:
	print("%s %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures.append(label)


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	check("main_scene_exists", scene != null)
	if scene == null:
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	await physics_frame
	var race: Node2D = main.drag_race
	var player: VehicleController2D = main.vehicle
	check("ashford_AI_race_installed",
		race != null and race.get_script() == load("res://scripts/world/ashford_ai_race.gd"))
	if race == null:
		quit(1)
		return
	var money := Ownership.new(false)
	race.economy = money
	player.set_physics_process(false)
	race.set_physics_process(false)
	check("rival_does_not_spawn_during_free_roam",race.get("opponent") == null)
	check("cannot_start_from_garage",not race.can_stage())
	player.global_position = race.start_m * 20.0
	player.rotation = race.direction.angle() + PI * 0.5
	player.linear_velocity = Vector2.ZERO
	player.velocity = Vector2.ZERO
	check("driving_to_strip_allows_staging",race.can_stage())
	check("F_action_starts_one_race_only",race.start_race() and not race.start_race())
	var rival: VehicleController2D = race.get("opponent") as VehicleController2D
	var driver: Node = race.get("opponent_driver") as Node
	check("real_rival_vehicle_and_waypoint_driver_spawned",
		is_instance_valid(rival) and is_instance_valid(driver))
	if not is_instance_valid(rival) or not is_instance_valid(driver):
		quit(1)
		return
	rival.set_physics_process(false)
	driver.set_physics_process(false)
	check("rival_is_externally_driven_with_world_surface",
		rival.external_input and rival.surface_provider == main.ground)
	check("rival_has_independent_identical_vehicle_specs",
		rival.config != player.config and
		is_equal_approx(rival.config.engine_torque_nm,player.config.engine_torque_nm) and
		is_equal_approx(rival.config.engine_power_kw,player.config.engine_power_kw) and
		is_equal_approx(rival.config.tire_grip,player.config.tire_grip) and
		is_equal_approx(rival.config.mass_kg,player.config.mass_kg))
	check("rival_is_on_a_separate_asphalt_lane",
		rival.global_position.distance_to(player.global_position) > 3.0 * 20.0 and
		str(main.ground.surface_at(rival.global_position).name) == "ASPHALT")
	check("countdown_does_not_award_race_prizes",
		race.state == "countdown" and money.player_xp == 0)
	race._physics_process(3.05)
	check("legal_countdown_releases_AI",race.state == "running" and driver.get("active"))
	driver._physics_process(0.10)
	check("AI_has_fixed_launch_reaction",rival.command.x == 0.0)
	driver._physics_process(0.60)
	driver._physics_process(0.016)
	var initial_gas := rival.command.x
	check("AI_accelerates_through_real_control_input",
		initial_gas > 0.0 and initial_gas <= float(driver.get("throttle_limit")))
	# A 200m deficit must NEVER grant power/grip/throttle beyond what the
	# exact same AI driver requested at the front of the route.
	rival.global_position -= race.direction * 200.0 * 20.0
	driver._physics_process(0.016)
	check("no_rubberband_after_falling_behind",
		is_equal_approx(rival.command.x,initial_gas) and
		is_equal_approx(rival.config.engine_torque_nm,player.config.engine_torque_nm) and
		is_equal_approx(rival.config.tire_grip,player.config.tire_grip))
	var cash_before := money.balance
	race.elapsed = 14.0
	race.opponent_elapsed = 12.5
	race.state = "running"
	race._complete()
	check("finishing_second_is_recorded_as_loss",
		race.state == "results" and race.get("_result_text").contains("RIVAL WINS"))
	check("loss_does_not_grant_cash_or_XP",
		money.player_xp == 0 and money.balance == cash_before)
	# Keep an isolated economy so this test cannot overwrite a real save.
	race.state = "idle"
	player.global_position = race.start_m * 20.0
	player.linear_velocity = Vector2.ZERO
	player.velocity = Vector2.ZERO
	check("race_can_be_restarted_after_loss",race.start_race())
	race._physics_process(3.05)
	race.elapsed = 14.0
	race.opponent_elapsed = -1.0
	race.state = "running"
	race._complete()
	check("player_winning_awards_real_race_progression",
		race.state == "results" and money.player_xp > 0 and
		race.get("_result_text").contains("YOU WIN"))
	var earned := money.player_xp
	race._complete()
	check("completing_same_race_twice_does_not_mint_XP",money.player_xp == earned)
	print("ASHFORD HEAD TO HEAD AI: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
