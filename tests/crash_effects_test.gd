extends SceneTree
## Regression for no parking-speed crash VFX, scaled sparks/debris, stable world
## contact coordinates, bounded bursts, resets, and real wall collisions.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const Fx = preload("res://scripts/visual/crash_effects.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,str(detail)])
	if not ok:failures.append(label)

func run() -> void:
	var below: Dictionary=Fx.impact_profile(6.69,16.0)
	var barely: Dictionary=Fx.impact_profile(6.7,2.19)
	var soft: Dictionary=Fx.impact_profile(7.0,3.0)
	var medium: Dictionary=Fx.impact_profile(15.0,10.0)
	var heavy: Dictionary=Fx.impact_profile(34.0,24.0)
	check("parking_speed_has_no_crash_effects",below.is_empty())
	check("grazing_contact_has_no_crash_effects",barely.is_empty())
	check("valid_moderate_and_high_speed_have_effect_profiles",
		not soft.is_empty() and not medium.is_empty() and not heavy.is_empty())
	check("spark_debris_and_flash_scale_up_with_impact",
		int(soft.get("sparks",0)) < int(medium.get("sparks",0)) and
		int(medium.get("sparks",0)) < int(heavy.get("sparks",0)) and
		int(soft.get("debris",0)) < int(heavy.get("debris",0)) and
		float(soft.get("flash_radius",0)) < float(heavy.get("flash_radius",0)))
	check("visual_particle_count_is_bounded",
		int(heavy.get("sparks",999))<=36 and int(heavy.get("debris",999))<=14 and
		int(heavy.get("dust",999))<=8 and Fx.MAX_PARTICLES<=160)
	var car: VehicleController2D=VehicleScene.instantiate()
	car.position=Vector2(200,1000)
	car.rotation=PI*.5
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	var fx: Node2D=car.get_node_or_null("CrashEffects")
	check("every_drivable_vehicle_has_crash_effects",fx!=null and fx.top_level)
	if fx==null:
		car.queue_free()
		print("CRASH EFFECTS: FAIL "+str(failures))
		quit(1)
		return
	car.crash_contact.emit(9.0,Vector2(225,1000),Vector2.LEFT,Vector2.RIGHT*6.0)
	check("low_speed_contact_emits_no_particles",
		fx.get("particles").is_empty() and fx.get("flashes").is_empty() and
		int(fx.get("emitted_bursts"))==0)
	car.crash_contact.emit(1.5,Vector2(225,1000),Vector2.LEFT,Vector2.RIGHT*18.0)
	check("fast_scrape_creates_only_small_guardrail_sparks",
		fx.get("particles").size()>0 and
		fx.get("particles").all(func(p):return p.kind=="spark"))
	var origin:=Vector2(225,1000)
	fx.call("_process",0.05)
	fx.call("_process",0.05)
	car.crash_contact.emit(10.0,origin,Vector2.LEFT,Vector2.RIGHT*18.0)
	var particles: Array=fx.get("particles")
	check("fast_contact_has_sparks_debris_smoke_and_flash",
		particles.any(func(p):return p.kind=="spark") and
		particles.any(func(p):return p.kind=="debris") and
		particles.any(func(p):return p.kind=="dust") and
		not fx.get("flashes").is_empty(),particles.size())
	# The earlier guardrail scrape intentionally leaves short-lived sparks
	# in the same particle pool. Inspect a fragment from this heavier event,
	# rather than assuming array index zero belongs to the latest collision.
	check("particles_spawn_at_world_collision_point",
		particles.any(func(p):return p.kind=="debris" and
			Vector2(p.point).distance_to(origin)<6.0))
	var first_burst: int=int(fx.get("emitted_bursts"))
	car.crash_contact.emit(16.0,origin,Vector2.LEFT,Vector2.RIGHT*28.0)
	check("same_frame_contacts_do_not_spam_effects",int(fx.get("emitted_bursts"))==first_burst)
	# Moving the car must not drag the burst away from the wall.
	car.position+=Vector2(100,0)
	fx.call("_process",0.02)
	check("crash_particles_remain_at_world_contact",
		Vector2(fx.get("particles")[0].point).distance_to(origin)<20.0)
	var art: Node=car.get_node("Art")
	art.call("_on_impact",5.0)
	check("low_speed_impact_has_no_body_shake",float(art.get("_impact"))==0.0)
	art.call("_on_impact",15.0)
	check("high_speed_impact_still_jolts_body",float(art.get("_impact"))>0.0)
	for i in 100:
		fx.call("_process",0.05)
	check("effects_fade_without_leaks",fx.get("particles").is_empty() and fx.get("flashes").is_empty())
	# Multiple hard crashes cannot grow the draw list without bound.
	for i in 12:
		fx.call("_process",.21)
		car.crash_contact.emit(24.0,origin,Vector2.LEFT,Vector2.RIGHT*32.0)
	check("repeated_impacts_stay_within_particle_and_flash_limits",
		fx.get("particles").size()<=Fx.MAX_PARTICLES and
		fx.get("flashes").size()<=Fx.MAX_FLASHES)
	car.reset_vehicle()
	check("reset_clears_crash_particles_and_flash",
		fx.get("particles").is_empty() and fx.get("flashes").is_empty())
	# Confirm the actual move_and_collide path publishes contact details and
	# generates effects. No synthetic signal required for this case.
	var barrier:=StaticBody2D.new()
	barrier.position=Vector2(270,1000)
	var blocker:=CollisionShape2D.new()
	var box:=RectangleShape2D.new()
	box.size=Vector2(20,320)
	blocker.shape=box
	barrier.add_child(blocker)
	root.add_child(barrier)
	await physics_frame
	car.position=Vector2(200,1000)
	car.rotation=PI*.5
	car.linear_velocity=Vector2.RIGHT*18.0
	var hits: Array[float]=[]
	car.crash_contact.connect(func(speed: float,_point: Vector2,_normal: Vector2,_vel: Vector2):
		hits.append(speed))
	for frame in 40:
		await physics_frame
		car.step_vehicle(1.0/60.0,Vector4.ZERO)
		if not hits.is_empty():break
	check("real_barrier_collision_emits_contact_data",not hits.is_empty(),hits)
	check("real_fast_barrier_collision_triggers_sparks",
		int(fx.get("emitted_bursts"))>first_burst and
		not fx.get("particles").is_empty())
	barrier.queue_free()
	car.queue_free()
	await process_frame
	print("CRASH EFFECTS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
