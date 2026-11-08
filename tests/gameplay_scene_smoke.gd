extends SceneTree

var failed: Array[String] = []

func _initialize() -> void:
    call_deferred("_test_scene")

func require_test(condition: bool, message: String) -> void:
    if not condition:
        failed.append(message)
        push_error(message)

func _test_scene() -> void:
    var packed: PackedScene = load("res://scenes/main.tscn")
    require_test(packed != null, "Main gameplay scene should load with Porsche art and Atlas Coast")
    if packed == null:
        quit(1)
        return
    var scene: Node2D = packed.instantiate()
    root.add_child(scene)
    await process_frame
    var car: StreetboundCar = scene.get_node_or_null("Car")
    var world: GDTRacingWorld = scene.get_node_or_null("World")
    require_test(car != null and world != null, "Gameplay must create car and world together")
    if car != null and world != null:
        car.set_physics_process(false)
        var sprite: Sprite2D = car.get_node_or_null("Sprite2D")
        require_test(sprite != null and sprite.texture != null, "Existing Porsche blueprint should be used as a car sprite")
        require_test((world.get_road_paths() as Array).size() == 132, "Entire Atlas Coast map must load")
        require_test(world.get_intersections().size() > 70, "Auto paved road junctions should be preserved")
        var spawn_markers: Array = world.get_markers("player_spawn")
        require_test(not spawn_markers.is_empty(), "Driver spawn marker must exist")
        if not spawn_markers.is_empty():
            var spawn: Dictionary = spawn_markers[0]
            require_test(car.global_position.distance_to(Vector2(float(spawn["x"]),float(spawn["y"]))) < 0.1,
                "Car should spawn at the saved world garage location")
        require_test(car.collision_mask > 0, "Car collision mask must be enabled")
        require_test(car.get_node_or_null("CollisionShape2D") != null, "Car needs a collision shape")
        require_test(world.get_node_or_null("WorldBlocking") != null, "World collision blockers must be created")
        var display: Label = scene.get_node_or_null("HUD/Panel/VBox/SpeedLabel")
        require_test(display != null and display.text.contains("km/h"), "Gameplay HUD must show speed")
    scene.queue_free()
    if failed.is_empty():
        print("STREETBOUND_GAMEPLAY_SCENE_PASS")
        quit(0)
    else:
        print("STREETBOUND_GAMEPLAY_SCENE_FAIL ",failed.size())
        quit(1)
