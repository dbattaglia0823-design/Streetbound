extends SceneTree
## Phase 2: real slipstream drag, aligned wakes, engine/exhaust visuals,
## bounded camera effects and compatible host cosmetic state replication.
const Draft = preload("res://scripts/vehicle/drafting_aerodynamics.gd")
const Exhaust = preload("res://scripts/visual/driving_exhaust.gd")
const Wake = preload("res://scripts/visual/driving_slipstream.gd")
const Online = preload("res://scripts/network/online_world.gd")
const CameraScript = preload("res://scripts/camera/driving_camera.gd")
const VehicleScene = preload("res://scenes/vehicle.tscn")
var failures: Array[String]=[]

class Road extends Node2D:
	func surface_at(_p: Vector2) -> Dictionary:
		return {"name":"ASPHALT","grip":1.0}

func _initialize() -> void:
	call_deferred("run")

func check(name: String, good: bool, detail: Variant="") -> void:
	print("%s %s %s" % ["PASS" if good else "FAIL",name,str(detail)])
	if not good:
		failures.append(name)

func _strength(at: Vector2,heading: float,velocity: Vector2,
		leader_at: Vector2=Vector2(0,-200),leader_heading: float=0.0,
		leader_velocity: Vector2=Vector2(0,-33)) -> float:
	return Draft.strength_for(at,heading,velocity,leader_at,leader_heading,
		leader_velocity)

