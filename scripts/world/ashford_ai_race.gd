extends "res://scripts/world/ashford_drag_race.gd"
## First 1v1 race prototype. Preserves the proven Ashford staging, timing,
## anti-teleport checks, and race progression while introducing a physical rival.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const DriverScript = preload("res://scripts/world/race_ai_driver.gd")
const NavigationScript = preload("res://scripts/world/race_navigation.gd")
const GuidanceScript = preload("res://scripts/world/race_guidance.gd")
const RIVAL_LANE_OFFSET_M := 4.1
var opponent: VehicleController2D
var opponent_driver: Node
var opponent_progress_m := 0.0
var opponent_elapsed := -1.0
var navigation: RefCounted
var world_guidance: Node2D


func _ready() -> void:
	super._ready()
	if not available:
		return
	navigation = NavigationScript.new()
	navigation.setup(PackedVector2Array([
		start_m, start_m + direction * QUARTER_MILE_M]), false)
	world_guidance = Node2D.new()
	world_guidance.name = "DragRacingLine"
	world_guidance.set_script(GuidanceScript)
	world_guidance.set("navigation", navigation)
	world_guidance.set("player", player)
	add_child(world_guidance)



func can_stage() -> bool:
	# A head-to-head race must not grant a free 15-metre head start.
	return super.can_stage() and absf(_local_position().x) <= 4.0


func start_race() -> bool:
	if not can_stage() or get_tree().paused:
		return false
	if not _spawn_opponent():
		return false
	if not super.start_race():
		_clear_opponent()
		return false
	opponent_progress_m = 0.0
	opponent_elapsed = -1.0
	return true


func _spawn_opponent() -> bool:
	_clear_opponent()
	if not is_instance_valid(player) or not is_instance_valid(world):
		return false
	opponent = VehicleScene.instantiate() as VehicleController2D
	if opponent == null:
		return false
	opponent.name = "AshfordRival"
	opponent.external_input = true
	opponent.surface_provider = world
	# The exact equipped chassis and upgrades; never modify physics to catch up.
	opponent.config = player.config.duplicate(true)
	opponent.collision_layer = 1
	opponent.collision_mask = 3
	opponent.z_index = 8
	opponent.add_to_group("race_opponent")
	add_child(opponent)
	var right := direction.orthogonal().normalized()
	var player_side := (player.global_position / PPM - start_m).dot(right)
	var rival_lane := -RIVAL_LANE_OFFSET_M if player_side >= 0.0 else RIVAL_LANE_OFFSET_M
	opponent.global_position = (start_m + right * rival_lane) * PPM
	opponent.global_rotation = direction.angle() + PI * 0.5
	opponent.reset_physics_interpolation()
	# Reflect the player's selected car artwork, wheel profile and dimensions.
	var source_wheels := player.get_node_or_null("Art/Wheels")
	var rival_wheels := opponent.get_node_or_null("Art/Wheels")
	if source_wheels != null and rival_wheels != null:
		var profile: Resource = source_wheels.get("appearance") as Resource
		if profile != null:
			rival_wheels.call("apply_appearance", profile.duplicate(true))
	var source_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var rival_shape := opponent.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if source_shape != null and rival_shape != null and source_shape.shape != null:
		rival_shape.shape = source_shape.shape.duplicate(true)
	var rival_sprite := opponent.get_node_or_null("Art/Sprite") as Sprite2D
	if rival_sprite != null:
		rival_sprite.modulate = Color(0.69, 0.85, 1.0)
	opponent_driver = Node.new()
	opponent_driver.name = "RivalWaypointDriver"
	opponent_driver.set_script(DriverScript)
	add_child(opponent_driver)
	var origin := opponent.global_position
	opponent_driver.call("setup", opponent, PackedVector2Array([
		origin, origin + direction * QUARTER_MILE_M * PPM,
		origin + direction * (QUARTER_MILE_M + 65.0) * PPM]))
	move_child(opponent_driver, 0)
	return true


func _clear_opponent() -> void:
	if is_instance_valid(opponent_driver):
		opponent_driver.call("stop")
		opponent_driver.queue_free()
	if is_instance_valid(opponent):
		opponent.collision_layer = 0
		opponent.collision_mask = 0
		opponent.hide()
		opponent.queue_free()
	opponent_driver = null
	opponent = null


func _update_opponent_progress() -> void:
	if not is_instance_valid(opponent) or opponent_elapsed >= 0.0:
		return
	var delta_m := opponent.global_position / PPM - start_m
	opponent_progress_m = maxf(0.0, delta_m.dot(direction))
	if opponent_progress_m >= QUARTER_MILE_M and \
			absf(delta_m.cross(direction)) <= LANE_HALF_WIDTH_M:
		opponent_elapsed = elapsed
		if is_instance_valid(opponent_driver):
			opponent_driver.call("stop")


func _physics_process(dt: float) -> void:
	if is_instance_valid(world_guidance):
		world_guidance.set_guidance(navigation, player, state in ["countdown", "running"])
	var before := state
	if state == "running":
		_update_opponent_progress()
	super._physics_process(dt)
	if before == "countdown" and state == "running" and \
			is_instance_valid(opponent_driver):
		opponent_driver.call("launch")
	if state in ["results", "aborted"] and is_instance_valid(opponent_driver):
		opponent_driver.call("stop")
	if before in ["results", "aborted"] and state == "idle":
		_clear_opponent()


func _complete() -> void:
	if state != "running":
		return
	if is_instance_valid(opponent_driver):
		opponent_driver.call("stop")
	if opponent_elapsed >= 0.0 and opponent_elapsed <= elapsed:
		state = "results"
		_status_clock = 8.0
		_result_text = "RIVAL WINS  %.2fs  /  YOU %.2fs\nSECOND PLACE / NO WIN REWARDS" % [
			opponent_elapsed, elapsed]
		race_finished.emit({"result":"lost", "player_seconds":elapsed,
			"opponent_seconds":opponent_elapsed})
		_refresh_overlay()
		return
	# The original physical finish validation and one-time XP award stay intact.
	super._complete()
	_result_text = "YOU WIN / PLAYER VS AI\n" + _result_text
	_refresh_overlay()


func _refresh_overlay() -> void:
	super._refresh_overlay()
	if _race_label == null or not available or not _race_panel.visible:
		return
	match state:
		"idle":
			_race_label.text = "ASHFORD  /  1V1 QUARTER-MILE\n%s" % (
				"PARK AT START / FACE STRIP / [ F ] TO RACE" if can_stage()
				else "DRIVE TO THE DRAG STRIP AND STOP AT STAGING")
		"countdown":
			_race_label.text = "ASHFORD  /  PLAYER VS AI\nLIGHTS IN %d" % maxi(1, ceili(countdown))
		"running":
			_race_label.text = "ASHFORD  /  %.2fs  /  PLAYER %.0fm\nRIVAL %.0fm   /   FINISH %.0fm" % [
				elapsed, maxf(0.0, progress_m), opponent_progress_m, QUARTER_MILE_M]
