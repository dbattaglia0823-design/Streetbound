extends SceneTree
## Phase 3 surface/weather contract; dry behavior, source independent.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const Conditions = preload("res://scripts/world/weather_conditions.gd")
const Dust = preload("res://scripts/visual/driving_dust.gd")
const Crashes = preload("res://scripts/visual/crash_effects.gd")
const WetVisuals = preload("res://scripts/visual/wet_road_effects.gd")
var failures: Array[String] = []

class Surface extends Node2D:
	var rain_intensity := 0.0
	func get_rain_intensity() -> float:
		return rain_intensity
	func surface_at(_p: Vector2) -> Dictionary:
		return {"name":"ASPHALT","grip":1.0}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures.append(label)

func run() -> void:
	var map := Surface.new()
	root.add_child(map)
	check("dry_surface_preserves_original_grip",
		Conditions.grip_multiplier("ASPHALT",0.0)==1.0 and
		Conditions.grip_multiplier("GRAVEL",0.0)==1.0)
	check("wet_asphalt_is_slipperier_but_not_ice",
		Conditions.grip_multiplier("ASPHALT",1.0)<1.0 and
		Conditions.grip_multiplier("ASPHALT",1.0)>.75)
	check("rain_range_is_clamped_and_gravel_not_as_slippery_as_asphalt",
		Conditions.grip_multiplier("ASPHALT",3.0)==Conditions.grip_multiplier("ASPHALT",1.0) and
		Conditions.grip_multiplier("GRAVEL",1.0)>Conditions.grip_multiplier("ASPHALT",1.0))
	check("dry_or_parked_tires_do_not_spray",
		Conditions.spray_strength("ASPHALT",30.0,0.0)==0.0 and
		Conditions.spray_strength("ASPHALT",0.0,1.0)==0.0)
	check("rain_spray_scales_with_speed",
		Conditions.spray_strength("ASPHALT",25.0,.8)>
		Conditions.spray_strength("ASPHALT",9.0,.8))
	check("wet_reflections_only_appear_on_pavement",
		WetVisuals.reflection_opacity(1.0,"ASPHALT")>.15 and
		WetVisuals.reflection_opacity(1.0,"GRAVEL")==0.0)
	check("scrape_sparks_do_not_spawn_collision_fragments",
		int(Crashes.impact_profile(24.0,1.5).get("sparks",0))>0 and
		int(Crashes.impact_profile(24.0,1.5).get("glass",1))==0)
	check("high_severity_impacts_can_shatter_body_parts",
		int(Crashes.impact_profile(30.0,18.0).get("glass",0))>0 and
		int(Crashes.impact_profile(30.0,18.0).get("plastic",0))>0)
	var car := VehicleScene.instantiate() as VehicleController2D
	car.surface_provider=map
	car.external_input=true
	root.add_child(car)
	car.set_physics_process(false)
	map.rain_intensity=0.0
	car.step_vehicle(1.0/120.0,Vector4.ZERO)
	var dry: float=car.surface_grip
	map.rain_intensity=1.0
	car.step_vehicle(1.0/120.0,Vector4.ZERO)
	check("vehicle_uses_provider_wet_grip_at_physics_tick",
		is_equal_approx(dry,1.0) and
		is_equal_approx(car.surface_grip,Conditions.grip_multiplier("ASPHALT",1.0)))
	var dust: Node2D=car.get_node("DrivingDust")
	car.linear_velocity=Vector2.UP*26.0
	car.wheel_spin=0.0
	car.handbrake=0.0
	for i in 12:
		dust._process(.05)
	check("wet_tires_emit_bounded_spray_without_drifting",
		dust.puffs.size()>0 and dust.puffs.size()<=Dust.MAX_PUFFS and
		dust.puffs.any(func(p: Dictionary): return str(p.get("kind",""))=="water"))
	var layer := Node2D.new()
	layer.set_script(WetVisuals)
	layer.world=map
	layer.focus_vehicle=car
	root.add_child(layer)
	layer._process(.05)
	check("weather_layer_is_world_aligned_and_bounded",
		layer.top_level and layer.drops.size()<=WetVisuals.MAX_DROPS)
	map.rain_intensity=0.0
	layer._process(.05)
	check("clearing_weather_clears_rain_particles",
		layer.drops.is_empty() and Conditions.rain_at(map)==0.0)
	print("DRIVING PHASE 3 FX: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
