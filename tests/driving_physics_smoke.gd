extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_check")

func expect_test(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)

func _check() -> void:
    var car_script: Script = load("res://scripts/car_controller.gd")
    expect_test(car_script != null, "Car physics script must parse")
    if car_script == null:
        quit(1)
        return
    var car: CharacterBody2D = car_script.new()
    root.add_child(car)
    car.set_physics_process(false)
    car.reset_vehicle(Vector2(100,100))
    for n in range(210):
        car.advance_physics(1.0/60.0,1.0,0.0,false)
    var cruise: float = car.get_speed_kph()
    expect_test(cruise > 50.0 and cruise < car.maximum_speed_kph+1.0,
        "Acceleration must increase speed smoothly and respect speed cap: " + str(cruise))
    var old_heading: float = car.rotation
    for n in range(50):
        car.advance_physics(1.0/60.0,1.0,1.0,false)
    expect_test(absf(car.rotation-old_heading)>0.05,"Steer should turn the car at speed")
    expect_test(rad_to_deg(absf(car.steer_angle)) < car.low_speed_steer_deg,
        "Steering range should decrease at speed")
    var before_brake: float = car.get_speed_kph()
    for n in range(100):
        car.advance_physics(1.0/60.0,-1.0,0.0,false)
    expect_test(car.get_speed_kph() < before_brake,
        "Braking forward speed must reduce velocity")
    car.reset_vehicle(Vector2(100,100))
    for n in range(125):
        car.advance_physics(1.0/60.0,-1.0,0.0,false)
    expect_test(car.get_forward_speed_kph() < -5.0,"Reverse must engage after stopping")
    car.set_surface("gravel")
    expect_test(car.surface_grip < 0.7,"Gravel must reduce tire grip")
    car.set_surface("track")
    expect_test(car.surface_grip > 1.0,"Track should provide greater tire grip")
    car.reset_vehicle(Vector2(10,20))
    expect_test(car.velocity.is_zero_approx() and car.get_speed_kph()==0.0,
        "Reset must clear momentum")

    var world_script: Script = load("res://worlds/world_loader.gd")
    expect_test(world_script != null,"World Forge loader must parse")
    if world_script != null:
        var world: Node2D = world_script.new()
        world.set("build_collision",false)
        root.add_child(world)
        var loaded: bool = world.call("load_world","res://worlds/atlas-coast.world.json")
        expect_test(loaded,"Archived Atlas Coast world must load unchanged")
        if loaded:
            expect_test((world.call("get_road_paths") as Array).size()==132,
                "All 132 road paths must remain")
            expect_test((world.call("get_intersections") as Array).size()>70,
                "Archived world should have paved intersections")
            expect_test((world.call("get_markers","dealership") as Array).size()==11,
                "11 dealerships must be preserved")
        world.queue_free()
    car.queue_free()
    if failures.is_empty():
        print("STREETBOUND_DRIVING_SMOKE_PASS")
        quit(0)
    else:
        print("STREETBOUND_DRIVING_SMOKE_FAIL ",failures.size())
        quit(1)