func run() -> void:
	var strong := _strength(Vector2.ZERO,0.0,Vector2(0,-34))
	check("aligned_high_speed_pair_has_full_draft",strong>.98,strong)
	check("draft_always_reduces_only_aero_drag_by_bounded_fraction",
		is_equal_approx(Draft.aero_drag_multiplier(1.0),.82) and
		is_equal_approx(Draft.aero_drag_multiplier(0.0),1.0) and
		is_equal_approx(Draft.aero_drag_multiplier(100.0),.82))
	check("cannot_draft_a_parked_car",
		_strength(Vector2.ZERO,0.0,Vector2(0,-30),
			Vector2(0,-200),0.0,Vector2.ZERO)==0.0)
	check("no_low_speed_drafting",
		_strength(Vector2.ZERO,0.0,Vector2(0,-8))==0.0)
	check("opposite_way_and_reverse_have_zero_draft",
		_strength(Vector2.ZERO,PI,Vector2(0,34))==0.0 and
		_strength(Vector2.ZERO,0.0,Vector2(0,34))==0.0)
	check("side_by_side_cars_and_adjacent_lanes_get_no_draft",
		_strength(Vector2.ZERO,0.0,Vector2(0,-34),
			Vector2(0,-200)+Vector2(90,0))==0.0 and
		_strength(Vector2.ZERO,0.0,Vector2(0,-34),
			Vector2(0,0))==0.0)
	check("distant_cars_do_not_draft",
		_strength(Vector2.ZERO,0.0,Vector2(0,-34),
			Vector2(0,-800))==0.0)
	check("drafting_fades_with_distance_and_lane_offset",
		_strength(Vector2.ZERO,0.0,Vector2(0,-34),
			Vector2(0,-600))<strong and
		_strength(Vector2.ZERO,0.0,Vector2(0,-34),
			Vector2(42,-200))<strong)
	check("drafting_reacts_to_wheel_alignment",
		_strength(Vector2.ZERO,.35,Vector2(0,-34))<strong)

	var road := Road.new()
	root.add_child(road)
	var leader := VehicleScene.instantiate() as VehicleController2D
	leader.external_input=true
	leader.surface_provider=road
	leader.position=Vector2(0,-220)
	root.add_child(leader)
	leader.set_physics_process(false)
	leader.linear_velocity=Vector2(0,-35)
	var follower := VehicleScene.instantiate() as VehicleController2D
	follower.external_input=true
	follower.surface_provider=road
	root.add_child(follower)
	follower.set_physics_process(false)
	follower.linear_velocity=Vector2(0,-34)
	check("all_racing_cars_have_slipstream_exhaust_scene_nodes",
		follower.get_node_or_null("Slipstream")!=null and
		follower.get_node_or_null("ExhaustEffects")!=null and
		follower.is_in_group("drafting_vehicle"))
	var direct := Draft.best_strength(follower)
	check("real_wake_scanner_finds_a_leading_racer",direct>.8,direct)
	for i in 8:
		follower.step_vehicle(1.0/60.0,Vector4.ZERO)
	check("vehicle_physics_uses_cached_smoothed_draft",
		follower.draft_strength>.3 and follower.draft_strength<=1.0,
		follower.draft_strength)
	check("leading_car_has_visible_wake_only_while_followed",
		Draft.wake_strength(leader,road,leader.linear_velocity)>.8)
	var wake: Node2D=leader.get_node("Slipstream")
	wake._process(.05)
	check("bounded_wake_visuals_are_reactive",
		wake.wake_intensity>0.0 and Wake.WAKE_LINES<=8)
	leader.position=Vector2(1200,-220)
	check("wake_disappears_after_separation",
		Draft.best_strength(follower)==0.0 and
		Draft.wake_strength(leader,road,leader.linear_velocity)==0.0)
	follower.reset_vehicle()
	check("reset_clears_previous_drafting_advantage",
		is_equal_approx(follower.draft_strength,0.0))
	
	var config: VehicleConfig=follower.config
	config.boost_max_psi=16.0
	config.audio_overrun=.85
	var exhaust: Node2D=follower.get_node("ExhaustEffects")
	check("configured_combustion_engines_can_backfire",
		Exhaust.should_backfire(config,5000,25.0,true,false) and
		Exhaust.should_backfire(config,5000,25.0,false,true))
	check("idle_or_low_speed_cannot_backfire",
		not Exhaust.should_backfire(config,1000,25.0,true,true) and
		not Exhaust.should_backfire(config,5000,2.0,true,true))
	config.audio_induction="electric"
	check("EVs_never_backfire_from_overrun",
		not Exhaust.should_backfire(config,5000,25.0,true,true))
	config.audio_induction="turbocharged"
	follower.linear_velocity=Vector2.UP*25.0
	follower.transmission.rpm=4900.0
	follower.throttle=.92
	exhaust._process(.05)
	follower.throttle=.02
	exhaust._process(.05)
	check("turbo_lift_off_spawns_exhaust_burst",
		exhaust.emitted_bursts>0 and not exhaust.particles.is_empty())
	follower.nitrous_active=true
	for i in 70:
		exhaust._process(.05)
	check("nitrous_uses_a_capped_blue_visual_particle_pool",
		exhaust.particles.size()<=Exhaust.MAX_PARTICLES and
		exhaust.particles.any(func(item: Dictionary):return str(item.kind)=="nitrous"))
	follower.reset_vehicle()
	check("vehicle_reset_clears_all_old_exhaust_puffs",
		exhaust.particles.is_empty())

	var cam: Camera2D=Camera2D.new()
	cam.set_script(CameraScript)
	cam.target=follower
	root.add_child(cam)
	follower.linear_velocity=Vector2.UP*35.0
	follower.transmission.shifted.emit(2)
	check("gearshift_adds_short_lived_camera_impulse",cam._shift_pulse>.0)
	var standard_zoom: float=CameraScript.target_zoom_for(34.0,1.0,1.2)
	var boosted_zoom: float=CameraScript.target_zoom_for(34.0,1.0,1.2,0.0,0.0,.8,1.0,.8)
	check("boost_and_drafting_widen_camera_without_exceeding_limits",
		boosted_zoom<standard_zoom and boosted_zoom>=CameraScript.ABSOLUTE_ZOOM_MIN)
	for i in 70:
		cam._physics_process(.016)
	check("shift_camera_impulse_decays_instead_of_accumulating",
		cam._shift_pulse<.01)

	var visual_snapshot: Array=Online._exhaust_state(follower)
	check("multiplayer_cosmetic_snapshot_is_optional_and_validated",
		visual_snapshot.size()==5 and Online.valid_exhaust_state(visual_snapshot) and
		not Online.valid_exhaust_state([true,INF,.8,4500,2]) and
		not Online.valid_exhaust_state([true,8.0,.4,4500,99]))
	check("multiplayer_movement_snapshot_still_has_exactly_six_fields",
		Online._car_state(follower).size()==6)
	print("DRIVING PHASE 2 FX: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
