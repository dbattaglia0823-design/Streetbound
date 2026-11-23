extends SceneTree
## Regression for shared rear lamps, per-model anchors and independent,
## bounded skidmarks/smoke across player, rival and ambient traffic cars.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const TrafficCar = preload("res://scripts/world/traffic_car.gd")
const Lights = preload("res://scripts/visual/vehicle_lights.gd")
const Dust = preload("res://scripts/visual/driving_dust.gd")
const Marks = preload("res://scripts/world/tire_marks.gd")
const Sampler = preload("res://scripts/world/vehicle_tire_trails.gd")
var failures: Array[String] = []

class TestSurface extends Node2D:
	func surface_at(_point: Vector2) -> Dictionary:
		return {"name":"ASPHALT","grip":1.0}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if passed else "FAIL",label,str(detail)])
	if not passed:
		failures.append(label)

func run() -> void:
	var world := TestSurface.new()
	root.add_child(world)
	var player := VehicleScene.instantiate() as VehicleController2D
	player.surface_provider=world
	root.add_child(player)
	player.set_physics_process(false)
	var lights: Node2D=player.get_node_or_null("RearLights")
	var dust: Node2D=player.get_node_or_null("DrivingDust")
	check("every_drivable_scene_has_running_brake_reverse_lamps",
		lights!=null and lights.get("rear_points").size()==2)
	check("every_drivable_scene_has_bounded_world_space_smoke",
		dust!=null and dust.top_level and Dust.MAX_PUFFS<=48 and
		dust.global_position.is_equal_approx(Vector2.ZERO))
	check("shared_lamps_use_actual_vehicle_dimensions",
		lights.rear_points[0].x < lights.rear_points[1].x and
		lights.rear_points[0].y > 0.0 and
		lights.rear_points[1].y > 0.0,lights.rear_points)
	player.brake=.95
	player.reversing=false
	lights._process(.02)
	check("service_brake_brightens_the_rear_lamps",lights.braking and not lights.reversing)
	player.brake=0.0
	player.reversing=true
	lights._process(.02)
	check("reverse_activates_white_lamps_without_brake_lighting",
		lights.reversing and not lights.braking)
	player.reversing=false
	player.handbrake=.8
	lights._process(.02)
	check("moving_handbrake_illuminates_stop_lamps",lights.braking)
	player.handbrake=0.0
	lights._process(.02)
	check("running_taillights_remain_without_braking",
		not lights.braking and not lights.reversing)

	var rig: Node=player.get_node("Art/Wheels")
	var left_before: Vector2=lights.rear_points[0]
	var profile: Resource=(rig.get("appearance") as Resource).duplicate(true)
	profile.set("rear_light_left_uv",Vector2(.12,.94))
	profile.set("rear_light_right_uv",Vector2(.88,.94))
	rig.call("apply_appearance",profile)
	lights._process(.02)
	check("lamp_anchors_follow_per_model_profile_and_body_switches",
		lights.rear_points[0].x < left_before.x and
		lights.rear_points[0].x < lights.rear_points[1].x,
		lights.rear_points)

	var traffic := CharacterBody2D.new()
	traffic.set_script(TrafficCar)
	root.add_child(traffic)
	var traffic_lights: Node2D=traffic.get_node_or_null("RearLights")
	check("ambient_traffic_has_same_universal_rear_lamps",
		traffic_lights!=null and traffic_lights.rear_points.size()==2)
	traffic.set("brake_lights_on",true)
	traffic_lights._process(.02)
	check("traffic_brake_state_reaches_visual_lights",traffic_lights.braking)

	check("normal_asphalt_rolling_emits_no_permanent_smoke",
		is_equal_approx(Dust.tire_smoke_strength(18.0,0.0,0.0,0.0,"ASPHALT"),0.0))
	check("burnout_and_drift_produce_visible_smoke",
		Dust.tire_smoke_strength(.5,0.0,1.0,0.0,"ASPHALT")>.4 and
		Dust.tire_smoke_strength(19.0,.42,0.0,0.0,"ASPHALT")>.6)
	check("loose_surfaces_emit_dust_during_normal_driving",
		Dust.tire_smoke_strength(14.0,0.0,0.0,0.0,"GRAVEL")>.5)
	player.wheel_spin=1.0
	dust._process(.35)
	check("smoke_emitter_is_installed_and_respects_per_car_cap",
		dust.puffs.size()>0 and dust.puffs.size()<=Dust.MAX_PUFFS,
		dust.puffs.size())

	var rival := VehicleScene.instantiate() as VehicleController2D
	rival.surface_provider=world
	rival.position=Vector2(500,0)
	root.add_child(rival)
	rival.set_physics_process(false)
	var marks: TireMarks2D=Marks.new()
	root.add_child(marks)
	player.wheel_spin=0.0
	for car in [player,rival]:
		car.rotation=0.0
		car.linear_velocity=Vector2(10,-8)
		car.surface="ASPHALT"
	Sampler.sample(marks,player,player,world)
	Sampler.sample(marks,rival,player,world)
	var rival_track: int=Sampler.track_id(rival,player,0)
	check("player_and_rival_mark_both_real_rear_wheel_contacts",
		marks.active_line(0)!=null and marks.active_line(1)!=null and
		marks.active_line(rival_track)!=null and
		marks.active_line(rival_track+1)!=null)
	var rival_line: Line2D=marks.active_line(rival_track)
	marks.reset_tracks(0)
	marks.reset_tracks(1)
	check("one_car_stopping_skid_does_not_break_other_tracks",
		marks.active_line(0)==null and marks.active_line(rival_track)==rival_line)
	rival.position+=Vector2(15,0)
	Sampler.sample(marks,rival,player,world)
	check("rival_skid_stays_continuous_after_player_track_reset",
		marks.active_line(rival_track)==rival_line and
		rival_line.get_point_count()>=2)
	check("shared_world_skid_buffer_remains_bounded",
		marks.trail_count()<=Marks.MAX_TRAILS and marks.point_count()<=Marks.CAPACITY)
	print("DRIVING PHASE 1 FX: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
