extends "res://tests/driving_test.gd"
## Exercising the real 120 Hz driving model, not a hand-made handling score.
const Catalog=preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Parts=preload("res://scripts/vehicle/upgrade_parts.gd")
const MODELS=["acura-integra","mclaren-570s","cadillac-escalade"]

func simulate_turn(settings: VehicleConfig,road_speed: float) -> Vector3:
	car.config=settings.duplicate(true)
	car.transmission.reset(car.config)
	fresh(road_speed)
	var peak_slip:=0.0
	for i in 180:
		car.step_vehicle(1.0/120.0,Vector4(0.25,0.0,0.73,0.0))
		peak_slip=maxf(peak_slip,absf(car.slip_angle))
	return Vector3(absf(car.rotation),peak_slip,car.linear_velocity.length())

func simulate_handbrake(settings: VehicleConfig,road_speed: float) -> Vector3:
	car.config=settings.duplicate(true)
	car.transmission.reset(car.config)
	fresh(road_speed)
	var total_turn:=0.0
	var previous_heading:=car.rotation
	for i in 360:
		car.step_vehicle(1.0/120.0,Vector4(0.24,0.0,1.0,1.0))
		# Node2D exposes heading normalized to +/- PI; integrate signed frame
		# differences to measure an actual 180 instead of a wrapped angle.
		total_turn += angle_difference(previous_heading,car.rotation)
		previous_heading=car.rotation
	return Vector3(absf(total_turn),car.linear_velocity.length(),car.yaw_rate)

func simulate_drift(settings: VehicleConfig) -> Vector3:
	car.config=settings.duplicate(true)
	car.transmission.reset(car.config)
	fresh(23.0)
	for i in 46:
		car.step_vehicle(1.0/120.0,Vector4(0.35,0.0,0.85,1.0))
	var holding_slip:=0.0
	for i in 160:
		car.step_vehicle(1.0/120.0,Vector4(0.44,0.0,0.58,0.0))
		holding_slip+=absf(car.slip_angle)
	return Vector3(holding_slip/160.0,car.rotation,car.linear_velocity.length())

func run() -> void:
	car=Vehicle.instantiate()
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	var all=Parts.all()
	check("catalog_keeps_120_parts",all.size()==120,all.size())
	for id in MODELS:
		var entry: Dictionary=Catalog.find_by_id(id)
		check("known_vehicle_"+id,not entry.is_empty(),id)
		if entry.is_empty():
			continue
		var stock: VehicleConfig=Catalog.make_configuration(entry)
		var track: VehicleConfig=Catalog.make_configuration(entry)
		Parts.apply_to_config(track,[Parts.get_part("suspension-grip-legendary"),Parts.get_part("tires-grip-legendary")])
		var drift: VehicleConfig=Catalog.make_configuration(entry)
		Parts.apply_to_config(drift,[Parts.get_part("suspension-drift-legendary"),Parts.get_part("tires-drift-legendary")])
		check(id+"_real_build_identity",track.high_speed_stability>stock.high_speed_stability and
			drift.drift_control>stock.drift_control and drift.handbrake_rotation_boost>stock.handbrake_rotation_boost and
			track.tire_grip>drift.tire_grip and drift.rear_grip_balance<track.rear_grip_balance,
			[stock.high_speed_stability,track.high_speed_stability,drift.drift_control,drift.handbrake_rotation_boost])
		var grip0: VehicleConfig=stock.duplicate(true)
		grip0.high_speed_stability=0.0
		var grip1: VehicleConfig=stock.duplicate(true)
		grip1.high_speed_stability=0.58
		var before:=simulate_turn(grip0,38.0)
		var after:=simulate_turn(grip1,38.0)
		check(id+"_faster_steer_when_planted",after.x>before.x*1.025 and after.x<before.x*1.5,
			[before,after])
		check(id+"_racing_steer_does_not_create_massive_spin",after.y<deg_to_rad(17.0) and after.z>13.0,[before,after])
		var slow_before:=simulate_turn(grip0,8.0)
		var slow_after:=simulate_turn(grip1,8.0)
		check(id+"_stability_upgrades_are_speed_dependent",absf(slow_after.x-slow_before.x)<0.1,
			[slow_before,slow_after])
		var hb:=simulate_handbrake(stock,24.0)
		check(id+"_stock_rolling_handbrake_can_180",hb.x>=deg_to_rad(175.0) and hb.y>1.0,hb)
		var equipped:=simulate_drift(drift)
		var original:=simulate_drift(stock)
		check(id+"_drift_parts_keep_sliding",equipped.x>deg_to_rad(7.0) and
			equipped.x>original.x*0.93,[original,equipped])
		# Holding a stationary handbrake and steering must never move or rotate.
		car.config=drift.duplicate(true)
		fresh()
		for i in 120:
			car.step_vehicle(1.0/120.0,Vector4(0,0,1,1))
		check(id+"_handbrake_has_no_stationary_rotation",absf(car.rotation)<0.001 and
			car.linear_velocity.length()<0.001, [car.rotation,car.linear_velocity])
	print("CAR RACE AND DRIFT PHYSICS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
