extends SceneTree
const Vehicle = preload("res://scenes/vehicle.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, valid: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL",label,value])
	if not valid:
		failures.append(label)

func run() -> void:
	var config := VehicleConfig.new()
	var transmission := VehicleTransmission.new()
	transmission.reset(config)
	transmission.update(1.0/60.0,24.0,1.0,false,config)
	check("auto_upshift_triggered",transmission.gear == 2,transmission.gear)
	check("automatic_shift_cut_shortened",
		transmission.shift_timer > 0.0 and transmission.shift_timer <= 0.09,
		transmission.shift_timer)
	transmission.update(0.10,24.0,1.0,false,config)
	check("automatic_shift_finishes_under_tenth_second",transmission.shift_timer == 0.0,
		transmission.shift_timer)
	transmission.gear=5
	transmission.shift_timer=0.18
	transmission.update(1.0/60.0,0.4,0.8,true,config)
	check("reverse_range_enters_first_immediately",transmission.gear == 1 and
		transmission.shift_timer == 0.0,[transmission.gear,transmission.shift_timer])
	transmission.gear=4
	transmission.shift_timer=0.18
	transmission.update(1.0/60.0,0.2,0.8,false,config)
	check("drive_range_returns_to_first_without_shift_wait",transmission.gear == 1 and
		transmission.shift_timer == 0.0,[transmission.gear,transmission.shift_timer])
	transmission.reset(config)
	transmission.automatic=false
	transmission.shift(1,config)
	check("manual_shift_duration_unchanged",
		is_equal_approx(transmission.shift_timer,config.shift_duration),
		transmission.shift_timer)
	var vehicle: VehicleController2D = Vehicle.instantiate()
	root.add_child(vehicle)
	vehicle.set_physics_process(false)
	await physics_frame
	vehicle.reversing=true
	vehicle.transmission.gear=4
	vehicle.linear_velocity=Vector2.DOWN*0.7
	vehicle.step_vehicle(1.0/60.0,Vector4(0.8,0,0,0))
	check("throttle_reselects_first_at_safe_low_reverse_speed",
		not vehicle.reversing and vehicle.transmission.gear==1,
		[vehicle.reversing,vehicle.transmission.gear])
	vehicle.reset_vehicle()
	for i in 16:
		await physics_frame
		vehicle.step_vehicle(1.0/60.0,Vector4(0,1,0,0))
	check("brake_enters_reverse_promptly_at_stop",vehicle.reversing,vehicle.reverse_hold)
	print("FAST AUTO / REVERSE TO FIRST: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
