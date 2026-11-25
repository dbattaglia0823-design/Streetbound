extends SceneTree
const Authored=preload("res://scripts/world/authored_race.gd")
const InteractionSpeed=preload("res://scripts/world/interaction_speed.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	for i in 8:await process_frame
	var player=game.vehicle;player.set_physics_process(false)
	# Isolate career state and keep the actual entry-fee/heat mechanics.
	var police: Node=game.police_pursuit
	police.set_physics_process(false)
	game.vehicle_ownership.persist_enabled=false
	game.vehicle_ownership.balance=32000
	game.vehicle_ownership.underground_reputation=6
	game.vehicle_damage_service.persist_enabled=false
	game.vehicle_damage_service.set_physics_process(false)
	game.vehicle_damage_service.repair_full()
	game.vehicle_damage_service.fuel.refill()
	game.vehicle_damage_service._apply_drive_condition()
	var flow: Node=game.ground.get_node("AmbientTraffic")
	flow.set_physics_process(false)
	flow.clear_traffic()
	var starting_xp: int=game.vehicle_ownership.player_xp
	var starting_balance: int=game.vehicle_ownership.balance
	var paid_entry_fees:=0
	var menu=game.pause_menu
	check("interaction_speed_is_exactly_15_mph",
		is_equal_approx(InteractionSpeed.MAX_SPEED_MPS,6.7056) and
		InteractionSpeed.allowed(6.7056) and
		not InteractionSpeed.allowed(6.71))
	menu.pause_game();check("quit_race_is_hidden_in_free_roam",not menu.quit_race_button.visible);menu.resume_game()
	var events: Array=[game.drag_race,game.circuit_race,game.street_race];events.append_array(game.extra_races)
	for race in events:
		race.set_physics_process(false)
		player.global_position=race.start_m*20;player.linear_velocity=Vector2.ZERO
		var forward: Vector2=race.direction if race==game.drag_race else race.heading
		player.rotation=forward.angle()+PI/2
		player.linear_velocity=forward*7.0
		check(str(race.race_title)+"_blocks_entry_above_15_mph",not race.can_stage())
		player.linear_velocity=forward*InteractionSpeed.MAX_SPEED_MPS
		player.velocity=player.linear_velocity*20.0
		var balance_before_stage: int=game.vehicle_ownership.balance
		check(str(race.race_title)+"_stages_while_rolling_at_15_mph",
			race.can_stage() and race.start_race() and
			player.linear_velocity.is_zero_approx() and
			player.velocity.is_zero_approx() and race.state=="countdown")
		paid_entry_fees+=balance_before_stage-int(game.vehicle_ownership.balance)
		menu.pause_game();check(str(race.race_title)+"_quit_available_during_countdown",menu.quit_race_button.visible)
		if race == events[0]:
			menu.pause_screen.controls["main_menu"].pressed.emit()
			check("leaving_active_race_requires_confirmation",
				menu.menu_state=="confirm" and paused and menu.confirmation_screen.visible)
			menu.back_to_pause()
			check("cancel_race_exit_returns_to_pause",
				menu.menu_state=="paused" and paused and menu.quit_race_button.visible)
		menu.quit_race_button.pressed.emit()
		check(str(race.race_title)+"_quit_resumes_free_driving",race.state=="idle" and not paused and not menu.quit_race_button.visible)
		player.global_position=race.start_m*20;player.linear_velocity=Vector2.ZERO;player.rotation=forward.angle()+PI/2
		balance_before_stage=game.vehicle_ownership.balance
		check(str(race.race_title)+"_can_restart_after_quitting",race.start_race())
		paid_entry_fees+=balance_before_stage-int(game.vehicle_ownership.balance)
		# All race types now teleport to their own starting grid (including
		# the offset player lane in a head-to-head drag race). Start this
		# off-course regression from the actual staged grid position.
		var grid_origin_m: Vector2=player.global_position/20.0
		race._physics_process(3.05)
		check(str(race.race_title)+"_countdown_reaches_running",race.state=="running")
		var side:=Vector2(-forward.y,forward.x)
		for step in range(1,31):
			player.global_position=(grid_origin_m+side*step)*20
			player.linear_velocity=side*5
			race._physics_process(.2)
		check(str(race.race_title)+"_does_not_cancel_away_from_route",race.state=="running")
		menu.pause_game();check(str(race.race_title)+"_quit_available_while_running",menu.quit_race_button.visible)
		menu.quit_race_button.pressed.emit()
		check(str(race.race_title)+"_quit_cleans_race_state",race.state=="idle" and not player.is_in_group("race_participant"))
		if race==game.drag_race or race==game.street_race or race in game.extra_races:check(str(race.race_title)+"_quit_clears_opponent",race.opponent==null)
		# Quitting a race does not clear an active pursuit. Confirm escape
		# before staging the next independent test event.
		if police.wanted_level>0:police._escape()
	var authored=Authored.new();authored.world=game.ground;authored.player=player
	authored.definition={"id":"race-test","name":"Editor Sprint","mode":"sprint","laps":1,"checkpoint_radius":4,"start_radius":8,"time_limit":0,"points":[{"x":2400,"y":3200},{"x":2450,"y":3200},{"x":2500,"y":3200}]}
	game.ground.add_child(authored);authored.set_physics_process(false)
	player.global_position=authored.start_m*20;player.rotation=PI/2
	player.linear_velocity=Vector2.RIGHT*7.0
	check("authored_race_denies_above_15_mph",not authored.can_stage())
	player.linear_velocity=Vector2.RIGHT*InteractionSpeed.MAX_SPEED_MPS
	player.velocity=player.linear_velocity*20.0
	check("authored_race_stages_at_15_mph",
		authored.available and authored.can_stage() and authored.start_race() and
		player.linear_velocity.is_zero_approx() and player.velocity.is_zero_approx())
	authored._physics_process(3.05)
	player.global_position=Vector2(2500,3200)*20;authored._physics_process(.016);authored._physics_process(.016)
	check("finish_cannot_skip_ordered_checkpoints",authored.state=="running" and authored.next_checkpoint==1)
	player.global_position=Vector2(2425,3200)*20;authored._physics_process(.016)
	for x in range(2426,2501):
		player.global_position=Vector2(x,3200)*20;player.linear_velocity=Vector2(5,0);authored._physics_process(.2)
		if authored.state=="results":break
	check("authored_race_finishes_after_ordered_gates",authored.state=="results")
	menu.pause_game();check("quit_race_is_hidden_after_finish",not menu.quit_race_button.visible);menu.resume_game()
	var circuits: Array=[]
	if FileAccess.file_exists("res://.runtime/race-editor-test/baked-races.json"):
		circuits=JSON.parse_string(FileAccess.get_file_as_string("res://.runtime/race-editor-test/baked-races.json"))
	if not circuits.is_empty():
		var circuit=Authored.new();circuit.world=game.ground;circuit.player=player;circuit.definition=circuits[0]
		game.ground.add_child(circuit);circuit.set_physics_process(false)
		player.global_position=circuit.start_m*20;player.rotation=circuit.heading.angle()+PI/2;player.linear_velocity=Vector2.ZERO
		check("baked_editor_circuit_loads_and_stages",circuit.available and circuit.start_race())
		circuit._physics_process(3.05)
		var gates: PackedVector2Array=circuit.checkpoints.duplicate();gates.remove_at(0);gates.append(circuit.start_m)
		for lap_index in int(circuit.definition.laps):
			for gate in gates:
				var from: Vector2=player.global_position/20
				var steps:=ceili(from.distance_to(gate)/2)
				for i in range(1,steps+1):
					player.global_position=from.lerp(gate,float(i)/steps)*20;player.linear_velocity=(gate-from).normalized()*40
					circuit._physics_process(.05)
					if circuit.state=="results":break
			check("editor_circuit_lap_%d_progresses_in_order"%[lap_index+1],circuit.state==("results" if lap_index==int(circuit.definition.laps)-1 else "running"))
		check("baked_editor_circuit_completes_all_configured_laps",circuit.state=="results" and circuit.lap==int(circuit.definition.laps))
	check("quitting_and_editor_time_trials_award_no_unearned_rewards",game.vehicle_ownership.player_xp==starting_xp and game.vehicle_ownership.balance==starting_balance-paid_entry_fees)
	if DisplayServer.get_name()!="headless":
		authored.state="idle";player.global_position=authored.start_m*20;player.linear_velocity=Vector2.ZERO;player.rotation=PI/2;authored.start_race();menu.pause_game()
		for i in 3:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://.runtime/race-editor-test/pause.png");menu.quit_race_button.pressed.emit()
	game.queue_free();await process_frame;await process_frame
	print("RACE PAUSE BEHAVIOR: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
